--[[ Ticket- & Coupon-Drucker (Selbst-Service). ]]

WL = WL or {}

local function findTicketTpl(key)
    for _, t in ipairs(Config.Templates.Tickets) do if t.key == key then return t end end
    return nil
end
local function chargeFee(ctx, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local acc = ctx.xp and ctx.xp.getAccount(Config.Cards.account)
    if not acc or acc.money < amount then return false end
    ctx.xp.removeAccountMoney(Config.Cards.account, amount)
    return true
end

WL.register('tickets.print', {}, function(ctx, data)
    local tpl = findTicketTpl(tostring(data.template_key or ''))
    if not tpl then return WL.fail('invalid_input') end
    local fields = {}
    for _, f in ipairs(tpl.fields or {}) do fields[f] = tostring((data.fields or {})[f] or ''):sub(1, 80) end
    if not chargeFee(ctx, Config.Cards.ticketFee) then return WL.fail('no_money') end
    local id = WL.Wallet.issue(ctx.identifier, tpl.type, tpl.key, fields, ctx, { title = tpl.label })
    if not id then return WL.fail('db_error') end
    WL.Audit.log(ctx, { action = 'ticket.print', target_type = 'card', target_id = id, new = { tpl = tpl.key } })
    return { ok = true, id = id, message = WL.L('ticket_printed') }
end)
