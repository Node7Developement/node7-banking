Config = {}

Config.Debug = false
Config.Locale = 'en'
Config.Command = 'bank'
Config.Keybind = 'E'
Config.PromptText = 'Open Bank'
Config.AlwaysOpen = true
Config.OpenTime = 8
Config.CloseTime = 20
Config.InteractionDistance = 2.5
Config.ServerValidationDistance = 5.0
Config.PedSpawnDistance = 35.0
Config.FadePeds = true
Config.SpawnBankers = true
Config.ShowBlips = true
Config.BlipSprite = 'blip_proc_bank'
Config.BlipScale = 0.2

Config.MinimumAmount = 0.01
Config.MaximumDeposit = 1000000.00
Config.MaximumWithdrawal = 1000000.00
Config.MaximumTransfer = 1000000.00
Config.WithdrawFeePercent = 0.00
Config.TransferFeePercent = 0.00
Config.TransactionHistoryLimit = 30
Config.SharedTransactionHistoryLimit = 40
Config.RateLimitWindowMs = 1500
Config.RateLimitMaxActions = 5


-- Multi-currency personal vault banking.
-- Cash continues to use the existing core `bank` account. Every other
-- supported currency is stored by node7-banking in a per-character vault so
-- depositing it never duplicates the carried/core/item balance.
Config.CurrencyBanking = {
    Enabled = true,
    CashItemResource = 'node7-cashitem',
    Currencies = {
        { key = 'cash', label = 'Canadian Dollars', icon = '$', source = 'cash_exact', decimals = 2, description = '$1, $5, $10, $20, $50, $100 bills plus quarters, dimes, nickels, and pennies.' },
        { key = 'gold', label = 'Gold Bars', icon = 'G', source = 'cashitem', decimals = 0, description = 'Physical gold bars synchronized by node7-cashitem.' },
        { key = 'bloodmoney', label = 'Blood Money', icon = 'BM', source = 'core', account = 'bloodmoney', decimals = 2, description = 'Blood money held on your character.' },
        { key = 'casino_chip', label = 'Casino Chips', icon = 'CC', source = 'core', account = 'casino_chip', decimals = 0, description = 'Casino chips held on your character.' },
        { key = 'bounty_voucher', label = 'Bounty Vouchers', icon = 'BV', source = 'core', account = 'bounty_voucher', decimals = 0, description = 'Bounty vouchers held on your character.' },
        { key = 'prison_token', label = 'Prison Tokens', icon = 'PT', source = 'core', account = 'prison_token', decimals = 0, description = 'Prison tokens held on your character.' },
        { key = 'saloon_token', label = 'Saloon Tokens', icon = 'ST', source = 'core', account = 'saloon_token', decimals = 0, description = 'Saloon tokens held on your character.' },
        { key = 'outlaw_marks', label = 'Outlaw Marks', icon = 'OM', source = 'cashitem', decimals = 0, description = 'Physical outlaw marks managed by node7-cashitem.' },
        { key = 'company_scrip', label = 'Company Scrip', icon = 'CS', source = 'cashitem', decimals = 0, description = 'Physical company scrip managed by node7-cashitem.' },
    },
}

-- Shared and society banking.
Config.EnableSharedAccounts = true
Config.AllowPlayerSharedAccountCreation = true
Config.SharedAccountCreationFee = 250.00
Config.MaxSharedAccountsPerOwner = 3
Config.SharedAccountLabelMaxLength = 48
Config.SharedAccountTransferMaximum = 1000000.00
Config.FrozenAccountsAcceptDeposits = true

-- Job account names remain exactly the job name because node7-core paycheck
-- logic calls exports['node7-banking']:GetAccountBalance(jobName).
Config.AutoCreateJobAccounts = true
Config.AutoCreateGangAccounts = true
Config.IgnoredJobAccounts = {
    unemployed = true,
}
Config.IgnoredGangAccounts = {
    none = true,
    nogang = true,
}

-- Non-boss job/gang members can see and fund their society account, but may
-- not take or transfer society funds. Boss grades receive full permissions.
Config.SocietyEmployeePermissions = {
    deposit = true,
    withdraw = false,
    transfer = false,
    manage = false,
}

Config.SharedRolePermissions = {
    owner = { deposit = true, withdraw = true, transfer = true, manage = true },
    manager = { deposit = true, withdraw = true, transfer = true, manage = true },
    member = { deposit = true, withdraw = false, transfer = false, manage = false },
    viewer = { deposit = false, withdraw = false, transfer = false, manage = false },
}

-- Optional accounts created automatically at resource startup.
Config.DefaultSharedAccounts = {
    -- { name = 'police', label = 'Sheriff Department', account_type = 'society', starting_balance = 0.00 },
    -- { name = 'medic', label = 'Medical Department', account_type = 'society', starting_balance = 0.00 },
}

Config.BankLocations = {
    {
        id = 'valentine',
        name = 'Valentine Bank',
        coords = vector3(-308.4189, 775.8842, 118.7017),
        npcmodel = 'S_M_M_BankClerk_01',
        npccoords = vector4(-308.14, 773.98, 118.70, 4.75),
        showblip = true,
    },
    {
        id = 'rhodes',
        name = 'Rhodes Bank',
        coords = vector3(1292.3070, -1301.5390, 77.0401),
        npcmodel = 'S_M_M_BankClerk_01',
        npccoords = vector4(1291.22, -1303.28, 77.04, 316.53),
        showblip = true,
    },
    {
        id = 'saintdenis',
        name = 'Saint Denis Bank',
        coords = vector3(2644.5790, -1292.3130, 52.2496),
        npcmodel = 'S_M_M_BankClerk_01',
        npccoords = vector4(2644.75, -1294.15, 52.25, 17.11),
        showblip = true,
    },
    {
        id = 'blackwater',
        name = 'Blackwater Bank',
        coords = vector3(-813.1633, -1277.4860, 43.6377),
        npcmodel = 'S_M_M_BankClerk_01',
        npccoords = vector4(-813.20, -1275.38, 43.64, 173.10),
        showblip = true,
    },
    {
        id = 'armadillo',
        name = 'Armadillo Bank',
        coords = vector3(-3666.2500, -2626.5700, -13.5900),
        npcmodel = 'S_M_M_BankClerk_01',
        npccoords = vector4(-3666.28, -2628.69, -13.59, 359.78),
        showblip = true,
    },
}
