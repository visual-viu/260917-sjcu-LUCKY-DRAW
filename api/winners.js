const { sb, send } = require('./_supabase');
module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return send(res, 405, { error: 'method_not_allowed' });
  try {
    const data = await sb('/rest/v1/winners?select=id,name,prize_id,prize_name,won_at&order=won_at.desc');
    return send(res, 200, data);
  } catch (e) {
    return send(res, 500, { error: 'winners_failed', message: e.message });
  }
};
