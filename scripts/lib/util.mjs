// Shared helpers for the data scripts. Node 20+, no dependencies.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const RAW = path.join(ROOT, 'data', 'raw');          // downloads, not committed
export const SOURCES = path.join(ROOT, 'data', 'sources');  // committed inputs (Changi list, geocode cache)
export const OUT = path.join(ROOT, 'SingaSmoke', 'Resources', 'Data');  // what ships in the app

export const sleep = ms => new Promise(r => setTimeout(r, ms));
export const log = (...a) => console.error(...a);
export const readJSON = f => JSON.parse(fs.readFileSync(f, 'utf8'));
export function writeJSON(f, obj) {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, JSON.stringify(obj));
}
export const r6 = n => Math.round(n * 1e6) / 1e6;   // ~0.1 m, for points
export const r5 = n => Math.round(n * 1e5) / 1e5;   // ~1.1 m, for polygon vertices

// Singapore, generously: anything outside this box is a data error.
export const SG_BOUNDS = { south: 1.13, north: 1.48, west: 103.55, east: 104.1 };
export const inSingapore = (lat, lng) =>
  lat > SG_BOUNDS.south && lat < SG_BOUNDS.north && lng > SG_BOUNDS.west && lng < SG_BOUNDS.east;

/* ---------------- text ---------------- */

export function parseCsv(text) {
  const rows = [];
  let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false; }
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (c !== '\r') field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows;
}

// The government registers are ALL CAPS; OSM names are already cased by people and left alone.
export const titleCase = s => s.toLowerCase()
  .replace(/\b[a-z]/g, c => c.toUpperCase())
  .replace(/\b(Mrt|Lrt|Dsa|Nea|Hdb|Spc|Ntuc|Ion|Jem|Llp|Sg|Ktv)\b/gi, m => m.toUpperCase())
  .replace(/\bPte\.? Ltd\.?\b/gi, 'Pte Ltd')
  .replace(/\b(\d+)(St|Nd|Rd|Th)\b/g, (_, n, sfx) => n + sfx.toLowerCase())
  .replace(/'S\b/g, "'s")
  .replace(/^(.+),\s*The$/i, 'The $1')
  .trim();

// "…, SINGAPORE(738733)" -> "738733"
export const postalOf = address => (address.match(/SINGAPORE\s*\(?\s*(\d{6})\s*\)?/i) || [])[1];

/* ---------------- network ---------------- */

export const USER_AGENT = 'SingaSmoke data build (+https://github.com/TheNarciss/SingaSmoke)';

export async function fetchRetry(url, options = {}, { tries = 5, wait = 3000, label = url } = {}) {
  let lastError;
  for (let attempt = 0; attempt < tries; attempt++) {
    try {
      const res = await fetch(url, {
        ...options,
        headers: { 'User-Agent': USER_AGENT, ...(options.headers || {}) },
        signal: AbortSignal.timeout(options.timeout ?? 300_000),
      });
      if (res.ok) return res;
      lastError = new Error(`HTTP ${res.status}`);
      if (res.status === 404) break;
    } catch (e) {
      lastError = e;
    }
    await sleep(wait * (attempt + 1));
  }
  throw new Error(`${label}: ${lastError?.message ?? 'failed'}`);
}

// data.gov.sg hands out a short-lived signed S3 URL, and allows ~5 unauthenticated calls a minute.
export async function dataGovDownload(id, label) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const meta = await fetch(`https://api-open.data.gov.sg/v1/public/api/datasets/${id}/poll-download`,
      { headers: { 'User-Agent': USER_AGENT }, signal: AbortSignal.timeout(60_000) })
      .then(r => r.json()).catch(() => null);
    if (meta?.data?.url) {
      const res = await fetchRetry(meta.data.url, {}, { label });
      return Buffer.from(await res.arrayBuffer());
    }
    await sleep(meta?.name === 'TOO_MANY_REQUESTS' ? 12_000 : 4_000);
  }
  throw new Error(`data.gov.sg: could not download ${id} (${label})`);
}

export async function dataGovMetadata(id) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const j = await fetch(`https://api-production.data.gov.sg/v2/public/api/datasets/${id}/metadata`,
      { headers: { 'User-Agent': USER_AGENT }, signal: AbortSignal.timeout(60_000) })
      .then(r => r.json()).catch(() => null);
    if (j?.data?.name) return j.data;
    await sleep(12_000);
  }
  return null;
}

// Overpass answers 429/504 under load and sometimes drops the connection mid-transfer.
const OVERPASS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];

export async function overpass(query, label) {
  let lastError;
  for (let attempt = 0; attempt < 8; attempt++) {
    const endpoint = OVERPASS[attempt % OVERPASS.length];
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json', 'User-Agent': USER_AGENT },
        body: new URLSearchParams({ data: query }),
        signal: AbortSignal.timeout(900_000),
      });
      if (res.ok) {
        const json = await res.json();
        if (Array.isArray(json.elements)) return json;
        lastError = new Error('no elements in answer');
      } else lastError = new Error(`HTTP ${res.status}`);
    } catch (e) {
      lastError = e;
    }
    log(`  overpass ${label}: attempt ${attempt + 1} failed (${lastError.message}), retrying`);
    await sleep(15_000 * (attempt + 1));
  }
  throw new Error(`overpass ${label}: ${lastError?.message}`);
}

/* ---------------- geometry (lng/lat pairs, GeoJSON order) ---------------- */

