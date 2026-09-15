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
    } else if (action === 'add_prize') {
      const name = String(req.body?.name || '').trim();
      const totalQty = Number(req.body?.totalQty);
      if (!name || !Number.isFinite(totalQty) || totalQty < 0) return send(res, 400, { error: 'invalid_input' });
      const existing = await sb('/rest/v1/prizes?select=display_order&order=display_order.desc&limit=1', { service: true });
      const nextOrder = existing.length ? Number(existing[0].display_order) + 1 : 0;
      const id = `prize_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
      await sb('/rest/v1/prizes', {
        method: 'POST', service: true,
        body: { id, name, total_qty: totalQty, remaining_qty: totalQty, display_order: nextOrder, is_active: true },
      });
    } else if (action === 'update_prize') {
      const prizeId = String(req.body?.prizeId || '');
      if (!prizeId) return send(res, 400, { error: 'invalid_input' });
      const patch = {};
      if (typeof req.body?.name === 'string' && req.body.name.trim()) patch.name = req.body.name.trim();
      if (req.body?.totalQty !== undefined) {
        const totalQty = Number(req.body.totalQty);
        if (!Number.isFinite(totalQty) || totalQty < 0) return send(res, 400, { error: 'invalid_input' });
        patch.total_qty = totalQty;
        patch.remaining_qty = totalQty;
      }
      if (!Object.keys(patch).length) return send(res, 400, { error: 'invalid_input' });
      await sb(`/rest/v1/prizes?id=eq.${encodeURIComponent(prizeId)}`, { method: 'PATCH', service: true, body: patch });
    } else if (action === 'delete_prize') {
      const prizeId = String(req.body?.prizeId || '');
      if (!prizeId) return send(res, 400, { error: 'invalid_input' });
      await sb(`/rest/v1/prizes?id=eq.${encodeURIComponent(prizeId)}`, { method: 'DELETE', service: true });
    } else if (action !== 'snapshot') {
      return send(res, 400, { error: 'unknown_action' });
    }
    return send(res, 200, await snapshot());
  } catch (e) {
    return send(res, 500, { error: 'admin_failed', message: e.message });
  }
};
