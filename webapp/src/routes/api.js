'use strict';
// REST-API der Web-App. Alle Endpunkte hinter requireAuth; jede sensible Aktion
// zusaetzlich mit requirePerm (serverseitige Rechtepruefung).
const express = require('express');
const db = require('../db');
const M = require('../models');
const { requirePerm, can } = require('../auth');
const cfg = require('../config');

const router = express.Router();

// async-Handler mit einheitlichem Fehlerfang
const h = (fn) => (req, res) => Promise.resolve(fn(req, res)).catch((e) => {
  console.error('[panel] API-Fehler', req.method, req.path, e.message);
  res.status(500).json({ error: 'Serverfehler.' });
});
const canFn = (req) => (perm) => can(req, perm);
const USERCOL = M.USERCOL;

// ---- Identitaet ----
router.get('/me', h(async (req, res) => {
  res.json({
    identity: { name: req.user.name, avatar: req.user.avatar, role: req.user.role, discordId: req.user.discordId },
    perms: req.user.perms,
    branding: cfg.branding,
  });
}));

// ---- Dashboard ----
router.get('/dashboard', requirePerm('tablet.open'), h(async (req, res) => {
  res.json({ dashboard: await M.dashboardData() });
}));

// ---- Patientensuche ----
router.get('/patients', requirePerm('patient.search'), h(async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (!q) return res.json({ results: [], total: 0, page: 1 });
  const page = M.clampInt(req.query.page || 1, 1);
  const pageSize = M.clampInt(req.query.pageSize || 15, 1, 50);
  const offset = (page - 1) * pageSize;
  const like = `%${q}%`;
  const field = req.query.field || 'auto';

  let where, params;
  if (field === 'firstname') { where = `u.\`${USERCOL.firstname}\` LIKE ?`; params = [like]; }
  else if (field === 'lastname') { where = `u.\`${USERCOL.lastname}\` LIKE ?`; params = [like]; }
  else if (field === 'dob') { where = `u.\`${USERCOL.dob}\` LIKE ?`; params = [like]; }
  else if (field === 'phone') { where = `u.\`${USERCOL.phone}\` LIKE ?`; params = [like]; }
  else if (field === 'charid') { where = 'u.identifier LIKE ? OR pr.char_id = ?'; params = [like, Number(q) || -1]; }
  else {
    where = `u.\`${USERCOL.firstname}\` LIKE ? OR u.\`${USERCOL.lastname}\` LIKE ?
             OR CONCAT(u.\`${USERCOL.firstname}\`,' ',u.\`${USERCOL.lastname}\`) LIKE ?
             OR u.\`${USERCOL.phone}\` LIKE ? OR u.identifier LIKE ?`;
    params = [like, like, like, like, like];
  }
  const from = `FROM users u LEFT JOIN mt_patient_records pr ON pr.identifier = u.identifier WHERE (${where})`;
  const total = await db.scalar('SELECT COUNT(*) AS c ' + from, params);
  const results = await db.query(
    `SELECT u.identifier, u.\`${USERCOL.firstname}\` AS firstname, u.\`${USERCOL.lastname}\` AS lastname,
            u.\`${USERCOL.dob}\` AS dob, u.\`${USERCOL.phone}\` AS phone, pr.id AS record_id, pr.last_treatment_at
     ${from} ORDER BY u.\`${USERCOL.lastname}\`, u.\`${USERCOL.firstname}\` LIMIT ${pageSize} OFFSET ${offset}`, params);
  await M.audit(req.user, { action: 'patient.search', reason: q });
  res.json({ results, total: Number(total) || 0, page, pageSize });
}));

// ---- Akte oeffnen ----
router.get('/patient', requirePerm('patient.view'), h(async (req, res) => {
  const identifier = String(req.query.identifier || '');
  if (!identifier) return res.status(400).json({ error: 'invalid_input' });
  const rec = await M.ensurePatient(identifier);
  if (!rec) return res.status(404).json({ error: 'player_not_found' });
  const treatments = await db.query(
    `SELECT id, treatment_no, staff_name, diagnosis, status, amount_base, amount_insurance, amount_discount, amount_final, created_at
     FROM mt_treatments WHERE patient_id = ? AND (archived_at IS NULL OR status='archived') ORDER BY created_at DESC LIMIT 100`, [rec.id]);
  const invoices = await db.query(
    `SELECT id, invoice_no, reason, amount_base, insurance_amount, discount_amount, amount_final, status, provider, provider_invoice_id, created_at
     FROM mt_invoice_refs WHERE patient_id = ? ORDER BY created_at DESC LIMIT 100`, [rec.id]);
  const insurance = await M.contractView(identifier);
  rec.canInternal = can(req, 'notes.internal.view');
  await M.audit(req.user, { action: 'patient.open', target_type: 'patient', target_id: rec.id });
  res.json({ record: rec, treatments, invoices, insurance });
}));

