/* SunLife Medic-Panel – Web-Frontend (Vanilla JS, REST gegen /api).
   Rechnungen laufen ueber die Warteschlange -> FiveM-Server erstellt sie via CodeM. */
(function () {
  'use strict';
  const $ = (s, r) => (r || document).querySelector(s);
  const el = (t, c, h) => { const e = document.createElement(t); if (c) e.className = c; if (h != null) e.innerHTML = h; return e; };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (v) => '$' + (Math.floor(Number(v) || 0)).toLocaleString('de-DE');
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'id-' + Date.now() + '-' + Math.random().toString(16).slice(2));
  const badge = (s) => `<span class="mt-badge b-${esc(s)}">${esc(s)}</span>`;
  const fmtDate = (s) => { if (!s) return '-'; const d = new Date(s); return isNaN(d) ? esc(String(s).slice(0, 16)) : d.toLocaleString('de-DE', { dateStyle: 'short', timeStyle: 'short' }); };

  const ERR = {
    no_permission: 'Fehlende Berechtigung.', invalid_input: 'Ungültige Eingabe.', invalid_amount: 'Ungültiger Betrag.',
    player_not_found: 'Spieler/Charakter nicht gefunden.', invoice_duplicate: 'Rechnung existiert bereits.',
    ins_none: 'Keine aktive Versicherung', ins_waiting: 'In Wartezeit', ins_paused: 'Pausiert',
    ins_charge_failed: 'Wochenbeitrag nicht bezahlt', ok: 'aktiv', not_found: 'Nicht gefunden.',
    billing_down: 'Rechnungssystem nicht bereit.', invoice_failed: 'Rechnung fehlgeschlagen.', patient_offline: 'Patient nicht online.'
  };
  const errText = (r) => ERR[r && r.data && r.data.error] || (r && r.data && r.data.error) || 'Fehler.';

  // ---- REST ----
  async function req(method, path, body) {
    const opt = { method, headers: {}, credentials: 'same-origin' };
    if (body) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
    let r;
    try { r = await fetch('/api' + path, opt); } catch (e) { return { ok: false, data: { error: 'Netzwerkfehler' } }; }
    if (r.status === 401) { location.href = '/login.html'; return { ok: false, data: {} }; }
    let data = {}; try { data = await r.json(); } catch (e) {}
    return { ok: r.ok, status: r.status, data };
  }
  const apiGet = (p, params) => req('GET', p + (params ? '?' + new URLSearchParams(params) : ''));
  const apiPost = (p, b) => req('POST', p, b || {});
  const apiPut = (p, b) => req('PUT', p, b || {});

  // ---- State ----
  const S = { branding: {}, perms: {}, identity: {}, view: 'dashboard', patient: null, pricelist: null, invoiceIdem: null };
  const can = (p) => !!(S.perms['admin.full'] || S.perms[p]);

  // ---- Toast / Modal ----
  function toast(msg, level) { const t = el('div', 'mt-toast ' + (level || ''), esc(msg)); $('#mt-toasts').appendChild(t); setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 200); }, 3400); }
  function modal(title, body, actions) {
    const box = $('#mt-modal-box');
    box.innerHTML = `<h2>${esc(title)}</h2><div id="mt-modal-content">${body}</div><div class="mt-modal-actions" id="mt-modal-actions"></div>`;
    (actions || [{ label: 'Schließen', cls: 'ghost', fn: closeModal }]).forEach(a => { const b = el('button', 'mt-btn ' + (a.cls || ''), esc(a.label)); b.onclick = () => a.fn && a.fn(); $('#mt-modal-actions').appendChild(b); });
    $('#mt-modal').classList.remove('mt-hidden'); return box;
  }
  const closeModal = () => $('#mt-modal').classList.add('mt-hidden');
  function confirmDialog(title, html, onYes, yesLabel) {
    modal(title, html, [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: yesLabel || 'Bestätigen', cls: 'primary', fn: () => { closeModal(); onYes(); } }]);
  }

  // ---- Branding / Nav ----
  function applyBranding() {
    const b = S.branding || {}, root = document.documentElement;
    if (b.colorPrimary) root.style.setProperty('--primary', b.colorPrimary);
    if (b.colorAccent) root.style.setProperty('--accent', b.colorAccent);
    if ((b.theme || 'dark') === 'light') root.classList.add('mt-light'); else root.classList.remove('mt-light');
    $('#mt-clinic').textContent = b.clinicName || 'Medical Center';
    $('#mt-server').textContent = b.serverName || 'SunLife Roleplay';
  }
  const NAV = [
    { id: 'dashboard', label: 'Dashboard', ico: '▤', perm: 'tablet.open' },
    { id: 'search', label: 'Patienten', ico: '⚇', perm: 'patient.search' },
    { id: 'pricelist', label: 'Preisliste', ico: '≣', perm: 'pricelist.view' },
    { id: 'insurance', label: 'Versicherung', ico: '◆', perm: 'insurance.patient.view' },
    { id: 'staff', label: 'Mitarbeiter', ico: '☰', perm: 'staff.view' },
    { id: 'logs', label: 'Protokolle', ico: '☷', perm: 'audit.view' },
  ];
  function buildNav() {
    const nav = $('#mt-nav'); nav.innerHTML = '';
    NAV.forEach(n => { if (n.perm && !can(n.perm)) return; const b = el('button', S.view === n.id ? 'active' : '', `<span class="ico">${n.ico}</span>${esc(n.label)}`); b.onclick = () => { closeSidebar(); go(n.id); }; nav.appendChild(b); });
  }
  const go = (v) => { S.view = v; buildNav(); render(); };
  function closeSidebar() { $('#mt-sidebar').classList.remove('open'); const s = $('#mt-scrim'); if (s) s.classList.remove('show'); }

  const TITLES = { dashboard: 'Dashboard', search: 'Patientensuche', record: 'Patientenakte', pricelist: 'Preisliste', insurance: 'Krankenversicherung', staff: 'Mitarbeiter', logs: 'Protokolle' };
  const setLoading = () => ($('#mt-content').innerHTML = '<div class="mt-spinner"></div>');
  function render() {
    $('#mt-view-title').textContent = TITLES[S.view] || '';
    $('#mt-top-actions').innerHTML = '';
    ({ dashboard: renderDashboard, search: renderSearch, record: renderRecord, pricelist: renderPricelist, insurance: renderInsurance, staff: renderStaff, logs: renderLogs }[S.view] || renderDashboard)();
  }

  // ---- helpers ----
  function tableWrap(head, rows) { return `<div class="mt-table-wrap"><table class="mt-table"><thead><tr>${head.map(h => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${Array.isArray(rows) ? rows.join('') : rows}</tbody></table></div>`; }
  const emptyRow = (m) => `<div class="mt-empty">${esc(m || 'Keine Daten.')}</div>`;
  const listOrEmpty = (a) => a.length ? a.join('') : emptyRow();
  function addTopBtn(l, c, fn) { const b = el('button', 'mt-btn ' + c, esc(l)); b.onclick = fn; $('#mt-top-actions').appendChild(b); }
  const statCard = (l, v, i) => `<div class="mt-card mt-stat"><span class="ico">${i}</span><span class="val">${esc(v)}</span><span class="lbl">${esc(l)}</span></div>`;
  let pagerSeq = 0;
  function pager(st, fn) {
    const pages = Math.max(1, Math.ceil((st.total || 0) / (st.pageSize || 15))); if (pages <= 1) return '';
    const name = '__pg' + (++pagerSeq); window[name] = (p) => fn(p);
    return `<div class="mt-pager"><button class="mt-btn ghost" ${st.page <= 1 ? 'disabled' : ''} onclick="${name}(${st.page - 1})">←</button> Seite ${st.page} / ${pages} <button class="mt-btn ghost" ${st.page >= pages ? 'disabled' : ''} onclick="${name}(${st.page + 1})">→</button></div>`;
  }
  const REASONS = ERR;

  // ================= DASHBOARD =================
  async function renderDashboard() {
    $('#mt-top-actions').innerHTML = ''; setLoading();
    const r = await apiGet('/dashboard');
    if (!r.ok) return ($('#mt-content').innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    const d = r.data.dashboard || {};
    $('#mt-content').innerHTML = `
      <div class="mt-grid mt-cols-4 mt-mb">
        ${statCard('Behandlungen heute', d.todayTreatments || 0, '✚')}
        ${statCard('Rechnungen heute', d.todayInvoices || 0, '$')}
        ${statCard('Offene Behandlungen', (d.openTreatments || []).length, '◷')}
        ${statCard('Zuletzt aktualisiert', (d.recentPatients || []).length, '⚇')}
      </div>
      <div class="mt-grid mt-cols-2">
        <div class="mt-card"><h3>Zuletzt bearbeitete Akten</h3>${listOrEmpty((d.recentPatients || []).map(p => `<div class="mt-kv" data-open="${esc(p.identifier)}" style="cursor:pointer"><span>${esc(p.firstname)} ${esc(p.lastname)}</span><span>${fmtDate(p.last_treatment_at)}</span></div>`))}</div>
        <div class="mt-card"><h3>Offene Behandlungen</h3>${listOrEmpty((d.openTreatments || []).map(t => `<div class="mt-kv"><span>${esc(t.treatment_no)} · ${esc(t.diagnosis || '')}</span><span>${badge(t.status)}</span></div>`))}</div>
      </div>`;
    $('#mt-content').querySelectorAll('[data-open]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-open')));
    if (can('patient.search')) addTopBtn('Patientensuche', 'primary', () => go('search'));
  }

  // ================= SEARCH =================
  let searchState = { q: '', field: 'auto', page: 1, total: 0, pageSize: 15 };
  function renderSearch() {
    $('#mt-content').innerHTML = `
      <div class="mt-searchbar">
        <input id="s-q" placeholder="Name, Geburtsdatum, Telefon, Charakter-ID…" value="${esc(searchState.q)}"/>
        <select id="s-field"><option value="auto">Alle Felder</option><option value="firstname">Vorname</option><option value="lastname">Nachname</option><option value="dob">Geburtsdatum</option><option value="phone">Telefon</option><option value="charid">Charakter-ID</option></select>
        <button class="mt-btn primary" id="s-go">Suchen</button>
      </div><div id="s-results"></div>`;
    $('#s-field').value = searchState.field; $('#s-go').onclick = () => doSearch(1);
    $('#s-q').onkeydown = (e) => { if (e.key === 'Enter') doSearch(1); };
    if (searchState.q) doSearch(searchState.page);
  }
  async function doSearch(page) {
    searchState.q = $('#s-q').value.trim(); searchState.field = $('#s-field').value; searchState.page = page || 1;
    if (!searchState.q) { $('#s-results').innerHTML = '<div class="mt-empty">Suchbegriff eingeben.</div>'; return; }
    $('#s-results').innerHTML = '<div class="mt-spinner"></div>';
    const r = await apiGet('/patients', { q: searchState.q, field: searchState.field, page: searchState.page, pageSize: searchState.pageSize });
    if (!r.ok) return ($('#s-results').innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    searchState.total = r.data.total || 0; const rows = r.data.results || [];
    if (!rows.length) { $('#s-results').innerHTML = '<div class="mt-empty">Keine Treffer.</div>'; return; }
    $('#s-results').innerHTML = `<div class="mt-list">${rows.map(p => `<div class="mt-list-item" data-id="${esc(p.identifier)}"><div><strong>${esc(p.firstname)} ${esc(p.lastname)}</strong><div class="meta">${p.dob ? 'geb. ' + esc(p.dob) + ' · ' : ''}${p.phone ? 'Tel. ' + esc(p.phone) + ' · ' : ''}${p.record_id ? 'Akte vorhanden' : 'Neue Akte'}</div></div><span class="mt-btn ghost">Öffnen →</span></div>`).join('')}</div>${pager(searchState, doSearch)}`;
    $('#s-results').querySelectorAll('[data-id]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-id')));
  }

  // ================= RECORD =================
  let recordTab = 'info';
  async function openRecord(identifier) {
    if (!can('patient.view')) return toast('Keine Berechtigung.', 'error');
    S.view = 'record'; buildNav(); $('#mt-view-title').textContent = 'Patientenakte'; $('#mt-top-actions').innerHTML = ''; setLoading();
    const r = await apiGet('/patient', { identifier });
    if (!r.ok) return ($('#mt-content').innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    S.patient = r.data; S.patient.identifier = r.data.record.identifier; render_record();
  }
  function renderRecord() { if (!S.patient) return go('search'); render_record(); }
  function render_record() {
    $('#mt-top-actions').innerHTML = ''; $('#mt-view-title').textContent = 'Patientenakte';
    addTopBtn('← Zurück', 'ghost', () => go('search'));
    const rec = S.patient.record;
    const tabs = [['info', 'Stammdaten'], ['treatments', 'Behandlungen'], ['invoices', 'Rechnungen'], ['insurance', 'Versicherung']];
    if (can('notes.internal.view')) tabs.push(['notes', 'Interne Notizen']);
    $('#mt-content').innerHTML = `
      <div class="mt-card mt-mb"><div class="mt-row">
        <div><label>Name</label><strong>${esc(rec.firstname)} ${esc(rec.lastname)}</strong></div>
        <div><label>Geburtsdatum</label>${esc(rec.dateofbirth || '-')}</div>
        <div><label>Telefon</label>${esc(rec.phone || '-')}</div>
        <div><label>Charakter-ID</label><span title="${esc(rec.identifier)}">${esc(String(rec.identifier).slice(0, 18))}…</span></div>
      </div></div>
      <div class="mt-tabs">${tabs.map(t => `<div class="mt-tab ${recordTab === t[0] ? 'active' : ''}" data-tab="${t[0]}">${esc(t[1])}</div>`).join('')}</div>
      <div id="rec-body"></div>`;
    document.querySelectorAll('[data-tab]').forEach(x => x.onclick = () => { recordTab = x.getAttribute('data-tab'); render_record(); });
    const body = $('#rec-body');
    ({ info: recInfo, treatments: recTreat, invoices: recInv, insurance: recIns, notes: recNotes }[recordTab] || recInfo)(body, rec);
  }
  function recInfo(body, rec) {
    const ro = !can('patient.edit');
    body.innerHTML = `<div class="mt-grid mt-cols-2">
      <div class="mt-card"><h3>Medizinische Stammdaten</h3>
        <label>Blutgruppe</label><input id="f-blood_type" value="${esc(rec.blood_type || '')}" ${ro ? 'disabled' : ''}/>
        <div class="mt-mt"><label>Allergien</label><textarea id="f-allergies" ${ro ? 'disabled' : ''}>${esc(rec.allergies || '')}</textarea></div>
        <div class="mt-mt"><label>Vorerkrankungen</label><textarea id="f-preconditions" ${ro ? 'disabled' : ''}>${esc(rec.preconditions || '')}</textarea></div></div>
      <div class="mt-card"><h3>Weitere Angaben</h3>
        <label>Aktuelle Medikamente</label><textarea id="f-medications" ${ro ? 'disabled' : ''}>${esc(rec.medications || '')}</textarea>
        <div class="mt-mt"><label>Medizinische Hinweise</label><textarea id="f-medical_notes" ${ro ? 'disabled' : ''}>${esc(rec.medical_notes || '')}</textarea></div>
        <div class="mt-mt"><label>Telefon</label><input id="f-phone" value="${esc(rec.phone || '')}" ${ro ? 'disabled' : ''}/></div></div>
      </div>${ro ? '' : '<div class="mt-mt"><button class="mt-btn primary" id="save-info">Speichern</button></div>'}`;
    if (!ro) $('#save-info').onclick = async () => {
      const p = { identifier: S.patient.identifier };
      ['blood_type', 'allergies', 'preconditions', 'medications', 'medical_notes', 'phone'].forEach(f => p[f] = $('#f-' + f).value);
      const r = await apiPut('/patient', p); if (r.ok) toast('Gespeichert.', 'ok'); else toast(errText(r), 'error');
    };
  }
  function recTreat(body) {
    const ts = S.patient.treatments || [];
    body.innerHTML = `${can('treatment.create') ? '<div class="mt-mb"><button class="mt-btn primary" id="new-treat">＋ Neue Behandlung</button></div>' : ''}
      ${ts.length ? tableWrap(['Nr.', 'Diagnose', 'Mitarbeiter', 'Status', 'Betrag', 'Datum', ''], ts.map(t => `<tr><td>${esc(t.treatment_no)}</td><td>${esc(t.diagnosis || '-')}</td><td>${esc(t.staff_name)}</td><td>${badge(t.status)}</td><td class="r">${money(t.amount_final)}</td><td>${fmtDate(t.created_at)}</td><td><button class="mt-btn ghost" data-view="${t.id}">Ansehen</button></td></tr>`)) : emptyRow('Keine Behandlungen.')}`;
    if (can('treatment.create')) $('#new-treat').onclick = openNewTreatment;
    body.querySelectorAll('[data-view]').forEach(x => x.onclick = () => viewTreatment(x.getAttribute('data-view')));
  }
  function recInv(body) {
    const inv = S.patient.invoices || [];
    body.innerHTML = `${can('invoice.create') ? '<div class="mt-mb"><button class="mt-btn primary" id="new-inv">＋ Rechnung erstellen</button></div>' : ''}
      ${inv.length ? tableWrap(['Nr.', 'Grund', 'Basis', 'Versicherung', 'Rabatt', 'Endbetrag', 'Status'], inv.map(i => `<tr><td>${esc(i.invoice_no)}</td><td>${esc(i.reason)}</td><td class="r">${money(i.amount_base)}</td><td class="r" style="color:var(--ok)">${money(i.insurance_amount)}</td><td class="r" style="color:var(--accent)">${money(i.discount_amount)}</td><td class="r"><strong>${money(i.amount_final)}</strong></td><td>${badge(i.status)}</td></tr>`)) : emptyRow('Keine Rechnungen.')}`;
    if (can('invoice.create')) $('#new-inv').onclick = () => openInvoiceForm(null);
  }
  function recIns(body) {
    const ins = S.patient.insurance || { hasContract: false };
    if (!ins.hasContract) { body.innerHTML = '<div class="mt-empty">Keine Krankenversicherung.</div>'; return; }
    const t = ins.tier || {};
    body.innerHTML = `<div class="mt-status-box">
      <div class="mt-kv"><span>Versicherung</span><span><strong style="color:${esc(t.color || '#fff')}">${esc(t.label || '')}</strong></span></div>
      <div class="mt-kv"><span>Status</span><span>${badge(ins.status)} ${ins.coverable ? '✓ Deckung aktiv' : '⚠ ' + (REASONS[ins.reason] || '')}</span></div>
      <div class="mt-kv"><span>Kostenübernahme</span><span>${esc(t.coverage_pct || 0)} %</span></div>
      <div class="mt-kv"><span>Wochenlimit übrig</span><span>${ins.weekly_remaining < 0 ? 'unbegrenzt' : money(ins.weekly_remaining)}</span></div>
      <div class="mt-kv"><span>Nächste Abbuchung</span><span>${fmtDate(ins.next_charge_at)}</span></div>
      <div class="mt-kv"><span>Letzte Abbuchung</span><span>${fmtDate(ins.last_charge_at)}</span></div></div>
      ${can('insurance.manage') ? `<div class="mt-row"><button class="mt-btn" data-mng="pause">Pausieren</button><button class="mt-btn" data-mng="resume">Reaktivieren</button><button class="mt-btn danger" data-mng="cancel">Kündigen</button></div>` : ''}`;
    body.querySelectorAll('[data-mng]').forEach(x => x.onclick = () => { const act = x.getAttribute('data-mng'); confirmDialog('Versicherung verwalten', `Aktion "<strong>${act}</strong>" ausführen?`, async () => { const r = await apiPost('/insurance/contract/manage', { identifier: S.patient.identifier, action: act }); if (r.ok) { toast('Aktualisiert.', 'ok'); S.patient.insurance = r.data.contract; render_record(); } else toast(errText(r), 'error'); }); });
  }
  async function recNotes(body) {
    body.innerHTML = '<div class="mt-spinner"></div>';
    const r = await apiGet('/patient/notes', { identifier: S.patient.identifier });
    if (!r.ok) return (body.innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    const notes = r.data.notes || [];
    body.innerHTML = `<div class="mt-card mt-mb"><h3>Neue interne Notiz</h3><textarea id="note-body" placeholder="Sensible interne Notiz…"></textarea><div class="mt-mt"><button class="mt-btn primary" id="add-note">Notiz hinzufügen</button></div></div>
      ${notes.length ? notes.map(n => `<div class="mt-card mt-mb"><div class="mt-kv"><span><strong>${esc(n.author_name)}</strong></span><span>${fmtDate(n.created_at)}</span></div><div class="mt-mt">${esc(n.body)}</div></div>`).join('') : emptyRow('Keine Notizen.')}`;
    $('#add-note').onclick = async () => { const b = $('#note-body').value.trim(); if (!b) return; const rr = await apiPost('/patient/notes', { identifier: S.patient.identifier, body: b }); if (rr.ok) { toast('Notiz gespeichert.', 'ok'); recNotes(body); } else toast(errText(rr), 'error'); };
  }
  async function viewTreatment(id) {
    const r = await apiGet('/treatment', { id }); if (!r.ok) return toast(errText(r), 'error');
    const t = r.data.treatment, items = r.data.items || [];
    modal('Behandlung ' + esc(t.treatment_no), `
      <div class="mt-kv"><span>Status</span><span>${badge(t.status)}</span></div>
      <div class="mt-kv"><span>Mitarbeiter</span><span>${esc(t.staff_name)}</span></div>
      <div class="mt-kv"><span>Diagnose</span><span>${esc(t.diagnosis || '-')}</span></div>
      <div class="mt-mt"><label>Maßnahmen</label>${esc(t.measures || '-')}</div>
      <div class="mt-mt"><label>Bericht</label>${esc(t.report || '-')}</div>
      ${t.internal_note ? `<div class="mt-mt"><label>Interne Notiz</label>${esc(t.internal_note)}</div>` : ''}
      <div class="mt-mt">${tableWrap(['Leistung', 'Einzel', 'Menge', 'Summe'], items.map(i => `<tr><td>${esc(i.label)}</td><td class="r">${money(i.unit_price)}</td><td class="r">${i.quantity}</td><td class="r">${money(i.line_total)}</td></tr>`))}</div>
      <div class="mt-breakdown mt-mt"><div class="mt-brk-row"><span>Basis</span><span>${money(t.amount_base)}</span></div><div class="mt-brk-row"><span class="ins">Versicherung</span><span class="ins">− ${money(t.amount_insurance)}</span></div><div class="mt-brk-row"><span class="disc">Rabatt</span><span class="disc">− ${money(t.amount_discount)}</span></div><div class="mt-brk-row total"><span>Endbetrag</span><span>${money(t.amount_final)}</span></div></div>`,
      [{ label: 'Schließen', cls: 'ghost', fn: closeModal }, can('invoice.create') && t.status !== 'cancelled' ? { label: 'Rechnung erstellen', cls: 'primary', fn: () => { closeModal(); openInvoiceForm(t.id); } } : null].filter(Boolean));
  }

  // ---- New treatment ----
  let treatLines = [];
  async function openNewTreatment() {
    if (!S.pricelist) { const r = await apiGet('/pricelist'); if (r.ok) S.pricelist = r.data; }
    const items = (S.pricelist && S.pricelist.items) || [];
    const opts = items.map(i => `<option value="${i.code}">${esc(i.label)} – ${money(i.price)}</option>`).join('');
    modal('Neue Behandlung', `
      <label>Diagnose</label><input id="t-diag"/>
      <div class="mt-mt"><label>Maßnahmen</label><textarea id="t-meas"></textarea></div>
      <div class="mt-mt"><label>Behandlungsbericht</label><textarea id="t-rep"></textarea></div>
      ${can('notes.internal.view') ? '<div class="mt-mt"><label>Interne Notiz</label><textarea id="t-int"></textarea></div>' : ''}
      <div class="mt-mt"><label>Leistungen</label><div class="mt-row"><select id="t-item">${opts}</select><input id="t-qty" type="number" value="1" min="1" style="max-width:90px"/><button class="mt-btn" id="t-add">＋</button></div><div id="t-lines" class="mt-mt"></div></div>
      <div class="mt-mt"><label>Status</label><select id="t-status"><option value="draft">Entwurf</option><option value="ongoing">Behandlung läuft</option><option value="completed">Abgeschlossen</option></select></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: submitTreatment }]);
    treatLines = [];
    $('#t-add').onclick = () => { const code = $('#t-item').value, qty = Math.max(1, parseInt($('#t-qty').value) || 1), it = items.find(x => x.code === code); if (it) { treatLines.push({ code, quantity: qty, label: it.label, price: it.price }); drawT(); } };
    drawT();
  }
  function drawT() { const box = $('#t-lines'); if (!box) return; box.innerHTML = treatLines.length ? treatLines.map((l, i) => `<div class="mt-kv"><span>${esc(l.label)} × ${l.quantity}</span><span>${money(l.price * l.quantity)} <button class="mt-btn ghost" data-del="${i}">✕</button></span></div>`).join('') : '<div class="mt-empty" style="padding:12px">Noch keine Leistungen.</div>'; box.querySelectorAll('[data-del]').forEach(x => x.onclick = () => { treatLines.splice(+x.getAttribute('data-del'), 1); drawT(); }); }
  async function submitTreatment() {
    if (!treatLines.length) return toast('Mindestens eine Leistung wählen.', 'warn');
    const p = { identifier: S.patient.identifier, diagnosis: $('#t-diag').value, measures: $('#t-meas').value, report: $('#t-rep').value, status: $('#t-status').value, items: treatLines.map(l => ({ code: l.code, quantity: l.quantity })) };
    if ($('#t-int')) p.internal_note = $('#t-int').value;
    const r = await apiPost('/treatment', p); if (!r.ok) return toast(errText(r), 'error');
    closeModal(); toast('Behandlung gespeichert.', 'ok');
    const ref = await apiGet('/patient', { identifier: S.patient.identifier }); if (ref.ok) { S.patient = ref.data; S.patient.identifier = ref.data.record.identifier; recordTab = 'treatments'; render_record(); }
  }

  // ---- Invoice (queue + poll) ----
  let invLines = [];
  async function openInvoiceForm(treatmentId) {
    if (!S.pricelist) { const r = await apiGet('/pricelist'); if (r.ok) S.pricelist = r.data; }
    S.invoiceIdem = uuid(); invLines = [];
    const fromTreatment = !!treatmentId;
    const items = (S.pricelist && S.pricelist.items) || [];
    const opts = items.map(i => `<option value="${i.code}">${esc(i.label)} – ${money(i.price)}</option>`).join('');
    modal('Rechnung erstellen', `
      ${fromTreatment ? '<div class="mt-brk-note mt-mb">Leistungen aus der Behandlung.</div>' : `<label>Leistungen</label><div class="mt-row"><select id="i-item">${opts}</select><input id="i-qty" type="number" value="1" min="1" style="max-width:90px"/><button class="mt-btn" id="i-add">＋</button></div><div id="i-lines" class="mt-mt"></div>`}
      <div class="mt-mt"><label>Rechnungsgrund</label><input id="i-reason" placeholder="z.B. Notfallbehandlung"/></div>
      ${can('discount.grant') ? '<div class="mt-mt"><label>Zusätzlicher Rabatt ($)</label><input id="i-disc" type="number" value="0" min="0"/></div>' : ''}
      <div class="mt-mt"><button class="mt-btn accent" id="i-preview">Kostenaufteilung berechnen</button></div>
      <div id="i-breakdown" class="mt-mt"></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }]);
    if (!fromTreatment) { $('#i-add').onclick = () => { const code = $('#i-item').value, qty = Math.max(1, parseInt($('#i-qty').value) || 1), it = items.find(x => x.code === code); if (it) { invLines.push({ code, quantity: qty, label: it.label, price: it.price }); drawI(); } }; drawI(); }
    $('#i-preview').onclick = () => previewInvoice(treatmentId, fromTreatment);
  }
  function drawI() { const box = $('#i-lines'); if (!box) return; box.innerHTML = invLines.length ? invLines.map((l, i) => `<div class="mt-kv"><span>${esc(l.label)} × ${l.quantity}</span><span>${money(l.price * l.quantity)} <button class="mt-btn ghost" data-del="${i}">✕</button></span></div>`).join('') : '<div class="mt-empty" style="padding:12px">Noch keine Leistungen.</div>'; box.querySelectorAll('[data-del]').forEach(x => x.onclick = () => { invLines.splice(+x.getAttribute('data-del'), 1); drawI(); }); }
  function invPayload(treatmentId, fromTreatment) { const p = { identifier: S.patient.identifier }; if (fromTreatment) p.treatment_id = treatmentId; else p.items = invLines.map(l => ({ code: l.code, quantity: l.quantity })); if ($('#i-disc')) p.discount = parseInt($('#i-disc').value) || 0; if ($('#i-reason')) p.reason = $('#i-reason').value; return p; }
  async function previewInvoice(treatmentId, fromTreatment) {
    const p = invPayload(treatmentId, fromTreatment);
    if (!fromTreatment && !invLines.length) return toast('Mindestens eine Leistung wählen.', 'warn');
    $('#i-breakdown').innerHTML = '<div class="mt-spinner"></div>';
    const r = await apiPost('/billing/preview', p);
    if (!r.ok) return ($('#i-breakdown').innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    const d = r.data.display;
    const insLine = d.insurance_covered > 0 ? `<div class="mt-brk-row"><span class="ins">Versicherung (${esc(d.insurance_name)}, ${esc(d.insurance_pct)}%)</span><span class="ins">− ${money(d.insurance_covered)}</span></div>` : '';
    const note = d.insurance_key ? (d.coverable ? `<div class="mt-brk-note">Patient zahlt weniger: <strong>${esc(d.insurance_name)}</strong> übernimmt ${esc(d.insurance_pct)}% (${money(d.insurance_covered)}). Kein Rabatt.</div>` : `<div class="mt-brk-warn">⚠ Versicherung "${esc(d.insurance_name)}" ohne Übernahme: ${esc(REASONS[d.reason_key] || d.reason_key)}.</div>`) : '<div class="mt-brk-warn">Keine aktive Versicherung – voller Betrag.</div>';
    $('#i-breakdown').innerHTML = `<div class="mt-breakdown">
      <div class="mt-brk-row"><span>Ursprünglicher Rechnungsbetrag</span><span>${money(d.amount_base)}</span></div>${insLine}
      ${d.discount > 0 ? `<div class="mt-brk-row"><span class="disc">Zusätzlicher Rabatt</span><span class="disc">− ${money(d.discount)}</span></div>` : ''}
      <div class="mt-brk-row total"><span>Vom Patienten zu zahlen</span><span>${money(d.amount_final)}</span></div>${note}</div>
      <div class="mt-modal-actions"><button class="mt-btn ghost" id="i-cancel2">Abbrechen</button><button class="mt-btn primary" id="i-confirm">Rechnung erstellen (${money(d.amount_final)})</button></div>`;
    $('#i-cancel2').onclick = closeModal;
    const btn = $('#i-confirm');
    btn.onclick = async () => {
      btn.disabled = true; btn.textContent = 'Wird eingereicht…';
      const cp = invPayload(treatmentId, fromTreatment); cp.idempotency_key = S.invoiceIdem;
      const rr = await apiPost('/billing/queue', cp);
      if (!rr.ok) { toast(errText(rr), 'error'); btn.disabled = false; btn.textContent = 'Erneut versuchen'; return; }
      pollInvoice(S.invoiceIdem, btn);
    };
  }
  async function pollInvoice(idem, btn) {
    let tries = 0;
    const iv = setInterval(async () => {
      tries++;
      const r = await apiGet('/billing/queue/' + idem);
      if (r.ok && r.data.status === 'done') {
        clearInterval(iv); toast('Rechnung über CodeM erstellt: ' + (r.data.invoice ? r.data.invoice.invoice_no : ''), 'ok'); closeModal();
        const ref = await apiGet('/patient', { identifier: S.patient.identifier }); if (ref.ok) { S.patient = ref.data; S.patient.identifier = ref.data.record.identifier; recordTab = 'invoices'; render_record(); }
      } else if (r.ok && r.data.status === 'failed') {
        clearInterval(iv); toast('Rechnung fehlgeschlagen: ' + (ERR[r.data.error] || r.data.error || ''), 'error'); if (btn) { btn.disabled = false; btn.textContent = 'Erneut versuchen'; }
      } else if (tries > 20) {
        clearInterval(iv); toast('Rechnung wird noch verarbeitet – prüfe später die Rechnungsliste.', 'warn'); closeModal();
      }
    }, 1200);
  }

  // ================= PRICELIST =================
  async function renderPricelist() {
    $('#mt-top-actions').innerHTML = ''; setLoading();
    const r = await apiGet('/pricelist', { all: '1' });
    if (!r.ok) return ($('#mt-content').innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    S.pricelist = r.data; const cats = r.data.categories || [], items = r.data.items || [];
    const catName = (id) => { const c = cats.find(x => x.id === id); return c ? c.label : '–'; };
    if (r.data.canEdit) { addTopBtn('＋ Leistung', 'primary', () => editItem(null, cats)); addTopBtn('＋ Kategorie', 'ghost', editCategory); }
    $('#mt-content').innerHTML = tableWrap(['Code', 'Bezeichnung', 'Kategorie', 'Preis', 'Status', ''], items.map(i => `<tr><td>${esc(i.code)}</td><td>${esc(i.label)}<div class="meta">${esc(i.description || '')}</div></td><td>${esc(catName(i.category_id))}</td><td class="r">${money(i.price)}</td><td>${i.active ? badge('active') : badge('paused')}</td><td>${r.data.canEdit ? `<button class="mt-btn ghost" data-edit="${i.id}">✎</button> <button class="mt-btn ghost" data-tog="${i.id}">${i.active ? '⏸' : '▶'}</button> <button class="mt-btn danger" data-arch="${i.id}">🗄</button>` : ''}</td></tr>`));
    const c = $('#mt-content');
    c.querySelectorAll('[data-edit]').forEach(x => x.onclick = () => editItem(items.find(i => i.id == x.getAttribute('data-edit')), cats));
    c.querySelectorAll('[data-tog]').forEach(x => x.onclick = async () => { const r2 = await apiPost('/pricelist/item/' + x.getAttribute('data-tog') + '/toggle'); if (r2.ok) renderPricelist(); else toast(errText(r2), 'error'); });
    c.querySelectorAll('[data-arch]').forEach(x => x.onclick = () => confirmDialog('Archivieren', 'Leistung archivieren?', async () => { const r2 = await apiPost('/pricelist/item/' + x.getAttribute('data-arch') + '/archive'); if (r2.ok) renderPricelist(); else toast(errText(r2), 'error'); }));
  }
  function editItem(it, cats) {
    it = it || {};
    modal(it.id ? 'Leistung bearbeiten' : 'Neue Leistung', `
      <div class="mt-row"><div><label>Bezeichnung</label><input id="p-label" value="${esc(it.label || '')}"/></div><div><label>Code</label><input id="p-code" value="${esc(it.code || '')}" ${it.id ? 'disabled' : ''}/></div></div>
      <div class="mt-mt"><label>Beschreibung</label><input id="p-desc" value="${esc(it.description || '')}"/></div>
      <div class="mt-row mt-mt"><div><label>Preis ($)</label><input id="p-price" type="number" value="${esc(it.price || 0)}"/></div><div><label>Kategorie</label><select id="p-cat">${cats.map(c => `<option value="${c.id}" ${it.category_id == c.id ? 'selected' : ''}>${esc(c.label)}</option>`).join('')}</select></div></div>
      <div class="mt-mt"><label>Benötigte Berechtigung (optional)</label><input id="p-perm" value="${esc(it.required_perm || '')}"/></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => { const p = { id: it.id, label: $('#p-label').value, code: $('#p-code').value, description: $('#p-desc').value, price: parseInt($('#p-price').value) || 0, category_id: +$('#p-cat').value, required_perm: $('#p-perm').value }; const r = await apiPost('/pricelist/item', p); if (r.ok) { closeModal(); toast('Gespeichert.', 'ok'); renderPricelist(); } else toast(errText(r), 'error'); } }]);
  }
  function editCategory() {
    modal('Neue Kategorie', '<label>Bezeichnung</label><input id="cat-label"/><div class="mt-mt"><label>Sortierung</label><input id="cat-sort" type="number" value="0"/></div>',
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => { const r = await apiPost('/pricelist/category', { label: $('#cat-label').value, sort: parseInt($('#cat-sort').value) || 0 }); if (r.ok) { closeModal(); renderPricelist(); } else toast(errText(r), 'error'); } }]);
  }

  // ================= INSURANCE =================
  async function renderInsurance() {
    $('#mt-top-actions').innerHTML = ''; setLoading();
    const r = await apiGet('/insurance/tiers');
    if (!r.ok) return ($('#mt-content').innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    const tiers = r.data.tiers || [];
    $('#mt-content').innerHTML = `<div class="mt-tiers">${tiers.map(t => `<div class="mt-tier"><span class="tname" style="color:${esc(t.color)}">${esc(t.label)} ${t.active ? '' : badge('paused')}</span><span class="price">${money(t.weekly_premium)}<small>/Woche</small></span><ul><li>${esc(t.coverage_pct)}% Kostenübernahme</li><li>Max. ${t.max_per_invoice > 0 ? money(t.max_per_invoice) : 'unbegrenzt'} pro Rechnung</li><li>Wochenlimit ${t.weekly_cap > 0 ? money(t.weekly_cap) : 'unbegrenzt'}</li><li>Wartezeit ${t.waiting_days} Tg · Mindestlaufzeit ${t.min_term_days} Tg</li></ul>${r.data.canManage ? `<button class="mt-btn" data-tier="${t.id}">Bearbeiten</button>` : ''}</div>`).join('')}</div>
      ${can('insurance.failed.view') ? '<div class="mt-mt"><button class="mt-btn accent" id="failed-btn">Fehlgeschlagene Beiträge</button></div>' : ''}`;
    $('#mt-content').querySelectorAll('[data-tier]').forEach(x => x.onclick = () => editTier(tiers.find(t => t.id == x.getAttribute('data-tier'))));
    if (can('insurance.failed.view')) $('#failed-btn').onclick = showFailed;
  }
  function editTier(t) {
    const f = (k, l, ty) => `<div><label>${l}</label><input id="ti-${k}" ${ty || ''} value="${esc(t[k])}"/></div>`;
    modal('Versicherung: ' + esc(t.label), `
      <div class="mt-row">${f('label', 'Name')}${f('color', 'Farbe')}</div>
      <div class="mt-mt"><label>Beschreibung</label><input id="ti-description" value="${esc(t.description)}"/></div>
      <div class="mt-row mt-mt">${f('weekly_premium', 'Beitrag/Woche', 'type=number')}${f('coverage_pct', 'Übernahme %', 'type=number')}</div>
      <div class="mt-row mt-mt">${f('max_per_invoice', 'Max/Rechnung', 'type=number')}${f('weekly_cap', 'Wochenlimit', 'type=number')}</div>
      <div class="mt-row mt-mt">${f('waiting_days', 'Wartezeit (Tg)', 'type=number')}${f('min_term_days', 'Mindestlaufzeit', 'type=number')}${f('cancel_notice_days', 'Kündigungsfrist', 'type=number')}</div>
      <div class="mt-mt"><label><input type="checkbox" id="ti-active" ${t.active ? 'checked' : ''} style="width:auto"/> Aktiv</label></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => { const p = { label: $('#ti-label').value, color: $('#ti-color').value, description: $('#ti-description').value, weekly_premium: +$('#ti-weekly_premium').value, coverage_pct: +$('#ti-coverage_pct').value, max_per_invoice: +$('#ti-max_per_invoice').value, weekly_cap: +$('#ti-weekly_cap').value, waiting_days: +$('#ti-waiting_days').value, min_term_days: +$('#ti-min_term_days').value, cancel_notice_days: +$('#ti-cancel_notice_days').value, active: $('#ti-active').checked }; const r = await apiPost('/insurance/tier/' + t.id, p); if (r.ok) { closeModal(); toast('Gespeichert.', 'ok'); renderInsurance(); } else toast(errText(r), 'error'); } }]);
  }
  let failedPage = 1;
  async function showFailed(page) {
    failedPage = typeof page === 'number' ? page : 1;
    const r = await apiGet('/insurance/failed', { page: failedPage, pageSize: 15 });
    if (!r.ok) return toast(errText(r), 'error');
    const rows = r.data.rows || [];
    modal('Fehlgeschlagene Beiträge', rows.length ? tableWrap(['Charakter', 'Stufe', 'Betrag', 'Woche', 'Status', 'Versuche'], rows.map(x => `<tr><td title="${esc(x.identifier)}">${esc(String(x.identifier).slice(0, 16))}…</td><td>${esc(x.tier_key)}</td><td class="r">${money(x.amount)}</td><td>${x.week_key}</td><td>${badge(x.status)}</td><td>${x.attempts}</td></tr>`)) + pager({ page: failedPage, total: r.data.total, pageSize: 15 }, showFailed) + '<div class="mt-brk-note mt-mt">Erneute Abbuchung erfolgt automatisch bzw. im Spiel (insurance.retry).</div>' : '<div class="mt-empty">Keine offenen Fälle.</div>');
  }

  // ================= STAFF / LOGS =================
  async function renderStaff() {
    $('#mt-top-actions').innerHTML = ''; setLoading();
    const r = await apiGet('/staff');
    if (!r.ok) return ($('#mt-content').innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    $('#mt-content').innerHTML = `<div class="mt-card"><h3>Letzte Aktivitäten</h3>${tableWrap(['Mitarbeiter', 'Aktion', 'Ziel', 'Ergebnis', 'Zeit'], (r.data.activity || []).map(a => `<tr><td>${esc(a.actor_name)}</td><td>${esc(a.action)}</td><td>${esc(a.target_type)} ${esc(a.target_id || '')}</td><td>${badge(a.result)}</td><td>${fmtDate(a.created_at)}</td></tr>`))}</div>`;
  }
  let logState = { page: 1, category: 'all' };
  function renderLogs() {
    $('#mt-top-actions').innerHTML = '';
    $('#mt-content').innerHTML = `<div class="mt-searchbar"><select id="log-cat" style="width:220px"><option value="all">Alle Kategorien</option><option value="default">Allgemein</option><option value="billing">Rechnungen</option><option value="insurance">Versicherung</option><option value="settings">Einstellungen</option><option value="security">Sicherheit</option></select></div><div id="log-body"><div class="mt-spinner"></div></div>`;
    $('#log-cat').value = logState.category; $('#log-cat').onchange = () => { logState.category = $('#log-cat').value; loadLogs(1); };
    loadLogs(1);
  }
  async function loadLogs(page) {
    logState.page = page || 1;
    const r = await apiGet('/audit', { page: logState.page, category: logState.category, pageSize: 25 });
    const body = $('#log-body'); if (!r.ok) return (body.innerHTML = `<div class="mt-brk-warn">${esc(errText(r))}</div>`);
    const rows = r.data.rows || [];
    body.innerHTML = rows.length ? tableWrap(['Zeit', 'Mitarbeiter', 'Kategorie', 'Aktion', 'Ziel', 'Ergebnis'], rows.map(a => `<tr><td>${fmtDate(a.created_at)}</td><td>${esc(a.actor_name)}</td><td>${esc(a.category)}</td><td>${esc(a.action)}</td><td>${esc(a.target_type)} ${esc(a.target_id || '')}</td><td>${badge(a.result)}</td></tr>`)) + pager({ page: logState.page, total: r.data.total, pageSize: 25 }, loadLogs) : '<div class="mt-empty">Keine Einträge.</div>';
  }

  // ================= INIT =================
  async function init() {
    const me = await apiGet('/me');
    if (!me.ok) { location.href = '/login.html'; return; }
    S.identity = me.data.identity || {}; S.perms = me.data.perms || {}; S.branding = me.data.branding || {};
    applyBranding();
    $('#mt-username').textContent = S.identity.name || '-';
    $('#mt-userrole').textContent = S.identity.role || 'Medic';
    if (S.identity.avatar) { const img = $('#mt-avatar'); img.src = S.identity.avatar; img.style.display = 'block'; $('#mt-avatar-fallback').style.display = 'none'; }
    else { $('#mt-avatar-fallback').textContent = (S.identity.name || 'M').charAt(0).toUpperCase(); }
    S.view = can('tablet.open') ? 'dashboard' : 'search';
    buildNav(); render();
  }

  // burger / scrim / logout / modal overlay
  const scrim = el('div', 'mt-scrim'); scrim.id = 'mt-scrim'; document.body.appendChild(scrim);
  scrim.onclick = closeSidebar;
  document.addEventListener('click', (e) => {
    if (e.target.id === 'mt-burger') { $('#mt-sidebar').classList.toggle('open'); scrim.classList.toggle('show'); }
    if (e.target.id === 'mt-logout') { fetch('/logout', { method: 'POST', credentials: 'same-origin' }).then(() => location.href = '/login.html'); }
    if (e.target.id === 'mt-modal') closeModal();
  });
  init();
})();
