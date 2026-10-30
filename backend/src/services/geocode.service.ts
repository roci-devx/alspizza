import { config } from '../config.js';

export interface GeoResult {
  label: string;
  line1: string;
  city: string;
  state: string;
  zip: string;
  lat: number;
  lng: number;
}

const cache = new Map<string, { at: number; value: GeoResult[] }>();
const TTL = 1000 * 60 * 60 * 6;

// Nominatim's usage policy allows ~1 request/second; serialize calls.
let queue: Promise<unknown> = Promise.resolve();
function throttled<T>(fn: () => Promise<T>): Promise<T> {
  const run = queue.then(fn, fn);
  queue = run.then(
    () => new Promise((r) => setTimeout(r, 1100)),
    () => new Promise((r) => setTimeout(r, 1100)),
  );
  return run;
}

interface GoogleResult {
  formatted_address: string;
  geometry: { location: { lat: number; lng: number } };
  address_components: { long_name: string; short_name: string; types: string[] }[];
}

function fromGoogle(r: GoogleResult): GeoResult {
  const part = (type: string, short = false) => {
    const c = r.address_components.find((a) => a.types.includes(type));
    return (short ? c?.short_name : c?.long_name) ?? '';
  };
  const street = [part('street_number'), part('route')].filter(Boolean).join(' ');
  return {
    label: r.formatted_address.replace(/, USA$/, ''),
    line1: street || r.formatted_address.split(',')[0]!,
    city: part('locality') || part('sublocality') || part('postal_town'),
    state: part('administrative_area_level_1', true),
    zip: part('postal_code'),
    lat: r.geometry.location.lat,
    lng: r.geometry.location.lng,
  };
}

interface NominatimResult {
  lat: string;
  lon: string;
  display_name: string;
  address?: Record<string, string>;
}

function fromNominatim(r: NominatimResult): GeoResult {
  const a = r.address ?? {};
  const street = [a.house_number, a.road].filter(Boolean).join(' ');
  const city = a.city ?? a.town ?? a.village ?? a.hamlet ?? a.suburb ?? '';
  const state = a['ISO3166-2-lvl4']?.replace(/^US-/, '') ?? a.state ?? '';
  return {
    label: [street, city, state].filter(Boolean).join(', ') + (a.postcode ? ` ${a.postcode}` : ''),
    line1: street || r.display_name.split(',')[0]!,
    city,
    state,
    zip: a.postcode ?? '',
    lat: Number(r.lat),
    lng: Number(r.lon),
  };
}

const userAgent = () => `AlsPizzaApp/1.0 (${config.nominatimEmail || 'dev@alspizza.local'})`;

export async function searchAddress(query: string, near?: { lat: number; lng: number }): Promise<GeoResult[]> {
  const q = query.trim();
  if (q.length < 4) return [];
  const key = `${q.toLowerCase()}|${near ? `${near.lat.toFixed(2)},${near.lng.toFixed(2)}` : ''}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < TTL) return hit.value;

  let results: GeoResult[] = [];
  try {
    if (config.google.mapsKey) {
      const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
      url.searchParams.set('address', q);
      url.searchParams.set('components', 'country:US');
      if (near) url.searchParams.set('bounds', `${near.lat - 0.3},${near.lng - 0.3}|${near.lat + 0.3},${near.lng + 0.3}`);
      url.searchParams.set('key', config.google.mapsKey);
      const res = await fetch(url);
      const data = (await res.json()) as { results?: GoogleResult[] };
      results = (data.results ?? []).slice(0, 5).map(fromGoogle);
    } else {
      results = await throttled(async () => {
        const url = new URL('https://nominatim.openstreetmap.org/search');
        url.searchParams.set('format', 'jsonv2');
        url.searchParams.set('addressdetails', '1');
        url.searchParams.set('limit', '5');
        url.searchParams.set('countrycodes', 'us');
        url.searchParams.set('q', q);
        if (near) url.searchParams.set('viewbox', `${near.lng - 0.4},${near.lat + 0.4},${near.lng + 0.4},${near.lat - 0.4}`);
        const res = await fetch(url, { headers: { 'User-Agent': userAgent(), 'Accept-Language': 'en' } });
        if (!res.ok) return [];
        return ((await res.json()) as NominatimResult[]).map(fromNominatim);
      });
    }
  } catch (err) {
    console.warn('[geo] search failed', err);
  }
  results = results.filter((r) => r.lat && r.lng);
  cache.set(key, { at: Date.now(), value: results });
  return results;
}

export async function reverseGeocode(lat: number, lng: number): Promise<GeoResult | null> {
  try {
    if (config.google.mapsKey) {
      const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
      url.searchParams.set('latlng', `${lat},${lng}`);
      url.searchParams.set('key', config.google.mapsKey);
      const data = (await (await fetch(url)).json()) as { results?: GoogleResult[] };
      return data.results?.[0] ? { ...fromGoogle(data.results[0]), lat, lng } : null;
    }
    return await throttled(async () => {
      const url = new URL('https://nominatim.openstreetmap.org/reverse');
      url.searchParams.set('format', 'jsonv2');
      url.searchParams.set('addressdetails', '1');
      url.searchParams.set('lat', String(lat));
      url.searchParams.set('lon', String(lng));
      const res = await fetch(url, { headers: { 'User-Agent': userAgent(), 'Accept-Language': 'en' } });
      if (!res.ok) return null;
      const r = (await res.json()) as NominatimResult;
      return r?.lat ? { ...fromNominatim(r), lat, lng } : null;
    });
  } catch (err) {
    console.warn('[geo] reverse failed', err);
    return null;
  }
}
