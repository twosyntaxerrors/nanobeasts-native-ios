// The app sends each zone's exact bounding box (computed with MapKit, which this
// Worker can't reproduce precisely). Results are keyed by zone and box together,
// so every phone asking for the same zone shares one cached answer.
const STREETS =
  '^(primary|secondary|tertiary|residential|unclassified|living_street|pedestrian|primary_link|secondary_link|tertiary_link)$';
const OVERPASS = [
  'https://overpass-api.de/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

/// A zone is ~800 m across; anything far from that is rejected.
function parseBox(value) {
  const box = (value || '').split(',').map(Number);
  if (box.length !== 4 || box.some((v) => !Number.isFinite(v))) return null;
  const [south, west, north, east] = box;
  const latSpan = north - south;
  const lonSpan = east - west;
  if (south < -86 || north > 86 || west < -180 || east > 180) return null;
  if (latSpan < 0.002 || latSpan > 0.03 || lonSpan < 0.002 || lonSpan > 0.08) return null;
  return box;
}

async function queryOverpass([south, west, north, east]) {
  const query =
    `[out:json][timeout:25];way["highway"~"${STREETS}"]["access"!~"^(private|no)$"]` +
    `(${south},${west},${north},${east});out skel geom qt;`;
  // OpenStreetMap's public servers are often briefly busy: two passes, a beat apart.
  for (const endpoint of [...OVERPASS, ...OVERPASS]) {
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'Nanobeasts zone cache' },
        body: 'data=' + encodeURIComponent(query),
      });
      if (!response.ok) {
        await new Promise((resolve) => setTimeout(resolve, 1500));
        continue;
      }
      const result = await response.json();
      if (result.remark) continue; // Timed out: the list may be partial, so never store it.
      // ~1 m precision, each point stored as the change from the previous one:
      // [lat0, lon0, dLat1, dLon1, …] in units of 0.00001°. Tiny once gzipped.
      return result.elements
        .filter((e) => Array.isArray(e.geometry) && e.geometry.length > 1)
        .map((e) => {
          const out = [];
          let lat = 0;
          let lon = 0;
          e.geometry.forEach((p, i) => {
            const nextLat = Math.round(p.lat * 1e5);
            const nextLon = Math.round(p.lon * 1e5);
            out.push(i === 0 ? nextLat : nextLat - lat, i === 0 ? nextLon : nextLon - lon);
            lat = nextLat;
            lon = nextLon;
          });
          return out;
        });
    } catch {
      // Try the next server.
    }
  }
  return null;
}

// Stored gzipped (~2 KB a zone) and sent as-is; phones unzip it automatically.
const headers = {
  'Content-Type': 'application/json',
  'Content-Encoding': 'gzip',
  'Cache-Control': 'public, max-age=2592000',
  'Access-Control-Allow-Origin': '*',
};

const gzip = async (text) =>
  new Uint8Array(await new Response(new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer());
const reply = (body) => new Response(body, { headers, encodeBody: 'manual' });

export default {
  async fetch(request, env, ctx) {
    const match = new URL(request.url).pathname.match(/^\/zone-streets\/v2\/(-?\d+)_(-?\d+)_(-?\d+)\.json$/);
    if (!match || request.method !== 'GET') return new Response('Not found', { status: 404 });
    const url = new URL(request.url);
    const box = parseBox(url.searchParams.get('b'));
    if (!box) return new Response('Bad zone', { status: 400 });
    const id = `${match[1]}_${match[2]}_${match[3]}_${box.map((v) => v.toFixed(5)).join('_')}`;

    const key = `zone-streets/v2/${id}.json.gz`;
    const stored = await env.ASSETS.get(key);
    if (stored) return reply(stored.body);

    const ways = await queryOverpass(box);
    if (!ways) return new Response('Streets unavailable', { status: 503, headers: { 'Retry-After': '5' } });
    const body = await gzip(JSON.stringify({ ways }));
    ctx.waitUntil(env.ASSETS.put(key, body, { httpMetadata: { contentType: 'application/json', contentEncoding: 'gzip' } }));
    return reply(body);
  },
};
