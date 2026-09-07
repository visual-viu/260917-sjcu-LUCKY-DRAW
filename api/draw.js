const { sb, send } = require('./_supabase');
module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
  try {
    const data = await sb('/rest/v1/rpc/draw_lucky_prize', { method: 'POST', body: {} });
    return send(res, 200, data);
  } catch (e) {
    return send(res, 500, { error: 'draw_failed', message: e.message });
  }
};