router.put('/patient', requirePerm('patient.edit'), h(async (req, res) => {
  const rec = await db.single('SELECT * FROM mt_patient_records WHERE identifier = ?', [String(req.body.identifier || '')]);
  if (!rec) return res.status(404).json({ error: 'player_not_found' });
  const fields = ['blood_type', 'allergies', 'preconditions', 'medications', 'medical_notes', 'phone'];
  const sets = [], params = [], oldv = {}, newv = {};
  for (const f of fields) if (req.body[f] != null) { sets.push(`\`${f}\` = ?`); params.push(String(req.body[f]).slice(0, 2000)); oldv[f] = rec[f]; newv[f] = req.body[f]; }
  if (!sets.length) return res.status(400).json({ error: 'invalid_input' });
  params.push(rec.id);
  await db.update('UPDATE mt_patient_records SET ' + sets.join(', ') + ' WHERE id = ?', params);
  await M.audit(req.user, { action: 'patient.update', target_type: 'patient', target_id: rec.id, old: oldv, new: newv });
  res.json({ ok: true });
}));

router.get('/patient/notes', requirePerm('notes.internal.view'), h(async (req, res) => {
  const rec = await db.single('SELECT id FROM mt_patient_records WHERE identifier = ?', [String(req.query.identifier || '')]);
  if (!rec) return res.status(404).json({ error: 'player_not_found' });
  const notes = await db.query('SELECT id, author_name, body, created_at FROM mt_medical_notes WHERE patient_id = ? AND archived_at IS NULL ORDER BY created_at DESC LIMIT 100', [rec.id]);
  res.json({ notes });
}));

router.post('/patient/notes', requirePerm('notes.internal.view'), h(async (req, res) => {
  const rec = await db.single('SELECT id FROM mt_patient_records WHERE identifier = ?', [String(req.body.identifier || '')]);
  if (!rec) return res.status(404).json({ error: 'player_not_found' });
  const body = String(req.body.body || '').trim();
  if (!body) return res.status(400).json({ error: 'invalid_input' });
  const id = await db.insert('INSERT INTO mt_medical_notes (patient_id, author_identifier, author_name, body, sensitive) VALUES (?,?,?,?,1)',
    [rec.id, req.user.identifier, req.user.name, body.slice(0, 2000)]);
  await M.audit(req.user, { action: 'note.add', target_type: 'patient', target_id: rec.id });
  res.json({ ok: true, id });
}));

// ---- Behandlungen ----
async function resolveLines(req, data) {
  if (data.treatment_id) {
    const t = await db.single('SELECT * FROM mt_treatments WHERE id = ?', [Number(data.treatment_id)]);
    if (!t) return { err: 'invalid_input' };
    const items = await db.query('SELECT item_code, label, unit_price, quantity, line_total FROM mt_treatment_items WHERE treatment_id = ?', [t.id]);
    const base = items.reduce((a, l) => a + (l.line_total || 0), 0);
    return { lines: items, base, treatment: t };
  }
  const r = await M.buildLines(canFn(req), data.items || []);
  if (r.err) return { err: r.err };
  return { lines: r.lines, base: r.base };
}

router.get('/treatment', requirePerm('patient.view'), h(async (req, res) => {
  const t = await db.single('SELECT * FROM mt_treatments WHERE id = ?', [Number(req.query.id)]);
  if (!t) return res.status(404).json({ error: 'invalid_input' });
  if (!can(req, 'notes.internal.view')) t.internal_note = null;
  const items = await db.query('SELECT item_code, label, unit_price, quantity, line_total FROM mt_treatment_items WHERE treatment_id = ?', [t.id]);
  res.json({ treatment: t, items });
}));

