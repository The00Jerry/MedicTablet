# SunLife Medic-Panel (Web-App)

Externe **Web-App / Team-Panel** zum In-Game-Medic-Tablet. Läuft als eigenständiger
Node.js-Dienst, nutzt **dieselbe MySQL-Datenbank** wie das FiveM-Script und ist so für ein
echtes Tablet neben dir gedacht (touch-optimiert, responsive).

- **Login:** Discord OAuth2 – Rechte kommen aus deinen Discord-Rollen.
- **Funktionen:** Dashboard, Patientensuche & -akte, Behandlungen, Preisliste, Versicherung
  (inkl. Verwaltung), Protokolle.
- **Rechnungen:** Da nur der laufende FiveM-Server eine echte CodeM-Rechnung erstellen kann,
  legt das Panel Rechnungen in die Warteschlange `mt_invoice_queue`; der FiveM-Server
  (`server/webbridge.lua`) holt sie ab und erstellt sie **echt** über den CodeM-Adapter.
  Das Panel pollt den Status und zeigt das Ergebnis an.

---

## 1. Voraussetzungen

- Node.js ≥ 18 (fetch integriert)
- Zugriff auf dieselbe MySQL-DB wie das FiveM-Script
- Eine Discord-Anwendung (https://discord.com/developers/applications)
- `sql/install.sql` **und** `sql/webapp.sql` sind eingespielt

## 2. Discord-App einrichten

1. Neue Application → Tab **OAuth2**.
2. **Client ID** und **Client Secret** notieren.
3. Unter **Redirects** exakt eintragen: `https://panel.deinserver.de/auth/callback`
   (muss mit `publicUrl` + `discord.redirectPath` übereinstimmen).
4. Scopes werden vom Panel angefordert: `identify`, `guilds.members.read`
   (damit die Rollen im Guild gelesen werden können – **kein Bot-Token nötig**).
5. **Guild-ID** (Server-ID) und die **Rollen-IDs** deiner Medic-Ränge notieren
   (Discord → Entwicklermodus an → Rechtsklick auf Rolle/Server → ID kopieren).

## 3. Installation

```bash
cd webapp
npm install
cp .env.example .env         # Secrets eintragen (DB, Discord, JWT)
cp config.example.json config.json   # Rollen-Mapping, publicUrl, Branding
npm start
```

### `.env` (Secrets)
DB-Zugang, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `JWT_SECRET` (langer Zufallswert).

### `config.json`
- `publicUrl`: öffentliche URL des Panels (für den OAuth-Redirect).
- `discord.guildId`: deine Server-ID.
- `roles.adminRoleIds`: Rollen mit `admin.full`.
- `roles.map`: Rolle → Grade (0–4). Rechte kumulativ wie im Spiel
  (siehe `../docs/PERMISSIONS.md`).
- `branding`, `rateLimit`, `billingBridge.enabled`.

## 4. Betrieb hinter Reverse-Proxy (empfohlen)

HTTPS ist Pflicht (Cookies laufen `secure`). Beispiel nginx:

```nginx
server {
  server_name panel.deinserver.de;
  location / { proxy_pass http://127.0.0.1:8080; proxy_set_header X-Forwarded-For $remote_addr; proxy_set_header X-Forwarded-Proto $scheme; }
}
```

Für lokalen Test ohne HTTPS: in `config.json` `"cookieSecure": false` setzen.

## 5. Tablet nutzen

Öffne `https://panel.deinserver.de` im Browser des Tablets → **Mit Discord anmelden**.
Nach erfolgreicher Rollenprüfung landest du im Panel. Zum „App-Feeling" auf dem iPad die
Seite über *Teilen → Zum Home-Bildschirm* als PWA-artige Verknüpfung ablegen.

---

## Sicherheit

- Discord-Client-Secret, DB-Zugang und JWT-Secret liegen **nur serverseitig** (`.env`),
  niemals im Browser.
- Session als **httpOnly**-Cookie (JWT, signiert), `SameSite=Lax`, `Secure`.
- Jede API-Route prüft die Berechtigung **serverseitig** (`requirePerm`).
- Ausschließlich parametrisierte SQL-Queries (mysql2 prepared statements).
- Rate-Limit pro IP/Session, Sicherheits-Header inkl. strenger CSP.
- Rechnungen niemals direkt: nur über die serverseitig abgearbeitete Warteschlange
  (idempotent über `idempotency_key`).

## Architektur

```
Browser (Tablet)  ──HTTPS──►  Node/Express (webapp)  ──MySQL──►  mt_* Tabellen
                                     │                                 ▲
                                     └─ schreibt mt_invoice_queue ─────┘
                                                                       │  liest/erstellt
FiveM-Server (server/webbridge.lua) ──────────────────────────────────┘  via CodeM-Adapter
```

Dieselben Tabellen wie das In-Game-Tablet → Daten sind sofort in beiden Welten sichtbar.
