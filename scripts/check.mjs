// Sanity checks on the generated data. A bad rebuild here means someone standing in a park
// or on Orchard Road gets told they are fine, so the data job fails instead of shipping it.
import fs from 'node:fs';
import path from 'node:path';
import { OUT, readJSON, inSingapore, pointInGeometry } from './lib/util.mjs';

const load = f => readJSON(path.join(OUT, f));
const spots = load('spots.geojson').features;
const zones = load('zones.geojson').features;
const retailers = load('retailers.geojson').features;
const meta = load('meta.json');

let failed = 0;
const ok = (cond, label, detail = '') => {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${detail ? '  — ' + detail : ''}`);
  if (!cond) failed++;
};
const count = (arr, pred) => arr.filter(pred).length;
const src = s => f => f.properties.source === s;
const kind = k => f => f.properties.kind === k;
const latlng = f => ({ lng: f.geometry.coordinates[0], lat: f.geometry.coordinates[1] });

/* ---- shape ---- */
console.log('\nstructure');
ok(count(spots, src('nea')) >= 40, 'at least 40 NEA designated smoking areas', `${count(spots, src('nea'))}`);
ok(count(spots, src('changi')) >= 20, 'at least 20 Changi Airport smoking areas', `${count(spots, src('changi'))}`);
ok(count(spots, f => f.properties.source.startsWith('osm')) >= 30, 'at least 30 OpenStreetMap spots', `${count(spots, f => f.properties.source.startsWith('osm'))}`);
ok(spots.filter(src('changi')).every(f => f.properties.approx), 'every Changi pin is flagged approximate');
ok(spots.filter(src('changi')).every(f => { const p = latlng(f); return p.lat > 1.32 && p.lat < 1.38 && p.lng > 103.97 && p.lng < 104.01; }),
  'every Changi pin is on airport land');
ok(spots.filter(src('nea')).every(f => f.properties.photo), 'every NEA area carries its photo');
ok(new Set(spots.map(f => f.id)).size === spots.length, 'spot ids are unique');
ok(spots.every(f => f.properties.name), 'every spot has a name');
ok(spots.every(f => { const p = latlng(f); return inSingapore(p.lat, p.lng); }), 'every spot is in Singapore');

ok(retailers.length >= 3000, 'at least 3,000 licensed retailers', `${retailers.length}`);
ok(new Set(retailers.map(f => f.id)).size === retailers.length, 'retailer ids are unique');
ok(retailers.every(f => { const p = latlng(f); return inSingapore(p.lat, p.lng); }), 'every retailer is in Singapore');
ok(retailers.every(f => ['convenience', 'supermarket', 'minimart', 'petrol', 'kopitiam', 'other'].includes(f.properties.category)),
  'every retailer has a known category');

ok(count(zones, kind('nsz')) >= 1, 'Orchard Road No-Smoking Zone present');
ok(count(zones, src('nparks')) >= 300, 'at least 300 NParks no-smoking polygons', `${count(zones, src('nparks'))}`);
ok(count(zones, kind('bus_stop')) >= 4000, 'at least 4,000 bus stops', `${count(zones, kind('bus_stop'))}`);
ok(count(zones, kind('playground')) >= 1000, 'at least 1,000 playgrounds', `${count(zones, kind('playground'))}`);
ok(count(zones, kind('hawker')) >= 100, 'at least 100 hawker centres / food courts', `${count(zones, kind('hawker'))}`);
ok(count(zones, kind('school')) >= 300, 'at least 300 schools', `${count(zones, kind('school'))}`);
ok(new Set(zones.map(f => f.id)).size === zones.length, 'zone ids are unique');
ok(zones.every(f => ['Point', 'Polygon', 'MultiPolygon'].includes(f.geometry.type)), 'zone geometries are points or polygons');
ok(zones.every(f => f.geometry.type !== 'Point' || f.properties.buffer > 0), 'every point zone has a radius');

/* ---- the part that has consequences ---- */

// Metres between a point and a zone (0 inside), equirectangular around Singapore.
const KX = 111_320 * Math.cos(1.35 * Math.PI / 180), KY = 110_574;
function segDist(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
  const t = len2 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) : 0;
  return Math.hypot(ax + t * dx - px, ay + t * dy - py);
}
function distanceTo(lat, lng, g) {
  const px = lng * KX, py = lat * KY;
  if (g.type === 'Point') return Math.hypot(g.coordinates[0] * KX - px, g.coordinates[1] * KY - py);
  if (pointInGeometry([lng, lat], g)) return 0;
  const polys = g.type === 'Polygon' ? [g.coordinates] : g.coordinates;
  let best = Infinity;
  for (const poly of polys) for (const ring of poly) for (let i = 1; i < ring.length; i++) {
    best = Math.min(best, segDist(px, py, ring[i - 1][0] * KX, ring[i - 1][1] * KY, ring[i][0] * KX, ring[i][1] * KY));
  }
  return best;
}
const zonesAt = (lat, lng) => zones.filter(f => distanceTo(lat, lng, f.geometry) <= f.properties.buffer).map(f => f.properties.kind);

console.log('\nno-smoking detection');
const MUST = [
  ['ION Orchard', 1.30390, 103.83170, 'nsz'],
  ['Ngee Ann City', 1.30280, 103.83480, 'nsz'],
  ['Somerset MRT', 1.30030, 103.83900, 'nsz'],
  ['Botanic Gardens', 1.31380, 103.81590, 'park'],
  ['East Coast Park', 1.30100, 103.91200, 'park'],
  ['Bishan-AMK Park', 1.36230, 103.84680, 'park'],
  ['Labrador Park', 1.26620, 103.80230, 'park'],
];
for (const [name, lat, lng, want] of MUST) {
  const got = zonesAt(lat, lng);
  ok(got.includes(want), name.padEnd(20), `expected ${want}, got [${got.join(', ')}]`);
}
const MUST_NOT = [
  ['Raffles Place', 1.28400, 103.85150, ['nsz', 'park']],
  ['Jurong East MRT', 1.33330, 103.74220, ['nsz', 'park']],
  ['Woodlands Causeway', 1.44500, 103.76900, ['nsz', 'park']],
];
for (const [name, lat, lng, notWanted] of MUST_NOT) {
  const got = zonesAt(lat, lng);
  ok(!got.some(k => notWanted.includes(k)), name.padEnd(20), `must not be in [${notWanted.join(', ')}], got [${got.join(', ')}]`);
}

// Every NEA designated area sits inside the Orchard zone: that is the point of them, and the
// strongest end-to-end check that the two NEA datasets still agree.
const nsz = zones.filter(kind('nsz'));
const outside = spots.filter(src('nea')).filter(f => { const p = latlng(f); return !nsz.some(z => pointInGeometry([p.lng, p.lat], z.geometry)); });
console.log('\ncross-dataset agreement');
ok(outside.length === 0, 'every NEA designated area is inside the Orchard zone',
  outside.length ? outside.map(f => f.properties.name).join(', ') : `${count(spots, src('nea'))}/${count(spots, src('nea'))}`);

/* ---- weight ---- */
console.log('\nbundle size');
const size = f => fs.statSync(path.join(OUT, f)).size / 1024 / 1024;
const total = ['spots.geojson', 'zones.geojson', 'retailers.geojson', 'meta.json'].reduce((s, f) => s + size(f), 0);
ok(total < 12, 'bundled data under 12 MB', `${total.toFixed(1)} MB`);
ok(!!meta.generated, 'meta.json has a generation date', meta.generated);

console.log(failed ? `\n${failed} check(s) FAILED\n` : '\nall checks passed\n');
process.exit(failed ? 1 : 0);
