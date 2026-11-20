/** Cloudflare Worker proxy for MET Norway Locationforecast. */
function expiry(headers, now) {
  const control = headers.get('Cache-Control') || '';
  if (/\bno-cache\b/i.test(control)) return now;
  const maxAge = control.match(/(?:^|,)\s*(?:s-maxage|max-age)\s*=\s*"?(\d+)/i);
  if (maxAge) return now + Math.max(0, Number(maxAge[1]) - Number(headers.get('Age') || 0)) * 1000;
  const expires = Date.parse(headers.get('Expires') || '');
  return Number.isFinite(expires) ? expires : now;
}

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'GET') return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET' } });
    const contact = env.MET_CONTACT;
    if (!contact || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contact)) return new Response('MET_CONTACT must contain the developer contact email', { status: 503 });
    const url = new URL(request.url);
    const latitude = url.searchParams.get('lat');
    const longitude = url.searchParams.get('lon');
    const lat = Number(latitude), lon = Number(longitude);
    if (latitude === null || longitude === null || !latitude.trim() || !longitude.trim() || !Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return new Response('Invalid coordinates', { status: 400 });
    const upstream = new URL('https://api.met.no/weatherapi/locationforecast/2.0/compact');
    upstream.searchParams.set('lat', lat.toFixed(4));
    upstream.searchParams.set('lon', lon.toFixed(4));
    const key = new Request(upstream.toString());
    const cache = caches.default;
    const cached = await cache.match(key);
    const now = Date.now();
    function clientResponse(entry) {
      const headers = new Headers(entry.headers);
      const originalControl = headers.get('X-Atmos-Cache-Control');
      const originalExpires = headers.get('X-Atmos-Expires');
      headers.delete('X-Atmos-Fresh-Until');
      headers.delete('X-Atmos-Cache-Control');
      headers.delete('X-Atmos-Expires');
      headers.delete('Cache-Control');
      headers.delete('Expires');
      if (originalControl) headers.set('Cache-Control', originalControl);
      if (originalExpires) headers.set('Expires', originalExpires);
      return new Response(entry.body, { status: 200, headers });
    }
    if (cached && now < Number(cached.headers.get('X-Atmos-Fresh-Until'))) return clientResponse(cached);
    const headers = new Headers({ 'User-Agent': `Atmos/1.0 (contact: ${contact})`, Accept: 'application/json' });
    if (cached?.headers.has('Last-Modified')) headers.set('If-Modified-Since', cached.headers.get('Last-Modified'));
    let response;
    try { response = await fetch(upstream, { headers }); }
    catch { return new Response('Weather service unavailable', { status: 502 }); }
    if (response.status === 304 && cached) {
      const combined = new Headers(cached.headers);
      for (const name of ['Cache-Control', 'Expires', 'Last-Modified', 'Date', 'Age']) {
        if (response.headers.has(name)) combined.set(name, response.headers.get(name));
      }
      // Restore the origin policy before calculating the new freshness lifetime.
      if (!response.headers.has('Cache-Control')) {
        const original = cached.headers.get('X-Atmos-Cache-Control');
        if (original) combined.set('Cache-Control', original); else combined.delete('Cache-Control');
      }
      if (!response.headers.has('Expires')) {
        const original = cached.headers.get('X-Atmos-Expires');
        if (original) combined.set('Expires', original); else combined.delete('Expires');
      }
      combined.delete('X-Atmos-Fresh-Until');
      combined.delete('X-Atmos-Cache-Control');
      combined.delete('X-Atmos-Expires');
      response = new Response(cached.body, { status: 200, headers: combined });
    }
    if (!response.ok) {
      const errorHeaders = new Headers();
      if (response.headers.has('Retry-After')) errorHeaders.set('Retry-After', response.headers.get('Retry-After'));
      return new Response('Weather service returned an error', { status: response.status, headers: errorHeaders });
    }
    const originHeaders = new Headers(response.headers);
    const result = new Response(response.body, { status: 200, headers: originHeaders });
    const policy = originHeaders.get('Cache-Control') || '';
    if (!/\b(no-store|private)\b/i.test(policy)) {
      const storedHeaders = new Headers(originHeaders);
      storedHeaders.set('X-Atmos-Fresh-Until', String(expiry(originHeaders, now)));
      if (policy) storedHeaders.set('X-Atmos-Cache-Control', policy); else storedHeaders.delete('X-Atmos-Cache-Control');
      if (originHeaders.has('Expires')) storedHeaders.set('X-Atmos-Expires', originHeaders.get('Expires')); else storedHeaders.delete('X-Atmos-Expires');
      // Retain validators beyond freshness for revalidation; never serve stale entries.
      storedHeaders.set('Cache-Control', 'public, max-age=604800');
      storedHeaders.delete('Expires');
      ctx.waitUntil(cache.put(key, new Response(result.clone().body, { headers: storedHeaders })).catch(() => {}));
    }
    return result;
  }
};
