/* DOL Wallet – NUI Frontend (Vanilla JS). Kommuniziert ueber den 'request'-Kanal. */
(function () {
  'use strict';
  const RES = 'lswallet';
  const $ = (s, r) => (r || document).querySelector(s);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (v) => '$' + (Math.floor(Number(v) || 0)).toLocaleString('de-DE');
  const fmtDate = (s) => s ? esc(String(s).replace('T', ' ').slice(0, 10)) : '—';
  const PHOTO = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12a5 5 0 1 0-5-5 5 5 0 0 0 5 5Zm0 2c-4 0-9 2-9 6v2h18v-2c0-4-5-6-9-6Z"/></svg>';

  function nui(name, data) { return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).then(r => r.json()).catch(() => ({ ok: false, data: { error: 'NUI-Fehler' } })); }
  const api = (action, data) => nui('request', { action, data: data || {} });
  function closeUI() { nui('close', {}); hideAll(); }

  const S = { branding: {}, identity: {}, wallet: { cards: [], licenses: [], tickets: [] }, perms: {}, isAdmin: false, dmv: {}, fees: {} };
  const CARD_COLOR = { national_id: '#3b6ea5', driver_license: '#7c828c', business_card: '#6d4bd6', job_wallet: '#2b4c8c', ticket: '#b3468a', coupon: '#c9a94a' };
  const color = (c) => c.color || CARD_COLOR[c.ctype] || '#3b6ea5';

  function toast(msg, level) { const t = document.createElement('div'); t.className = 'wl-toast ' + (level || ''); t.textContent = msg; $('#wl-toasts').appendChild(t); setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 200); }, 3200); }
  function modal(title, body, actions) {
    const box = $('#wl-modal-box');
    box.innerHTML = `<h2>${esc(title)}</h2><div id="wl-modal-content">${body}</div><div class="wl-modal-actions" id="wl-modal-actions"></div>`;
    (actions || [{ label: 'Schließen', cls: 'ghost', fn: closeModal }]).forEach(a => { const b = document.createElement('button'); b.className = 'wl-btn ' + (a.cls || ''); b.textContent = a.label; b.onclick = () => a.fn && a.fn(); $('#wl-modal-actions').appendChild(b); });
    $('#wl-modal').classList.remove('wl-hidden');
  }
  const closeModal = () => $('#wl-modal').classList.add('wl-hidden');

  // ---------- Wallet ----------
  function miniStack(cards) {
    if (!cards.length) return '<div class="empty">Keine Einträge</div>';
    const top = cards.slice(0, 3);
    return `<div class="stack">${top.map((c, i) => `<div class="mini" style="top:${i * 12}px;background:${esc(color(c))}"></div>`).join('')}<span class="count">${cards.length}</span></div>`;
  }
  function renderWallet() {
    $('#wl-close-wallet').onclick = closeUI;
    const w = S.wallet;
    const cats = [['Cards', w.cards], ['Licenses', w.licenses], ['Tickets & Coupons', w.tickets]];
    $('#wl-wallet-body').innerHTML = cats.map(([label, arr], idx) => `<div class="wl-cat" data-cat="${idx}"><h4>${esc(label)}</h4>${miniStack(arr)}</div>`).join('');
    $('#wl-wallet-body').querySelectorAll('[data-cat]').forEach(x => x.onclick = () => showCategory(+x.getAttribute('data-cat')));
    const foot = [];
    foot.push('Klicke eine Kategorie, um deine Einträge zu sehen.');
    $('#wl-wallet-foot').innerHTML = foot.join('');
    if (S.isAdmin) { const b = document.createElement('button'); b.className = 'wl-btn accent'; b.style.marginTop = '10px'; b.textContent = 'Admin Control Center'; b.onclick = openAdmin; $('#wl-wallet-foot').appendChild(document.createElement('br')); $('#wl-wallet-foot').appendChild(b); }
  }
  function showCategory(idx) {
    const arr = [S.wallet.cards, S.wallet.licenses, S.wallet.tickets][idx];
    const label = ['Cards', 'Licenses', 'Tickets & Coupons'][idx];
    $('#wl-wallet-body').innerHTML = `<button class="wl-btn ghost" id="cat-back">← Zurück</button><h4 style="margin:12px 2px">${esc(label)}</h4>${arr.length ? arr.map((c, i) => `<div class="wl-cat" data-i="${i}"><div style="display:flex;justify-content:space-between;align-items:center"><span><span class="badge-pill" style="border-color:${esc(color(c))};color:${esc(color(c))}">${esc(c.ctype)}</span> ${esc(c.title || cardName(c))}</span><span class="badge-pill">${esc(c.serial || '')}</span></div></div>`).join('') : '<div class="wl-empty">Keine Einträge.</div>'}`;
    $('#cat-back').onclick = renderWallet;
    $('#wl-wallet-body').querySelectorAll('[data-i]').forEach(x => x.onclick = () => viewCard(arr[+x.getAttribute('data-i')]));
  }
  function cardName(c) { return ({ national_id: 'Personalausweis', driver_license: 'Führerschein', business_card: 'Visitenkarte', job_wallet: 'Dienstmarke', ticket: 'Ticket', coupon: 'Coupon' })[c.ctype] || c.ctype; }

  // ---------- Card render ----------
  function fieldRow(k, v) { return `<div class="f"><span>${esc(k)}</span><span>${esc(v)}</span></div>`; }
  function renderCardHtml(c) {
    const d = c.data || {};
    const name = ((d.firstname || S.identity.firstname || '') + ' ' + (d.lastname || S.identity.lastname || '')).trim();
    const col = color(c);
    if (c.ctype === 'job_wallet') {
      return `<div class="card badge"><div class="c-head" style="background:${esc(col)}"><span class="c-h1">${esc(c.header || 'BADGE')}</span><span class="c-h2">${esc(c.title || '')}</span></div>
        <div class="c-body"><div class="c-photo">${PHOTO}</div><div class="c-fields">${fieldRow('Name', name)}${fieldRow('Dienststelle', d.dept || c.dept || '')}${fieldRow('Rang', d.rank || '')}${fieldRow('Marke', c.serial || '')}</div></div>
        <div class="c-foot"><span>${esc(S.branding.deptName || '')}</span><span>OFFICIAL</span></div></div>`;
    }
    if (c.ctype === 'business_card') {
      return `<div class="card" style="background:#161022;color:#efeaf7"><div class="c-head" style="background:${esc(col)}"><span class="c-h1">${esc(d.company || 'Business Card')}</span></div>
        <div class="c-body"><div class="c-fields" style="color:#cfc6dd">${fieldRow('Name', name)}${d.role ? fieldRow('Position', d.role) : ''}${d.phone ? fieldRow('Telefon', d.phone) : ''}${d.email ? fieldRow('E-Mail', d.email) : ''}${d.slogan ? fieldRow('Slogan', d.slogan) : ''}</div></div>
        <div class="c-foot" style="color:#9a90ad;border-color:#2a2338"><span>${esc(c.serial || '')}</span></div></div>`;
    }
    if (c.ctype === 'ticket' || c.ctype === 'coupon') {
      const d2 = c.data || {};
      return `<div class="card ticket"><div class="c-head" style="background:${esc(col)}"><span class="c-h1">${esc(c.title || cardName(c))}</span></div>
        <div class="c-body"><div class="c-fields">${Object.keys(d2).map(k => fieldRow(k, d2[k])).join('') || '<div class="f"><span>—</span><span></span></div>'}</div></div>
        <div class="c-foot"><span>${esc(c.serial || '')}</span><span>${esc(c.ctype.toUpperCase())}</span></div></div>`;
    }
    // national_id / driver_license
    const isId = c.ctype === 'national_id';
    return `<div class="card"><div class="c-head" style="background:${esc(col)}"><span class="c-h1">${esc(isId ? 'UNITED STATES OF AMERICA' : 'LOS SANTOS GOVERNMENT')}</span><span class="c-h2">${esc(isId ? 'Los Santos City' : 'Driving Licence')}</span></div>
      <div class="c-body"><div class="c-photo">${PHOTO}</div><div class="c-fields">
        ${fieldRow('Name', name)}
        ${d.dateofbirth ? fieldRow('Geburtsdatum', d.dateofbirth) : ''}
        ${isId && d.sex ? fieldRow('Geschlecht', d.sex) : ''}
        ${!isId && d.class ? fieldRow('Klasse', d.class) : ''}
        ${fieldRow('Nr.', c.serial || '')}
        ${fieldRow('Ausgestellt', fmtDate(c.issued_at))}
        ${fieldRow('Gültig bis', c.expires_at ? fmtDate(c.expires_at) : 'unbegrenzt')}
      </div></div>
      <div class="c-foot"><span>${esc(S.branding.cityName || 'City of Los Santos')}</span><span>${esc(name)}</span></div></div>`;
  }
  function viewCard(c) {
    $('#wl-viewer-inner').innerHTML = renderCardHtml(c) + '<div class="card-actions"><button class="wl-btn" id="wl-view-close">Schließen</button></div>';
    $('#wl-viewer').classList.remove('wl-hidden');
    $('#wl-view-close').onclick = () => $('#wl-viewer').classList.add('wl-hidden');
  }

  // ---------- DMV ----------
  function renderDMV() {
    $('#wl-close-dmv').onclick = closeUI;
    if (S.branding.cityName) $('#wl-city').textContent = S.branding.cityName.toUpperCase();
    if (S.branding.deptName) $('#wl-dept').textContent = S.branding.deptName;
    const nm = S.identity.lastname ? ('Mr./Mrs. ' + S.identity.lastname) : (S.identity.name || '');
    $('#wl-welcome').innerHTML = `<strong>Welcome ${esc(nm)}</strong><br><small>Bitte wähle eine Kategorie.</small>`;
    const tiles = [
      ['Get ID Card', '🪪', () => doGetId()],
      ['Get Business Card', '💼', () => doBusiness()],
      ['Get License', '🚗', () => doLicense()],
      ['Ticket & Coupon Printer', '🎫', () => doTicket()],
    ];
    $('#wl-dmv-body').innerHTML = tiles.map((t, i) => `<div class="wl-tile" data-t="${i}"><div class="wl-tile-ico">${t[1]}</div><div class="wl-tile-lbl">${esc(t[0])}</div></div>`).join('');
    $('#wl-dmv-body').querySelectorAll('[data-t]').forEach(x => x.onclick = () => tiles[+x.getAttribute('data-t')][2]());
  }
  async function refreshData() { const r = await api('wallet.get'); if (r.ok) { S.wallet = r.data.wallet; S.pending = r.data.pending; } }
  async function doGetId() {
    modal('Personalausweis beantragen', `Gebühr: <strong>${money(S.fees.id || 0)}</strong><br>Deine Stammdaten werden übernommen.`, [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Ausstellen', cls: 'primary', fn: async () => { const r = await api('dmv.getId'); if (r.ok) { closeModal(); toast(r.data.message || 'Ausgestellt.', 'ok'); await refreshData(); } else toast(err(r), 'error'); } }]);
  }
  function doLicense() {
    const classes = (S.dmv.classes || ['B']);
    modal('Führerschein beantragen', `Gebühr: <strong>${money(S.fees.driver || 0)}</strong><div class="wl-mt"><label>Klasse</label><select id="dl-class">${classes.map(c => `<option>${esc(c)}</option>`).join('')}</select></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Beantragen', cls: 'primary', fn: async () => { const r = await api('dmv.applyDriver', { class: $('#dl-class').value }); if (r.ok) { closeModal(); toast(r.data.message || 'Erledigt.', 'ok'); await refreshData(); } else toast(err(r), 'error'); } }]);
  }
  function doBusiness() {
    modal('Visitenkarte erstellen', `Gebühr: <strong>${money(S.fees.business || 0)}</strong>
      <div class="wl-mt"><label>Firma</label><input id="bc-company"/></div>
      <div class="wl-row wl-mt"><div><label>Position</label><input id="bc-role"/></div><div><label>Telefon</label><input id="bc-phone"/></div></div>
      <div class="wl-mt"><label>E-Mail</label><input id="bc-email"/></div>
      <div class="wl-mt"><label>Slogan</label><input id="bc-slogan"/></div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Drucken', cls: 'primary', fn: async () => { const r = await api('dmv.businessCard', { fields: { company: $('#bc-company').value, role: $('#bc-role').value, phone: $('#bc-phone').value, email: $('#bc-email').value, slogan: $('#bc-slogan').value } }); if (r.ok) { closeModal(); toast(r.data.message || 'Erstellt.', 'ok'); await refreshData(); } else toast(err(r), 'error'); } }]);
  }
  function doTicket() {
    const tpls = S.dmv.tickets || [];
    let cur = tpls[0];
    const fieldInputs = (t) => (t.fields || []).map(f => `<div class="wl-mt"><label>${esc(f)}</label><input data-tf="${esc(f)}"/></div>`).join('');
    modal('Ticket & Coupon Drucker', `<label>Vorlage</label><select id="tk-tpl">${tpls.map((t, i) => `<option value="${i}">${esc(t.label)}</option>`).join('')}</select><div id="tk-fields">${fieldInputs(cur)}</div>`,
      [{ label: 'Abbrechen', cls: 'ghost', fn: closeModal }, { label: 'Drucken', cls: 'primary', fn: async () => { const idx = +$('#tk-tpl').value; const t = tpls[idx]; const fields = {}; document.querySelectorAll('[data-tf]').forEach(x => fields[x.getAttribute('data-tf')] = x.value); const r = await api('tickets.print', { template_key: t.key, fields }); if (r.ok) { closeModal(); toast(r.data.message || 'Gedruckt.', 'ok'); await refreshData(); } else toast(err(r), 'error'); } }]);
    $('#tk-tpl').onchange = () => { $('#tk-fields').innerHTML = fieldInputs(tpls[+$('#tk-tpl').value]); };
  }

  // ---------- Admin ----------
  let adminTab = 'lookup';
  function openAdmin() {
    $('#wl-admin').classList.remove('wl-hidden');
    $('#wl-close-admin').onclick = () => $('#wl-admin').classList.add('wl-hidden');
    const tabs = [['lookup', 'Wallet Lookup'], ['applications', 'Applications'], ['templates', 'Templates']];
    $('#wl-admin-tabs').innerHTML = tabs.map(t => `<button data-at="${t[0]}" class="${adminTab === t[0] ? 'active' : ''}">${esc(t[1])}</button>`).join('');
    $('#wl-admin-tabs').querySelectorAll('[data-at]').forEach(x => x.onclick = () => { adminTab = x.getAttribute('data-at'); openAdmin(); });
    ({ lookup: adminLookup, applications: adminApps, templates: adminTemplates }[adminTab])();
  }
  function adminLookup() {
    $('#wl-admin-body').innerHTML = `<div class="wl-row"><input id="al-q" placeholder="Name, Charakter-ID oder Kartennummer…"/><button class="wl-btn primary" id="al-go" style="flex:0 0 auto">Lookup</button></div><div id="al-res" class="wl-mt"></div>`;
    $('#al-go').onclick = doLookup; $('#al-q').onkeydown = (e) => { if (e.key === 'Enter') doLookup(); };
  }
  async function doLookup() {
    const q = $('#al-q').value.trim(); if (!q) return;
    $('#al-res').innerHTML = '…';
    const r = await api('admin.lookup', { query: q });
    if (!r.ok) return ($('#al-res').innerHTML = `<div class="wl-empty">${esc(err(r))}</div>`);
    if (!r.data.found) return ($('#al-res').innerHTML = '<div class="wl-empty">Keine Person gefunden.</div>');
    const id = r.data.identity, cards = r.data.cards || [];
    $('#al-res').innerHTML = `<div class="wl-cat"><strong>${esc(id.firstname)} ${esc(id.lastname)}</strong> <span class="badge-pill">${esc(id.dateofbirth || '')}</span><div style="color:var(--muted);font-size:12px;margin-top:4px">${esc(id.identifier)}</div></div>
      <table class="wl-table wl-mt"><thead><tr><th>Typ</th><th>Karte</th><th>Nr.</th><th></th></tr></thead><tbody>
      ${cards.length ? cards.map(c => `<tr><td>${esc(c.ctype)}</td><td>${esc(c.title || cardName(c))}</td><td>${esc(c.serial)}</td><td>${r.data.canRevoke ? `<button class="wl-btn danger" data-rev="${c.id}">Entziehen</button>` : ''}</td></tr>`).join('') : '<tr><td colspan="4" class="wl-empty">Keine Karten.</td></tr>'}
      </tbody></table>
      ${r.data.canIssue ? `<div class="wl-mt"><button class="wl-btn accent" id="al-issue">Personalausweis manuell ausstellen</button></div>` : ''}`;
    $('#al-res').querySelectorAll('[data-rev]').forEach(x => x.onclick = async () => { const rr = await api('admin.revoke', { id: +x.getAttribute('data-rev') }); if (rr.ok) { toast('Entzogen.', 'ok'); doLookup(); } else toast(err(rr), 'error'); });
    if (r.data.canIssue && $('#al-issue')) $('#al-issue').onclick = async () => { const rr = await api('admin.issue', { identifier: id.identifier, ctype: 'national_id', template_key: 'national_id', data: { firstname: id.firstname, lastname: id.lastname, dateofbirth: id.dateofbirth, sex: id.sex, address: 'Los Santos' } }); if (rr.ok) { toast('Ausgestellt.', 'ok'); doLookup(); } else toast(err(rr), 'error'); };
  }
  async function adminApps() {
    $('#wl-admin-body').innerHTML = '…';
    const r = await api('admin.applications');
    if (!r.ok) return ($('#wl-admin-body').innerHTML = `<div class="wl-empty">${esc(err(r))}</div>`);
    const apps = r.data.applications || [];
    $('#wl-admin-body').innerHTML = apps.length ? `<table class="wl-table"><thead><tr><th>Antragsteller</th><th>Typ</th><th>Details</th><th>Datum</th><th></th></tr></thead><tbody>
      ${apps.map(a => `<tr><td>${esc(a.applicant_name)}</td><td>${esc(a.atype)}</td><td>${esc((a.payload && a.payload.class) ? 'Klasse ' + a.payload.class : '')}</td><td>${fmtDate(a.created_at)}</td><td><button class="wl-btn primary" data-ap="${a.id}">Genehmigen</button> <button class="wl-btn danger" data-dn="${a.id}">Ablehnen</button></td></tr>`).join('')}
      </tbody></table>` : '<div class="wl-empty">Keine offenen Anträge.</div>';
    $('#wl-admin-body').querySelectorAll('[data-ap]').forEach(x => x.onclick = async () => { const rr = await api('admin.decideApplication', { id: +x.getAttribute('data-ap'), decision: 'approve' }); if (rr.ok) { toast(rr.data.message || 'Genehmigt.', 'ok'); adminApps(); } else toast(err(rr), 'error'); });
    $('#wl-admin-body').querySelectorAll('[data-dn]').forEach(x => x.onclick = async () => { const rr = await api('admin.decideApplication', { id: +x.getAttribute('data-dn'), decision: 'deny' }); if (rr.ok) { toast('Abgelehnt.', 'ok'); adminApps(); } else toast(err(rr), 'error'); });
  }
  async function adminTemplates() {
    $('#wl-admin-body').innerHTML = '…';
    const r = await api('admin.templates');
    if (!r.ok) return ($('#wl-admin-body').innerHTML = `<div class="wl-empty">${esc(err(r))}</div>`);
    const t = r.data.templates || [];
    $('#wl-admin-body').innerHTML = t.length ? `<table class="wl-table"><thead><tr><th>Key</th><th>Typ</th><th>Bezeichnung</th></tr></thead><tbody>${t.map(x => `<tr><td>${esc(x.tkey)}</td><td>${esc(x.ctype)}</td><td>${esc(x.label)}</td></tr>`).join('')}</tbody></table>` : '<div class="wl-empty">Keine Vorlagen.</div>';
  }

  const err = (r) => (r.data && r.data.error) || 'Fehler.';

  // ---------- Visibility ----------
  function hideAll() { ['wl-root', 'wl-wallet', 'wl-dmv', 'wl-viewer', 'wl-admin', 'wl-modal'].forEach(id => $('#' + id).classList.add('wl-hidden')); }
  function show(mode) {
    $('#wl-root').classList.remove('wl-hidden');
    $('#wl-wallet').classList.toggle('wl-hidden', mode !== 'wallet');
    $('#wl-dmv').classList.toggle('wl-hidden', mode !== 'dmv');
  }

  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.type === 'open') {
      const p = m.payload || {};
      S.branding = p.branding || {}; S.identity = p.identity || {}; S.wallet = p.wallet || { cards: [], licenses: [], tickets: [] };
      S.perms = p.perms || {}; S.isAdmin = !!p.isAdmin; S.dmv = p.dmv || {}; S.fees = p.fees || {}; S.pending = p.pending || [];
      show(m.mode || 'wallet');
      if ((m.mode || 'wallet') === 'dmv') renderDMV(); else renderWallet();
    } else if (m.type === 'close') { hideAll(); }
    else if (m.type === 'notify') { toast(m.message, m.level === 'error' ? 'error' : 'ok'); }
  });
  document.addEventListener('keyup', (e) => { if (e.key === 'Escape') closeUI(); });
})();
