// Turns data/raw/* into the GeoJSON files the app ships with (SingaSmoke/Resources/Data).
//   spots.geojson      places where smoking is allowed (NEA, Changi, OpenStreetMap)
//   zones.geojson      places where it is prohibited (NEA, NParks, OpenStreetMap)
//   retailers.geojson  licensed tobacco retailers (HSA)
//   meta.json          dates, counts and attributions
// Several rules here are adapted from likalight/smokingarea-sg (MIT).
import fs from 'node:fs';
import path from 'node:path';
import {
  RAW, SOURCES, OUT, log, readJSON, writeJSON, r6, parseCsv, titleCase, postalOf, inSingapore,
  haversine, pointInGeometry, cleanGeometry, geometryCentroid, osmAreaGeometry, ringArea,
} from './lib/util.mjs';

const raw = f => readJSON(path.join(RAW, f));
const point = (lng, lat) => ({ type: 'Point', coordinates: [r6(lng), r6(lat)] });
const feature = (id, geometry, properties) => ({ type: 'Feature', id, geometry, properties });
const isoDate = s => (s && /^\d{8}/.test(String(s)) ? `${String(s).slice(0, 4)}-${String(s).slice(4, 6)}-${String(s).slice(6, 8)}` : null);
const isPrivate = t => /^(private|no)$/.test(t.access || '');

function emit(name, obj) {
  const file = path.join(OUT, name);
  writeJSON(file, obj);
  log(`  ${name.padEnd(18)} ${(fs.statSync(file).size / 1024).toFixed(0).padStart(6)} KB`);
}

/* ======================= 1. Smoking spots ======================= */

const spots = [];

// NEA Designated Smoking Areas: the yellow boxes inside the Orchard Road No-Smoking Zone.
for (const f of raw('nea_dsa.geojson').features) {
  const p = f.properties, [lng, lat] = f.geometry.coordinates;
  spots.push(feature(`nea-${p.OBJECTID}`, point(lng, lat), {
    name: titleCase(p.BUILDING_N || 'Designated Smoking Area'),
    details: (p.DESCRIPTION || '').trim(),
    source: 'nea',
    approx: false,
    photo: p.PHOTOURL || null,
    updated: isoDate(p.FMEL_UPD_D),
  }));
}

// Changi Airport Group's list. Worded locations only: the pin goes on the gate the text names
// (OpenStreetMap knows the gates), otherwise on the terminal. Always flagged approximate.
{
  const cag = readJSON(path.join(SOURCES, 'changi_dsa.json'));
  const osm = raw('osm_changi.json').elements;
  const terminals = { T1: [103.99108, 1.36271], T2: [103.99045, 1.35379], T3: [103.98508, 1.35461], T4: [103.98427, 1.33879] };
  for (const e of osm) {
    const m = (e.tags?.name || '').match(/Terminal\s*(\d)/i);
    if (e.tags?.aeroway === 'terminal' && m && e.center) terminals['T' + m[1]] = [e.center.lon, e.center.lat];
  }
  // "A6-A8" and "C13/C14" name several gates on one node.
  const gates = {};
  for (const e of osm) {
    if (e.tags?.aeroway !== 'gate' || !e.tags.ref) continue;
    for (const part of e.tags.ref.split('/')) {
      const range = part.match(/^([A-H])(\d+)-(?:[A-H])?(\d+)$/);
      const refs = range ? Array.from({ length: +range[3] - +range[2] + 1 }, (_, i) => range[1] + (+range[2] + i)) : [part];
      for (const r of refs) gates[r.trim()] = [e.lon, e.lat];
    }
  }
  const gatesIn = where => {
    const m = where.match(/\bGates?\s+([A-H])(\d+)(?:\s*(?:to|–|-)\s*[A-H]?(\d+))?/i);
    if (!m) return [];
    const from = +m[2], to = m[3] ? +m[3] : from;
    const refs = Array.from({ length: Math.max(1, to - from + 1) }, (_, i) => m[1].toUpperCase() + (from + i));
    return refs.map(r => gates[r]).filter(Boolean);
  };
  const perTerminal = {};
  cag.areas.forEach(a => {
    const base = terminals[a.t];
    if (!base) return;
    const found = gatesIn(a.where);
    let lng, lat, radius;
    if (found.length) {
      lng = found.reduce((s, g) => s + g[0], 0) / found.length;
      lat = found.reduce((s, g) => s + g[1], 0) / found.length;
      radius = 80;
    } else {
      // Deterministic spread around the terminal centroid so pins do not stack.
      const i = (perTerminal[a.t] = (perTerminal[a.t] ?? -1) + 1);
      const angle = (i / 8) * Math.PI * 2;
      lng = base[0] + 0.00026 * Math.sin(angle);
      lat = base[1] + 0.00026 * Math.cos(angle);
      radius = 300;
    }
    // Stable id from the wording, so a spot keeps its id across rebuilds.
    const slug = `${a.t}-${a.zone}-${a.level}-${a.where}`.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    let id = `cag-${slug}`;
    for (let n = 2; spots.some(s => s.id === id); n++) id = `cag-${slug}-${n}`;
    spots.push(feature(id, point(lng, lat), {
      name: `Changi Airport ${a.t}`,
      details: a.where,
      source: 'changi',
      approx: true,
      approxRadius: radius,
      level: a.level,
      airside: a.zone === 'transit',
      url: cag._source,
      updated: cag._captured,
    }));
  });
}

