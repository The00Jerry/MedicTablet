--[[ Wallet-Kern: Karten ausstellen/ansehen, Job-Wallets, Schalter-Aktionen. ]]

WL = WL or {}
WL.Wallet = {}

local USERCOL = { firstname = 'firstname', lastname = 'lastname', dob = 'dateofbirth', sex = 'sex', phone = 'phone_number' }
local SERIAL_PREFIX = { national_id = 'USLSC', driver_license = 'LSDL', business_card = 'BC', ticket = 'TK', coupon = 'CP' }

function WL.Wallet.getUser(identifier)
    return WL.DB.single(([[SELECT identifier, `%s` AS firstname, `%s` AS lastname, `%s` AS dateofbirth, `%s` AS sex, `%s` AS phone
        FROM users WHERE identifier = ?]]):format(USERCOL.firstname, USERCOL.lastname, USERCOL.dob, USERCOL.sex, USERCOL.phone), { identifier })
end

-- Karte ausstellen. return cardId | nil
function WL.Wallet.issue(identifier, ctype, templateKey, data, actor, opts)
    opts = opts or {}
    if not WL.Util.CardTypes[ctype] then return nil end
    local serial = WL.Util.serial(SERIAL_PREFIX[ctype] or 'LS')
    local expires = nil
    if opts.expiresDays and opts.expiresDays > 0 then
        expires = os.date('%Y-%m-%d %H:%M:%S', os.time() + opts.expiresDays * 86400)
    end
    local id = WL.DB.insert([[INSERT INTO lw_cards (identifier, ctype, template_key, title, data, photo_url, serial, issued_by, issued_by_name, expires_at)
        VALUES (?,?,?,?,?,?,?,?,?,?)]],
        { identifier, ctype, templateKey or '', opts.title or '', json.encode(data or {}), opts.photo or '',
          serial, (actor and actor.identifier) or 'SYSTEM', (actor and actor.name) or 'System', expires })
    return id
end

-- Alle Karten eines Charakters (ohne Job-Wallet)
function WL.Wallet.getCards(identifier)
    local rows = WL.DB.query('SELECT * FROM lw_cards WHERE identifier = ? AND revoked = 0 ORDER BY created_at DESC', { identifier }) or {}
    for _, c in ipairs(rows) do c.data = c.data and json.decode(c.data) or {} end
    return rows
end

-- Job-Wallet (Dienstmarke) aus ESX-Job – nicht gespeichert
local function jobWallet(ctx)
    local jw = Config.Templates.JobWallets[ctx.job]
    if not jw then return nil end
    return {
        ctype = 'job_wallet', template_key = 'job:' .. ctx.job, title = jw.label, color = jw.color,
        header = jw.header, dept = jw.dept, serial = 'BADGE-' .. tostring(ctx.grade),
        data = { firstname = ctx.firstname, lastname = ctx.lastname, rank = tostring(ctx.grade), dept = jw.dept },
    }
end

