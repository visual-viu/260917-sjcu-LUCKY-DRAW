const SUPABASE_URL = process.env.SUPABASE_URL;
const ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

function ensureEnv() {
  if (!SUPABASE_URL || !ANON_KEY || !SERVICE_KEY) {
    throw new Error('Supabase environment variables are missing');
  }
}

async function sb(path, { method = 'GET', body, service = false, extraHeaders = {} } = {}) {
  ensureEnv();
  const key = service ? SERVICE_KEY : ANON_KEY;
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...extraHeaders,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data = null;
  if (text) {
    try { data = JSON.parse(text); } catch { data = text; }
  }
  if (!res.ok) {
    const err = new Error(typeof data === 'object' && data?.message ? data.message : `Supabase ${res.status}`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function send(res, status, body) {
  res.status(status).setHeader('Cache-Control', 'no-store').json(body);
}

module.exports = { sb, send };