// OpenStreetMap. Two different things, kept apart:
//   amenity=smoking_area / smoking=designated          -> a smoking area   ('osm_area')
//   smoking=outside|separated|isolated|yes on a venue   -> a smoking corner ('osm_venue')
const CORNER = { isolated: 'Salle fumeur fermée', separated: 'Espace fumeur séparé', outside: 'Coin fumeur en extérieur', yes: 'Fumer autorisé selon OSM' };
{
  const seen = new Set();
  for (const e of raw('osm_smoking.json').elements) {
    const lat = e.lat ?? e.center?.lat, lng = e.lon ?? e.center?.lon;
    if (lat == null || lng == null || !inSingapore(lat, lng)) continue;
    const t = e.tags || {};
    if (isPrivate(t) || t.smoking === 'no') continue;
    if (/changi airport/i.test(t.name || '')) continue;   // CAG's own list is better
    const isArea = t.amenity === 'smoking_area' || /^(designated|dedicated)$/.test(t.smoking || '') || /smoking/i.test(t.name || '');
    const corner = CORNER[t.smoking];
    if (!isArea && !corner) continue;
    const id = `osm-${e.type}-${e.id}`;
    if (seen.has(id)) continue;
    seen.add(id);
    const bits = [];
    if (t.shelter === 'yes' || t.covered === 'yes') bits.push('abrité');
    if (t.bench === 'yes') bits.push('banc');
    if (t.bin === 'yes' || t.ashtray === 'yes') bits.push('cendrier');
    if (t.lit === 'yes') bits.push('éclairé');
    spots.push(feature(id, point(lng, lat), {
      name: (t.name || '').trim() || (isArea ? 'Espace fumeur' : 'Coin fumeur'),
      details: isArea ? bits.join(' · ') : corner,
      source: isArea ? 'osm_area' : 'osm_venue',
      approx: false,
      venueKind: isArea ? null : (t.amenity || t.tourism || t.shop || t.leisure || null),
      hours: t.opening_hours || null,
      level: t.level ?? null,
      url: `https://www.openstreetmap.org/${e.type}/${e.id}`,
      updated: t.check_date || t['survey:date'] || null,
    }));
  }
}

/* ======================= 2. No-smoking zones ======================= */

const TOL = 0.00002;   // ~2 m simplification: well under GPS error, keeps the file small
const zones = [];

for (const f of raw('nea_nsz.geojson').features) {
  const g = cleanGeometry(f.geometry, TOL);
  if (!g) continue;
  const name = String(f.properties.NAME || '').replace(/^NSZ\s*/i, '').trim() || 'Orchard';
  zones.push(feature(`nea-nsz-${f.properties.OBJECTID}`, g, { kind: 'nsz', name: `${name} Road No-Smoking Zone`.replace('Road Road', 'Road'), source: 'nea', buffer: 0 }));
}

