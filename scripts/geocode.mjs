// Resolves every postal code in the HSA licence register to a lat/lng.
// In Singapore a postal code is one building, so the result is building-level.
//
//   1. OpenStreetMap: the bulk postcode table fetched by fetch.mjs (~70% of the register, no rate limit).
//   2. OneMap search (Singapore Land Authority, public endpoint, no key) for the rest. It throttles
//      hard (HTTP 429), so this pass is patient and caches every answer in
//      data/sources/geocache.json, which is committed: a re-run only asks for what is new.
//
// Failures are never cached, so re-running always resumes on what is left.
import fs from 'node:fs';
import path from 'node:path';
import { RAW, SOURCES, log, sleep, readJSON, writeJSON, parseCsv, postalOf, USER_AGENT } from './lib/util.mjs';

const CACHE = path.join(SOURCES, 'geocache.json');
const OUT = path.join(RAW, 'postal_latlng.json');

const rows = parseCsv(fs.readFileSync(path.join(RAW, 'hsa_retailers.csv'), 'utf8')).slice(1).filter(r => r.length >= 3 && r[0]);
const need = [...new Set(rows.map(r => postalOf(r[2])).filter(Boolean))];

/* ---- source 1: OpenStreetMap ---- */

const table = {};
const osmFile = path.join(RAW, 'osm_postcodes.json');
if (fs.existsSync(osmFile)) {
  for (const el of readJSON(osmFile).elements || []) {
    const p = String(el.tags?.['addr:postcode'] ?? '').trim();
    if (!/^\d{6}$/.test(p) || table[p]) continue;
    const lat = el.lat ?? el.center?.lat, lng = el.lon ?? el.center?.lon;
    if (lat == null || lng == null) continue;
    // addr:housename only: el.tags.name is whatever shop sits at that address.
    table[p] = { lat, lng, bldg: el.tags['addr:housename'] || null, src: 'osm' };
  }
}
const fromOsm = need.filter(p => table[p]).length;

/* ---- source 2: OneMap, cached ---- */

const cache = {};
if (fs.existsSync(CACHE)) for (const [k, v] of Object.entries(readJSON(CACHE))) if (v) cache[k] = v;
for (const [p, v] of Object.entries(cache)) if (!table[p]) table[p] = { ...v, src: 'onemap' };

const todo = need.filter(p => !table[p]);
log(`register: ${need.length} postal codes — ${fromOsm} from OSM, ${Object.keys(cache).length} cached from OneMap, ${todo.length} to look up`);

let hits = 0, misses = 0, throttled = 0, gaveUp = 0;

async function lookup(p) {
  for (let attempt = 0; attempt < 8; attempt++) {
    try {
      const res = await fetch(
        `https://www.onemap.gov.sg/api/common/elastic/search?searchVal=${p}&returnGeom=Y&getAddrDetails=Y&pageNum=1`,
        { headers: { Accept: 'application/json', 'User-Agent': USER_AGENT }, signal: AbortSignal.timeout(20_000) },
      );
      if (res.status === 429) { throttled++; await sleep(2500 + attempt * 1500); continue; }
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const j = await res.json();
      const hit = (j.results || []).find(x => x.POSTAL === p) || (j.results || [])[0];
      if (hit?.LATITUDE) {
        cache[p] = { lat: +hit.LATITUDE, lng: +hit.LONGITUDE, bldg: hit.BUILDING && hit.BUILDING !== 'NIL' ? hit.BUILDING : null };
        table[p] = { ...cache[p], src: 'onemap' };
        hits++;
      } else misses++;
      return;
    } catch {
      await sleep(900 * (attempt + 1));
    }
  }
  gaveUp++;
}

const save = () => {
  const sorted = Object.fromEntries(Object.entries(cache).sort(([a], [b]) => a.localeCompare(b)));
  fs.writeFileSync(CACHE, JSON.stringify(sorted, null, 0).replace(/},"/g, '},\n"'));
  writeJSON(OUT, table);
};

save();
for (let i = 0; i < todo.length; i++) {
  await lookup(todo[i]);
  await sleep(700);
  if ((i + 1) % 50 === 0) {
    save();
    log(`  ${i + 1}/${todo.length}  hits=${hits} miss=${misses} 429=${throttled} gaveup=${gaveUp}`);
  }
}
save();

const got = need.filter(p => table[p]).length;
log(`resolved ${got}/${need.length} postal codes (${(got / need.length * 100).toFixed(1)}%)` +
  (gaveUp ? ` — ${gaveUp} hit the throttle, re-run to retry them` : ''));
