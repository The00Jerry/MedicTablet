'use strict';
// Gemeinsame DB-Logik der Web-App – spiegelt die serverseitige Lua-Logik
// (Versicherungsberechnung, Patientenakte, Preis-Snapshots) fuer dieselben mt_*-Tabellen.
const db = require('./db');
const perms = require('./permissions');

// ESX-Spalten der users-Tabelle (an eigene Struktur anpassen, wie im Script)
const USERCOL = { firstname: 'firstname', lastname: 'lastname', dob: 'dateofbirth', sex: 'sex', phone: 'phone_number' };

const TREATMENT_STATUS = new Set(['draft', 'ongoing', 'completed', 'cancelled', 'archived']);

function isoWeekKey(d = new Date()) {
  const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const dayNum = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - dayNum + 3);
  const firstThursday = new Date(Date.UTC(date.getUTCFullYear(), 0, 4));
  const week = 1 + Math.round(((date - firstThursday) / 86400000 - 3 + ((firstThursday.getUTCDay() + 6) % 7)) / 7);
  return date.getUTCFullYear() * 100 + week;
}

function clampInt(v, min, max) {
  v = Math.floor(Number(v) || 0);
  if (min != null && v < min) v = min;
  if (max != null && v > max) v = max;
  return v;
}

// ---------- Patient ----------
async function ensurePatient(identifier) {
  let rec = await db.single('SELECT * FROM mt_patient_records WHERE identifier = ?', [identifier]);
  if (rec) return rec;
  const u = await db.single(
    `SELECT identifier, \`${USERCOL.firstname}\` AS firstname, \`${USERCOL.lastname}\` AS lastname,
            \`${USERCOL.dob}\` AS dob, \`${USERCOL.sex}\` AS sex, \`${USERCOL.phone}\` AS phone
     FROM users WHERE identifier = ?`, [identifier]);
  if (!u) return null;
  const id = await db.insert(
    'INSERT INTO mt_patient_records (identifier, firstname, lastname, dateofbirth, sex, phone) VALUES (?,?,?,?,?,?)',
    [identifier, u.firstname || '', u.lastname || '', u.dob || '', u.sex || '', u.phone || '']);
  return db.single('SELECT * FROM mt_patient_records WHERE id = ?', [id]);
}

// ---------- Preisliste ----------
async function buildLines(canFn, items) {
  if (!Array.isArray(items) || items.length === 0) return { err: 'invalid_input' };
  const lines = [];
  let base = 0;
  for (const sel of items) {
    const code = String(sel.code || '');
    const qty = clampInt(sel.quantity || 1, 1, 999);
    const item = await db.single(
      'SELECT * FROM mt_pricelist_items WHERE code = ? AND active = 1 AND archived_at IS NULL', [code]);
    if (!item) return { err: 'invalid_input' };
    if (item.required_perm && !canFn(item.required_perm)) return { err: 'no_permission' };
    const lineTotal = item.price * qty;
    lines.push({ item_code: item.code, label: item.label, unit_price: item.price, quantity: qty, line_total: lineTotal });
    base += lineTotal;
  }
  return { lines, base };
}

// ---------- Versicherung ----------
async function weeklyReimbursed(identifier) {
  const s = await db.scalar(
    'SELECT COALESCE(SUM(amount),0) AS s FROM mt_insurance_reimbursements WHERE identifier = ? AND week_key = ?',
    [identifier, isoWeekKey()]);
  return Number(s) || 0;
}

async function currentWeekPaid(contract) {
  if (!contract) return false;
  const wk = isoWeekKey();
  if ((Number(contract.last_week_key) || 0) >= wk) return true;
  const p = await db.single('SELECT status FROM mt_insurance_premiums WHERE identifier = ? AND week_key = ?',
    [contract.identifier, wk]);
  return !!(p && p.status === 'paid');
}

async function isCovered(contract) {
  if (!contract) return { ok: false, reason: 'ins_none' };
  if (contract.status === 'cancelled') return { ok: false, reason: 'ins_none' };
  if (contract.status === 'paused') return { ok: false, reason: 'ins_paused' };
  if (contract.status === 'waiting') return { ok: false, reason: 'ins_waiting' };
  if (contract.waiting_until && new Date(contract.waiting_until) > new Date()) return { ok: false, reason: 'ins_waiting' };
  if (!(await currentWeekPaid(contract))) return { ok: false, reason: 'ins_charge_failed' };
  return { ok: true, reason: 'ok' };
}