const nparks = [];
for (const f of raw('nparks_nosmoking.geojson').features) {
  const g = cleanGeometry(f.geometry, TOL);
  if (!g) continue;
  nparks.push(g);
  zones.push(feature(`nparks-${f.properties.L_CODE || f.properties.OBJECTID}`, g, { kind: 'park', name: null, source: 'nparks', buffer: 0 }));
}

const hawkers = [];
for (const f of raw('nea_hawker.geojson').features) {
  if (f.geometry?.type !== 'Point') continue;
  const [lng, lat] = f.geometry.coordinates;
  if (!inSingapore(lat, lng)) continue;
  const p = f.properties;
  // Only centres that exist today; the dataset also lists ones under construction.
  if (p.STATUS && !/existing/i.test(p.STATUS)) continue;
  hawkers.push([lng, lat]);
  zones.push(feature(`nea-hawker-${p.OBJECTID}`, point(lng, lat), { kind: 'hawker', name: p.NAME ? titleCase(p.NAME) : null, source: 'nea', buffer: 35 }));
}

const COURT_SPORTS_EXCLUDED = /golf|shooting|motor|equestrian|horse|archery/;

// tags -> { kind, buffer (m around an area), radius (m around a node, 0 = ignore nodes) }
function classify(t) {
  if (t.highway === 'bus_stop') return { kind: 'bus_stop', buffer: 0, radius: 11 };   // 5 m from a ~12 m shelter
  if (t.amenity === 'bus_station') return { kind: 'bus_interchange', buffer: 5, radius: 40 };
  if (t.amenity === 'hospital') return { kind: 'hospital', buffer: 0, radius: 60 };
  if (/^(school|kindergarten|childcare|college|university)$/.test(t.amenity || '')) return { kind: 'school', buffer: 5, radius: 40 };
  if (/^(food_court|marketplace)$/.test(t.amenity || '')) return { kind: 'hawker', buffer: 0, radius: 20 };
  if (t.amenity === 'ferry_terminal') return { kind: 'ferry_terminal', buffer: 5, radius: 30 };
  if (isPrivate(t)) return null;
  if (t.amenity === 'parking') return { kind: 'car_park', buffer: 0, radius: 0 };
  if (t.leisure === 'playground') return { kind: 'playground', buffer: 3, radius: 12 };
  if (t.leisure === 'fitness_station') return { kind: 'fitness', buffer: 3, radius: 8 };
  if (t.leisure === 'pitch') return COURT_SPORTS_EXCLUDED.test(t.sport || '') ? null : { kind: 'court', buffer: 2, radius: 15 };
  if (t.leisure === 'stadium') return { kind: 'stadium', buffer: 0, radius: 0 };
  if (t.leisure === 'sports_centre') return { kind: 'sports_centre', buffer: 0, radius: 0 };
  if (t.leisure === 'park' || t.leisure === 'garden') return { kind: 'park', buffer: 0, radius: 0 };
  // The regulations name ten recreational beaches; most beaches in OSM carry no name, so every
  // public one is kept (indicative) rather than letting an unnamed East Coast stretch read as clear.
  if (t.natural === 'beach') return { kind: 'beach', buffer: 0, radius: 0 };
  // Water surface only: decks and boardwalks. The banks are mostly parks, already covered.
  if (t.water === 'reservoir' || t.landuse === 'reservoir') return { kind: 'reservoir', buffer: 0, radius: 0 };
  return null;
}

const osmZoneCounts = {};
let droppedDuplicate = 0;
for (const e of raw('osm_zones.json').elements) {
  const t = e.tags || {};
  const c = classify(t);
  if (!c) continue;
  let geometry;
  if (e.type === 'node') {
    if (!c.radius || !inSingapore(e.lat, e.lon)) continue;
    geometry = point(e.lon, e.lat);
  } else {
    const g = osmAreaGeometry(e);
    if (!g) continue;
    geometry = cleanGeometry(g, TOL);
    if (!geometry) continue;
    const outer = geometry.type === 'Polygon' ? geometry.coordinates[0] : geometry.coordinates[0][0];
    if (ringArea(outer) < 10) continue;
    const [cx, cy] = geometryCentroid(geometry);
    if (!inSingapore(cy, cx)) continue;
    // Same place already present from an official source.
    if (c.kind === 'park' && nparks.some(p => pointInGeometry([cx, cy], p))) { droppedDuplicate++; continue; }
    if (c.kind === 'hawker' && hawkers.some(([hx, hy]) => haversine(cy, cx, hy, hx) < 60)) { droppedDuplicate++; continue; }
  }
  osmZoneCounts[c.kind] = (osmZoneCounts[c.kind] || 0) + 1;
  zones.push(feature(`osm-${e.type}-${e.id}`, geometry, {
    kind: c.kind,
    name: (t.name || t['name:en'] || '').trim() || null,
    source: 'osm',
    buffer: e.type === 'node' ? c.radius : c.buffer,
  }));
}

