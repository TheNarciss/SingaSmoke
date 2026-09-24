// Downloads every raw source into data/raw/ (and refreshes data/sources/changi_dsa.json).
// Safe to re-run: each file is replaced only after a successful download.
//   node scripts/fetch.mjs            everything
//   node scripts/fetch.mjs datagov    only data.gov.sg
//   node scripts/fetch.mjs osm        only OpenStreetMap (or: zones, postcodes)
//   node scripts/fetch.mjs changi     only the Changi Airport page
import fs from 'node:fs';
import path from 'node:path';
import { RAW, SOURCES, log, sleep, writeJSON, dataGovDownload, dataGovMetadata, overpass, fetchRetry } from './lib/util.mjs';

fs.mkdirSync(RAW, { recursive: true });
const only = process.argv[2];
const want = part => !only || only === part;

/* ---------------- data.gov.sg ---------------- */

export const DATASETS = [
  { id: 'd_d0fa8f07ef80ab23feaa3b870323bf27', file: 'nea_dsa.geojson', key: 'nea_dsa', label: 'NEA Designated Smoking Areas' },
  { id: 'd_491641889c8add4c7835721bd72aa84a', file: 'nea_nsz.geojson', key: 'nea_nsz', label: 'NEA No-Smoking Zones' },
  { id: 'd_3c8343c1efaeb05d4d1dbcdd0f599077', file: 'nparks_nosmoking.geojson', key: 'nparks', label: 'NParks No-Smoking Locations' },
  { id: 'd_4a086da0a5553be1d89383cd90d07ecd', file: 'nea_hawker.geojson', key: 'nea_hawker', label: 'NEA Hawker Centres' },
  { id: 'd_c5822c4f3e210a3b0625e49b3faaac09', file: 'hsa_retailers.csv', key: 'hsa', label: 'HSA Licensed Tobacco Retailers' },
];

if (want('datagov')) {
  log('data.gov.sg:');
  const meta = {};
  for (const d of DATASETS) {
    const body = await dataGovDownload(d.id, d.label);
    fs.writeFileSync(path.join(RAW, d.file), body);
    await sleep(12_000);   // ~5 calls a minute without an API key
    const m = await dataGovMetadata(d.id);
    meta[d.key] = { id: d.id, name: m?.name ?? d.label, publisher: m?.managedBy ?? null, updated: m?.lastUpdatedAt ?? null };
    log(`  ${d.file.padEnd(26)} ${(body.length / 1024).toFixed(0).padStart(6)} KB  updated ${m?.lastUpdatedAt?.slice(0, 10) ?? '?'}`);
    await sleep(12_000);
  }
  writeJSON(path.join(RAW, 'datagov_meta.json'), meta);
}

/* ---------------- OpenStreetMap ---------------- */

const SG = 'area["ISO3166-1"="SG"][admin_level=2]->.sg;';

// Smoking spots. Contributors record the same thing several ways, so the net is wide;
// build.mjs sorts the catch into real smoking areas and venues with a smoking corner.
const SMOKING = `[out:json][timeout:300];${SG}
(
  nwr["amenity"="smoking_area"](area.sg);
  nwr["name"~"[Ss]moking"](area.sg);
  nwr["smoking"~"^(yes|outside|separated|isolated|designated|dedicated)$"](area.sg);
);
out center tags;`;

// Places where the Smoking (Prohibition in Certain Places) Regulations apply island-wide and
// that OSM maps well enough to test a GPS fix against. Indoor places, lift lobbies, covered
// walkways, overhead bridges and building entrances are NOT here: a phone cannot tell them
// apart from the pavement next to them, so the app states those rules in words instead.
// One query per family: the public Overpass server times out on the whole lot at once.
const ZONE_QUERIES = [
  ['bus stops', 'node["highway"="bus_stop"](area.sg);'],
  ['playgrounds, fitness corners', 'nwr["leisure"~"^(playground|fitness_station)$"](area.sg);'],
  ['sports courts', 'nwr["leisure"="pitch"](area.sg);'],
  ['parks, gardens', 'wr["leisure"="park"](area.sg); wr["leisure"="garden"]["name"](area.sg);'],
  ['beaches, reservoirs', 'wr["natural"="beach"](area.sg); wr["water"="reservoir"](area.sg); wr["landuse"="reservoir"](area.sg);'],
  ['hospitals, schools', 'nwr["amenity"~"^(hospital|school|kindergarten|childcare|college|university)$"](area.sg);'],
  ['hawkers, interchanges, stadiums, car parks',
    'nwr["amenity"~"^(food_court|marketplace|bus_station|ferry_terminal)$"](area.sg); nwr["leisure"~"^(stadium|sports_centre)$"](area.sg); nwr["amenity"="parking"]["parking"="multi-storey"](area.sg);'],
].map(([label, body]) => [label, `[out:json][timeout:600];${SG}\n(\n  ${body}\n);\nout geom qt;`]);