async function insuranceCalc(identifier, base) {
  base = clampInt(base, 0);
  const snap = {
    base, tier_key: '', tier_label: '', pct: 0, covered: 0, cap_applied: 0,
    status_at_time: 'none', coverable: false, reason: 'ins_none',
    weekly_cap: 0, weekly_remaining: 0, max_per_invoice: 0,
  };
  const contract = await db.single('SELECT * FROM mt_insurance_contracts WHERE identifier = ?', [identifier]);
  if (!contract) return snap;
  const tier = await db.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', [contract.tier_id]);
  if (!tier) return snap;

  snap.tier_key = tier.tier_key; snap.tier_label = tier.label; snap.pct = tier.coverage_pct;
  snap.status_at_time = contract.status; snap.max_per_invoice = tier.max_per_invoice; snap.weekly_cap = tier.weekly_cap;

  const cov = await isCovered(contract);
  snap.coverable = cov.ok; snap.reason = cov.reason;

  let remaining = -1;
  if (tier.weekly_cap > 0) remaining = Math.max(0, tier.weekly_cap - (await weeklyReimbursed(identifier)));
  snap.weekly_remaining = remaining;

  if (!cov.ok) return snap;

  let raw = Math.floor((base * tier.coverage_pct) / 100);
  if (tier.max_per_invoice > 0) raw = Math.min(raw, tier.max_per_invoice);
  if (remaining >= 0) raw = Math.min(raw, remaining);
  raw = Math.min(raw, base);
  snap.covered = Math.max(0, raw);
  snap.cap_applied = remaining >= 0 ? remaining : 0;
  return snap;
}

async function contractView(identifier) {
  const contract = await db.single('SELECT * FROM mt_insurance_contracts WHERE identifier = ?', [identifier]);
  if (!contract) return { hasContract: false };
  const tier = await db.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', [contract.tier_id]);
  const cov = await isCovered(contract);
  return {
    hasContract: true, tier, status: contract.status, coverable: cov.ok, reason: cov.reason,
    started_at: contract.started_at, next_charge_at: contract.next_charge_at, last_charge_at: contract.last_charge_at,
    grace_until: contract.grace_until, waiting_until: contract.waiting_until,
    cancel_effective_at: contract.cancel_effective_at, failed_count: contract.failed_count,
    weekly_remaining: tier && tier.weekly_cap > 0 ? Math.max(0, tier.weekly_cap - (await weeklyReimbursed(identifier))) : -1,
  };
}

// ---------- Dashboard ----------
async function dashboardData() {
  const todayTreatments = await db.scalar("SELECT COUNT(*) AS c FROM mt_treatments WHERE DATE(created_at)=CURDATE()");
  const todayInvoices = await db.scalar("SELECT COUNT(*) AS c FROM mt_invoice_refs WHERE status='issued' AND DATE(created_at)=CURDATE()");
  const openTreatments = await db.query("SELECT id, treatment_no, staff_name, diagnosis, status, created_at FROM mt_treatments WHERE status IN ('draft','ongoing') ORDER BY created_at DESC LIMIT 10");
  const recentPatients = await db.query('SELECT identifier, firstname, lastname, last_treatment_at, updated_at FROM mt_patient_records ORDER BY updated_at DESC LIMIT 8');
  return {
    todayTreatments: Number(todayTreatments) || 0,
    todayInvoices: Number(todayInvoices) || 0,
    openTreatments, recentPatients,
  };
}

// ---------- Audit ----------
async function audit(user, e) {
  try {
    await db.insert(
      `INSERT INTO mt_audit_log (actor_identifier, actor_name, discord_id, category, action, target_type, target_id, old_value, new_value, reason, result)
       VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
      [user.identifier || '', user.name || '', user.discordId || '', e.category || 'default', e.action || 'unknown',
       e.target_type || '', String(e.target_id || ''),
       e.old != null ? JSON.stringify(e.old) : null, e.new != null ? JSON.stringify(e.new) : null,
       (e.reason || 'web'), e.result || 'ok']);
  } catch (err) { console.error('[panel] audit failed', err.message); }
}

function genTreatmentNo() {
  const d = new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
  return `BH-${ymd}-${String(Math.floor(Math.random() * 1000)).padStart(3, '0')}`;
}

module.exports = {
  isoWeekKey, clampInt, ensurePatient, buildLines, insuranceCalc, contractView,
  dashboardData, audit, genTreatmentNo, TREATMENT_STATUS, USERCOL, perms,
};