/* ======================= 3. Licensed tobacco retailers ======================= */

const BRANDS = [
  [/\b7[\s-]?ELEVEN\b|\bSEVEN[\s-]?ELEVEN\b/, '7-Eleven', 'convenience'],
  [/\bCHEERS\b/, 'Cheers', 'convenience'],
  [/\bBUZZ\b/, 'Buzz', 'convenience'],
  [/\bFAIRPRICE\b|\bNTUC\b/, 'FairPrice', 'supermarket'],
  [/\bSHENG\s?SIONG\b/, 'Sheng Siong', 'supermarket'],
  [/\bCOLD\s?STORAGE\b/, 'Cold Storage', 'supermarket'],
  [/\bGIANT\b/, 'Giant', 'supermarket'],
  [/\bPRIME\s?SUPERMARKET\b/, 'Prime', 'supermarket'],
  [/\bDON\s?DON\s?DONKI\b/, 'Don Don Donki', 'supermarket'],
  [/\bSHELL\b/, 'Shell', 'petrol'],
  [/\bESSO\b/, 'Esso', 'petrol'],
  [/\bCALTEX\b/, 'Caltex', 'petrol'],
  [/\bSPC\b|\bSINGAPORE PETROLEUM\b/, 'SPC', 'petrol'],
  [/\bSINOPEC\b/, 'Sinopec', 'petrol'],
];

// Most of the register is small independents whose name says nothing about the shop
// ("Heng Lai Heng Trading"). Only real signals in the name are used; the rest stays 'other'.
function classifyShop(name) {
  const n = name.toUpperCase();
  for (const [re, brand, category] of BRANDS) if (re.test(n)) return { brand, category };
  const bare = n.replace(/\bPTE\.?\s*LTD\.?\b|\bPRIVATE\s+LIMITED\b|\bLIMITED\b|\bLLP\b/g, ' ')
    .replace(/\s*\(\s*S(INGAPORE)?\s*\)\s*/g, ' ');
  if (/EATING HOUSE|COFFEE ?SHOP|KOPITIAM|KOPI TIAM|FOOD ?COURT|FOOD ?CENTRE|HAWKER|CANTEEN|KOUFU|RESTAURANT|CATERING|\bBAR\b|\bPUB\b|TAVERN|BISTRO|\bCAFE\b|COFFEE|\bBEER\b|LIQUOR|\bWINE\b|BEVERAGE|\bF ?& ?B\b|HOTEL|RESORT|CLUB\b/.test(bare)) return { brand: null, category: 'kopitiam' };
  if (/SUPERMARKET|HYPERMART|HYPERMARKET|EMPORIUM/.test(bare) && !/MINI/.test(bare)) return { brand: null, category: 'supermarket' };
  if (/MINI[\s-]?MART|MINI[\s-]?MARKET|MINIMART|SUPERMART|SUPER ?MINI|PROVISION|MARKETPLACE|\bMART\b|SUNDRY|SUNDRIES|\bKIOSK\b|CONFECTIONER|\bSTALL\b|\bSTORE\b|\bSHOP\b|\bCORNER\b|NEWSAGEN|NEWS ?STAND|CONVENIENCE/.test(bare)) return { brand: null, category: 'minimart' };
  return { brand: null, category: 'other' };
}

