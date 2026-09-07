const { sb, send } = require('./_supabase');

async function snapshot() {
  const [prizes, winners, drawLogs] = await Promise.all([
    sb('/rest/v1/prizes?select=id,name,total_qty,remaining_qty,display_order,is_active&order=display_order.asc', { service: true }),
    sb('/rest/v1/winners?select=id,name,prize_id,prize_name,won_at&order=won_at.desc', { service: true }),
    sb('/rest/v1/draw_logs?select=id', { service: true }),
  ]);
  return { prizes, winners, drawCount: Array.isArray(drawLogs) ? drawLogs.length : 0 };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
  const pin = String(req.body?.pin || '');
  const expected = process.env.ADMIN_PIN || '0919';
  if (pin !== expected) return send(res, 401, { error: 'invalid_pin' });

  const action = String(req.body?.action || 'snapshot');
  try {
    if (action === 'delete_winner') {
      await sb('/rest/v1/rpc/delete_winner', {
        method: 'POST', service: true,
        body: { p_winner_id: req.body?.winnerId, p_restore_stock: req.body?.restoreStock !== false },
      });
    } else if (action === 'adjust_stock') {
      await sb('/rest/v1/rpc/adjust_prize_stock', {
        method: 'POST', service: true,
        body: { p_prize_id: req.body?.prizeId, p_delta: Number(req.body?.delta || 0) },
      });
    } else if (action === 'reset') {
      await sb('/rest/v1/rpc/reset_lucky_draw', { method: 'POST', service: true, body: {} });
    } else if (action !== 'snapshot') {
      return send(res, 400, { error: 'unknown_action' });
    }
    return send(res, 200, await snapshot());
  } catch (e) {
    return send(res, 500, { error: 'admin_failed', message: e.message });
  }
};