router.post('/treatment', requirePerm('treatment.create'), h(async (req, res) => {
  const d = req.body || {};
  const rec = await M.ensurePatient(String(d.identifier || ''));
  if (!rec) return res.status(404).json({ error: 'player_not_found' });
  const r = await M.buildLines(canFn(req), d.items || []);
  if (r.err) return res.status(400).json({ error: r.err });
  const discount = M.clampInt(d.discount || 0, 0, r.base);
  if (discount > 0 && !can(req, 'discount.grant')) return res.status(403).json({ error: 'no_permission' });
  const snap = await M.insuranceCalc(rec.identifier, r.base);
  const final = Math.max(0, r.base - snap.covered - discount);
  let status = String(d.status || 'draft');
  if (!M.TREATMENT_STATUS.has(status)) status = 'draft';
  const internalNote = can(req, 'notes.internal.view') ? String(d.internal_note || '').slice(0, 2000) : '';
  const tno = M.genTreatmentNo();
  const tid = await db.insert(
    `INSERT INTO mt_treatments (treatment_no, patient_id, identifier, staff_identifier, staff_name, diagnosis, measures, medications, report, internal_note, amount_base, amount_insurance, amount_discount, amount_final, status)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    [tno, rec.id, rec.identifier, req.user.identifier, req.user.name, String(d.diagnosis || '').slice(0, 500),
     String(d.measures || '').slice(0, 2000), String(d.medications || '').slice(0, 2000), String(d.report || '').slice(0, 4000),
     internalNote, r.base, snap.covered, discount, final, status]);
  for (const l of r.lines) {
    await db.insert('INSERT INTO mt_treatment_items (treatment_id, item_code, label, unit_price, quantity, line_total) VALUES (?,?,?,?,?,?)',
      [tid, l.item_code, l.label, l.unit_price, l.quantity, l.line_total]);
  }
  await db.update('UPDATE mt_patient_records SET last_treatment_at = NOW() WHERE id = ?', [rec.id]);
  await M.audit(req.user, { action: 'treatment.create', target_type: 'treatment', target_id: tid, new: { no: tno, base: r.base, final } });
  res.json({ ok: true, id: tid, treatment_no: tno, insurance: snap, amount_base: r.base, amount_final: final });
}));

router.put('/treatment', requirePerm('treatment.edit'), h(async (req, res) => {
  const d = req.body || {};
  const t = await db.single('SELECT * FROM mt_treatments WHERE id = ?', [Number(d.id)]);
  if (!t) return res.status(404).json({ error: 'invalid_input' });
  const sets = [], params = [], oldv = {}, newv = {};
  for (const f of ['diagnosis', 'measures', 'medications', 'report', 'status']) {
    if (d[f] != null) {
      let v = String(d[f]);
      if (f === 'status' && !M.TREATMENT_STATUS.has(v)) v = t.status;
      sets.push(`\`${f}\` = ?`); params.push(v.slice(0, 4000)); oldv[f] = t[f]; newv[f] = v;
    }
  }
  if (d.internal_note != null && can(req, 'notes.internal.view')) { sets.push('internal_note = ?'); params.push(String(d.internal_note).slice(0, 2000)); }
  if (!sets.length) return res.status(400).json({ error: 'invalid_input' });
  params.push(t.id);
  await db.update('UPDATE mt_treatments SET ' + sets.join(', ') + ' WHERE id = ?', params);
  await M.audit(req.user, { action: 'treatment.update', target_type: 'treatment', target_id: t.id, old: oldv, new: newv });
  res.json({ ok: true });
}));

router.post('/treatment/archive', requirePerm('treatment.archive'), h(async (req, res) => {
  const t = await db.single('SELECT * FROM mt_treatments WHERE id = ?', [Number(req.body.id)]);
  if (!t) return res.status(404).json({ error: 'invalid_input' });
  await db.update("UPDATE mt_treatments SET status='archived', archived_at=NOW() WHERE id=?", [t.id]);
  await M.audit(req.user, { action: 'treatment.archive', target_type: 'treatment', target_id: t.id });
  res.json({ ok: true });
}));