const geo = raw('postal_latlng.json');
const rows = parseCsv(fs.readFileSync(path.join(RAW, 'hsa_retailers.csv'), 'utf8')).slice(1).filter(r => r.length >= 3 && r[0]);
const retailers = [];
const seenShops = new Set();
let noPostal = 0, noGeo = 0;
for (const [company, validity, address] of rows) {
  const postal = postalOf(address);
  if (!postal) { noPostal++; continue; }
  const g = geo[postal];
  if (!g || !inSingapore(g.lat, g.lng)) { noGeo++; continue; }
  const escaped = company.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const addr = address
    .replace(new RegExp('^' + escaped + ',?\\s*', 'i'), '')
    .replace(/,?\s*SINGAPORE\s*\(?\s*\d{6}\s*\)?\s*$/i, '')
    .replace(/\s*,\s*/g, ', ')
    .replace(/^,|,$/g, '')
    .trim();
  const unit = (addr.match(/#[\w-]+/) || [])[0] || '';
  const key = `${company}|${postal}|${unit}`;
  if (seenShops.has(key)) continue;
  seenShops.add(key);
  const { brand, category } = classifyShop(company);
  retailers.push(feature(`hsa-${postal}-${retailers.length}`, point(g.lng, g.lat), {
    name: brand || titleCase(company),
    licensee: brand ? titleCase(company) : null,
    address: (addr ? titleCase(addr) + ', ' : '') + `Singapore ${postal}`,
    postal,
    category,
    brand,
    building: g.bldg && g.bldg !== 'NIL' ? titleCase(g.bldg) : null,
    validity: validity || null,
  }));
}

/* ======================= output ======================= */

const byKey = (arr, f) => arr.reduce((acc, x) => ((acc[f(x)] = (acc[f(x)] || 0) + 1), acc), {});
log('build:');
emit('spots.geojson', { type: 'FeatureCollection', features: spots });
emit('zones.geojson', { type: 'FeatureCollection', features: zones });
emit('retailers.geojson', { type: 'FeatureCollection', features: retailers });

const dg = fs.existsSync(path.join(RAW, 'datagov_meta.json')) ? raw('datagov_meta.json') : {};
const osmStamp = raw('osm_zones.json').osm3s?.timestamp_osm_base ?? null;
const cag = readJSON(path.join(SOURCES, 'changi_dsa.json'));
const govSource = (key, fallbackName) => ({
  id: key,
  name: dg[key]?.name ?? fallbackName,
  publisher: dg[key]?.publisher ?? null,
  updated: dg[key]?.updated?.slice(0, 10) ?? null,
  url: dg[key]?.id ? `https://data.gov.sg/datasets/${dg[key].id}/view` : 'https://data.gov.sg',
  licence: 'Singapore Open Data Licence v1.0',
});
const meta = {
  generated: new Date().toISOString().slice(0, 10),
  sources: [
    govSource('nea_dsa', 'Designated Smoking Areas'),
    govSource('nea_nsz', 'No-Smoking Zones'),
    govSource('nparks', 'NParks No-Smoking Locations'),
    govSource('nea_hawker', 'Hawker Centres'),
    govSource('hsa', 'Listing of Licensed Tobacco Retailers'),
    { id: 'changi', name: 'Smoking areas at Changi Airport', publisher: 'Changi Airport Group', updated: cag._captured, url: cag._source, licence: 'Public web page, transcribed' },
    { id: 'osm', name: 'OpenStreetMap', publisher: 'OpenStreetMap contributors', updated: osmStamp?.slice(0, 10) ?? null, url: 'https://www.openstreetmap.org/copyright', licence: 'ODbL 1.0' },
    { id: 'onemap', name: 'OneMap geocoding', publisher: 'Singapore Land Authority', updated: null, url: 'https://www.onemap.gov.sg', licence: 'OneMap Terms of Use' },
  ],
  counts: {
    spots: byKey(spots, f => f.properties.source),
    zones: byKey(zones, f => `${f.properties.kind}`),
    retailers: byKey(retailers, f => f.properties.category),
  },
};
emit('meta.json', meta);

log(`  spots      ${JSON.stringify(meta.counts.spots)}`);
log(`  zones      ${JSON.stringify(meta.counts.zones)}  (${droppedDuplicate} OSM duplicates of official data dropped)`);
log(`  retailers  ${retailers.length} from ${rows.length} licence rows (no postal ${noPostal}, not geocoded ${noGeo})  ${JSON.stringify(meta.counts.retailers)}`);
