'use strict';
// Express-Server: Discord-Login, statische Web-App, REST-API.
const express = require('express');
const cookieParser = require('cookie-parser');
const path = require('path');
const cfg = require('./config');
const auth = require('./auth');
const api = require('./routes/api');

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1); // hinter Reverse-Proxy (nginx) fuer secure-Cookies/IP

// ---- Sicherheits-Header (ohne Zusatzabhaengigkeit) ----
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Content-Security-Policy',
    "default-src 'self'; img-src 'self' https://cdn.discordapp.com data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'");
  next();
});

app.use(express.json({ limit: '256kb' }));
app.use(cookieParser());

// ---- einfacher In-Memory Rate-Limiter fuer /api ----
const buckets = new Map();
app.use('/api', (req, res, next) => {
  const key = (req.ip || 'x') + '|' + (req.cookies[auth.COOKIE] ? 'u' : 'a');
  const now = Date.now();
  let b = buckets.get(key);
  if (!b || now - b.start > cfg.rateLimit.windowMs) { b = { start: now, n: 0 }; buckets.set(key, b); }
  b.n++;
  if (b.n > cfg.rateLimit.max) return res.status(429).json({ error: 'Zu viele Anfragen. Bitte kurz warten.' });
  next();
});
setInterval(() => { const now = Date.now(); for (const [k, b] of buckets) if (now - b.start > cfg.rateLimit.windowMs * 2) buckets.delete(k); }, 60000).unref();

// ============ AUTH ============
app.get('/login', (req, res) => {
  if (auth.currentUser(req)) return res.redirect('/');
  res.redirect(auth.loginUrl());
});

app.get(cfg.discord.redirectPath, async (req, res) => {
  const code = req.query.code;
  if (!code) return res.redirect('/login.html?error=1');
  try {
    const result = await auth.handleCallback(String(code));
    if (!result.allowed) return res.redirect('/login.html?denied=1');
    auth.issueSession(res, result.user);
    res.redirect('/');
  } catch (e) {
    console.error('[panel] OAuth-Fehler:', e.message);
    res.redirect('/login.html?error=1');
  }
});

app.post('/logout', (req, res) => { auth.clearSession(res); res.json({ ok: true }); });

// ============ API ============
app.use('/api', auth.requireAuth, api);

// ============ STATIC ============
const pub = path.join(__dirname, '..', 'public');
// index.html nur fuer angemeldete Nutzer; sonst zur Login-Seite
app.get('/', (req, res) => {
  if (!auth.currentUser(req)) return res.redirect('/login.html');
  res.sendFile(path.join(pub, 'index.html'));
});
app.use(express.static(pub));

// 404 fuer unbekannte API
app.use('/api', (req, res) => res.status(404).json({ error: 'not_found' }));

app.listen(cfg.port, () => {
  console.log(`[panel] SunLife Medic-Panel laeuft auf Port ${cfg.port} (${cfg.publicUrl})`);
  console.log(`[panel] Discord-Redirect: ${cfg.publicUrl}${cfg.discord.redirectPath}`);
});