export function haversine(lat1, lng1, lat2, lng2) {
  const R = 6_371_008.8, rad = Math.PI / 180;
  const dLat = (lat2 - lat1) * rad, dLng = (lng2 - lng1) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function pointInRing([x, y], ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export const pointInPolygon = (pt, rings) => pointInRing(pt, rings[0]) && !rings.slice(1).some(h => pointInRing(pt, h));

export function pointInGeometry(pt, g) {
  if (g.type === 'Polygon') return pointInPolygon(pt, g.coordinates);
  if (g.type === 'MultiPolygon') return g.coordinates.some(p => pointInPolygon(pt, p));
  return false;
}

// Area of a ring in square metres (equirectangular around Singapore's latitude, plenty at this scale).
export function ringArea(ring) {
  const k = 111_320 * Math.cos(1.35 * Math.PI / 180);
  let a = 0;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    a += (ring[j][0] * k) * (ring[i][1] * 110_574) - (ring[i][0] * k) * (ring[j][1] * 110_574);
  }
  return Math.abs(a / 2);
}

// Ramer–Douglas–Peucker; tolerance in degrees (1e-5 deg ~ 1.1 m).
export function simplify(points, tol) {
  if (points.length < 3) return points;
  const [ax, ay] = points[0], [bx, by] = points[points.length - 1];
  const dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
  let maxD = 0, index = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const [px, py] = points[i];
    let t = len2 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0;
    t = Math.max(0, Math.min(1, t));
    const ex = ax + t * dx - px, ey = ay + t * dy - py;
    const d = ex * ex + ey * ey;
    if (d > maxD) { maxD = d; index = i; }
  }
  if (Math.sqrt(maxD) > tol) {
    return [...simplify(points.slice(0, index + 1), tol).slice(0, -1), ...simplify(points.slice(index), tol)];
  }
  return [points[0], points[points.length - 1]];
}

// Simplify a closed ring and round it; returns null if it collapses.
export function cleanRing(ring, tol) {
  const closed = ring.length > 1 && ring[0][0] === ring[ring.length - 1][0] && ring[0][1] === ring[ring.length - 1][1]
    ? ring : [...ring, ring[0]];
  const out = simplify(closed, tol).map(([x, y]) => [r5(x), r5(y)]);
  const dedup = out.filter((p, i) => i === 0 || p[0] !== out[i - 1][0] || p[1] !== out[i - 1][1]);
  if (dedup.length < 4) return null;
  dedup[dedup.length - 1] = [...dedup[0]];
  return dedup;
}

// Join OSM member ways (arrays of [lng,lat]) into closed rings.
export function assembleRings(segments) {
  const key = p => `${p[0].toFixed(7)},${p[1].toFixed(7)}`;
  const pool = segments.filter(s => s.length >= 2).map(s => s.slice());
  const rings = [];
  while (pool.length) {
    let ring = pool.shift();
    for (let guard = 0; key(ring[0]) !== key(ring[ring.length - 1]) && guard < 5000; guard++) {
      const end = key(ring[ring.length - 1]);
      const i = pool.findIndex(s => key(s[0]) === end || key(s[s.length - 1]) === end);
      if (i < 0) break;
      let next = pool.splice(i, 1)[0];
      if (key(next[0]) !== end) next = next.reverse();
      ring = ring.concat(next.slice(1));
    }
    if (ring.length >= 4 && key(ring[0]) === key(ring[ring.length - 1])) rings.push(ring);
  }
  return rings;
}

// Overpass `out geom` element -> GeoJSON geometry (Polygon/MultiPolygon), or null.
export function osmAreaGeometry(el) {
  if (el.type === 'way') {
    const ring = (el.geometry || []).map(p => [p.lon, p.lat]);
    if (ring.length < 4) return null;
    const [a, b] = [ring[0], ring[ring.length - 1]];
    if (a[0] !== b[0] || a[1] !== b[1]) return null;   // an open way is a line, not an area
    return { type: 'Polygon', coordinates: [ring] };
  }
  if (el.type === 'relation') {
    const members = (el.members || []).filter(m => m.type === 'way' && m.geometry);
    const outer = assembleRings(members.filter(m => m.role !== 'inner').map(m => m.geometry.map(p => [p.lon, p.lat])));
    const inner = assembleRings(members.filter(m => m.role === 'inner').map(m => m.geometry.map(p => [p.lon, p.lat])));
    if (!outer.length) return null;
    const polys = outer.map(o => [o]);
    for (const hole of inner) {
      const owner = polys.find(p => pointInRing(hole[0], p[0]));
      if (owner) owner.push(hole);
    }
    return polys.length === 1 ? { type: 'Polygon', coordinates: polys[0] } : { type: 'MultiPolygon', coordinates: polys };
  }
  return null;
}

// Simplify + round every ring of a Polygon/MultiPolygon; drops what collapses.
export function cleanGeometry(g, tol) {
  const polys = g.type === 'Polygon' ? [g.coordinates] : g.coordinates;
  const kept = polys
    .map(p => {
      const outer = cleanRing(p[0], tol);
      if (!outer) return null;
      return [outer, ...p.slice(1).map(h => cleanRing(h, tol)).filter(Boolean)];
    })
    .filter(Boolean);
  if (!kept.length) return null;
  return kept.length === 1 ? { type: 'Polygon', coordinates: kept[0] } : { type: 'MultiPolygon', coordinates: kept };
}

export function geometryCentroid(g) {
  const ring = g.type === 'Polygon' ? g.coordinates[0] : g.coordinates[0][0];
  let x = 0, y = 0;
  for (const [px, py] of ring) { x += px; y += py; }
  return [x / ring.length, y / ring.length];
}
