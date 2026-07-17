/* LSPD MDT – NUI Frontend (Vanilla JS, self-contained).
   Generischer 'request'-Kanal zum Server-Dispatcher (serverseitige Rechtepruefung). */
(function () {
  'use strict';
  const RES = 'lspdtablet';
  const $ = (s, r) => (r || document).querySelector(s);
  const el = (t, c, h) => { const e = document.createElement(t); if (c) e.className = c; if (h != null) e.innerHTML = h; return e; };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (v) => '$' + (Math.floor(Number(v) || 0)).toLocaleString('de-DE');
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'id-' + Date.now() + '-' + Math.random().toString(16).slice(2));
  const badge = (s) => `<span class="mt-badge b-${esc(s)}">${esc(s)}</span>`;
  const fmtDate = (s) => s ? esc(String(s).replace('T', ' ').slice(0, 16)) : '-';

  function nui(name, data) {
    return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) })
      .then(r => r.json()).catch(() => ({ ok: false, data: { error: 'NUI-Fehler' } }));
  }
  const api = (action, data) => nui('request', { action, data: data || {} });
  function closeUI() { nui('close', {}); hideAll(); }

  const S = { branding: {}, features: {}, perms: {}, identity: {}, view: 'dashboard', citizen: null, penal: null, citIdem: null };
  const can = (p) => !!(S.perms['admin.full'] || S.perms[p]);
  const feat = (f) => S.features[f] !== false;

  // ---- Toast / Modal ----
  function toast(msg, level) { const t = el('div', 'mt-toast ' + (level || ''), esc(msg)); $('#mt-toasts').appendChild(t); setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 200); }, 3400); }
  function modal(title, body, actions) {
    const box = $('#mt-modal-box');
    box.innerHTML = `<h2>${esc(title)}</h2><div id="mt-modal-content">${body}</div><div class="mt-modal-actions" id="mt-modal-actions"></div>`;
    (actions || [{ label: 'Schließen', cls: 'ghost', fn: closeModal }]).forEach(a => { const b = el('button', 'mt-btn ' + (a.cls || ''), esc(a.label)); b.onclick = () => a.fn && a.fn(); $('#mt-modal-actions').appendChild(b); });
    $('#mt-modal').classList.remove('mt-hidden'); return box;
  }
  const closeModal = () => $('#mt-modal').classList.add('mt-hidden');
  function confirmDialog(title, html, onYes, yesLabel) { modal(title, html, [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: yesLabel || 'Bestätigen', cls: 'primary', fn: () => { closeModal(); onYes(); } }]); }

  function applyBranding() {
    const b = S.branding || {}, root = document.documentElement;
    if (b.colorPrimary) root.style.setProperty('--primary', b.colorPrimary);
    if (b.colorAccent) root.style.setProperty('--accent', b.colorAccent);
    if (b.colorBg) root.style.setProperty('--bg', b.colorBg);
    if ((b.theme || 'dark') === 'light') root.classList.add('mt-light'); else root.classList.remove('mt-light');
    if ($('#mt-dept')) $('#mt-dept').textContent = b.deptName || 'Police Department';
    if ($('#mt-server')) $('#mt-server').textContent = b.serverName || 'SunLife Roleplay';
    if (b.logo && $('#mt-logo')) $('#mt-logo').src = b.logo;
  }

  const NAV = [
    { id: 'dashboard', label: 'Dashboard', ico: '▤', feature: 'dashboard' },
    { id: 'search', label: 'Personen', ico: '⚇', perm: 'citizen.search', feature: 'citizenSearch' },
    { id: 'wanted', label: 'Fahndung', ico: '◎', perm: 'wanted.view', feature: 'wanted' },
    { id: 'penalcode', label: 'Strafenkatalog', ico: '≣', perm: 'penalcode.view', feature: 'penalcode' },
    { id: 'reports', label: 'Berichte', ico: '▦', perm: 'report.view', feature: 'reports' },
    { id: 'vehicles', label: 'Kennzeichen', ico: '⬒', perm: 'vehicle.lookup', feature: 'vehicles' },
    { id: 'staff', label: 'Beamte', ico: '☰', perm: 'staff.view', feature: 'staffOverview' },
    { id: 'logs', label: 'Protokolle', ico: '☷', perm: 'audit.view', feature: 'auditLog' },
    { id: 'settings', label: 'Einstellungen', ico: '⚙', perm: 'settings.edit', feature: 'settings' },
  ];
  function buildNav() {
    const nav = $('#mt-nav'); nav.innerHTML = '';
    NAV.forEach(n => { if (n.feature && !feat(n.feature)) return; if (n.perm && !can(n.perm)) return; const b = el('button', S.view === n.id ? 'active' : '', `<span class="ico">${n.ico}</span>${esc(n.label)}`); b.onclick = () => go(n.id); nav.appendChild(b); });
  }
  const go = (v) => { S.view = v; buildNav(); render(); };

  const TITLES = { dashboard: 'Dashboard', search: 'Personensuche', record: 'Personenakte', wanted: 'Fahndung / BOLO', penalcode: 'Strafenkatalog', reports: 'Berichte', vehicles: 'Kennzeichenabfrage', staff: 'Beamte im Dienst', logs: 'Protokolle', settings: 'Einstellungen' };
  const setLoading = () => ($('#mt-content').innerHTML = '<div class="mt-spinner"></div>');
  function render() {
    $('#mt-view-title').textContent = TITLES[S.view] || '';
    $('#mt-top-actions').innerHTML = '';
    ({ dashboard: renderDashboard, search: renderSearch, record: renderRecord, wanted: renderWanted, penalcode: renderPenal, reports: renderReports, vehicles: renderVehicles, staff: renderStaff, logs: renderLogs, settings: renderSettings }[S.view] || renderDashboard)();
  }

  // ---- shared UI helpers ----
  function tableWrap(head, rows) { return `<div class="mt-table-wrap"><table class="mt-table"><thead><tr>${head.map(h => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${Array.isArray(rows) ? rows.join('') : rows}</tbody></table></div>`; }
  const emptyRow = (m) => `<div class="mt-empty">${esc(m || 'Keine Daten.')}</div>`;
  const listOrEmpty = (a) => a.length ? a.join('') : emptyRow();
  const statCard = (l, v, i) => `<div class="mt-card mt-stat"><span class="ico">${i}</span><span class="val">${esc(v)}</span><span class="lbl">${esc(l)}</span></div>`;
  function addTopBtn(l, c, fn) { const b = el('button', 'mt-btn ' + c, esc(l)); b.onclick = fn; $('#mt-top-actions').appendChild(b); }
  const errHtml = (r) => `<div class="mt-brk-warn">${esc((r.data && r.data.error) || 'Fehler.')}</div>`;
  const errBox = (r) => { $('#mt-content').innerHTML = errHtml(r); };
  const errToast = (r) => toast((r.data && r.data.error) || 'Fehler.', 'error');
  let pagerSeq = 0;
  function pager(st, fn) { const pages = Math.max(1, Math.ceil((st.total || 0) / (st.pageSize || 15))); if (pages <= 1) return ''; const name = '__pg' + (++pagerSeq); window[name] = (p) => fn(p); return `<div class="mt-pager"><button class="mt-btn ghost" ${st.page <= 1 ? 'disabled' : ''} onclick="${name}(${st.page - 1})">←</button> Seite ${st.page} / ${pages} <button class="mt-btn ghost" ${st.page >= pages ? 'disabled' : ''} onclick="${name}(${st.page + 1})">→</button></div>`; }

  // ================= FINGERPRINT =================
  function fpScan() {
    $('#fp-overlay').classList.remove('mt-hidden');
    nui('fingerprintScan', {}).then(res => {
      $('#fp-overlay').classList.add('mt-hidden');
      if (res && res.ok && res.data && res.data.scan) {
        toast(res.data.message || 'Person identifiziert.', 'ok');
        openScanResult(res.data.scan);
      } else {
        toast((res && res.data && res.data.error) || 'Scan fehlgeschlagen.', 'error');
      }
    });
  }
  function openScanResult(full) { S.citizen = full; S.citizen.identifier = full.record.identifier; recordTab = 'overview'; S.view = 'record'; buildNav(); render_record(); }

  // ================= DASHBOARD =================
  async function renderDashboard() {
    setLoading();
    const r = await api('dashboard.data'); if (!r.ok) return errBox(r);
    const d = r.data.dashboard || {};
    $('#mt-content').innerHTML = `
      <div class="mt-grid mt-cols-4 mt-mb">
        ${statCard('Beamte im Dienst', (d.onDuty || []).length, '★')}
        ${statCard('Aktive Fahndungen', d.activeWanted || 0, '◎')}
        ${statCard('Offene Berichte', d.openReports || 0, '▦')}
        ${statCard('Anzeigen heute', d.todayCharges || 0, '§')}
      </div>
      ${(d.notice && d.notice.text) ? `<div class="mt-brk-note mt-mb">${esc(d.notice.text)}</div>` : ''}
      <div class="mt-grid mt-cols-2">
        <div class="mt-card"><h3>Aktuelle Fahndungen</h3>${listOrEmpty((d.topWanted || []).map(w => `<div class="mt-kv" data-open="${esc(w.identifier)}" style="cursor:pointer"><span>${esc(w.firstname)} ${esc(w.lastname)} · ${esc(w.reason)}</span><span>${badge(w.level)}</span></div>`))}</div>
        <div class="mt-card"><h3>Im Dienst</h3>${listOrEmpty((d.onDuty || []).map(m => `<div class="mt-kv"><span>${esc(m.name)}</span><span>${esc(m.grade_label || '')}</span></div>`))}</div>
      </div>
      <div class="mt-card mt-mt"><h3>Zuletzt bearbeitete Akten</h3>${listOrEmpty((d.recentCitizens || []).map(p => `<div class="mt-kv" data-open="${esc(p.identifier)}" style="cursor:pointer"><span>${esc(p.firstname)} ${esc(p.lastname)} ${p.is_wanted ? '<span class="wanted-chip">GESUCHT</span>' : ''}</span><span>${fmtDate(p.updated_at)}</span></div>`))}</div>`;
    $('#mt-content').querySelectorAll('[data-open]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-open')));
    if (can('fingerprint.scan') && feat('fingerprint')) addTopBtn('☝ Fingerabdruck scannen', 'accent', fpScan);
    if (can('citizen.search')) addTopBtn('Personensuche', 'primary', () => go('search'));
  }

  // ================= SEARCH =================
  let searchState = { q: '', field: 'auto', page: 1, total: 0, pageSize: 15 };
  function renderSearch() {
    if (can('fingerprint.scan') && feat('fingerprint')) addTopBtn('☝ Fingerabdruck scannen', 'accent', fpScan);
    $('#mt-content').innerHTML = `
      <div class="mt-searchbar">
        <input id="s-q" placeholder="Name, Geburtsdatum, Telefon, Charakter-ID, Fingerabdruck…" value="${esc(searchState.q)}"/>
        <select id="s-field"><option value="auto">Alle Felder</option><option value="firstname">Vorname</option><option value="lastname">Nachname</option><option value="dob">Geburtsdatum</option><option value="phone">Telefon</option><option value="charid">Charakter-ID</option><option value="fingerprint">Fingerabdruck</option></select>
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
    const r = await api('citizens.search', { q: searchState.q, field: searchState.field, page: searchState.page, pageSize: searchState.pageSize });
    if (!r.ok) return ($('#s-results').innerHTML = errHtml(r));
    searchState.total = r.data.total || 0; const rows = r.data.results || [];
    if (!rows.length) { $('#s-results').innerHTML = '<div class="mt-empty">Keine Treffer.</div>'; return; }
    $('#s-results').innerHTML = `<div class="mt-list">${rows.map(p => `<div class="mt-list-item" data-id="${esc(p.identifier)}"><div><strong>${esc(p.firstname)} ${esc(p.lastname)}</strong> ${Number(p.is_wanted) ? '<span class="wanted-chip">GESUCHT</span>' : ''}<div class="meta">${p.dob ? 'geb. ' + esc(p.dob) + ' · ' : ''}${p.phone ? 'Tel. ' + esc(p.phone) + ' · ' : ''}${p.fingerprint ? esc(p.fingerprint) : ''}</div></div><span class="mt-btn ghost">Öffnen →</span></div>`).join('')}</div>${pager(searchState, doSearch)}`;
    $('#s-results').querySelectorAll('[data-id]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-id')));
  }

  // ================= RECORD =================
  let recordTab = 'overview';
  async function openRecord(identifier) {
    if (!can('citizen.view')) return toast('Keine Berechtigung.', 'error');
    S.view = 'record'; buildNav(); $('#mt-view-title').textContent = 'Personenakte'; $('#mt-top-actions').innerHTML = ''; setLoading();
    const r = await api('citizens.open', { identifier });
    if (!r.ok) return errBox(r);
    S.citizen = r.data; S.citizen.identifier = r.data.record.identifier; recordTab = 'overview'; render_record();
  }
  function renderRecord() { if (!S.citizen) return go('search'); render_record(); }
  function render_record() {
    $('#mt-top-actions').innerHTML = ''; $('#mt-view-title').textContent = 'Personenakte';
    addTopBtn('← Zurück', 'ghost', () => go('search'));
    if (can('wanted.manage') && feat('wanted')) addTopBtn('◎ Zur Fahndung', 'danger', addWantedDialog);
    if (can('citation.create') && feat('citations')) addTopBtn('§ Anzeige/Bußgeld', 'accent', openCitationForm);
    const c = S.citizen, rec = c.record;
    const tabs = [['overview', 'Übersicht'], ['priors', 'Vorstrafen'], ['reports', 'Berichte']];
    if (c.canNotes) tabs.push(['notes', 'Notizen']);
    $('#mt-content').innerHTML = `
      <div class="mt-card mt-mb"><div class="mt-row">
        <div><label>Name</label><strong>${esc(rec.firstname)} ${esc(rec.lastname)}</strong> ${rec.is_wanted ? '<span class="wanted-chip">GESUCHT</span>' : ''}</div>
        <div><label>Geburtsdatum</label>${esc(rec.dateofbirth || '-')}</div>
        <div><label>Telefon</label>${esc(rec.phone || '-')}</div>
        <div><label>Fingerabdruck</label><strong style="color:var(--accent)">${esc(rec.fingerprint || '-')}</strong></div>
        <div><label>Vorstrafen</label>${esc(c.priors.count)} · Haft ${esc(c.priors.jail)} Mon.</div>
      </div></div>
      <div class="mt-tabs">${tabs.map(t => `<div class="mt-tab ${recordTab === t[0] ? 'active' : ''}" data-tab="${t[0]}">${esc(t[1])}</div>`).join('')}</div>
      <div id="rec-body"></div>`;
    document.querySelectorAll('[data-tab]').forEach(x => x.onclick = () => { recordTab = x.getAttribute('data-tab'); render_record(); });
    const body = $('#rec-body');
    ({ overview: recOverview, priors: recPriors, reports: recReports, notes: recNotes }[recordTab] || recOverview)(body);
  }
  function recOverview(body) {
    const c = S.citizen, rec = c.record, lic = rec.licenses || {};
    const licKeys = Object.keys(lic).length ? lic : { driver: false, weapon: false };
    const pills = Object.keys(licKeys).map(k => `<span class="lic-pill ${licKeys[k] ? 'lic-on' : 'lic-off'}" ${c.canLicenses ? `data-lic="${esc(k)}" data-val="${licKeys[k] ? 0 : 1}" style="cursor:pointer"` : ''}>${licKeys[k] ? '✓' : '✕'} ${esc(k)}</span>`).join('');
    body.innerHTML = `
      <div class="mt-grid mt-cols-2">
        <div class="mt-card"><h3>Aktive Fahndung</h3>${(c.wanted || []).length ? (c.wanted.map(w => `<div class="mt-kv"><span>${badge(w.level)} ${esc(w.reason)}</span><span>${esc(w.officer_name)} · ${fmtDate(w.created_at)} ${can('wanted.manage') ? `<button class="mt-btn ghost" data-clear="${w.id}">aufheben</button>` : ''}</span></div>`).join('')) : emptyRow('Keine aktive Fahndung.')}</div>
        <div class="mt-card"><h3>Lizenzen</h3><div>${pills || emptyRow('Keine Daten.')}</div>
          ${c.canEdit ? '<div class="mt-mt"><label>Interne Hinweise</label><textarea id="cz-notes">' + esc(rec.notes || '') + '</textarea><div class="mt-mt"><button class="mt-btn primary" id="cz-save">Speichern</button></div></div>' : ''}
        </div>
      </div>`;
    body.querySelectorAll('[data-lic]').forEach(x => x.onclick = async () => { const r = await api('citizens.setLicense', { identifier: S.citizen.identifier, key: x.getAttribute('data-lic'), value: x.getAttribute('data-val') === '1' }); if (r.ok) { S.citizen.record.licenses = r.data.licenses; render_record(); } else errToast(r); });
    body.querySelectorAll('[data-clear]').forEach(x => x.onclick = () => confirmDialog('Fahndung aufheben', 'Diese Fahndung wirklich aufheben?', async () => { const r = await api('wanted.clear', { id: +x.getAttribute('data-clear') }); if (r.ok) { toast('Aufgehoben.', 'ok'); refreshRecord(); } else errToast(r); }));
    if (c.canEdit && $('#cz-save')) $('#cz-save').onclick = async () => { const r = await api('citizens.update', { identifier: S.citizen.identifier, notes: $('#cz-notes').value }); if (r.ok) toast('Gespeichert.', 'ok'); else errToast(r); };
  }
  function recPriors(body) {
    const ch = S.citizen.charges || [];
    body.innerHTML = ch.length ? tableWrap(['Az.', 'Grund', 'Bußgeld', 'Haft', 'Punkte', 'Status', 'Datum', ''], ch.map(x => `<tr><td>${esc(x.charge_no)}</td><td>${esc(x.reason)}</td><td class="r">${money(x.fine_total)}</td><td class="r">${esc(x.jail_total)}</td><td class="r">${esc(x.points_total)}</td><td>${badge(x.status)}</td><td>${fmtDate(x.created_at)}</td><td>${can('citation.cancel') && x.status === 'issued' ? `<button class="mt-btn danger" data-cancel="${x.id}">Storno</button>` : ''}</td></tr>`)) : emptyRow('Keine Vorstrafen.');
    body.querySelectorAll('[data-cancel]').forEach(x => x.onclick = () => confirmDialog('Anzeige stornieren', 'Diese Anzeige stornieren?', async () => { const r = await api('citations.cancel', { id: +x.getAttribute('data-cancel'), reason: 'MDT' }); if (r.ok) { toast('Storniert.', 'ok'); refreshRecord(); } else errToast(r); }));
  }
  function recReports(body) {
    const rp = S.citizen.reports || [];
    body.innerHTML = rp.length ? tableWrap(['Nr.', 'Titel', 'Typ', 'Rolle', 'Status', 'Datum', ''], rp.map(x => `<tr><td>${esc(x.report_no)}</td><td>${esc(x.title)}</td><td>${esc(x.type)}</td><td>${badge(x.role)}</td><td>${badge(x.status)}</td><td>${fmtDate(x.created_at)}</td><td><button class="mt-btn ghost" data-rep="${x.id}">Ansehen</button></td></tr>`)) : emptyRow('Keine Berichte.');
    body.querySelectorAll('[data-rep]').forEach(x => x.onclick = () => openReport(x.getAttribute('data-rep')));
  }
  async function recNotes(body) {
    const notes = S.citizen.notes || [];
    body.innerHTML = `${can('notes.add') ? '<div class="mt-card mt-mb"><h3>Neue Notiz</h3><textarea id="note-body" placeholder="Interne Notiz…"></textarea><div class="mt-mt"><button class="mt-btn primary" id="add-note">Notiz hinzufügen</button></div></div>' : ''}
      ${notes.length ? notes.map(n => `<div class="mt-card mt-mb"><div class="mt-kv"><span><strong>${esc(n.author_name)}</strong></span><span>${fmtDate(n.created_at)}</span></div><div class="mt-mt">${esc(n.body)}</div></div>`).join('') : emptyRow('Keine Notizen.')}`;
    if (can('notes.add')) $('#add-note').onclick = async () => { const b = $('#note-body').value.trim(); if (!b) return; const r = await api('citizens.addNote', { identifier: S.citizen.identifier, body: b }); if (r.ok) { toast('Notiz gespeichert.', 'ok'); refreshRecord(); } else errToast(r); };
  }
  async function refreshRecord() { const r = await api('citizens.open', { identifier: S.citizen.identifier }); if (r.ok) { S.citizen = r.data; S.citizen.identifier = r.data.record.identifier; render_record(); } }

  function addWantedDialog() {
    modal('Zur Fahndung ausschreiben', `<label>Grund</label><textarea id="w-reason"></textarea><div class="mt-mt"><label>Stufe</label><select id="w-level"><option value="low">Niedrig</option><option value="medium" selected>Mittel</option><option value="high">Hoch</option></select></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Ausschreiben', cls: 'danger', fn: async () => { const r = await api('wanted.add', { identifier: S.citizen.identifier, reason: $('#w-reason').value, level: $('#w-level').value }); if (r.ok) { closeModal(); toast(r.data.message || 'Ausgeschrieben.', 'ok'); refreshRecord(); } else errToast(r); } }]);
  }

  // ---- Citation (Anzeige/Bußgeld) ----
  let citLines = [];
  async function openCitationForm() {
    if (!S.penal) { const r = await api('penalcode.list'); if (r.ok) S.penal = r.data; }
    S.citIdem = uuid(); citLines = [];
    const offs = (S.penal && S.penal.offenses) || [];
    const opts = offs.map(o => `<option value="${o.code}">${esc(o.label)} – ${money(o.fine)}${o.jail ? ' / ' + o.jail + ' Mon.' : ''}</option>`).join('');
    modal('Anzeige erstellen – ' + esc(S.citizen.record.firstname) + ' ' + esc(S.citizen.record.lastname), `
      <label>Delikt hinzufügen</label><div class="mt-row"><select id="c-off">${opts}</select><input id="c-qty" type="number" value="1" min="1" style="max-width:80px"/><button class="mt-btn" id="c-add">＋</button></div>
      <div id="c-lines" class="mt-mt"></div>
      <div class="mt-mt"><label>Grund / Vermerk</label><input id="c-reason" placeholder="z.B. Verkehrskontrolle"/></div>
      <div id="c-totals" class="mt-mt"></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }]);
    $('#c-add').onclick = () => { const code = $('#c-off').value, qty = Math.max(1, parseInt($('#c-qty').value) || 1), o = offs.find(x => x.code === code); if (o) { citLines.push({ code, quantity: qty, label: o.label, fine: o.fine, jail: o.jail, points: o.points }); drawCit(); } };
    drawCit();
  }
  function drawCit() {
    const box = $('#c-lines'); if (!box) return;
    if (!citLines.length) { box.innerHTML = '<div class="mt-empty" style="padding:12px">Noch keine Delikte.</div>'; $('#c-totals').innerHTML = ''; return; }
    box.innerHTML = citLines.map((l, i) => `<div class="mt-kv"><span>${esc(l.label)} × ${l.quantity}</span><span>${money(l.fine * l.quantity)}${l.jail ? ' · ' + (l.jail * l.quantity) + ' Mon.' : ''} <button class="mt-btn ghost" data-del="${i}">✕</button></span></div>`).join('');
    box.querySelectorAll('[data-del]').forEach(x => x.onclick = () => { citLines.splice(+x.getAttribute('data-del'), 1); drawCit(); });
    const fine = citLines.reduce((a, l) => a + l.fine * l.quantity, 0), jail = citLines.reduce((a, l) => a + l.jail * l.quantity, 0), pts = citLines.reduce((a, l) => a + l.points * l.quantity, 0);
    $('#c-totals').innerHTML = `<div class="mt-breakdown"><div class="mt-brk-row"><span>Bußgeld gesamt</span><span>${money(fine)}</span></div><div class="mt-brk-row"><span>Haft gesamt</span><span>${jail} Monate</span></div><div class="mt-brk-row"><span>Führerscheinpunkte</span><span>${pts}</span></div><div class="mt-brk-row total"><span>Zu zahlen</span><span>${money(fine)}</span></div></div>
      <div class="mt-modal-actions"><button class="mt-btn ghost" id="c-cancel">Abbrechen</button><button class="mt-btn primary" id="c-confirm">Anzeige ausstellen (${money(fine)})</button></div>`;
    $('#c-cancel').onclick = closeModal;
    const btn = $('#c-confirm');
    btn.onclick = async () => { btn.disabled = true; btn.textContent = 'Wird erstellt…'; const r = await api('citations.create', { identifier: S.citizen.identifier, items: citLines.map(l => ({ code: l.code, quantity: l.quantity })), reason: $('#c-reason').value, idempotency_key: S.citIdem }); if (r.ok) { toast(r.data.duplicate ? 'Anzeige existierte bereits.' : 'Anzeige erstellt.', 'ok'); closeModal(); recordTab = 'priors'; refreshRecord(); } else { errToast(r); btn.disabled = false; btn.textContent = 'Erneut versuchen'; } };
  }

  // ================= WANTED =================
  async function renderWanted() {
    setLoading();
    const r = await api('wanted.list'); if (!r.ok) return errBox(r);
    const rows = r.data.wanted || [];
    $('#mt-content').innerHTML = rows.length ? tableWrap(['Person', 'Stufe', 'Grund', 'Beamter', 'Datum', ''], rows.map(w => `<tr><td data-open="${esc(w.identifier)}" style="cursor:pointer"><strong>${esc(w.firstname)} ${esc(w.lastname)}</strong><div class="meta">${esc(w.fingerprint || '')}</div></td><td>${badge(w.level)}</td><td>${esc(w.reason)}</td><td>${esc(w.officer_name)}</td><td>${fmtDate(w.created_at)}</td><td>${can('wanted.manage') ? `<button class="mt-btn ghost" data-clear="${w.id}">aufheben</button>` : ''}</td></tr>`)) : emptyRow('Keine aktiven Fahndungen.');
    $('#mt-content').querySelectorAll('[data-open]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-open')));
    $('#mt-content').querySelectorAll('[data-clear]').forEach(x => x.onclick = () => confirmDialog('Fahndung aufheben', 'Diese Fahndung wirklich aufheben?', async () => { const r2 = await api('wanted.clear', { id: +x.getAttribute('data-clear') }); if (r2.ok) { toast('Aufgehoben.', 'ok'); renderWanted(); } else errToast(r2); }));
  }

  // ================= PENALCODE =================
  async function renderPenal() {
    setLoading();
    const r = await api('penalcode.list', { all: true }); if (!r.ok) return errBox(r);
    S.penal = r.data; const cats = r.data.categories || [], offs = r.data.offenses || [];
    const catName = (id) => { const c = cats.find(x => x.id === id); return c ? c.label : '–'; };
    if (r.data.canEdit) { addTopBtn('＋ Delikt', 'primary', () => editOffense(null, cats)); addTopBtn('＋ Kategorie', 'ghost', editPenalCat); }
    $('#mt-content').innerHTML = tableWrap(['Code', 'Delikt', 'Kategorie', 'Bußgeld', 'Haft', 'Punkte', 'Status', ''], offs.map(o => `<tr><td>${esc(o.code)}</td><td>${esc(o.label)}<div class="meta">${esc(o.description || '')}</div></td><td>${esc(catName(o.category_id))}</td><td class="r">${money(o.fine)}</td><td class="r">${esc(o.jail)}</td><td class="r">${esc(o.points)}</td><td>${o.active ? badge('active') : badge('pending')}</td><td>${r.data.canEdit ? `<button class="mt-btn ghost" data-edit="${o.id}">✎</button> <button class="mt-btn ghost" data-tog="${o.id}">${o.active ? '⏸' : '▶'}</button> <button class="mt-btn danger" data-arch="${o.id}">🗄</button>` : ''}</td></tr>`));
    const c = $('#mt-content');
    c.querySelectorAll('[data-edit]').forEach(x => x.onclick = () => editOffense(offs.find(o => o.id == x.getAttribute('data-edit')), cats));
    c.querySelectorAll('[data-tog]').forEach(x => x.onclick = async () => { const r2 = await api('penalcode.toggle', { id: +x.getAttribute('data-tog') }); if (r2.ok) renderPenal(); else errToast(r2); });
    c.querySelectorAll('[data-arch]').forEach(x => x.onclick = () => confirmDialog('Archivieren', 'Delikt archivieren?', async () => { const r2 = await api('penalcode.archive', { id: +x.getAttribute('data-arch') }); if (r2.ok) renderPenal(); else errToast(r2); }));
  }
  function editOffense(o, cats) {
    o = o || {};
    modal(o.id ? 'Delikt bearbeiten' : 'Neues Delikt', `
      <div class="mt-row"><div><label>Bezeichnung</label><input id="o-label" value="${esc(o.label || '')}"/></div><div><label>Code</label><input id="o-code" value="${esc(o.code || '')}" ${o.id ? 'disabled' : ''}/></div></div>
      <div class="mt-mt"><label>Beschreibung</label><input id="o-desc" value="${esc(o.description || '')}"/></div>
      <div class="mt-row mt-mt"><div><label>Bußgeld ($)</label><input id="o-fine" type="number" value="${esc(o.fine || 0)}"/></div><div><label>Haft (Monate)</label><input id="o-jail" type="number" value="${esc(o.jail || 0)}"/></div><div><label>Punkte</label><input id="o-points" type="number" value="${esc(o.points || 0)}"/></div></div>
      <div class="mt-mt"><label>Kategorie</label><select id="o-cat">${cats.map(c => `<option value="${c.id}" ${o.category_id == c.id ? 'selected' : ''}>${esc(c.label)}</option>`).join('')}</select></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => { const p = { id: o.id, label: $('#o-label').value, code: $('#o-code').value, description: $('#o-desc').value, fine: parseInt($('#o-fine').value) || 0, jail: parseInt($('#o-jail').value) || 0, points: parseInt($('#o-points').value) || 0, category_id: +$('#o-cat').value }; const r = await api('penalcode.saveOffense', p); if (r.ok) { closeModal(); toast('Gespeichert.', 'ok'); renderPenal(); } else errToast(r); } }]);
  }
  function editPenalCat() { modal('Neue Kategorie', '<label>Bezeichnung</label><input id="pc-label"/><div class="mt-mt"><label>Sortierung</label><input id="pc-sort" type="number" value="0"/></div>', [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => { const r = await api('penalcode.saveCategory', { label: $('#pc-label').value, sort: parseInt($('#pc-sort').value) || 0 }); if (r.ok) { closeModal(); renderPenal(); } else errToast(r); } }]); }

  // ================= REPORTS =================
  let repState = { page: 1, status: '' };
  function renderReports() {
    if (can('report.create')) addTopBtn('＋ Neuer Bericht', 'primary', newReport);
    $('#mt-content').innerHTML = `<div class="mt-searchbar"><select id="rp-status" style="width:200px"><option value="">Alle</option><option value="open">Offen</option><option value="closed">Geschlossen</option></select></div><div id="rp-body"><div class="mt-spinner"></div></div>`;
    $('#rp-status').value = repState.status; $('#rp-status').onchange = () => { repState.status = $('#rp-status').value; loadReports(1); };
    loadReports(1);
  }
  async function loadReports(page) {
    repState.page = page || 1;
    const r = await api('reports.list', { page: repState.page, status: repState.status });
    const body = $('#rp-body'); if (!r.ok) return (body.innerHTML = errHtml(r));
    const rows = r.data.rows || [];
    body.innerHTML = rows.length ? tableWrap(['Nr.', 'Titel', 'Typ', 'Beamter', 'Status', 'Datum', ''], rows.map(x => `<tr><td>${esc(x.report_no)}</td><td>${esc(x.title)}</td><td>${esc(x.type)}</td><td>${esc(x.officer_name)}</td><td>${badge(x.status)}</td><td>${fmtDate(x.created_at)}</td><td><button class="mt-btn ghost" data-rep="${x.id}">Öffnen</button></td></tr>`)) + pager({ page: repState.page, total: r.data.total, pageSize: 20 }, loadReports) : emptyRow('Keine Berichte.');
    body.querySelectorAll('[data-rep]').forEach(x => x.onclick = () => openReport(x.getAttribute('data-rep')));
  }
  function newReport() {
    modal('Neuer Bericht', `<label>Titel</label><input id="nr-title"/><div class="mt-mt"><label>Typ</label><select id="nr-type"><option value="incident">Vorfall</option><option value="arrest">Festnahme</option><option value="traffic">Verkehr</option><option value="investigation">Ermittlung</option></select></div><div class="mt-mt"><label>Bericht</label><textarea id="nr-body" style="min-height:120px"></textarea></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Speichern', cls: 'primary', fn: async () => { const r = await api('reports.create', { title: $('#nr-title').value, type: $('#nr-type').value, body: $('#nr-body').value }); if (r.ok) { closeModal(); toast('Bericht gespeichert.', 'ok'); if (S.view === 'reports') loadReports(1); else openReport(r.data.id); } else errToast(r); } }]);
  }
  async function openReport(id) {
    const r = await api('reports.get', { id }); if (!r.ok) return errToast(r);
    const rep = r.data.report, involved = r.data.involved || [], evidence = r.data.evidence || [];
    modal('Bericht ' + esc(rep.report_no), `
      <div class="mt-kv"><span>Titel</span><span><strong>${esc(rep.title)}</strong></span></div>
      <div class="mt-kv"><span>Typ / Status</span><span>${esc(rep.type)} · ${badge(rep.status)}</span></div>
      <div class="mt-kv"><span>Beamter</span><span>${esc(rep.officer_name)}</span></div>
      <div class="mt-mt"><label>Bericht</label>${esc(rep.body || '-')}</div>
      <div class="mt-mt"><label>Beteiligte Personen</label>${involved.length ? involved.map(p => `<div class="mt-kv"><span>${esc(p.name || p.identifier)}</span><span>${badge(p.role)}</span></div>`).join('') : '<div class="meta">keine</div>'}</div>
      <div class="mt-mt"><label>Beweismittel</label>${evidence.length ? evidence.map(e => `<div class="mt-kv"><span>${esc(e.label)}</span><span class="meta">${esc(e.description || '')}</span></div>`).join('') : '<div class="meta">keine</div>'}</div>
      ${r.data.canEdit ? '<div class="mt-mt"><label>Beweismittel hinzufügen</label><div class="mt-row"><input id="ev-label" placeholder="Bezeichnung"/><input id="ev-desc" placeholder="Beschreibung"/><button class="mt-btn" id="ev-add">＋</button></div></div>' : ''}`,
      [{ label: 'Schließen', cls: 'ghost', fn: closeModal },
       r.data.canClose && rep.status === 'open' ? { label: 'Bericht schließen', cls: 'primary', fn: async () => { const rr = await api('reports.close', { id: rep.id }); if (rr.ok) { closeModal(); toast('Geschlossen.', 'ok'); if (S.view === 'reports') loadReports(repState.page); } else errToast(rr); } } : null].filter(Boolean));
    if (r.data.canEdit && $('#ev-add')) $('#ev-add').onclick = async () => { const lbl = $('#ev-label').value.trim(); if (!lbl) return; const rr = await api('reports.update', { id: rep.id, addEvidence: { label: lbl, description: $('#ev-desc').value } }); if (rr.ok) { toast('Beweismittel hinzugefügt.', 'ok'); openReport(rep.id); } else errToast(rr); };
  }

  // ================= VEHICLES =================
  function renderVehicles() {
    $('#mt-content').innerHTML = `<div class="mt-searchbar"><input id="v-plate" placeholder="Kennzeichen eingeben…"/><button class="mt-btn primary" id="v-go">Abfragen</button></div><div id="v-body"></div>`;
    $('#v-go').onclick = plateLookup; $('#v-plate').onkeydown = (e) => { if (e.key === 'Enter') plateLookup(); };
  }
  async function plateLookup() {
    const plate = $('#v-plate').value.trim(); if (!plate) return;
    $('#v-body').innerHTML = '<div class="mt-spinner"></div>';
    const r = await api('vehicles.lookup', { plate });
    if (!r.ok) return ($('#v-body').innerHTML = errHtml(r));
    const d = r.data, o = d.owner;
    $('#v-body').innerHTML = `<div class="mt-card mt-mb"><h3>Kennzeichen ${esc(d.plate)}</h3>
      ${o ? `<div class="mt-kv"><span>Halter</span><span data-open="${esc(o.identifier)}" style="cursor:pointer"><strong>${esc(o.firstname)} ${esc(o.lastname)}</strong> ${Number(o.is_wanted) ? '<span class="wanted-chip">GESUCHT</span>' : ''}</span></div>${o.fingerprint ? `<div class="mt-kv"><span>Fingerabdruck</span><span>${esc(o.fingerprint)}</span></div>` : ''}` : '<div class="meta">Kein Halter gefunden (nicht registriert).</div>'}
    </div>
    <div class="mt-card"><h3>Markierungen</h3>${(d.flags || []).length ? d.flags.map(f => `<div class="mt-kv"><span>${badge('high')} ${esc(f.flag)} – ${esc(f.reason)}</span><span>${d.canFlag ? `<button class="mt-btn ghost" data-cf="${f.id}">entfernen</button>` : ''}</span></div>`).join('') : '<div class="meta">keine</div>'}
      ${d.canFlag ? `<div class="mt-mt mt-row"><select id="vf-flag" style="max-width:150px"><option value="stolen">Gestohlen</option><option value="impound">Beschlagnahmt</option><option value="bolo">BOLO</option></select><input id="vf-reason" placeholder="Grund"/><button class="mt-btn danger" id="vf-add">Markieren</button></div>` : ''}</div>`;
    $('#v-body').querySelectorAll('[data-open]').forEach(x => x.onclick = () => openRecord(x.getAttribute('data-open')));
    $('#v-body').querySelectorAll('[data-cf]').forEach(x => x.onclick = async () => { const rr = await api('vehicles.clearFlag', { id: +x.getAttribute('data-cf') }); if (rr.ok) plateLookup(); else errToast(rr); });
    if (d.canFlag && $('#vf-add')) $('#vf-add').onclick = async () => { const rr = await api('vehicles.flag', { plate: d.plate, flag: $('#vf-flag').value, reason: $('#vf-reason').value }); if (rr.ok) { toast('Markiert.', 'ok'); plateLookup(); } else errToast(rr); };
  }

  // ================= STAFF / LOGS / SETTINGS =================
  async function renderStaff() {
    setLoading(); const r = await api('staff.overview'); if (!r.ok) return errBox(r);
    $('#mt-content').innerHTML = `<div class="mt-card mt-mb"><h3>Im Dienst (${(r.data.onDuty || []).length})</h3>${listOrEmpty((r.data.onDuty || []).map(m => `<div class="mt-kv"><span>${esc(m.name)}</span><span>${esc(m.grade_label || '')}</span></div>`))}</div>
      <div class="mt-card"><h3>Letzte Aktivitäten</h3>${tableWrap(['Beamter', 'Aktion', 'Ziel', 'Ergebnis', 'Zeit'], (r.data.activity || []).map(a => `<tr><td>${esc(a.actor_name)}</td><td>${esc(a.action)}</td><td>${esc(a.target_type)} ${esc(a.target_id || '')}</td><td>${badge(a.result)}</td><td>${fmtDate(a.created_at)}</td></tr>`))}</div>`;
  }
  let logState = { page: 1, category: 'all' };
  function renderLogs() {
    $('#mt-content').innerHTML = `<div class="mt-searchbar"><select id="log-cat" style="width:220px"><option value="all">Alle Kategorien</option><option value="default">Allgemein</option><option value="citations">Anzeigen</option><option value="wanted">Fahndung</option><option value="settings">Einstellungen</option><option value="security">Sicherheit</option></select></div><div id="log-body"><div class="mt-spinner"></div></div>`;
    $('#log-cat').value = logState.category; $('#log-cat').onchange = () => { logState.category = $('#log-cat').value; loadLogs(1); }; loadLogs(1);
  }
  async function loadLogs(page) {
    logState.page = page || 1;
    const r = await api('audit.list', { page: logState.page, category: logState.category, pageSize: 25 });
    const body = $('#log-body'); if (!r.ok) return (body.innerHTML = errHtml(r));
    const rows = r.data.rows || [];
    body.innerHTML = rows.length ? tableWrap(['Zeit', 'Beamter', 'Kategorie', 'Aktion', 'Ziel', 'Ergebnis'], rows.map(a => `<tr><td>${fmtDate(a.created_at)}</td><td>${esc(a.actor_name)}</td><td>${esc(a.category)}</td><td>${esc(a.action)}</td><td>${esc(a.target_type)} ${esc(a.target_id || '')}</td><td>${badge(a.result)}</td></tr>`)) + pager({ page: logState.page, total: r.data.total, pageSize: 25 }, loadLogs) : emptyRow('Keine Einträge.');
  }
  async function renderSettings() {
    setLoading(); const r = await api('settings.get'); if (!r.ok) return errBox(r);
    const b = r.data.branding || {}, fe = r.data.features || {}, notice = r.data.notice || {};
    const featRows = Object.keys(fe).map(k => `<label style="display:flex;gap:8px;align-items:center"><input type="checkbox" data-feat="${k}" ${fe[k] ? 'checked' : ''} style="width:auto"/> ${esc(k)}</label>`).join('');
    $('#mt-content').innerHTML = `<div class="mt-grid mt-cols-2">
      <div class="mt-card"><h3>Branding</h3>
        <label>Servername</label><input id="b-serverName" value="${esc(b.serverName || '')}"/>
        <div class="mt-mt"><label>Dienststelle</label><input id="b-deptName" value="${esc(b.deptName || '')}"/></div>
        <div class="mt-row mt-mt"><div><label>Hauptfarbe</label><input id="b-colorPrimary" value="${esc(b.colorPrimary || '')}"/></div><div><label>Akzentfarbe</label><input id="b-colorAccent" value="${esc(b.colorAccent || '')}"/></div></div>
        <div class="mt-mt"><label>Theme</label><select id="b-theme"><option value="dark" ${b.theme === 'dark' ? 'selected' : ''}>Dunkel</option><option value="light" ${b.theme === 'light' ? 'selected' : ''}>Hell</option></select></div>
        <div class="mt-mt"><button class="mt-btn primary" id="save-brand">Branding speichern</button></div></div>
      <div class="mt-card"><h3>Module</h3><div class="mt-list">${featRows}</div><div class="mt-mt"><button class="mt-btn primary" id="save-feat">Module speichern</button></div>
        <h3 class="mt-mt">Interner Hinweis</h3><textarea id="s-notice">${esc(notice.text || '')}</textarea><div class="mt-mt"><button class="mt-btn" id="save-notice">Hinweis speichern</button></div></div>
      </div>`;
    $('#save-brand').onclick = async () => { const nb = Object.assign({}, b, { serverName: $('#b-serverName').value, deptName: $('#b-deptName').value, colorPrimary: $('#b-colorPrimary').value, colorAccent: $('#b-colorAccent').value, theme: $('#b-theme').value }); const rr = await api('settings.save', { branding: nb }); if (rr.ok) { S.branding = nb; applyBranding(); toast('Gespeichert.', 'ok'); } else errToast(rr); };
    $('#save-feat').onclick = async () => { const nf = Object.assign({}, fe); document.querySelectorAll('[data-feat]').forEach(x => nf[x.getAttribute('data-feat')] = x.checked); const rr = await api('settings.save', { features: nf }); if (rr.ok) { S.features = nf; buildNav(); toast('Gespeichert.', 'ok'); } else errToast(rr); };
    $('#save-notice').onclick = async () => { const rr = await api('settings.save', { notice: { text: $('#s-notice').value } }); if (rr.ok) toast('Gespeichert.', 'ok'); else errToast(rr); };
  }

  // ---- Visibility / messages ----
  function hideAll() { $('#mt-root').classList.add('mt-hidden'); $('#mt-tablet').classList.add('mt-hidden'); $('#fp-overlay').classList.add('mt-hidden'); closeModal(); }
  function showTablet() { $('#mt-root').classList.remove('mt-hidden'); $('#mt-tablet').classList.remove('mt-hidden'); }

  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.type === 'open') {
      const p = m.payload || {};
      S.branding = p.branding || {}; S.features = p.features || {}; S.perms = p.perms || {}; S.identity = p.identity || {};
      applyBranding();
      $('#mt-username').textContent = S.identity.name || '-';
      $('#mt-userrole').textContent = (S.identity.job || '') + ' • Rang ' + (S.identity.grade != null ? S.identity.grade : '-');
      $('#mt-avatar').textContent = (S.identity.name || 'O').charAt(0).toUpperCase();
      S.view = feat('dashboard') ? 'dashboard' : 'search';
      showTablet(); buildNav(); render();
    } else if (m.type === 'close') { hideAll(); }
    else if (m.type === 'notify') { toast(m.message, m.level === 'success' ? 'ok' : (m.level ? 'warn' : 'ok')); }
    else if (m.type === 'fingerprintResult') { if (m.payload && m.payload.scan) { $('#fp-overlay').classList.add('mt-hidden'); openScanResult(m.payload.scan); } }
  });

  document.addEventListener('keyup', (e) => { if (e.key === 'Escape') closeUI(); });
  document.addEventListener('click', (e) => { if (e.target && e.target.id === 'mt-close') closeUI(); if (e.target && e.target.id === 'mt-modal') closeModal(); });
})();