// Changi: terminal outlines and the boarding gates, to place CAG's worded locations.
const CHANGI = `[out:json][timeout:120];
(
  node["aeroway"="gate"](1.32,103.97,1.38,104.01);
  way["aeroway"="terminal"](1.32,103.97,1.38,104.01);
);
out center tags;`;

// Every postcode OSM knows: geocodes most of the HSA register in one request.
const POSTCODES = `[out:json][timeout:300];${SG}
(
  node["addr:postcode"](area.sg);
  way["addr:postcode"](area.sg);
);
out center tags;`;

const part = name => want('osm') || only === name;
if (part('zones') || part('postcodes')) {
  log('overpass:');
  const save = (file, json) => {
    fs.writeFileSync(path.join(RAW, file), JSON.stringify(json));
    log(`  ${file.padEnd(22)} ${String(json.elements.length).padStart(7)} elements  (OSM ${json.osm3s?.timestamp_osm_base ?? '?'})`);
  };
  if (want('osm')) {
    save('osm_smoking.json', await overpass(SMOKING, 'smoking spots'));
    save('osm_changi.json', await overpass(CHANGI, 'Changi gates'));
  }
  if (part('zones')) {
    const merged = { osm3s: null, elements: [] };
    const seen = new Set();
    for (const [label, query] of ZONE_QUERIES) {
      await sleep(5_000);
      const json = await overpass(query, label);
      merged.osm3s ??= json.osm3s;
      let added = 0;
      for (const e of json.elements) {
        const key = `${e.type}/${e.id}`;
        if (seen.has(key)) continue;
        seen.add(key);
        merged.elements.push(e);
        added++;
      }
      log(`    ${label.padEnd(44)} ${String(added).padStart(6)}`);
    }
    save('osm_zones.json', merged);
  }
  if (part('postcodes')) {
    await sleep(5_000);
    save('osm_postcodes.json', await overpass(POSTCODES, 'postcodes'));
  }
}

/* ---------------- Changi Airport Group ----------------
   CAG publishes its smoking areas on a web page, in words ("near Gate B10"), never as
   coordinates. The page embeds a schema.org list of Places; we read that. If the page ever
   changes shape the committed file stays as it was, and the build carries on with it. */

function parseChangi(html) {
  const places = [];
  const walk = o => {
    if (Array.isArray(o)) return o.forEach(walk);
    if (!o || typeof o !== 'object') return;
    if (o['@type'] === 'Place' && typeof o.address?.streetAddress === 'string') places.push(o.address.streetAddress);
    Object.values(o).forEach(walk);
  };
  for (const [, block] of html.matchAll(/<script[^>]*application\/ld\+json[^>]*>([\s\S]*?)<\/script>/g)) {
    try { walk(JSON.parse(block)); } catch { /* not JSON we understand */ }
  }
  const areas = [];
  for (const raw of places) {
    // "T3 Transit, Level 2, Departure Transit Hall North, Outdoor Smoking Area, (opposite Gate B10)"
    const m = raw.replace(/\s+/g, ' ').match(/^(T\d)\s+(Public|Transit)\s*,\s*Level\s*([\w]+)\s*,\s*(.+)$/i);
    if (!m) continue;
    const where = m[4]
      .replace(/,\s*\(/g, ' (')
      .replace(/\s*\(([^)]*)\)\s*$/, ' — $1')
      .replace(/’/g, "'")
      .trim();
    areas.push({ t: m[1].toUpperCase(), zone: m[2].toLowerCase() === 'transit' ? 'transit' : 'public', level: m[3], where });
  }
  return areas;
}

if (want('changi')) {
  const url = 'https://www.changiairport.com/en/at-changi/facilities-and-services-directory/smoking-areas.html';
  log('changi airport:');
  try {
    const html = await (await fetchRetry(url, { headers: { Accept: 'text/html' } }, { label: 'CAG page' })).text();
    const areas = parseChangi(html);
    if (areas.length >= 20) {
      writeJSON(path.join(SOURCES, 'changi_dsa.json'), {
        _source: url,
        _publisher: 'Changi Airport Group',
        _captured: new Date().toISOString().slice(0, 10),
        _note: 'Read from the schema.org Place list embedded in the CAG page by scripts/fetch.mjs. CAG gives locations in words only; build.mjs places each pin on the gate it names (OpenStreetMap) or on the terminal, and flags it approximate.',
        areas,
      });
      log(`  changi_dsa.json  ${areas.length} areas`);
    } else {
      log(`  only ${areas.length} areas parsed — keeping the committed data/sources/changi_dsa.json`);
    }
  } catch (e) {
    log(`  ${e.message} — keeping the committed data/sources/changi_dsa.json`);
  }
}

log('\nnext: node scripts/geocode.mjs && node scripts/build.mjs && node scripts/check.mjs');