// ---- Rechnungen: Vorschau + Warteschlange ----
router.post('/billing/preview', requirePerm('invoice.create'), h(async (req, res) => {
  const d = req.body || {};
  let identifier = String(d.identifier || '');
  const r = await resolveLines(req, d);
  if (r.err) return res.status(400).json({ error: r.err });
  if (r.treatment && r.treatment.identifier) identifier = r.treatment.identifier;
  if (!identifier) return res.status(400).json({ error: 'invalid_input' });
  if (r.base <= 0) return res.status(400).json({ error: 'invalid_amount' });
  const snap = await M.insuranceCalc(identifier, r.base);
  const discount = M.clampInt(d.discount || 0, 0, Math.max(0, r.base - snap.covered));
  if (discount > 0 && !can(req, 'discount.grant')) return res.status(403).json({ error: 'no_permission' });
  const final = Math.max(0, r.base - snap.covered - discount);
  res.json({
    lines: r.lines,
    display: {
      amount_base: r.base, insurance_name: snap.tier_label, insurance_key: snap.tier_key, insurance_pct: snap.pct,
      insurance_covered: snap.covered, insurance_status: snap.status_at_time, coverable: snap.coverable,
      reason_key: snap.reason, weekly_cap: snap.weekly_cap, weekly_remaining: snap.weekly_remaining,
      discount, amount_final: final,
    },
  });
}));

router.post('/billing/queue', requirePerm('invoice.create'), h(async (req, res) => {
  const d = req.body || {};
  const idem = String(d.idempotency_key || '');
  if (idem.length < 8) return res.status(400).json({ error: 'invalid_input' });
  let identifier = String(d.identifier || '');
  const r = await resolveLines(req, d);
  if (r.err) return res.status(400).json({ error: r.err });
  if (r.treatment && r.treatment.identifier) identifier = r.treatment.identifier;
  if (!identifier || r.base <= 0) return res.status(400).json({ error: 'invalid_amount' });
  if (M.clampInt(d.discount || 0, 0) > 0 && !can(req, 'discount.grant')) return res.status(403).json({ error: 'no_permission' });

  // Bereits in der Queue?
  const existing = await db.single('SELECT id, status, result_invoice_id, error FROM mt_invoice_queue WHERE idempotency_key = ?', [idem]);
  if (existing) return res.json({ ok: true, queued: true, id: existing.id, status: existing.status });

  const id = await db.insert(
    `INSERT INTO mt_invoice_queue (idempotency_key, identifier, treatment_id, items_json, discount, reason, actor_identifier, actor_name, actor_discord, actor_perms, status)
     VALUES (?,?,?,?,?,?,?,?,?,?, 'pending')`,
    [idem, identifier, d.treatment_id || null, d.treatment_id ? null : JSON.stringify(d.items || []),
     M.clampInt(d.discount || 0, 0), String(d.reason || '').slice(0, 200),
     req.user.identifier, req.user.name, req.user.discordId, JSON.stringify(req.user.perms)]);
  await M.audit(req.user, { action: 'invoice.queue', target_type: 'invoice_queue', target_id: id, new: { identifier } });
  res.json({ ok: true, queued: true, id, status: 'pending' });
}));

router.get('/billing/queue/:idem', requirePerm('invoice.create'), h(async (req, res) => {
  const row = await db.single('SELECT id, status, result_invoice_id, error FROM mt_invoice_queue WHERE idempotency_key = ?', [String(req.params.idem)]);
  if (!row) return res.status(404).json({ error: 'not_found' });
  let invoice = null;
  if (row.result_invoice_id) invoice = await db.single('SELECT invoice_no, amount_final, provider, provider_invoice_id FROM mt_invoice_refs WHERE id = ?', [row.result_invoice_id]);
  res.json({ status: row.status, error: row.error, invoice });
}));

// ---- Preisliste ----
router.get('/pricelist', requirePerm('pricelist.view'), h(async (req, res) => {
  const includeInactive = req.query.all === '1' && can(req, 'pricelist.edit');
  const categories = await db.query('SELECT * FROM mt_pricelist_categories WHERE archived_at IS NULL ORDER BY sort, label');
  let sql = 'SELECT * FROM mt_pricelist_items WHERE archived_at IS NULL' + (includeInactive ? '' : ' AND active = 1') + ' ORDER BY label';
  const items = await db.query(sql);
  res.json({ categories, items, canEdit: can(req, 'pricelist.edit') });
}));

