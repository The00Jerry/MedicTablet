--[[
    Team-Panel-Anbindung (Sync-Schicht) + Tablet-Einstellungen.

    Standard: Config.Panel.enabled = false -> Quelle der Wahrheit ist Config + DB.
    Bei Aktivierung:
      * OUTBOUND: server-only PerformHttpRequest mit Bearer-API-Key ueber HTTPS.
        Jede Anfrage wird zusaetzlich HMAC-SHA256-signiert (X-Signature, X-Timestamp,
        X-Nonce) -> Manipulations-/Replay-Schutz. API-Key/Secret NUR serverseitig.
      * INBOUND: SetHttpHandler-Endpunkte, die eingehende Panel-Requests per
        HMAC + Zeitfenster verifizieren.
      * Bei Ausfall: onOutage='last_known' -> Weiterbetrieb mit DB-Settings.
        Nach Reconnect wird automatisch neu synchronisiert.

    Der vollstaendige API-Vertrag ist in docs/API.md beschrieben.
]]

MT = MT or {}
MT.Panel = {}

-- =====================================================================
-- HMAC-SHA256 (pure Lua 5.4, native Bitoperatoren) fuer Signaturen
-- =====================================================================
local MASK = 0xFFFFFFFF
local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & MASK end

local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function sha256_bin(msg)
  local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  local len = #msg
  msg = msg .. '\128'
  while (#msg % 64) ~= 56 do msg = msg .. '\0' end
  local bl = len * 8
  for i = 7, 0, -1 do msg = msg .. string.char((bl >> (i * 8)) & 0xFF) end

  for chunk = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do
      local a, b, c, d = msg:byte(chunk + i*4, chunk + i*4 + 3)
      w[i] = ((a << 24) | (b << 16) | (c << 8) | d) & MASK
    end
    for i = 16, 63 do
      local s0 = rrot(w[i-15],7) ~ rrot(w[i-15],18) ~ (w[i-15] >> 3)
      local s1 = rrot(w[i-2],17) ~ rrot(w[i-2],19) ~ (w[i-2] >> 10)
      w[i] = (w[i-16] + s0 + w[i-7] + s1) & MASK
    end
    local a,b,c,d,e,f,g,hh = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
    for i = 0, 63 do
      local S1 = rrot(e,6) ~ rrot(e,11) ~ rrot(e,25)
      local ch = (e & f) ~ ((~e & MASK) & g)
      local t1 = (hh + S1 + ch + K[i+1] + w[i]) & MASK
      local S0 = rrot(a,2) ~ rrot(a,13) ~ rrot(a,22)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = (S0 + maj) & MASK
      hh=g; g=f; f=e; e=(d + t1) & MASK; d=c; c=b; b=a; a=(t1 + t2) & MASK
    end
    h[1]=(h[1]+a)&MASK; h[2]=(h[2]+b)&MASK; h[3]=(h[3]+c)&MASK; h[4]=(h[4]+d)&MASK
    h[5]=(h[5]+e)&MASK; h[6]=(h[6]+f)&MASK; h[7]=(h[7]+g)&MASK; h[8]=(h[8]+hh)&MASK
  end

  local out = {}
  for i = 1, 8 do
    out[i] = string.char((h[i]>>24)&0xFF,(h[i]>>16)&0xFF,(h[i]>>8)&0xFF,h[i]&0xFF)
  end
  return table.concat(out)
end

local function toHex(s)
  return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end

function MT.Panel.hmac(key, msg)
  if #key > 64 then key = sha256_bin(key) end
  key = key .. string.rep('\0', 64 - #key)
  local o, i = {}, {}
  for n = 1, 64 do
    local b = key:byte(n)
    o[n] = string.char(b ~ 0x5c)
    i[n] = string.char(b ~ 0x36)
  end
  return toHex(sha256_bin(table.concat(o) .. sha256_bin(table.concat(i) .. msg)))
end

-- =====================================================================
-- Tablet-Einstellungen (perm settings.edit)
-- =====================================================================
MT.register('settings.get', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    return {
        branding = MT.Settings.get('branding', Config.Branding),
        features = MT.Settings.get('features', Config.Features),
        notice   = MT.Settings.get('notice', { text = '' }),
        panel    = { enabled = Config.Panel.enabled, apiUrl = Config.Panel.apiUrl,
                     lastSync = MT.DB.query('SELECT area, last_sync_at, last_ok, last_error FROM mt_sync_state') or {} },
    }
end)

MT.register('settings.save', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    local saved = {}
    if type(data.branding) == 'table' then MT.Settings.set('branding', data.branding, ctx.identifier); saved.branding = true end
    if type(data.features) == 'table' then MT.Settings.set('features', data.features, ctx.identifier); saved.features = true end
    if type(data.notice) == 'table' then MT.Settings.set('notice', data.notice, ctx.identifier); saved.notice = true end
    MT.Audit.log(ctx, { category = 'settings', action = 'settings.save', new = saved })
    return { ok = true, message = MT.L('saved') }
end)

-- Berechtigungen/Overrides/Sperren (admin)
MT.register('perms.setOverride', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    local perm = tostring(data.perm or '')
    if identifier == '' or perm == '' then return MT.fail('invalid_input') end
    local allow = (data.allow == true or data.allow == 1) and 1 or 0
    MT.DB.update([[INSERT INTO mt_permission_overrides (identifier, perm, allow, created_by)
        VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE allow=VALUES(allow), created_by=VALUES(created_by)]],
        { identifier, perm, allow, ctx.identifier })
    MT.Perms.invalidate(identifier)
    MT.Audit.log(ctx, { category = 'settings', action = 'perm.override', target_type = 'user', target_id = identifier,
        new = { perm = perm, allow = allow } })
    return { ok = true }
end)

MT.register('perms.lock', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    if identifier == '' then return MT.fail('invalid_input') end
    local locked = (data.locked == true or data.locked == 1) and 1 or 0
    MT.DB.update([[INSERT INTO mt_user_locks (identifier, locked, reason, created_by)
        VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE locked=VALUES(locked), reason=VALUES(reason)]],
        { identifier, locked, tostring(data.reason or ''):sub(1, 200), ctx.identifier })
    MT.Perms.invalidate(identifier)
    MT.Audit.log(ctx, { category = 'security', action = 'user.lock', target_type = 'user', target_id = identifier,
        new = { locked = locked } })
    return { ok = true }
end)

-- =====================================================================
-- Sync-Client (nur wenn Config.Panel.enabled)
-- =====================================================================
local function setSyncState(area, ok, err, hash)
    MT.DB.update([[INSERT INTO mt_sync_state (area, last_sync_at, last_ok, last_error, payload_hash)
        VALUES (?, NOW(), ?, ?, ?) ON DUPLICATE KEY UPDATE last_sync_at=NOW(), last_ok=VALUES(last_ok),
        last_error=VALUES(last_error), payload_hash=VALUES(payload_hash)]],
        { area, ok and 1 or 0, (err or ''):sub(1, 250), hash or '' })
end

-- Signierter HTTP-Request an das Panel
function MT.Panel.request(method, path, body, cb)
    local url = Config.Panel.apiUrl .. path
    local payload = body and json.encode(body) or ''
    local ts = tostring(os.time())
    local nonce = MT.Util.genId('N')
    local headers = {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = 'Bearer ' .. Config.Panel.apiKey,
        ['X-Timestamp'] = ts,
        ['X-Nonce'] = nonce,
    }
    if Config.Panel.hmacSecret ~= '' then
        headers['X-Signature'] = MT.Panel.hmac(Config.Panel.hmacSecret, ts .. nonce .. method .. path .. payload)
    end
    PerformHttpRequest(url, function(status, resText)
        if status >= 200 and status < 300 then
            local ok, parsed = pcall(function() return resText and resText ~= '' and json.decode(resText) or {} end)
            cb(true, ok and parsed or {})
        else
            cb(false, ('HTTP ' .. tostring(status)))
        end
    end, method, payload, headers)
end

-- Pull: autoritative Konfiguration vom Panel holen und in DB anwenden
local function pullArea(area)
    MT.Panel.request('GET', '/' .. area, nil, function(ok, res)
        if not ok then
            setSyncState(area, false, tostring(res))
            MT.Util.warn(('Panel-Sync (%s) fehlgeschlagen: %s – nutze zuletzt gespeicherte Werte.'):format(area, tostring(res)))
            return
        end
        if area == 'settings' then
            if res.branding then MT.Settings.set('branding', res.branding, 'PANEL') end
            if res.features then MT.Settings.set('features', res.features, 'PANEL') end
            if res.notice then MT.Settings.set('notice', res.notice, 'PANEL') end
        elseif area == 'insurance' and type(res.tiers) == 'table' then
            for _, t in ipairs(res.tiers) do
                MT.DB.update([[INSERT INTO mt_insurance_tiers (tier_key,label,description,color,icon,weekly_premium,coverage_pct,max_per_invoice,weekly_cap,active,min_term_days,cancel_notice_days,waiting_days)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON DUPLICATE KEY UPDATE label=VALUES(label),description=VALUES(description),color=VALUES(color),icon=VALUES(icon),
                      weekly_premium=VALUES(weekly_premium),coverage_pct=VALUES(coverage_pct),max_per_invoice=VALUES(max_per_invoice),
                      weekly_cap=VALUES(weekly_cap),active=VALUES(active),min_term_days=VALUES(min_term_days),
                      cancel_notice_days=VALUES(cancel_notice_days),waiting_days=VALUES(waiting_days)]],
                    { t.tier_key, t.label, t.description or '', t.color or '#38bdf8', t.icon or 'shield',
                      t.weekly_premium or 0, t.coverage_pct or 0, t.max_per_invoice or 0, t.weekly_cap or 0,
                      (t.active and 1 or 0), t.min_term_days or 0, t.cancel_notice_days or 0, t.waiting_days or 0 })
            end
        elseif area == 'pricelist' and type(res.items) == 'table' then
            for _, it in ipairs(res.items) do
                MT.DB.update([[INSERT INTO mt_pricelist_items (code,label,description,price,required_perm,active,created_by,updated_by)
                    VALUES (?,?,?,?,?,?,?,?)
                    ON DUPLICATE KEY UPDATE label=VALUES(label),description=VALUES(description),price=VALUES(price),
                      required_perm=VALUES(required_perm),active=VALUES(active),updated_by='PANEL']],
                    { it.code, it.label, it.description or '', it.price or 0, it.required_perm or '',
                      (it.active and 1 or 0), 'PANEL', 'PANEL' })
            end
        end
        setSyncState(area, true, '')
        MT.Util.dbg('Panel-Sync ok:', area)
    end)
end

CreateThread(function()
    if not Config.Panel.enabled then
        MT.Util.dbg('Team-Panel deaktiviert – nutze Config + DB.')
        return
    end
    Wait(10000)
    while true do
        if Config.Panel.sync.settings  then pullArea('settings')  end
        if Config.Panel.sync.insurance then pullArea('insurance') end
        if Config.Panel.sync.pricelist then pullArea('pricelist') end
        Wait(math.max(1, Config.Panel.syncIntervalMinutes) * 60000)
    end
end)

-- =====================================================================
-- Inbound-Endpunkte (Panel -> FiveM), nur wenn aktiviert
-- =====================================================================
local function verifyInbound(req)
    if not Config.Panel.inbound.requireSignature then return true end
    local ts = req.headers['X-Timestamp'] or req.headers['x-timestamp']
    local nonce = req.headers['X-Nonce'] or req.headers['x-nonce']
    local sig = req.headers['X-Signature'] or req.headers['x-signature']
    if not ts or not nonce or not sig then return false end
    if math.abs(os.time() - (tonumber(ts) or 0)) > Config.Panel.inbound.maxSkewSeconds then return false end
    local expect = MT.Panel.hmac(Config.Panel.hmacSecret, ts .. nonce .. (req.method or '') .. (req.path or '') .. (req.body or ''))
    return expect == sig
end

if Config.Panel.enabled and Config.Panel.inbound.enabled then
    SetHttpHandler(function(req, res)
        local body = ''
        req.setDataHandler(function(data) body = data or '' end)
        Wait(0)
        req.body = body
        local function send(code, tbl)
            res.writeHead(code, { ['Content-Type'] = 'application/json' })
            res.send(json.encode(tbl))
        end
        if not verifyInbound(req) then
            MT.Audit.log({ identifier = 'PANEL', name = 'Panel' },
                { category = 'security', action = 'panel.inbound.denied', result = 'denied', reason = req.path })
            return send(401, { error = 'unauthorized' })
        end
        -- Beispiel: /trigger-sync -> sofortiger Pull
        if req.path == '/trigger-sync' then
            pullArea('settings'); pullArea('insurance'); pullArea('pricelist')
            return send(200, { ok = true })
        end
        return send(404, { error = 'not_found' })
    end)
    MT.Util.log('Panel-Inbound-Endpunkte aktiv.')
end
