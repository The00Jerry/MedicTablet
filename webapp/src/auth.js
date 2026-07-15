'use strict';
// Discord-OAuth2-Login + JWT-Session (httpOnly-Cookie) + Rechte-Middleware.
const jwt = require('jsonwebtoken');
const cfg = require('./config');
const perms = require('./permissions');

const COOKIE = 'mtp_session';
const DISCORD_API = 'https://discord.com/api';

function redirectUri() {
  return cfg.publicUrl + cfg.discord.redirectPath;
}

// Schritt 1: Authorize-URL
function loginUrl(state) {
  const p = new URLSearchParams({
    client_id: cfg.discord.clientId,
    redirect_uri: redirectUri(),
    response_type: 'code',
    scope: 'identify guilds.members.read',
    state: state || '',
    prompt: 'none',
  });
  return `${DISCORD_API}/oauth2/authorize?${p.toString()}`;
}

// Schritt 2: Code -> Token -> User + Rollen -> Rechte
async function handleCallback(code) {
  // Token
  const body = new URLSearchParams({
    client_id: cfg.discord.clientId,
    client_secret: cfg.discord.clientSecret,
    grant_type: 'authorization_code',
    code,
    redirect_uri: redirectUri(),
  });
  const tokRes = await fetch(`${DISCORD_API}/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!tokRes.ok) throw new Error('token_exchange_failed');
  const tok = await tokRes.json();

  // User
  const meRes = await fetch(`${DISCORD_API}/users/@me`, { headers: { Authorization: `Bearer ${tok.access_token}` } });
  if (!meRes.ok) throw new Error('userinfo_failed');
  const me = await meRes.json();

  // Rollen im Guild (scope guilds.members.read)
  let memberRoles = [];
  if (cfg.discord.guildId) {
    const mRes = await fetch(`${DISCORD_API}/users/@me/guilds/${cfg.discord.guildId}/member`, {
      headers: { Authorization: `Bearer ${tok.access_token}` },
    });
    if (mRes.ok) {
      const member = await mRes.json();
      memberRoles = member.roles || [];
    }
  }

  const resolved = perms.permsForRoles(memberRoles, cfg.roles);
  if (!resolved.hasAccess) return { allowed: false };

  const name = me.global_name || (me.username + (me.discriminator && me.discriminator !== '0' ? '#' + me.discriminator : ''));
  return {
    allowed: true,
    user: {
      discordId: me.id,
      name,
      avatar: me.avatar ? `https://cdn.discordapp.com/avatars/${me.id}/${me.avatar}.png` : null,
      perms: resolved.perms,
      roleLabel: resolved.label,
    },
  };
}

function issueSession(res, user) {
  const token = jwt.sign(
    { sub: user.discordId, name: user.name, avatar: user.avatar, perms: user.perms, role: user.roleLabel },
    cfg.jwtSecret,
    { expiresIn: `${cfg.sessionHours}h` }
  );
  res.cookie(COOKIE, token, {
    httpOnly: true,
    secure: cfg.cookieSecure,
    sameSite: 'lax',
    maxAge: cfg.sessionHours * 3600 * 1000,
  });
}

function clearSession(res) {
  res.clearCookie(COOKIE, { httpOnly: true, secure: cfg.cookieSecure, sameSite: 'lax' });
}

function currentUser(req) {
  const t = req.cookies && req.cookies[COOKIE];
  if (!t) return null;
  try {
    const d = jwt.verify(t, cfg.jwtSecret);
    return {
      discordId: d.sub,
      name: d.name,
      avatar: d.avatar,
      perms: d.perms || {},
      role: d.role,
      identifier: 'discord:' + d.sub, // Attribution im Audit-Log
    };
  } catch (e) {
    return null;
  }
}

// Middleware
function requireAuth(req, res, next) {
  const u = currentUser(req);
  if (!u) return res.status(401).json({ error: 'Nicht angemeldet.' });
  req.user = u;
  next();
}
function requirePerm(perm) {
  return (req, res, next) => {
    if (!perms.has(req.user.perms, perm)) return res.status(403).json({ error: 'Fehlende Berechtigung.' });
    next();
  };
}
function can(req, perm) { return perms.has(req.user.perms, perm); }

module.exports = { COOKIE, loginUrl, handleCallback, issueSession, clearSession, currentUser, requireAuth, requirePerm, can };