router.post('/pricelist/item', requirePerm('pricelist.edit'), h(async (req, res) => {
  const d = req.body || {};
  const label = String(d.label || '').trim();
  if (!label) return res.status(400).json({ error: 'invalid_input' });
  const price = M.clampInt(d.price || 0, 0);
  const desc = String(d.description || '').slice(0, 500);
  const perm = String(d.required_perm || '');
  const catId = d.category_id ? Number(d.category_id) : null;
  if (d.id) {
    const old = await db.single('SELECT * FROM mt_pricelist_items WHERE id = ?', [Number(d.id)]);
    if (!old) return res.status(404).json({ error: 'invalid_input' });
    await db.update('UPDATE mt_pricelist_items SET label=?, description=?, category_id=?, price=?, required_perm=?, updated_by=? WHERE id=?',
      [label, desc, catId, price, perm, req.user.identifier, old.id]);
    await M.audit(req.user, { action: 'pricelist.update', category: 'settings', target_type: 'pricelist_item', target_id: old.id, old: { price: old.price }, new: { price } });
    return res.json({ ok: true });
  }
  let code = String(d.code || '').replace(/\s/g, '').toUpperCase() || ('ITEM' + (Date.now() % 100000));
  const id = await db.insert('INSERT INTO mt_pricelist_items (code,label,description,category_id,price,required_perm,created_by,updated_by) VALUES (?,?,?,?,?,?,?,?)',
    [code, label, desc, catId, price, perm, req.user.identifier, req.user.identifier]);
  await M.audit(req.user, { action: 'pricelist.create', category: 'settings', target_type: 'pricelist_item', target_id: id, new: { code, price } });
  res.json({ ok: true, id });
}));

router.post('/pricelist/item/:id/toggle', requirePerm('pricelist.edit'), h(async (req, res) => {
  const it = await db.single('SELECT * FROM mt_pricelist_items WHERE id = ?', [Number(req.params.id)]);
  if (!it) return res.status(404).json({ error: 'invalid_input' });
  const na = it.active === 1 ? 0 : 1;
  await db.update('UPDATE mt_pricelist_items SET active=?, updated_by=? WHERE id=?', [na, req.user.identifier, it.id]);
  await M.audit(req.user, { action: 'pricelist.toggle', category: 'settings', target_type: 'pricelist_item', target_id: it.id, new: { active: na } });
  res.json({ ok: true, active: na });
}));

router.post('/pricelist/item/:id/archive', requirePerm('pricelist.edit'), h(async (req, res) => {
  const it = await db.single('SELECT id FROM mt_pricelist_items WHERE id = ?', [Number(req.params.id)]);
  if (!it) return res.status(404).json({ error: 'invalid_input' });
  await db.update('UPDATE mt_pricelist_items SET archived_at=NOW(), active=0, updated_by=? WHERE id=?', [req.user.identifier, it.id]);
  await M.audit(req.user, { action: 'pricelist.archive', category: 'settings', target_type: 'pricelist_item', target_id: it.id });
  res.json({ ok: true });
}));

router.post('/pricelist/category', requirePerm('pricelist.edit'), h(async (req, res) => {
  const d = req.body || {};
  const label = String(d.label || '').trim();
  if (!label) return res.status(400).json({ error: 'invalid_input' });
  const sort = M.clampInt(d.sort || 0, 0);
  if (d.id) await db.update('UPDATE mt_pricelist_categories SET label=?, sort=? WHERE id=?', [label, sort, Number(d.id)]);
  else await db.insert('INSERT INTO mt_pricelist_categories (cat_key,label,sort) VALUES (?,?,?)', [String(d.cat_key || label.toLowerCase().replace(/\s/g, '_')), label, sort]);
  await M.audit(req.user, { action: 'pricelist.category.save', category: 'settings' });
  res.json({ ok: true });
}));

// ---- Versicherung ----
router.get('/insurance/tiers', requirePerm('insurance.patient.view'), h(async (req, res) => {
  const tiers = await db.query('SELECT * FROM mt_insurance_tiers ORDER BY weekly_premium ASC');
  res.json({ tiers, canManage: can(req, 'insurance.manage') });
}));

router.post('/insurance/tier/:id', requirePerm('insurance.manage'), h(async (req, res) => {
  const t = await db.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', [Number(req.params.id)]);
  if (!t) return res.status(404).json({ error: 'invalid_input' });
  const d = req.body || {};
  const numeric = ['weekly_premium', 'max_per_invoice', 'weekly_cap', 'min_term_days', 'cancel_notice_days', 'waiting_days'];
  const sets = [], params = [], oldv = {}, newv = {};
  for (const f of ['label', 'description', 'color', 'icon']) if (d[f] != null) { sets.push(`\`${f}\`=?`); params.push(String(d[f])); oldv[f] = t[f]; newv[f] = d[f]; }
  for (const f of numeric) if (d[f] != null) { const v = M.clampInt(d[f], 0); sets.push(`\`${f}\`=?`); params.push(v); oldv[f] = t[f]; newv[f] = v; }
  if (d.coverage_pct != null) { const v = M.clampInt(d.coverage_pct, 0, 100); sets.push('coverage_pct=?'); params.push(v); oldv.coverage_pct = t.coverage_pct; newv.coverage_pct = v; }
  if (d.active != null) { const v = (d.active === true || d.active === 1) ? 1 : 0; sets.push('active=?'); params.push(v); oldv.active = t.active; newv.active = v; }
  if (!sets.length) return res.status(400).json({ error: 'invalid_input' });
  params.push(t.id);
  await db.update('UPDATE mt_insurance_tiers SET ' + sets.join(', ') + ' WHERE id = ?', params);
  await M.audit(req.user, { action: 'insurance.tier.save', category: 'insurance', target_type: 'insurance_tier', target_id: t.id, old: oldv, new: newv });
  res.json({ ok: true });
}));

