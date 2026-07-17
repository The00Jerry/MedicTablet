--[[
    Karten-Vorlagen & Job-Wallets (SEED).
    Kartentypen: national_id | driver_license | business_card | job_wallet | ticket | coupon
    Vorlagen werden beim ersten Start in die DB (lw_templates) uebernommen und sind danach
    im Admin Control Center pflegbar.
]]

Config.Templates = {}

-- Behoerdliche Karten
Config.Templates.Cards = {
    {
        key = 'national_id', type = 'national_id', label = 'Personalausweis',
        header = 'UNITED STATES OF AMERICA', subheader = 'Los Santos City',
        color = '#3b6ea5',
        fields = { 'firstname', 'lastname', 'dateofbirth', 'sex', 'serial', 'issued_at', 'expires_at' },
    },
    {
        key = 'driver_license', type = 'driver_license', label = 'Fuehrerschein',
        header = 'LOS SANTOS GOVERNMENT', subheader = 'Driving Licence',
        color = '#8a8f98',
        fields = { 'firstname', 'lastname', 'dateofbirth', 'class', 'serial', 'issued_at', 'expires_at' },
        -- Fuehrerscheinklassen, die vergeben werden koennen
        classes = { 'B', 'BE', 'C', 'A' },
    },
    {
        key = 'business_card', type = 'business_card', label = 'Visitenkarte',
        header = '', subheader = '',
        color = '#6d4bd6',
        -- vom Spieler frei ausfuellbare Felder
        userFields = { 'company', 'role', 'phone', 'email', 'slogan' },
    },
}

-- Job-Wallets (Dienstmarken) – automatisch aus dem ESX-Job erzeugt (nicht gespeichert).
-- key = ESX-Jobname
Config.Templates.JobWallets = {
    police   = { label = 'LSPD', header = 'POLICE',            dept = 'Los Santos Police Dept.', color = '#2b4c8c' },
    sheriff  = { label = 'BCSO', header = 'SHERIFF',           dept = 'Blaine County SO',        color = '#3d6b2e' },
    fib      = { label = 'FIB',  header = 'FEDERAL BUREAU',     dept = 'FIB Field Office',        color = '#1f2733' },
    ambulance= { label = 'EMS',  header = 'EMERGENCY MEDICAL',  dept = 'Los Santos Medical Dept.',color = '#b3202e' },
    doj      = { label = 'DOJ',  header = 'DEPT. OF JUSTICE',   dept = 'Department of Justice',   color = '#5b4636' },
}

-- Ticket- & Coupon-Vorlagen (Drucker)
Config.Templates.Tickets = {
    { key = 'event_ticket', type = 'ticket', label = 'Event-Ticket', color = '#b3468a', fields = { 'event', 'date', 'seat' } },
    { key = 'discount_coupon', type = 'coupon', label = 'Rabatt-Coupon', color = '#c9a94a', fields = { 'shop', 'discount', 'valid_until' } },
}

-- Lizenzen (Fuehrerschein & weitere Scheine). Jede Lizenz vergibt zusaetzlich die
-- echte ESX-Lizenz `esxType` (siehe Config.Licenses). key ist stabil.
--   class = true  -> Lizenz hat eine Klasse (z.B. Fuehrerscheinklasse)
--   requireApplication = true -> erst nach Antrag + Autorisierung
Config.Templates.Licenses = {
    { key = 'driver',  label = 'Fuehrerschein',        esxType = 'drive',   class = true, classes = { 'B', 'BE', 'C', 'A' },
      fee = Config.Cards.driverFee, requireApplication = Config.Cards.requireApplicationForDriver, color = '#7c828c' },
    { key = 'weapon',  label = 'Waffenschein',         esxType = 'weapon',  fee = 2500, requireApplication = true,  color = '#8a4b3a' },
    { key = 'boat',    label = 'Bootsfuehrerschein',   esxType = 'boat',    fee = 800,  requireApplication = false, color = '#3a6a8a' },
    { key = 'pilot',   label = 'Pilotenlizenz',        esxType = 'pilot',   fee = 5000, requireApplication = true,  color = '#5b4636' },
    { key = 'fishing', label = 'Angelschein',          esxType = 'fishing', fee = 200,  requireApplication = false, color = '#2f6f4f' },
}
