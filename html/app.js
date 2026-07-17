/* SunLife Medic-Tablet – NUI Frontend (vanilla JS, self-contained)
   Kommuniziert ausschliesslich ueber den generischen 'request'-Kanal mit dem
   Server-Dispatcher, der ALLE Berechtigungen serverseitig prueft. */
(function () {
  'use strict';

  const RES = 'medictablet'; // Ressourcenname (fuer NUI-Fetch)
  const $ = (s, r) => (r || document).querySelector(s);
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };

  // ---- API ----
  function post(cb, data) {
    return fetch(`https://${RES}/${cb}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data || {})
    }).then(r => r.json()).catch(() => ({ ok: false, data: { error: 'NUI-Fehler' } }));
  }
  async function api(action, data) {
    const res = await post('request', { action, data: data || {} });
    return res; // { ok, data }
  }
  function closeUI() { post('close', {}); hideAll(); }

  // ---- Helpers ----
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (v) => '$' + (Math.floor(Number(v) || 0)).toLocaleString('de-DE');
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'id-' + Date.now() + '-' + Math.random().toString(16).slice(2));
  const badge = (s) => `<span class="mt-badge b-${esc(s)}">${esc(s)}</span>`;
  const fmtDate = (s) => s ? esc(String(s).replace('T', ' ').slice(0, 16)) : '-';

  const REASONS = {
    ins_none: 'Keine aktive Versicherung', ins_waiting: 'Versicherung in Wartezeit',
    ins_paused: 'Versicherung pausiert', ins_charge_failed: 'Wochenbeitrag nicht bezahlt',
    ok: 'aktiv'
  };

  // ---- State ----
  const S = {
    mode: 'tablet', branding: {}, features: {}, perms: {}, identity: {},
    view: 'dashboard', patient: null, pricelist: null, invoiceIdem: null
  };
  const can = (p) => !!(S.perms['admin.full'] || S.perms[p]);
  const feat = (f) => S.features[f] !== false;

  // ---- Toasts ----
  function toast(msg, level) {
    const t = el('div', 'mt-toast ' + (level || ''), esc(msg));
    $('#mt-toasts').appendChild(t);
    setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 200); }, 3200);
  }

  // ---- Modal ----
  function modal(title, bodyHtml, actions) {
    const box = $('#mt-modal-box');
    box.innerHTML = `<h2>${esc(title)}</h2><div id="mt-modal-content">${bodyHtml}</div>
      <div class="mt-modal-actions" id="mt-modal-actions"></div>`;
    const act = $('#mt-modal-actions');
    (actions || [{ label: 'Schließen', cls: 'ghost', fn: closeModal }]).forEach(a => {
      const b = el('button', 'mt-btn ' + (a.cls || ''), esc(a.label));
      b.onclick = () => a.fn && a.fn();
      act.appendChild(b);
    });
    $('#mt-modal').classList.remove('mt-hidden');
    return box;
  }
  function closeModal() { $('#mt-modal').classList.add('mt-hidden'); }
  function confirmDialog(title, html, onYes, yesLabel) {
    modal(title, html, [
      { label: 'Abbrechen', cls: 'ghost', fn: closeModal },
      { label: yesLabel || 'Bestätigen', cls: 'primary', fn: () => { closeModal(); onYes(); } }
    ]);
  }

  // ---- Branding ----
  function applyBranding() {
    const b = S.branding || {};
    const root = document.documentElement;
    root.style.setProperty('--primary', b.colorPrimary || '#e11d48');
    root.style.setProperty('--accent', b.colorAccent || '#f59e0b');
    if (b.colorBg) root.style.setProperty('--bg', b.colorBg);
    if ((b.theme || 'dark') === 'light') root.classList.add('mt-light'); else root.classList.remove('mt-light');
    if ($('#mt-clinic')) $('#mt-clinic').textContent = b.clinicName || 'Medical Center';
    if ($('#mt-server')) $('#mt-server').textContent = b.serverName || 'SunLife Roleplay';
    if ($('#mt-ins-server')) $('#mt-ins-server').textContent = b.serverName || 'SunLife Roleplay';
    if (b.logo && $('#mt-logo')) $('#mt-logo').src = b.logo;
  }

  // ---- Navigation ----
  const NAV = [
    { id: 'dashboard', label: 'Dashboard', ico: '▤', feature: 'dashboard' },
    { id: 'search', label: 'Patienten', ico: '⚇', perm: 'patient.search', feature: 'patientSearch' },
    { id: 'pricelist', label: 'Preisliste', ico: '≣', perm: 'pricelist.view', feature: 'pricelist' },
    { id: 'insurance', label: 'Versicherung', ico: '◆', perm: 'insurance.patient.view', feature: 'insurance' },
    { id: 'staff', label: 'Mitarbeiter', ico: '☰', perm: 'staff.view', feature: 'staffOverview' },
    { id: 'logs', label: 'Protokolle', ico: '☷', perm: 'audit.view', feature: 'auditLog' },
    { id: 'settings', label: 'Einstellungen', ico: '⚙', perm: 'settings.edit', feature: 'settings' }
  ];
  function buildNav() {
    const nav = $('#mt-nav'); nav.innerHTML = '';
    NAV.forEach(n => {
      if (n.feature && !feat(n.feature)) return;
      if (n.perm && !can(n.perm)) return;
      const b = el('button', S.view === n.id ? 'active' : '', `<span class="ico">${n.ico}</span>${esc(n.label)}`);
      b.onclick = () => go(n.id);
      nav.appendChild(b);
    });
  }
  function go(view) { S.view = view; buildNav(); render(); }

  // ---- Render dispatcher ----
  const TITLES = { dashboard: 'Dashboard', search: 'Patientensuche', record: 'Patientenakte', pricelist: 'Preisliste', insurance: 'Krankenversicherung', staff: 'Mitarbeiter', logs: 'Protokolle', settings: 'Einstellungen' };
  function setLoading() { $('#mt-content').innerHTML = '<div class="mt-spinner"></div>'; }
  function render() {
    $('#mt-view-title').textContent = TITLES[S.view] || '';
    $('#mt-top-actions').innerHTML = '';
    const map = { dashboard: renderDashboard, search: renderSearch, record: renderRecord, pricelist: renderPricelist, insurance: renderInsurance, staff: renderStaff, logs: renderLogs, settings: renderSettings };
    (map[S.view] || renderDashboard)();
  }

  // ================= DASHBOARD =================
  async function renderDashboard() {
    setLoading();
    const r = await api('dashboard.data');
    if (!r.ok) return errBox(r);
    const d = r.data.dashboard || {};
    const c = $('#mt-content');
    c.innerHTML = `
      <div class="mt-grid mt-cols-4 mt-mb">
        ${statCard('Im Dienst', (d.onDuty || []).length, '⚕')}
        ${statCard('Behandlungen heute', d.todayTreatments || 0, '✚')}
        ${statCard('Rechnungen heute', d.todayInvoices || 0, '$')}
        ${statCard('Offene Behandlungen', (d.openTreatments || []).length, '◷')}
      </div>
      ${(d.notice && d.notice.text) ? `<div class="mt-brk-note mt-mb">${esc(d.notice.text)}</div>` : ''}
      <div class="mt-grid mt-cols-2">
        <div class="mt-card"><h3>Im Dienst</h3>${listOrEmpty((d.onDuty || []).map(m => `<div class="mt-kv"><span>${esc(m.name)}</span><span>${esc(m.grade_label || '')}</span></div>`))}</div>
        <div class="mt-card"><h3>Zuletzt bearbeitete Akten</h3>${listOrEmpty((d.recentPatients || []).map(p => `<div class="mt-kv" data-open="${esc(p.identifier)}" style="cursor:pointer"><span>${esc(p.firstname)} ${esc(p.lastname)}</span><span>${fmtDate(p.last_treatment_at)}</span></div>`))}</div>
      </div>
      <div class="mt-card mt-mt"><h3>Offene Behandlungen</h3>${
        (d.openTreatments || []).length ? tableWrap(['Nr.', 'Diagnose', 'Mitarbeiter', 'Status', 'Datum'],
          d.openTreatments.map(t => `<tr><td>${esc(t.treatment_no)}</td><td>${esc(t.diagnosis)}</td><td>${esc(t.staff_name)}</td><td>${badge(t.status)}</td><td>${fmtDate(t.created_at)}</td></tr>`)) : emptyRow()
      }</div>`;
    c.querySelectorAll('[data-open]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-open')));

    // Schnellzugriffe
    if (can('patient.search')) addTopBtn('Patientensuche', 'primary', () => go('search'));
  }
  const statCard = (lbl, val, ico) => `<div class="mt-card mt-stat"><span class="ico">${ico}</span><span class="val">${esc(val)}</span><span class="lbl">${esc(lbl)}</span></div>`;

  // ================= SEARCH =================
  let searchState = { q: '', field: 'auto', page: 1, total: 0, pageSize: 15 };
  async function renderSearch() {
    const c = $('#mt-content');
    c.innerHTML = `
      <div class="mt-searchbar">
        <input id="s-q" placeholder="Name, Geburtsdatum, Telefon, Charakter-ID…" value="${esc(searchState.q)}"/>
        <select id="s-field">
          <option value="auto">Alle Felder</option>
          <option value="firstname">Vorname</option>
          <option value="lastname">Nachname</option>
          <option value="dob">Geburtsdatum</option>
          <option value="phone">Telefon</option>
          <option value="charid">Charakter-ID</option>
        </select>
        <button class="mt-btn primary" id="s-go">Suchen</button>
      </div>
      <div id="s-results"></div>`;
    $('#s-field').value = searchState.field;
    $('#s-go').onclick = doSearch;
    $('#s-q').onkeydown = (e) => { if (e.key === 'Enter') doSearch(); };
    if (searchState.q) doSearch();
  }
  async function doSearch(page) {
    searchState.q = $('#s-q').value.trim();
    searchState.field = $('#s-field').value;
    searchState.page = page || 1;
    if (!searchState.q) { $('#s-results').innerHTML = '<div class="mt-empty">Suchbegriff eingeben.</div>'; return; }
    $('#s-results').innerHTML = '<div class="mt-spinner"></div>';
    const r = await api('patients.search', { q: searchState.q, field: searchState.field, page: searchState.page, pageSize: searchState.pageSize });
    if (!r.ok) return ($('#s-results').innerHTML = errHtml(r));
    searchState.total = r.data.total || 0;
    const rows = r.data.results || [];
    if (!rows.length) { $('#s-results').innerHTML = '<div class="mt-empty">Keine Treffer.</div>'; return; }
    $('#s-results').innerHTML = `<div class="mt-list">${rows.map(p => `
      <div class="mt-list-item" data-id="${esc(p.identifier)}">
        <div><strong>${esc(p.firstname)} ${esc(p.lastname)}</strong>
          <div class="meta">${p.dob ? 'geb. ' + esc(p.dob) + ' · ' : ''}${p.phone ? 'Tel. ' + esc(p.phone) + ' · ' : ''}${p.record_id ? 'Akte vorhanden' : 'Neue Akte'}</div>
        </div><span class="mt-btn ghost">Öffnen →</span>
      </div>`).join('')}</div>${pager(searchState, doSearch)}`;
    $('#s-results').querySelectorAll('[data-id]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-id')));
  }

  // ================= PATIENT RECORD =================
  let recordTab = 'info';
  async function openRecord(identifier) {
    if (!can('patient.view')) return toast('Keine Berechtigung.', 'error');
    S.view = 'record'; buildNav();
    $('#mt-view-title').textContent = 'Patientenakte'; $('#mt-top-actions').innerHTML = ''; setLoading();
    const r = await api('patients.open', { identifier });
    if (!r.ok) return errBox(r);
    S.patient = r.data;
    S.patient.identifier = r.data.record.identifier;
    renderRecord();
  }
  function renderRecord() {
    if (!S.patient) return go('search');
    $('#mt-top-actions').innerHTML = '';
    $('#mt-view-title').textContent = 'Patientenakte';
    const rec = S.patient.record;
    addTopBtn('← Zurück', 'ghost', () => go('search'));
    const tabs = [['info', 'Stammdaten'], ['treatments', 'Behandlungen'], ['invoices', 'Rechnungen'], ['insurance', 'Versicherung']];
    if (can('notes.internal.view')) tabs.push(['notes', 'Interne Notizen']);
    const c = $('#mt-content');
    c.innerHTML = `
      <div class="mt-card mt-mb"><div class="mt-row">
        <div><label>Name</label><strong>${esc(rec.firstname)} ${esc(rec.lastname)}</strong></div>
        <div><label>Geburtsdatum</label>${esc(rec.dateofbirth || '-')}</div>
        <div><label>Telefon</label>${esc(rec.phone || '-')}</div>
        <div><label>Charakter-ID</label><span title="${esc(rec.identifier)}">${esc(rec.identifier.slice(0, 18))}…</span></div>
      </div></div>
      <div class="mt-tabs">${tabs.map(t => `<div class="mt-tab ${recordTab === t[0] ? 'active' : ''}" data-tab="${t[0]}">${esc(t[1])}</div>`).join('')}</div>
      <div id="rec-body"></div>`;
    c.querySelectorAll('[data-tab]').forEach(x => x.onclick = () => { recordTab = x.getAttribute('data-tab'); renderRecord(); });
    const body = $('#rec-body');
    if (recordTab === 'info') recTabInfo(body, rec);
    else if (recordTab === 'treatments') recTabTreatments(body);
    else if (recordTab === 'invoices') recTabInvoices(body);
    else if (recordTab === 'insurance') recTabInsurance(body);
    else if (recordTab === 'notes') recTabNotes(body);
  }
  function recTabInfo(body, rec) {
    const ro = !can('patient.edit');
    body.innerHTML = `
      <div class="mt-grid mt-cols-2">
        <div class="mt-card"><h3>Medizinische Stammdaten</h3>
          <label>Blutgruppe</label><input id="f-blood_type" value="${esc(rec.blood_type || '')}" ${ro ? 'disabled' : ''}/>
          <div class="mt-mt"><label>Allergien</label><textarea id="f-allergies" ${ro ? 'disabled' : ''}>${esc(rec.allergies || '')}</textarea></div>
          <div class="mt-mt"><label>Vorerkrankungen</label><textarea id="f-preconditions" ${ro ? 'disabled' : ''}>${esc(rec.preconditions || '')}</textarea></div>
        </div>
        <div class="mt-card"><h3>Weitere Angaben</h3>
          <label>Aktuelle Medikamente</label><textarea id="f-medications" ${ro ? 'disabled' : ''}>${esc(rec.medications || '')}</textarea>
          <div class="mt-mt"><label>Medizinische Hinweise</label><textarea id="f-medical_notes" ${ro ? 'disabled' : ''}>${esc(rec.medical_notes || '')}</textarea></div>
          <div class="mt-mt"><label>Telefon</label><input id="f-phone" value="${esc(rec.phone || '')}" ${ro ? 'disabled' : ''}/></div>
        </div>
      </div>
      ${ro ? '' : '<div class="mt-mt"><button class="mt-btn primary" id="save-info">Speichern</button></div>'}`;
    if (!ro) $('#save-info').onclick = async () => {
      const p = { identifier: S.patient.identifier };
      ['blood_type', 'allergies', 'preconditions', 'medications', 'medical_notes', 'phone'].forEach(f => p[f] = $('#f-' + f).value);
      const r = await api('patients.update', p);
      if (r.ok) { toast('Gespeichert.', 'ok'); } else errToast(r);
    };
  }
  function recTabTreatments(body) {
    const ts = S.patient.treatments || [];
    body.innerHTML = `${can('treatment.create') ? '<div class="mt-mb"><button class="mt-btn primary" id="new-treat">＋ Neue Behandlung</button></div>' : ''}
      ${ts.length ? tableWrap(['Nr.', 'Diagnose', 'Mitarbeiter', 'Status', 'Betrag', 'Datum', ''],
        ts.map(t => `<tr><td>${esc(t.treatment_no)}</td><td>${esc(t.diagnosis || '-')}</td><td>${esc(t.staff_name)}</td><td>${badge(t.status)}</td><td class="r">${money(t.amount_final)}</td><td>${fmtDate(t.created_at)}</td>
          <td><button class="mt-btn ghost" data-view="${t.id}">Ansehen</button></td></tr>`)) : emptyRow('Keine Behandlungen.')}`;
    if (can('treatment.create')) $('#new-treat').onclick = openNewTreatment;
    body.querySelectorAll('[data-view]').forEach(x => x.onclick = () => viewTreatment(x.getAttribute('data-view')));
  }
  function recTabInvoices(body) {
    const inv = S.patient.invoices || [];
    body.innerHTML = `${can('invoice.create') ? '<div class="mt-mb"><button class="mt-btn primary" id="new-inv">＋ Rechnung erstellen</button></div>' : ''}
      ${inv.length ? tableWrap(['Nr.', 'Grund', 'Basis', 'Versicherung', 'Rabatt', 'Endbetrag', 'Status', ''],
        inv.map(i => `<tr><td>${esc(i.invoice_no)}</td><td>${esc(i.reason)}</td><td class="r">${money(i.amount_base)}</td>
          <td class="r" style="color:var(--ok)">${money(i.insurance_amount)}</td><td class="r" style="color:var(--accent)">${money(i.discount_amount)}</td>
          <td class="r"><strong>${money(i.amount_final)}</strong></td><td>${badge(i.status)}</td>
          <td>${can('invoice.cancel') && i.status === 'issued' ? `<button class="mt-btn danger" data-cancel="${i.id}">Storno</button>` : ''}</td></tr>`)) : emptyRow('Keine Rechnungen.')}`;
    if (can('invoice.create')) $('#new-inv').onclick = () => openInvoiceForm(null);
    body.querySelectorAll('[data-cancel]').forEach(x => x.onclick = () => cancelInvoice(x.getAttribute('data-cancel')));
  }
  function recTabInsurance(body) {
    const ins = S.patient.insurance || { hasContract: false };
    if (!ins.hasContract) { body.innerHTML = '<div class="mt-empty">Dieser Patient hat keine Krankenversicherung.</div>'; return; }
    const t = ins.tier || {};
    body.innerHTML = `<div class="mt-status-box">
      <div class="mt-kv"><span>Versicherung</span><span><strong style="color:${esc(t.color || '#fff')}">${esc(t.label || ins.tier_key)}</strong></span></div>
      <div class="mt-kv"><span>Status</span><span>${badge(ins.status)} ${ins.coverable ? '✓ Deckung aktiv' : '⚠ ' + (REASONS[ins.reason] || '')}</span></div>
      <div class="mt-kv"><span>Kostenübernahme</span><span>${esc(t.coverage_pct || 0)} %</span></div>
      <div class="mt-kv"><span>Max. pro Rechnung</span><span>${t.max_per_invoice > 0 ? money(t.max_per_invoice) : 'unbegrenzt'}</span></div>
      <div class="mt-kv"><span>Wochenlimit übrig</span><span>${ins.weekly_remaining < 0 ? 'unbegrenzt' : money(ins.weekly_remaining)}</span></div>
      <div class="mt-kv"><span>Nächste Abbuchung</span><span>${fmtDate(ins.next_charge_at)}</span></div>
      <div class="mt-kv"><span>Letzte Abbuchung</span><span>${fmtDate(ins.last_charge_at)}</span></div>
    </div>
    ${can('insurance.manage') ? `<div class="mt-row">
      <button class="mt-btn" data-mng="pause">Pausieren</button>
      <button class="mt-btn" data-mng="resume">Reaktivieren</button>
      <button class="mt-btn danger" data-mng="cancel">Kündigen</button></div>` : ''}`;
    body.querySelectorAll('[data-mng]').forEach(x => x.onclick = () => {
      const act = x.getAttribute('data-mng');
      confirmDialog('Versicherung verwalten', `Aktion "<strong>${act}</strong>" für diesen Patienten ausführen?`, async () => {
        const r = await api('insurance.manageContract', { identifier: S.patient.identifier, action: act });
        if (r.ok) { toast('Aktualisiert.', 'ok'); S.patient.insurance = r.data.contract; renderRecord(); } else errToast(r);
      });
    });
  }
  async function recTabNotes(body) {
    body.innerHTML = '<div class="mt-spinner"></div>';
    const r = await api('patients.notes', { identifier: S.patient.identifier });
    if (!r.ok) return (body.innerHTML = errHtml(r));
    const notes = r.data.notes || [];
    body.innerHTML = `<div class="mt-card mt-mb"><h3>Neue interne Notiz</h3>
      <textarea id="note-body" placeholder="Sensible interne Notiz…"></textarea>
      <div class="mt-mt"><button class="mt-btn primary" id="add-note">Notiz hinzufügen</button></div></div>
      ${notes.length ? notes.map(n => `<div class="mt-card mt-mb"><div class="mt-kv"><span><strong>${esc(n.author_name)}</strong></span><span>${fmtDate(n.created_at)}</span></div><div class="mt-mt">${esc(n.body)}</div></div>`).join('') : emptyRow('Keine Notizen.')}`;
    $('#add-note').onclick = async () => {
      const b = $('#note-body').value.trim(); if (!b) return;
      const rr = await api('patients.addNote', { identifier: S.patient.identifier, body: b });
      if (rr.ok) { toast('Notiz gespeichert.', 'ok'); recTabNotes(body); } else errToast(rr);
    };
  }

  async function viewTreatment(id) {
    const r = await api('treatment.get', { id: Number(id) });
    if (!r.ok) return errToast(r);
    const t = r.data.treatment; const items = r.data.items || [];
    modal('Behandlung ' + esc(t.treatment_no), `
      <div class="mt-kv"><span>Status</span><span>${badge(t.status)}</span></div>
      <div class="mt-kv"><span>Mitarbeiter</span><span>${esc(t.staff_name)}</span></div>
      <div class="mt-kv"><span>Diagnose</span><span>${esc(t.diagnosis || '-')}</span></div>
      <div class="mt-mt"><label>Maßnahmen</label>${esc(t.measures || '-')}</div>
      <div class="mt-mt"><label>Medikamente</label>${esc(t.medications || '-')}</div>
      <div class="mt-mt"><label>Bericht</label>${esc(t.report || '-')}</div>
      ${t.internal_note ? `<div class="mt-mt"><label>Interne Notiz</label>${esc(t.internal_note)}</div>` : ''}
      <div class="mt-mt">${tableWrap(['Leistung', 'Einzel', 'Menge', 'Summe'], items.map(i => `<tr><td>${esc(i.label)}</td><td class="r">${money(i.unit_price)}</td><td class="r">${i.quantity}</td><td class="r">${money(i.line_total)}</td></tr>`))}</div>
      <div class="mt-breakdown mt-mt">
        <div class="mt-brk-row"><span>Basisbetrag</span><span>${money(t.amount_base)}</span></div>
        <div class="mt-brk-row"><span class="ins">Versicherung</span><span class="ins">− ${money(t.amount_insurance)}</span></div>
        <div class="mt-brk-row"><span class="disc">Rabatt</span><span class="disc">− ${money(t.amount_discount)}</span></div>
        <div class="mt-brk-row total"><span>Endbetrag</span><span>${money(t.amount_final)}</span></div>
      </div>`,
      [{ label: 'Schließen', cls: 'ghost', fn: closeModal },
       can('invoice.create') && t.status !== 'cancelled' ? { label: 'Rechnung erstellen', cls: 'primary', fn: () => { closeModal(); openInvoiceForm(t.id); } } : null].filter(Boolean));
  }

  // ============ NEW TREATMENT ============
  async function openNewTreatment() {
    if (!S.pricelist) { const r = await api('pricelist.list'); if (r.ok) S.pricelist = r.data; }
    const items = (S.pricelist && S.pricelist.items) || [];
    const opts = items.map(i => `<option value="${i.code}">${esc(i.label)} – ${money(i.price)}</option>`).join('');
    modal('Neue Behandlung', `
      <div class="mt-row"><div><label>Diagnose</label><input id="t-diag"/></div></div>
      <div class="mt-mt"><label>Maßnahmen</label><textarea id="t-meas"></textarea></div>
      <div class="mt-mt"><label>Verabreichte Medikamente</label><textarea id="t-med"></textarea></div>
      <div class="mt-mt"><label>Behandlungsbericht</label><textarea id="t-rep"></textarea></div>
      ${can('notes.internal.view') ? '<div class="mt-mt"><label>Interne Notiz (sensibel)</label><textarea id="t-int"></textarea></div>' : ''}
      <div class="mt-mt"><label>Leistungen</label>
        <div class="mt-row"><select id="t-item">${opts}</select><input id="t-qty" type="number" value="1" min="1" style="max-width:90px"/><button class="mt-btn" id="t-add">＋</button></div>
        <div id="t-lines" class="mt-mt"></div>
      </div>
      <div class="mt-mt"><label>Status</label><select id="t-status">
        <option value="draft">Entwurf</option><option value="ongoing">Behandlung läuft</option><option value="completed">Abgeschlossen</option></select></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal },
       { label: 'Speichern', cls: 'primary', fn: submitTreatment }]);
    treatLines = [];
    $('#t-add').onclick = () => { const code = $('#t-item').value, qty = Math.max(1, parseInt($('#t-qty').value) || 1); const it = items.find(x => x.code === code); if (!it) return; treatLines.push({ code, quantity: qty, label: it.label, price: it.price }); drawLines(); };
    drawLines();
  }
  let treatLines = [];
  function drawLines() {
    const box = $('#t-lines'); if (!box) return;
    if (!treatLines.length) { box.innerHTML = '<div class="mt-empty" style="padding:12px">Noch keine Leistungen.</div>'; return; }
    box.innerHTML = treatLines.map((l, i) => `<div class="mt-kv"><span>${esc(l.label)} × ${l.quantity}</span><span>${money(l.price * l.quantity)} <button class="mt-btn ghost" data-del="${i}">✕</button></span></div>`).join('');
    box.querySelectorAll('[data-del]').forEach(x => x.onclick = () => { treatLines.splice(+x.getAttribute('data-del'), 1); drawLines(); });
  }
  async function submitTreatment() {
    if (!treatLines.length) return toast('Mindestens eine Leistung wählen.', 'warn');
    const payload = {
      identifier: S.patient.identifier, diagnosis: $('#t-diag').value, measures: $('#t-meas').value,
      medications: $('#t-med').value, report: $('#t-rep').value, status: $('#t-status').value,
      items: treatLines.map(l => ({ code: l.code, quantity: l.quantity }))
    };
    if ($('#t-int')) payload.internal_note = $('#t-int').value;
    const r = await api('treatment.create', payload);
    if (!r.ok) return errToast(r);
    closeModal(); toast('Behandlung gespeichert.', 'ok');
    const ref = await api('patients.open', { identifier: S.patient.identifier });
    if (ref.ok) { S.patient = ref.data; S.patient.identifier = ref.data.record.identifier; recordTab = 'treatments'; renderRecord(); }
  }

  // ============ INVOICE (with cost breakdown) ============
  async function openInvoiceForm(treatmentId) {
    if (!S.pricelist) { const r = await api('pricelist.list'); if (r.ok) S.pricelist = r.data; }
    S.invoiceIdem = uuid(); // einmalig pro Rechnungsformular
    invLines = [];
    let fromTreatment = !!treatmentId;
    const items = (S.pricelist && S.pricelist.items) || [];
    const opts = items.map(i => `<option value="${i.code}">${esc(i.label)} – ${money(i.price)}</option>`).join('');
    modal('Rechnung erstellen', `
      ${fromTreatment ? '<div class="mt-brk-note mt-mb">Leistungen werden aus der Behandlung übernommen.</div>' :
        `<label>Leistungen</label><div class="mt-row"><select id="i-item">${opts}</select><input id="i-qty" type="number" value="1" min="1" style="max-width:90px"/><button class="mt-btn" id="i-add">＋</button></div><div id="i-lines" class="mt-mt"></div>`}
      <div class="mt-mt"><label>Rechnungsgrund</label><input id="i-reason" placeholder="z.B. Notfallbehandlung"/></div>
      ${can('discount.grant') ? '<div class="mt-mt"><label>Zusätzlicher Rabatt ($)</label><input id="i-disc" type="number" value="0" min="0"/></div>' : ''}
      <div class="mt-mt"><button class="mt-btn accent" id="i-preview">Kostenaufteilung berechnen</button></div>
      <div id="i-breakdown" class="mt-mt"></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }]);
    if (!fromTreatment) {
      $('#i-add').onclick = () => { const code = $('#i-item').value, qty = Math.max(1, parseInt($('#i-qty').value) || 1); const it = items.find(x => x.code === code); if (!it) return; invLines.push({ code, quantity: qty, label: it.label, price: it.price }); drawInvLines(); };
      drawInvLines();
    }
    $('#i-preview').onclick = () => previewInvoice(treatmentId, fromTreatment);
  }
  let invLines = [];
  function drawInvLines() {
    const box = $('#i-lines'); if (!box) return;
    box.innerHTML = invLines.length ? invLines.map((l, i) => `<div class="mt-kv"><span>${esc(l.label)} × ${l.quantity}</span><span>${money(l.price * l.quantity)} <button class="mt-btn ghost" data-del="${i}">✕</button></span></div>`).join('') : '<div class="mt-empty" style="padding:12px">Noch keine Leistungen.</div>';
    box.querySelectorAll('[data-del]').forEach(x => x.onclick = () => { invLines.splice(+x.getAttribute('data-del'), 1); drawInvLines(); });
  }
  function invPayloadBase(treatmentId, fromTreatment) {
    const p = { identifier: S.patient.identifier };
    if (fromTreatment) p.treatment_id = treatmentId; else p.items = invLines.map(l => ({ code: l.code, quantity: l.quantity }));
    if ($('#i-disc')) p.discount = parseInt($('#i-disc').value) || 0;
    if ($('#i-reason')) p.reason = $('#i-reason').value;
    return p;
  }
  async function previewInvoice(treatmentId, fromTreatment) {
    const p = invPayloadBase(treatmentId, fromTreatment);
    if (!fromTreatment && !invLines.length) return toast('Mindestens eine Leistung wählen.', 'warn');
    $('#i-breakdown').innerHTML = '<div class="mt-spinner"></div>';
    const r = await api('billing.preview', p);
    if (!r.ok) { $('#i-breakdown').innerHTML = errHtml(r); return; }
    const d = r.data.display;
    const insLine = d.insurance_covered > 0
      ? `<div class="mt-brk-row"><span class="ins">Versicherung (${esc(d.insurance_name)}, ${esc(d.insurance_pct)}%)</span><span class="ins">− ${money(d.insurance_covered)}</span></div>`
      : '';
    const note = d.insurance_key
      ? (d.coverable
        ? `<div class="mt-brk-note">Der Patient zahlt weniger, weil die <strong>${esc(d.insurance_name)}</strong> ${esc(d.insurance_pct)} % übernimmt (${money(d.insurance_covered)}). Der Versicherungsanteil ist KEIN Rabatt.</div>`
        : `<div class="mt-brk-warn">⚠ Versicherung "${esc(d.insurance_name)}" vorhanden, aber keine Übernahme: ${esc(REASONS[d.reason_key] || d.reason_key)}.</div>`)
      : '<div class="mt-brk-warn">Keine aktive Versicherung – voller Betrag.</div>';
    $('#i-breakdown').innerHTML = `<div class="mt-breakdown">
      <div class="mt-brk-row"><span>Ursprünglicher Rechnungsbetrag</span><span>${money(d.amount_base)}</span></div>
      ${insLine}
      ${d.discount > 0 ? `<div class="mt-brk-row"><span class="disc">Zusätzlicher Rabatt</span><span class="disc">− ${money(d.discount)}</span></div>` : ''}
      <div class="mt-brk-row total"><span>Vom Patienten zu zahlen</span><span>${money(d.amount_final)}</span></div>
      ${note}
      <div class="mt-mt">${d.weekly_remaining >= 0 ? 'Wochenlimit übrig: ' + money(d.weekly_remaining) : ''}</div>
    </div>
    <div class="mt-modal-actions"><button class="mt-btn ghost" id="i-cancel2">Abbrechen</button>
      <button class="mt-btn primary" id="i-confirm">Rechnung über CodeM Billing erstellen (${money(d.amount_final)})</button></div>`;
    $('#i-cancel2').onclick = closeModal;
    const btn = $('#i-confirm');
    btn.onclick = async () => {
      btn.disabled = true; btn.textContent = 'Wird erstellt…';
      const cp = invPayloadBase(treatmentId, fromTreatment); cp.idempotency_key = S.invoiceIdem;
      const rr = await api('billing.create', cp);
      if (rr.ok) {
        toast(rr.data.duplicate ? 'Rechnung existierte bereits.' : 'Rechnung erstellt.', 'ok');
        closeModal();
        const ref = await api('patients.open', { identifier: S.patient.identifier });
        if (ref.ok) { S.patient = ref.data; S.patient.identifier = ref.data.record.identifier; recordTab = 'invoices'; renderRecord(); }
      } else { errToast(rr); btn.disabled = false; btn.textContent = 'Erneut versuchen'; }
    };
  }
  function cancelInvoice(id) {
    confirmDialog('Rechnung stornieren', 'Diese Rechnung wirklich stornieren?<div class="mt-mt"><input id="c-reason" placeholder="Grund (optional)"/></div>', async () => {
      const reason = ($('#c-reason') && $('#c-reason').value) || '';
      const r = await api('billing.cancel', { id: Number(id), reason });
      if (r.ok) { toast('Storniert.', 'ok'); const ref = await api('patients.open', { identifier: S.patient.identifier }); if (ref.ok) { S.patient = ref.data; S.patient.identifier = ref.data.record.identifier; renderRecord(); } } else errToast(r);
    }, 'Stornieren');
  }

  // ================= PRICELIST =================
  async function renderPricelist() {
    $('#mt-top-actions').innerHTML = '';
    setLoading();
    const r = await api('pricelist.list', { all: true });
    if (!r.ok) return errBox(r);
    S.pricelist = r.data;
    const cats = r.data.categories || [], items = r.data.items || [];
    const catName = (id) => { const c = cats.find(x => x.id === id); return c ? c.label : '–'; };
    if (r.data.canEdit) { addTopBtn('＋ Leistung', 'primary', () => editItem(null, cats)); addTopBtn('＋ Kategorie', 'ghost', () => editCategory()); }
    $('#mt-content').innerHTML = tableWrap(['Code', 'Bezeichnung', 'Kategorie', 'Preis', 'Status', ''],
      items.map(i => `<tr><td>${esc(i.code)}</td><td>${esc(i.label)}<div class="meta">${esc(i.description || '')}</div></td>
        <td>${esc(catName(i.category_id))}</td><td class="r">${money(i.price)}</td><td>${i.active ? badge('active') : badge('paused')}</td>
        <td>${r.data.canEdit ? `<button class="mt-btn ghost" data-edit="${i.id}">✎</button> <button class="mt-btn ghost" data-tog="${i.id}">${i.active ? '⏸' : '▶'}</button> <button class="mt-btn danger" data-arch="${i.id}">🗄</button>` : ''}</td></tr>`));
    const c = $('#mt-content');
    c.querySelectorAll('[data-edit]').forEach(x => x.onclick = () => editItem(items.find(i => i.id == x.getAttribute('data-edit')), cats));
    c.querySelectorAll('[data-tog]').forEach(x => x.onclick = async () => { const r2 = await api('pricelist.toggle', { id: +x.getAttribute('data-tog') }); if (r2.ok) renderPricelist(); else errToast(r2); });
    c.querySelectorAll('[data-arch]').forEach(x => x.onclick = () => confirmDialog('Archivieren', 'Leistung archivieren?', async () => { const r2 = await api('pricelist.archive', { id: +x.getAttribute('data-arch') }); if (r2.ok) renderPricelist(); else errToast(r2); }));
  }
  function editItem(it, cats) {
    it = it || {};
    modal(it.id ? 'Leistung bearbeiten' : 'Neue Leistung', `
      <div class="mt-row"><div><label>Bezeichnung</label><input id="p-label" value="${esc(it.label || '')}"/></div>
      <div><label>Code</label><input id="p-code" value="${esc(it.code || '')}" ${it.id ? 'disabled' : ''}/></div></div>
      <div class="mt-mt"><label>Beschreibung</label><input id="p-desc" value="${esc(it.description || '')}"/></div>
      <div class="mt-row mt-mt"><div><label>Preis ($)</label><input id="p-price" type="number" value="${esc(it.price || 0)}"/></div>
      <div><label>Kategorie</label><select id="p-cat">${cats.map(c => `<option value="${c.id}" ${it.category_id == c.id ? 'selected' : ''}>${esc(c.label)}</option>`).join('')}</select></div></div>
      <div class="mt-mt"><label>Benötigte Berechtigung (optional)</label><input id="p-perm" value="${esc(it.required_perm || '')}"/></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => {
        const p = { id: it.id, label: $('#p-label').value, code: $('#p-code').value, description: $('#p-desc').value, price: parseInt($('#p-price').value) || 0, category_id: +$('#p-cat').value, required_perm: $('#p-perm').value };
        const r = await api('pricelist.saveItem', p); if (r.ok) { closeModal(); toast('Gespeichert.', 'ok'); renderPricelist(); } else errToast(r);
      } }]);
  }
  function editCategory() {
    modal('Neue Kategorie', '<label>Bezeichnung</label><input id="cat-label"/><div class="mt-mt"><label>Sortierung</label><input id="cat-sort" type="number" value="0"/></div>',
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => {
        const r = await api('pricelist.saveCategory', { label: $('#cat-label').value, sort: parseInt($('#cat-sort').value) || 0 });
        if (r.ok) { closeModal(); renderPricelist(); } else errToast(r);
      } }]);
  }

  // ================= INSURANCE (medic) =================
  async function renderInsurance() {
    $('#mt-top-actions').innerHTML = '';
    setLoading();
    const r = await api('insurance.tiers');
    if (!r.ok) return errBox(r);
    const tiers = r.data.tiers || [];
    $('#mt-content').innerHTML = `<div class="mt-tiers">${tiers.map(t => `
      <div class="mt-tier">
        <span class="tname" style="color:${esc(t.color)}">${esc(t.label)} ${t.active ? '' : badge('paused')}</span>
        <span class="price">${money(t.weekly_premium)}<small>/Woche</small></span>
        <ul><li>${esc(t.coverage_pct)}% Kostenübernahme</li>
          <li>Max. ${t.max_per_invoice > 0 ? money(t.max_per_invoice) : 'unbegrenzt'} pro Rechnung</li>
          <li>Wochenlimit ${t.weekly_cap > 0 ? money(t.weekly_cap) : 'unbegrenzt'}</li>
          <li>Wartezeit ${t.waiting_days} Tg · Mindestlaufzeit ${t.min_term_days} Tg</li></ul>
        ${r.data.canManage ? `<button class="mt-btn" data-tier="${t.id}">Bearbeiten</button>` : ''}
      </div>`).join('')}</div>
      ${can('insurance.failed.view') ? '<div class="mt-mt"><button class="mt-btn accent" id="failed-btn">Fehlgeschlagene Beiträge</button></div>' : ''}`;
    $('#mt-content').querySelectorAll('[data-tier]').forEach(x => x.onclick = () => editTier(tiers.find(t => t.id == x.getAttribute('data-tier'))));
    if (can('insurance.failed.view')) $('#failed-btn').onclick = showFailed;
  }
  function editTier(t) {
    const f = (k, l, type) => `<div><label>${l}</label><input id="ti-${k}" ${type || ''} value="${esc(t[k])}"/></div>`;
    modal('Versicherung: ' + esc(t.label), `
      <div class="mt-row">${f('label', 'Name')}${f('color', 'Farbe')}</div>
      <div class="mt-mt"><label>Beschreibung</label><input id="ti-description" value="${esc(t.description)}"/></div>
      <div class="mt-row mt-mt">${f('weekly_premium', 'Beitrag/Woche', 'type=number')}${f('coverage_pct', 'Übernahme %', 'type=number')}</div>
      <div class="mt-row mt-mt">${f('max_per_invoice', 'Max/Rechnung', 'type=number')}${f('weekly_cap', 'Wochenlimit', 'type=number')}</div>
      <div class="mt-row mt-mt">${f('waiting_days', 'Wartezeit (Tg)', 'type=number')}${f('min_term_days', 'Mindestlaufzeit (Tg)', 'type=number')}${f('cancel_notice_days', 'Kündigungsfrist (Tg)', 'type=number')}</div>
      <div class="mt-mt"><label><input type="checkbox" id="ti-active" ${t.active ? 'checked' : ''} style="width:auto"/> Aktiv</label></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => {
        const p = { id: t.id, label: $('#ti-label').value, color: $('#ti-color').value, description: $('#ti-description').value,
          weekly_premium: +$('#ti-weekly_premium').value, coverage_pct: +$('#ti-coverage_pct').value,
          max_per_invoice: +$('#ti-max_per_invoice').value, weekly_cap: +$('#ti-weekly_cap').value,
          waiting_days: +$('#ti-waiting_days').value, min_term_days: +$('#ti-min_term_days').value,
          cancel_notice_days: +$('#ti-cancel_notice_days').value, active: $('#ti-active').checked };
        const r = await api('insurance.saveTier', p); if (r.ok) { closeModal(); toast('Gespeichert.', 'ok'); renderInsurance(); } else errToast(r);
      } }]);
  }
  let failedPage = 1;
  async function showFailed(page) {
    failedPage = page || 1;
    const r = await api('insurance.failedList', { page: failedPage, pageSize: 15 });
    if (!r.ok) return errToast(r);
    const rows = r.data.rows || [];
    modal('Fehlgeschlagene Beiträge', rows.length ? tableWrap(['Charakter', 'Stufe', 'Betrag', 'Woche', 'Status', 'Versuche', ''],
      rows.map(x => `<tr><td title="${esc(x.identifier)}">${esc(x.identifier.slice(0, 16))}…</td><td>${esc(x.tier_key)}</td><td class="r">${money(x.amount)}</td><td>${x.week_key}</td><td>${badge(x.status)}</td><td>${x.attempts}</td>
        <td>${can('insurance.retry') ? `<button class="mt-btn primary" data-retry="${x.id}">Erneut</button>` : ''}</td></tr>`))
      + pager({ page: failedPage, total: r.data.total, pageSize: 15 }, showFailed) : '<div class="mt-empty">Keine offenen Fälle.</div>');
    $('#mt-modal-content').querySelectorAll('[data-retry]').forEach(b => b.onclick = async () => {
      const rr = await api('insurance.retry', { premium_id: +b.getAttribute('data-retry') });
      if (rr.ok) { toast('Ergebnis: ' + rr.data.status, rr.data.status === 'paid' ? 'ok' : 'warn'); showFailed(failedPage); } else errToast(rr);
    });
  }

  // ================= STAFF =================
  async function renderStaff() {
    setLoading();
    const r = await api('staff.overview');
    if (!r.ok) return errBox(r);
    $('#mt-content').innerHTML = `
      <div class="mt-card mt-mb"><h3>Im Dienst (${(r.data.onDuty || []).length})</h3>${listOrEmpty((r.data.onDuty || []).map(m => `<div class="mt-kv"><span>${esc(m.name)}</span><span>${esc(m.grade_label || '')}</span></div>`))}</div>
      <div class="mt-card"><h3>Letzte Aktivitäten</h3>${tableWrap(['Mitarbeiter', 'Aktion', 'Ziel', 'Ergebnis', 'Zeit'],
        (r.data.activity || []).map(a => `<tr><td>${esc(a.actor_name)}</td><td>${esc(a.action)}</td><td>${esc(a.target_type)} ${esc(a.target_id || '')}</td><td>${badge(a.result)}</td><td>${fmtDate(a.created_at)}</td></tr>`))}</div>`;
  }

  // ================= LOGS =================
  let logState = { page: 1, category: 'all' };
  async function renderLogs() {
    const c = $('#mt-content');
    c.innerHTML = `<div class="mt-searchbar"><select id="log-cat" style="width:220px">
      <option value="all">Alle Kategorien</option><option value="default">Allgemein</option><option value="billing">Rechnungen</option>
      <option value="insurance">Versicherung</option><option value="settings">Einstellungen</option><option value="security">Sicherheit</option>
      </select></div><div id="log-body"><div class="mt-spinner"></div></div>`;
    $('#log-cat').value = logState.category;
    $('#log-cat').onchange = () => { logState.category = $('#log-cat').value; loadLogs(1); };
    loadLogs(1);
  }
  async function loadLogs(page) {
    logState.page = page || 1;
    const r = await api('audit.list', { page: logState.page, category: logState.category, pageSize: 25 });
    const body = $('#log-body'); if (!r.ok) return (body.innerHTML = errHtml(r));
    const rows = r.data.rows || [];
    body.innerHTML = rows.length ? tableWrap(['Zeit', 'Mitarbeiter', 'Kategorie', 'Aktion', 'Ziel', 'Ergebnis'],
      rows.map(a => `<tr><td>${fmtDate(a.created_at)}</td><td>${esc(a.actor_name)}</td><td>${esc(a.category)}</td><td>${esc(a.action)}</td><td>${esc(a.target_type)} ${esc(a.target_id || '')}</td><td>${badge(a.result)}</td></tr>`))
      + pager({ page: logState.page, total: r.data.total, pageSize: 25 }, loadLogs) : '<div class="mt-empty">Keine Einträge.</div>';
  }

  // ================= SETTINGS =================
  async function renderSettings() {
    setLoading();
    const r = await api('settings.get');
    if (!r.ok) return errBox(r);
    const b = r.data.branding || {}, fe = r.data.features || {}, notice = r.data.notice || {};
    const featRows = Object.keys(fe).map(k => `<label style="display:flex;gap:8px;align-items:center"><input type="checkbox" data-feat="${k}" ${fe[k] ? 'checked' : ''} style="width:auto"/> ${esc(k)}</label>`).join('');
    $('#mt-content').innerHTML = `
      <div class="mt-grid mt-cols-2">
        <div class="mt-card"><h3>Branding</h3>
          <label>Servername</label><input id="b-serverName" value="${esc(b.serverName || '')}"/>
          <div class="mt-mt"><label>Klinikname</label><input id="b-clinicName" value="${esc(b.clinicName || '')}"/></div>
          <div class="mt-row mt-mt"><div><label>Hauptfarbe</label><input id="b-colorPrimary" value="${esc(b.colorPrimary || '')}"/></div>
          <div><label>Akzentfarbe</label><input id="b-colorAccent" value="${esc(b.colorAccent || '')}"/></div></div>
          <div class="mt-mt"><label>Theme</label><select id="b-theme"><option value="dark" ${b.theme === 'dark' ? 'selected' : ''}>Dunkel</option><option value="light" ${b.theme === 'light' ? 'selected' : ''}>Hell</option></select></div>
          <div class="mt-mt"><button class="mt-btn primary" id="save-brand">Branding speichern</button></div>
        </div>
        <div class="mt-card"><h3>Module</h3><div class="mt-list">${featRows}</div>
          <div class="mt-mt"><button class="mt-btn primary" id="save-feat">Module speichern</button></div>
          <h3 class="mt-mt">Interner Hinweis (Dashboard)</h3><textarea id="s-notice">${esc(notice.text || '')}</textarea>
          <div class="mt-mt"><button class="mt-btn" id="save-notice">Hinweis speichern</button></div>
        </div>
      </div>`;
    $('#save-brand').onclick = async () => {
      const nb = Object.assign({}, b, { serverName: $('#b-serverName').value, clinicName: $('#b-clinicName').value, colorPrimary: $('#b-colorPrimary').value, colorAccent: $('#b-colorAccent').value, theme: $('#b-theme').value });
      const rr = await api('settings.save', { branding: nb }); if (rr.ok) { S.branding = nb; applyBranding(); toast('Gespeichert.', 'ok'); } else errToast(rr);
    };
    $('#save-feat').onclick = async () => {
      const nf = Object.assign({}, fe); document.querySelectorAll('[data-feat]').forEach(x => nf[x.getAttribute('data-feat')] = x.checked);
      const rr = await api('settings.save', { features: nf }); if (rr.ok) { S.features = nf; buildNav(); toast('Gespeichert.', 'ok'); } else errToast(rr);
    };
    $('#save-notice').onclick = async () => { const rr = await api('settings.save', { notice: { text: $('#s-notice').value } }); if (rr.ok) toast('Gespeichert.', 'ok'); else errToast(rr); };
  }

  // ================= INSURANCE NPC MODE =================
  function renderInsuranceNPC(data) {
    const ins = (data && data.insurance) || {};
    const tiers = ins.tiers || [];
    const cv = ins.contract || { hasContract: false };
    const charges = ins.recentCharges || [];
    const body = $('#mt-ins-body');
    const statusBox = cv.hasContract ? `<div class="mt-status-box">
      <div class="mt-kv"><span>Deine Versicherung</span><span><strong style="color:${esc((cv.tier || {}).color || '#fff')}">${esc((cv.tier || {}).label || '')}</strong> ${badge(cv.status)}</span></div>
      <div class="mt-kv"><span>Deckung</span><span>${cv.coverable ? '✓ aktiv' : '⚠ ' + (REASONS[cv.reason] || '')}</span></div>
      <div class="mt-kv"><span>Nächste Abbuchung</span><span>${fmtDate(cv.next_charge_at)}</span></div>
      <div class="mt-kv"><span>Letzte Abbuchung</span><span>${fmtDate(cv.last_charge_at)}</span></div>
      <div class="mt-kv"><span>Fehlgeschlagene Zahlungen</span><span>${cv.failed_count || 0}</span></div>
      ${charges.length ? '<div class="mt-mt"><label>Letzte Buchungen</label>' + charges.map(c => `<div class="mt-kv"><span>${badge(c.status)} ${money(c.amount)}</span><span>${fmtDate(c.charged_at || c.scheduled_at)}</span></div>`).join('') + '</div>' : ''}
      </div>` : '<div class="mt-brk-warn mt-mb">Du hast aktuell keine Krankenversicherung.</div>';

    body.innerHTML = statusBox + `<div class="mt-tiers">${tiers.map(t => {
      const isCurrent = cv.hasContract && (cv.tier || {}).tier_key === t.tier_key && cv.status !== 'cancelled';
      return `<div class="mt-tier ${isCurrent ? 'current' : ''}">
        <span class="tname" style="color:${esc(t.color)}">${esc(t.label)}</span>
        <span class="price">${money(t.weekly_premium)}<small>/Woche</small></span>
        <p style="color:var(--muted);font-size:12px;margin:0">${esc(t.description)}</p>
        <ul><li><strong>${esc(t.coverage_pct)}%</strong> Kostenübernahme</li>
          <li>Max. ${t.max_per_invoice > 0 ? money(t.max_per_invoice) : 'unbegrenzt'} / Rechnung</li>
          <li>Wochenlimit: ${t.weekly_cap > 0 ? money(t.weekly_cap) : 'unbegrenzt'}</li>
          ${t.waiting_days > 0 ? `<li>Wartezeit: ${t.waiting_days} Tage</li>` : ''}</ul>
        ${isCurrent ? '<button class="mt-btn" disabled>Aktueller Tarif</button>'
          : (cv.hasContract && cv.status !== 'cancelled'
            ? `<button class="mt-btn primary" data-switch="${esc(t.tier_key)}" data-name="${esc(t.label)}" data-prem="${t.weekly_premium}">Wechseln</button>`
            : `<button class="mt-btn primary" data-sub="${esc(t.tier_key)}" data-name="${esc(t.label)}" data-prem="${t.weekly_premium}">Abschließen</button>`)}
      </div>`;
    }).join('')}</div>
    ${cv.hasContract && cv.status !== 'cancelled' ? '<div class="mt-mt"><button class="mt-btn danger" id="ins-cancel">Versicherung kündigen</button></div>' : ''}`;

    body.querySelectorAll('[data-sub]').forEach(b => b.onclick = () => insConfirm('subscribe', b.getAttribute('data-sub'), b.getAttribute('data-name'), b.getAttribute('data-prem')));
    body.querySelectorAll('[data-switch]').forEach(b => b.onclick = () => insConfirm('switch', b.getAttribute('data-switch'), b.getAttribute('data-name'), b.getAttribute('data-prem')));
    const cb = $('#ins-cancel'); if (cb) cb.onclick = () => insConfirm('cancel');
  }
  function insConfirm(action, tierKey, name, prem) {
    const texts = {
      subscribe: `Du schließt die <strong>${esc(name)}</strong> ab.<br>Erster Beitrag von <strong>${money(prem)}</strong> wird sofort abgebucht, danach wöchentlich.`,
      switch: `Du wechselst zur <strong>${esc(name)}</strong> (<strong>${money(prem)}</strong>/Woche).`,
      cancel: `Möchtest du deine Versicherung wirklich kündigen? Danach besteht kein Versicherungsschutz mehr.`
    };
    confirmDialog(action === 'cancel' ? 'Kündigen' : (action === 'switch' ? 'Wechseln' : 'Abschließen'), texts[action], async () => {
      const map = { subscribe: 'insurance.npc.subscribe', switch: 'insurance.npc.switch', cancel: 'insurance.npc.cancel' };
      const r = await api(map[action], { tier_key: tierKey });
      if (r.ok) { toast(r.data.message || 'Erledigt.', 'ok'); const rr = await api('insurance.npc.get'); if (rr.ok) renderInsuranceNPC({ insurance: rr.data }); }
      else errToast(r);
    }, action === 'cancel' ? 'Kündigen' : 'Bestätigen');
  }

  // ---- shared UI helpers ----
  function tableWrap(head, rows) {
    return `<div class="mt-table-wrap"><table class="mt-table"><thead><tr>${head.map(h => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${Array.isArray(rows) ? rows.join('') : rows}</tbody></table></div>`;
  }
  const emptyRow = (m) => `<div class="mt-empty">${esc(m || 'Keine Daten.')}</div>`;
  const listOrEmpty = (arr) => arr.length ? arr.join('') : emptyRow();
  function pager(st, fn) {
    const pages = Math.max(1, Math.ceil((st.total || 0) / (st.pageSize || 15)));
    if (pages <= 1) return '';
    return `<div class="mt-pager"><button class="mt-btn ghost" ${st.page <= 1 ? 'disabled' : ''} onclick="__mtpg(${st.page - 1})">←</button>
      Seite ${st.page} / ${pages} <button class="mt-btn ghost" ${st.page >= pages ? 'disabled' : ''} onclick="__mtpg(${st.page + 1})">→</button></div>`.replace(/__mtpg/g, registerPager(fn));
  }
  let pagerSeq = 0;
  function registerPager(fn) { const name = '__mtpg' + (++pagerSeq); window[name] = (p) => fn(p); return name; }
  function addTopBtn(label, cls, fn) { const b = el('button', 'mt-btn ' + cls, esc(label)); b.onclick = fn; $('#mt-top-actions').appendChild(b); }
  const errHtml = (r) => `<div class="mt-brk-warn">${esc((r.data && r.data.error) || 'Fehler.')}</div>`;
  const errBox = (r) => { $('#mt-content').innerHTML = errHtml(r); };
  const errToast = (r) => toast((r.data && r.data.error) || 'Fehler.', 'error');

  // ---- Visibility ----
  function hideAll() { $('#mt-root').classList.add('mt-hidden'); $('#mt-tablet').classList.add('mt-hidden'); $('#mt-insurance').classList.add('mt-hidden'); closeModal(); }
  function showTablet() { $('#mt-root').classList.remove('mt-hidden'); $('#mt-tablet').classList.remove('mt-hidden'); $('#mt-insurance').classList.add('mt-hidden'); }
  function showInsurance() { $('#mt-root').classList.remove('mt-hidden'); $('#mt-insurance').classList.remove('mt-hidden'); $('#mt-tablet').classList.add('mt-hidden'); }

  // ---- Message handler ----
  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.type === 'open') {
      S.mode = m.mode || 'tablet';
      const p = m.payload || {};
      if (S.mode === 'insurance') { applyBranding(); showInsurance(); renderInsuranceNPC(p); return; }
      S.branding = p.branding || {}; S.features = p.features || {}; S.perms = p.perms || {}; S.identity = p.identity || {};
      applyBranding();
      $('#mt-username').textContent = S.identity.name || '-';
      $('#mt-userrole').textContent = (S.identity.job || '') + ' • Rang ' + (S.identity.grade != null ? S.identity.grade : '-');
      $('#mt-avatar').textContent = (S.identity.name || 'M').charAt(0).toUpperCase();
      S.view = feat('dashboard') ? 'dashboard' : 'search';
      showTablet(); buildNav(); render();
    } else if (m.type === 'close') {
      hideAll();
    } else if (m.type === 'notify') {
      toast(m.message, m.level === 'success' ? 'ok' : (m.level === 'failed' || m.level === 'cancelled' ? 'error' : 'warn'));
    }
  });

  // ESC + close buttons
  document.addEventListener('keyup', (e) => { if (e.key === 'Escape') closeUI(); });
  document.addEventListener('click', (e) => {
    if (e.target && (e.target.id === 'mt-close' || e.target.id === 'mt-ins-close')) closeUI();
    if (e.target && e.target.id === 'mt-modal') closeModal(); // Klick auf Overlay
  });
})();
