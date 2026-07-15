'use strict';
// Laedt Secrets aus .env und die restliche Konfiguration aus config.json.
require('dotenv').config();
const fs = require('fs');
const path = require('path');

const cfgPath = process.env.CONFIG_PATH || path.join(process.cwd(), 'config.json');
let fileCfg = {};
try {
  fileCfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (e) {
  console.error(`[panel] config.json nicht gefunden/ungueltig (${cfgPath}). Kopiere config.example.json -> config.json.`);
  process.exit(1);
}

function req(name) {
  const v = process.env[name];
  if (!v) { console.error(`[panel] Fehlende Umgebungsvariable ${name} (.env).`); process.exit(1); }
  return v;
}

module.exports = {
  port: Number(process.env.PORT || fileCfg.port || 8080),
  publicUrl: (fileCfg.publicUrl || `http://localhost:${fileCfg.port || 8080}`).replace(/\/$/, ''),
  cookieSecure: fileCfg.cookieSecure !== false,
  sessionHours: Number(fileCfg.sessionHours || 12),

  db: {
    host: process.env.DB_HOST || '127.0.0.1',
    port: Number(process.env.DB_PORT || 3306),
    user: req('DB_USER'),
    password: process.env.DB_PASSWORD || '',
    database: req('DB_NAME'),
  },

  discord: {
    clientId: req('DISCORD_CLIENT_ID'),
    clientSecret: req('DISCORD_CLIENT_SECRET'),
    guildId: fileCfg.discord && fileCfg.discord.guildId,
    redirectPath: (fileCfg.discord && fileCfg.discord.redirectPath) || '/auth/callback',
  },

  jwtSecret: req('JWT_SECRET'),

  roles: fileCfg.roles || { adminRoleIds: [], map: [] },
  branding: fileCfg.branding || {},
  billingBridge: fileCfg.billingBridge || { enabled: true },
  rateLimit: fileCfg.rateLimit || { windowMs: 10000, max: 120 },
};
