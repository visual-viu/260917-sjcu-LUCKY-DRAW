const { sb, send } = require('./_supabase');
module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
  const name = String(req.body?.name || '').trim();
  const prizeId = String(req.body?.prizeId || '').trim();
  if (!name || !prizeId) return send(res, 400, { error: 'invalid_input' });
  if (name.length > 40) return send(res, 400, { error: 'name_too_long' });
  try {
    const data = await sb('/rest/v1/rpc/register_winner', {
      method: 'POST',
      body: { p_name: name, p_prize_id: prizeId },
    });
    return send(res, 200, data);
  } catch (e) {
    return send(res, 500, { error: 'register_failed', message: e.message });
  }
};