local function chargeFee(ctx, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local acc = ctx.xp and ctx.xp.getAccount(Config.Cards.account)
    if not acc or acc.money < amount then return false end
    ctx.xp.removeAccountMoney(Config.Cards.account, amount)
    return true
end

-----------------------------------------------------------------------------
-- Wallet oeffnen
-----------------------------------------------------------------------------
WL.register('wallet.get', {}, function(ctx, data)
    local u = WL.Wallet.getUser(ctx.identifier) or {}
    ctx.firstname = u.firstname; ctx.lastname = u.lastname
    local cards = WL.Wallet.getCards(ctx.identifier)
    local grouped = { cards = {}, licenses = {}, tickets = {} }
    for _, c in ipairs(cards) do
        if c.ctype == 'driver_license' or c.ctype == 'license' then grouped.licenses[#grouped.licenses + 1] = c
        elseif c.ctype == 'ticket' or c.ctype == 'coupon' then grouped.tickets[#grouped.tickets + 1] = c
        else grouped.cards[#grouped.cards + 1] = c end
    end
    -- Job-Wallet an den Anfang der Karten
    local jw = jobWallet(ctx)
    if jw then table.insert(grouped.cards, 1, jw) end

    -- Vorhandene ECHTE ESX-Lizenzen ins Wallet spiegeln (auch anderswo vergebene)
    local represented = {}
    for _, c in ipairs(grouped.licenses) do if c.data and c.data.esxType then represented[c.data.esxType] = true end end
    for _, esxType in ipairs(WL.License.list(ctx.identifier)) do
        if not represented[esxType] then
            local def = WL.License.defByEsxType(esxType)
            grouped.licenses[#grouped.licenses + 1] = {
                ctype = (def and def.key == 'driver') and 'driver_license' or 'license',
                template_key = def and def.key or esxType, title = def and def.label or esxType,
                color = def and def.color or nil, serial = 'ESX-' .. esxType:upper(), virtual = true,
                data = { firstname = u.firstname, lastname = u.lastname, dateofbirth = u.dateofbirth, esxType = esxType, label = def and def.label or esxType },
            }
        end
    end

    local pendingApps = WL.DB.query("SELECT id, atype, status, created_at FROM lw_applications WHERE identifier = ? AND status='pending'", { ctx.identifier }) or {}

    return {
        branding = Config.Branding,
        identity = { name = ctx.name, firstname = u.firstname, lastname = u.lastname, dateofbirth = u.dateofbirth, sex = u.sex, phone = u.phone, identifier = ctx.identifier, job = ctx.job, grade = ctx.grade },
        wallet = grouped,
        pending = pendingApps,
        isAdmin = ctx.can('wallet.admin.view'),
        perms = WL.Perms.list(ctx.perms),
        dmv = { licenses = Config.Templates.Licenses, tickets = Config.Templates.Tickets },
        fees = { id = Config.Cards.idFee, driver = Config.Cards.driverFee, business = Config.Cards.businessFee },
    }
end)

WL.register('wallet.viewCard', {}, function(ctx, data)
    local card = WL.DB.single('SELECT * FROM lw_cards WHERE id = ?', { tonumber(data.id) })
    if not card then return WL.fail('invalid_input') end
    if card.identifier ~= ctx.identifier and not ctx.can('wallet.admin.view') then return WL.fail('no_permission') end
    card.data = card.data and json.decode(card.data) or {}
    return { card = card }
end)

-----------------------------------------------------------------------------
-- Schalter (DMV) – Selbst-Service
-----------------------------------------------------------------------------
WL.register('dmv.getId', {}, function(ctx, data)
    if not Config.Cards.idSelfService then return WL.fail('no_permission') end
    local existing = WL.DB.single("SELECT id FROM lw_cards WHERE identifier = ? AND ctype='national_id' AND revoked=0", { ctx.identifier })
    if existing then return WL.fail('id_exists') end
    local u = WL.Wallet.getUser(ctx.identifier)
    if not u then return WL.fail('player_not_found') end
    if not chargeFee(ctx, Config.Cards.idFee) then return WL.fail('no_money') end
    local id = WL.Wallet.issue(ctx.identifier, 'national_id', 'national_id',
        { firstname = u.firstname, lastname = u.lastname, dateofbirth = u.dateofbirth, sex = u.sex, address = 'Los Santos' },
        ctx, { expiresDays = Config.Cards.idExpiryDays })
    if not id then return WL.fail('db_error') end
    -- optional: Perso zusaetzlich als echte ESX-Lizenz setzen
    if Config.Licenses.idEsxType and Config.Licenses.idEsxType ~= '' then WL.License.grant(ctx.identifier, Config.Licenses.idEsxType) end
    WL.Audit.log(ctx, { action = 'card.issue', target_type = 'card', target_id = id, new = { ctype = 'national_id' } })
    return { ok = true, id = id, message = WL.L('id_issued') }
end)

WL.register('dmv.businessCard', {}, function(ctx, data)
    local fields = {}
    for _, f in ipairs((Config.Templates.Cards[3] and Config.Templates.Cards[3].userFields) or {}) do
        fields[f] = tostring((data.fields or {})[f] or ''):sub(1, 80)
    end
    if not chargeFee(ctx, Config.Cards.businessFee) then return WL.fail('no_money') end
    local u = WL.Wallet.getUser(ctx.identifier) or {}
    fields.firstname = u.firstname; fields.lastname = u.lastname
    local id = WL.Wallet.issue(ctx.identifier, 'business_card', 'business_card', fields, ctx, { title = fields.company or 'Visitenkarte' })
    if not id then return WL.fail('db_error') end
    WL.Audit.log(ctx, { action = 'card.issue', target_type = 'card', target_id = id, new = { ctype = 'business_card' } })
    return { ok = true, id = id, message = WL.L('card_issued') }
end)
