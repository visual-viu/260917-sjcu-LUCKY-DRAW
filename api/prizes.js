const { sb, send } = require('./_supabase');
module.exports = async function handler(req, res) {
  if (req.method !== 'GET') return send(res, 405, { error: 'method_not_allowed' });
  try {
    const data = await sb('/rest/v1/prizes?select=id,name,total_qty,remaining_qty,display_order,is_active&is_active=eq.true&order=display_order.asc');
    return send(res, 200, data);
  } catch (e) {
    return send(res, 500, { error: 'prizes_failed', message: e.message });
  }
};