router.post('/insurance/contract/manage', requirePerm('insurance.manage'), h(async (req, res) => {
  const identifier = String(req.body.identifier || '');
  const action = String(req.body.action || '');
  const contract = await db.single('SELECT * FROM mt_insurance_contracts WHERE identifier = ?', [identifier]);
  if (!contract) return res.status(404).json({ error: 'ins_none' });
  if (action === 'pause') {
    await db.update("UPDATE mt_insurance_contracts SET status='paused', next_charge_at=NULL WHERE identifier=?", [identifier]);
  } else if (action === 'resume') {
    await db.update("UPDATE mt_insurance_contracts SET status='active', grace_until=NULL, failed_count=0 WHERE identifier=?", [identifier]);
  } else if (action === 'cancel') {
    await db.update("UPDATE mt_insurance_contracts SET status='cancelled', next_charge_at=NULL WHERE identifier=?", [identifier]);
  } else return res.status(400).json({ error: 'invalid_input' });
  await db.insert('INSERT INTO mt_insurance_changes (identifier, change_type, from_tier, to_tier, actor_identifier, reason) VALUES (?,?,?,?,?,?)',
    [identifier, action === 'resume' ? 'resume' : (action === 'cancel' ? 'cancel' : 'pause'), contract.tier_key, null, req.user.identifier, 'panel']);
  await M.audit(req.user, { action: 'insurance.manage.' + action, category: 'insurance', target_type: 'insurance', target_id: identifier });
  res.json({ ok: true, contract: await M.contractView(identifier) });
}));

router.get('/insurance/failed', requirePerm('insurance.failed.view'), h(async (req, res) => {
  const page = M.clampInt(req.query.page || 1, 1);
  const pageSize = M.clampInt(req.query.pageSize || 20, 1, 50);
  const offset = (page - 1) * pageSize;
  const total = await db.scalar("SELECT COUNT(*) AS c FROM mt_insurance_premiums WHERE status IN ('failed','grace')");
  const rows = await db.query(
    `SELECT id, identifier, tier_key, amount, week_key, status, attempts, last_error, scheduled_at
     FROM mt_insurance_premiums WHERE status IN ('failed','grace') ORDER BY scheduled_at DESC LIMIT ${pageSize} OFFSET ${offset}`);
  res.json({ rows, total: Number(total) || 0, page, pageSize });
}));

// ---- Staff / Audit ----
router.get('/staff', requirePerm('staff.view'), h(async (req, res) => {
  const activity = await db.query('SELECT actor_name, action, target_type, target_id, result, created_at FROM mt_audit_log ORDER BY id DESC LIMIT 30');
  res.json({ activity });
}));

router.get('/audit', requirePerm('audit.view'), h(async (req, res) => {
  const page = M.clampInt(req.query.page || 1, 1);
  const pageSize = M.clampInt(req.query.pageSize || 25, 1, 100);
  const offset = (page - 1) * pageSize;
  const cat = String(req.query.category || '');
  let where = '1=1', params = [];
  if (cat && cat !== 'all') { where = 'category = ?'; params = [cat]; }
  const total = await db.scalar('SELECT COUNT(*) AS c FROM mt_audit_log WHERE ' + where, params);
  const rows = await db.query(
    `SELECT id, actor_name, actor_identifier, category, action, target_type, target_id, result, reason, created_at
     FROM mt_audit_log WHERE ${where} ORDER BY id DESC LIMIT ${pageSize} OFFSET ${offset}`, params);
  res.json({ rows, total: Number(total) || 0, page, pageSize });
}));

module.exports = router;
