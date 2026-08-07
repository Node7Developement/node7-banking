local Node7Core = exports['node7-core']:GetCoreObject()
lib.locale()

local rateLimits = {}
local databaseReady = false

local function roundMoney(value)
    return tonumber(string.format('%.2f', tonumber(value) or 0))
end

local function cleanText(value, maxLength)
    local text = tostring(value or ''):gsub('[\r\n\t]', ' '):gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text:sub(1, maxLength or 128)
end

local function normalizeAccountName(value)
    return tostring(value or ''):lower():gsub('[^%w_%-]', ''):sub(1, 64)
end

local function validAmount(value, maximum)
    local amount

    if type(value) == 'number' then
        amount = value
    else
        local normalized = tostring(value or '')
        normalized = normalized:gsub('%$', ''):gsub(',', ''):gsub('%s+', '')
        if normalized == '' then return nil end
        amount = tonumber(normalized)
    end

    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then
        return nil
    end

    amount = roundMoney(amount)
    maximum = tonumber(maximum) or math.huge
    if amount < (tonumber(Config.MinimumAmount) or 0.01) or amount > maximum then
        return nil
    end

    return amount
end

local function currencyDefinition(key)
    key = tostring(key or ''):lower()
    for i = 1, #(((Config.CurrencyBanking or {}).Currencies) or {}) do
        local definition = Config.CurrencyBanking.Currencies[i]
        if tostring(definition.key or ''):lower() == key then
            return definition
        end
    end
    return nil
end

local function validCurrencyAmount(definition, value, maximum)
    local amount = validAmount(value, maximum)
    if not amount then return nil end
    if tonumber(definition and definition.decimals) == 0 and amount % 1 ~= 0 then
        return nil
    end
    return amount
end

local function currencyLabel(definition)
    return tostring((definition and definition.label) or (definition and definition.key) or 'Currency')
end

local function bool(value)
    return value == true or value == 1 or value == '1'
end

local function result(success, message, data)
    return { success = success == true, message = message, data = data }
end

local function transactionReference()
    return ('N7-%s-%04d'):format(os.date('%Y%m%d%H%M%S'), math.random(0, 9999))
end

local function characterName(Player)
    local info = Player.PlayerData.charinfo or {}
    local fullName = (('%s %s'):format(info.firstname or '', info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return fullName ~= '' and fullName or Player.PlayerData.name or 'Unknown Character'
end

local function withinBankDistance(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for i = 1, #Config.BankLocations do
        if #(coords - Config.BankLocations[i].coords) <= Config.ServerValidationDistance then
            return true
        end
    end
    return false
end

local function allowedAction(source, action)
    local now = GetGameTimer()
    local key = ('%s:%s'):format(source, action)
    local entry = rateLimits[key]
    if not entry or now - entry.started >= Config.RateLimitWindowMs then
        rateLimits[key] = { started = now, count = 1 }
        return true
    end
    entry.count = entry.count + 1
    return entry.count <= Config.RateLimitMaxActions
end

local function notify(source, description, notificationType, title)
    Node7Core.Functions.Notify(source, {
        title = title or 'NODE7 FRONTIER BANK',
        description = description,
        type = notificationType or 'info',
        duration = 5500,
    })
end

local function requireBankPlayer(source, action)
    if not databaseReady then
        return nil, result(false, 'The banking database is still starting. Please try again.')
    end
    if not allowedAction(source, action) then
        return nil, result(false, locale('too_many_requests'))
    end
    if not withinBankDistance(source) then
        return nil, result(false, locale('not_near_bank'))
    end
    local Player = Node7Core.Functions.GetPlayer(source)
    if not Player then return nil, result(false, locale('transaction_failed')) end
    return Player
end

local function recordTransaction(citizenid, accountNumber, transactionType, amount, balanceAfter, description, counterparty, reference, currency)
    local ok, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO node7_bank_transactions
                (citizenid, account_number, transaction_type, currency, amount, balance_after, description, counterparty, reference)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            citizenid,
            accountNumber or '',
            transactionType,
            tostring(currency or 'cash'):lower():sub(1, 32),
            roundMoney(amount),
            roundMoney(balanceAfter),
            cleanText(description, 255),
            cleanText(counterparty, 128),
            cleanText(reference or transactionReference(), 64),
        })
    end)
    if not ok then
        print(('^1[node7-banking]^7 Personal ledger insert failed: %s'):format(tostring(err)))
    end
    return ok
end

local function getHistory(citizenid)
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT id, transaction_type AS type, currency, amount, balance_after AS balanceAfter,
                   description, counterparty, reference, created_at AS createdAt
            FROM node7_bank_transactions
            WHERE citizenid = ?
            ORDER BY id DESC
            LIMIT ?
        ]], { citizenid, Config.TransactionHistoryLimit }) or {}
    end)
    if not ok then
        print(('^1[node7-banking]^7 Personal ledger query failed for %s: %s'):format(tostring(citizenid), tostring(rows)))
        return {}
    end
    return rows
end

local function generateSharedAccountNumber()
    for _ = 1, 25 do
        local number = ('N7S-%04d-%04d'):format(math.random(0, 9999), math.random(0, 9999))
        local exists = MySQL.scalar.await('SELECT 1 FROM node7_bank_accounts WHERE account_number = ? LIMIT 1', { number })
        if not exists then return number end
    end
    return ('N7S-%s-%04d'):format(os.time(), math.random(0, 9999))
end

local function ensureSharedAccount(name, label, accountType, startingBalance, ownerCitizenid)
    name = normalizeAccountName(name)
    if name == '' then return false end

    local account = MySQL.single.await('SELECT account_name, account_number FROM node7_bank_accounts WHERE account_name = ? LIMIT 1', { name })
    if account then
        if not account.account_number or account.account_number == '' then
            MySQL.update.await('UPDATE node7_bank_accounts SET account_number = ? WHERE account_name = ?', { generateSharedAccountNumber(), name })
        end
        MySQL.update.await('UPDATE node7_bank_accounts SET label = ?, account_type = ? WHERE account_name = ?', {
            (function() local cleaned = cleanText(label, Config.SharedAccountLabelMaxLength); return cleaned ~= '' and cleaned or name end)(),
            cleanText(accountType or 'society', 32),
            name,
        })
        return true
    end

    MySQL.insert.await([[
        INSERT INTO node7_bank_accounts
            (account_name, account_number, label, account_type, owner_citizenid, balance, frozen)
        VALUES (?, ?, ?, ?, ?, ?, 0)
    ]], {
        name,
        generateSharedAccountNumber(),
        (function() local cleaned = cleanText(label, Config.SharedAccountLabelMaxLength); return cleaned ~= '' and cleaned or name end)(),
        cleanText(accountType or 'society', 32),
        cleanText(ownerCitizenid, 50),
        roundMoney(startingBalance or 0),
    })
    return true
end

local function getSharedBalance(name)
    local balance = MySQL.scalar.await('SELECT balance FROM node7_bank_accounts WHERE account_name = ?', { normalizeAccountName(name) })
    return roundMoney(balance or 0)
end

local function recordSharedTransaction(accountName, transactionType, amount, balanceAfter, description, actorCitizenid, actorName, counterparty, reference)
    local ok, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO node7_bank_account_transactions
                (account_name, transaction_type, amount, balance_after, description,
                 actor_citizenid, actor_name, counterparty, reference)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            normalizeAccountName(accountName),
            cleanText(transactionType, 32),
            roundMoney(amount),
            roundMoney(balanceAfter),
            cleanText(description, 255),
            cleanText(actorCitizenid, 50),
            cleanText(actorName, 128),
            cleanText(counterparty, 128),
            cleanText(reference or transactionReference(), 64),
        })
    end)
    if not ok then
        print(('^1[node7-banking]^7 Shared ledger insert failed: %s'):format(tostring(err)))
    end
    return ok
end

local function rolePermissions(role)
    local configured = Config.SharedRolePermissions[role] or Config.SharedRolePermissions.viewer
    return {
        deposit = configured.deposit == true,
        withdraw = configured.withdraw == true,
        transfer = configured.transfer == true,
        manage = configured.manage == true,
    }
end

local function accountRow(name)
    return MySQL.single.await([[
        SELECT account_name AS name, account_number AS accountNumber, label,
               account_type AS type, owner_citizenid AS ownerCitizenid,
               balance, frozen, created_at AS createdAt, updated_at AS updatedAt
        FROM node7_bank_accounts
        WHERE account_name = ?
        LIMIT 1
    ]], { normalizeAccountName(name) })
end

local function dynamicAccountAccess(Player, name)
    local pdata = Player.PlayerData
    local job = pdata.job or {}
    local gang = pdata.gang or {}

    if job.name and normalizeAccountName(job.name) == name and not Config.IgnoredJobAccounts[job.name] then
        local boss = job.isboss == true or (job.grade and job.grade.isboss == true)
        return {
            role = boss and 'boss' or 'employee',
            permissions = boss and rolePermissions('owner') or {
                deposit = Config.SocietyEmployeePermissions.deposit == true,
                withdraw = Config.SocietyEmployeePermissions.withdraw == true,
                transfer = Config.SocietyEmployeePermissions.transfer == true,
                manage = Config.SocietyEmployeePermissions.manage == true,
            },
        }
    end

    local gangName = gang.name and normalizeAccountName(('gang_%s'):format(gang.name)) or ''
    if gangName ~= '' and gangName == name and not Config.IgnoredGangAccounts[gang.name] then
        local boss = gang.isboss == true or (gang.grade and gang.grade.isboss == true)
        return {
            role = boss and 'boss' or 'member',
            permissions = boss and rolePermissions('owner') or {
                deposit = Config.SocietyEmployeePermissions.deposit == true,
                withdraw = Config.SocietyEmployeePermissions.withdraw == true,
                transfer = Config.SocietyEmployeePermissions.transfer == true,
                manage = Config.SocietyEmployeePermissions.manage == true,
            },
        }
    end

    return nil
end

local function explicitAccountAccess(Player, account)
    local citizenid = Player.PlayerData.citizenid
    if account.ownerCitizenid and account.ownerCitizenid ~= '' and account.ownerCitizenid == citizenid then
        return { role = 'owner', permissions = rolePermissions('owner') }
    end

    local row = MySQL.single.await([[
        SELECT role, can_deposit, can_withdraw, can_transfer, can_manage
        FROM node7_bank_account_members
        WHERE account_name = ? AND citizenid = ?
        LIMIT 1
    ]], { account.name, citizenid })

    if not row then return nil end
    return {
        role = row.role or 'member',
        permissions = {
            deposit = bool(row.can_deposit),
            withdraw = bool(row.can_withdraw),
            transfer = bool(row.can_transfer),
            manage = bool(row.can_manage),
        },
    }
end

local function getAccountAccess(Player, name)
    local account = accountRow(name)
    if not account then return nil, nil end

    if IsPlayerAceAllowed(Player.PlayerData.source, 'node7.banking.admin') then
        return account, { role = 'administrator', permissions = rolePermissions('owner'), admin = true }
    end

    local dynamic = dynamicAccountAccess(Player, account.name)
    if dynamic then return account, dynamic end

    local explicit = explicitAccountAccess(Player, account)
    if explicit then return account, explicit end

    return account, nil
end

local function ensurePlayerSocietyAccounts(Player)
    if not Config.EnableSharedAccounts then return end
    local pdata = Player.PlayerData
    local job = pdata.job or {}
    local gang = pdata.gang or {}

    if Config.AutoCreateJobAccounts and job.name and not Config.IgnoredJobAccounts[job.name] then
        ensureSharedAccount(job.name, job.label or job.name, 'society', 0, '')
    end

    if Config.AutoCreateGangAccounts and gang.name and not Config.IgnoredGangAccounts[gang.name] then
        ensureSharedAccount(('gang_%s'):format(gang.name), gang.label or gang.name, 'gang', 0, '')
    end
end

local function accessibleSharedAccounts(Player)
    if not Config.EnableSharedAccounts then return {} end
    ensurePlayerSocietyAccounts(Player)

    local citizenid = Player.PlayerData.citizenid
    local rows = MySQL.query.await([[
        SELECT DISTINCT a.account_name AS name, a.account_number AS accountNumber,
               a.label, a.account_type AS type, a.owner_citizenid AS ownerCitizenid,
               a.balance, a.frozen
        FROM node7_bank_accounts a
        LEFT JOIN node7_bank_account_members m ON m.account_name = a.account_name
        WHERE a.owner_citizenid = ? OR m.citizenid = ?
        ORDER BY a.label ASC
    ]], { citizenid, citizenid }) or {}

    local byName = {}
    for i = 1, #rows do byName[rows[i].name] = rows[i] end

    local job = Player.PlayerData.job or {}
    if job.name and not Config.IgnoredJobAccounts[job.name] then
        local row = accountRow(job.name)
        if row then byName[row.name] = row end
    end

    local gang = Player.PlayerData.gang or {}
    if gang.name and not Config.IgnoredGangAccounts[gang.name] then
        local row = accountRow(('gang_%s'):format(gang.name))
        if row then byName[row.name] = row end
    end

    if IsPlayerAceAllowed(Player.PlayerData.source, 'node7.banking.admin') then
        local all = MySQL.query.await([[
            SELECT account_name AS name, account_number AS accountNumber, label,
                   account_type AS type, owner_citizenid AS ownerCitizenid,
                   balance, frozen
            FROM node7_bank_accounts ORDER BY label ASC
        ]]) or {}
        for i = 1, #all do byName[all[i].name] = all[i] end
    end

    local output = {}
    for name, row in pairs(byName) do
        local _, access = getAccountAccess(Player, name)
        if access then
            output[#output + 1] = {
                name = row.name,
                accountNumber = row.accountNumber,
                label = row.label,
                type = row.type,
                balance = roundMoney(row.balance),
                frozen = bool(row.frozen),
                role = access.role,
                permissions = access.permissions,
            }
        end
    end
    table.sort(output, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return output
end

local function sharedHistory(name)
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT id, transaction_type AS type, amount, balance_after AS balanceAfter,
                   description, actor_name AS actorName, counterparty, reference,
                   created_at AS createdAt
            FROM node7_bank_account_transactions
            WHERE account_name = ?
            ORDER BY id DESC
            LIMIT ?
        ]], { normalizeAccountName(name), Config.SharedTransactionHistoryLimit }) or {}
    end)
    if not ok then return {} end
    return rows
end

local function sharedMembers(name)
    return MySQL.query.await([[
        SELECT citizenid, member_name AS memberName, role,
               can_deposit AS canDeposit, can_withdraw AS canWithdraw,
               can_transfer AS canTransfer, can_manage AS canManage,
               created_at AS createdAt
        FROM node7_bank_account_members
        WHERE account_name = ?
        ORDER BY FIELD(role, 'owner', 'manager', 'member', 'viewer'), member_name ASC
    ]], { normalizeAccountName(name) }) or {}
end

local function sharedAccountData(Player, name)
    local account, access = getAccountAccess(Player, name)
    if not account or not access then return nil end
    account.balance = roundMoney(account.balance)
    account.frozen = bool(account.frozen)
    account.role = access.role
    account.permissions = access.permissions
    account.history = sharedHistory(account.name)
    account.members = access.permissions.manage and sharedMembers(account.name) or {}
    return account
end

local function getVaultBalances(citizenid)
    local balances = {}
    local rows = MySQL.query.await([[
        SELECT currency, amount
        FROM node7_bank_currency_balances
        WHERE citizenid = ?
    ]], { citizenid }) or {}

    for i = 1, #rows do
        balances[tostring(rows[i].currency or ''):lower()] = roundMoney(rows[i].amount)
    end
    return balances
end

local function adjustVaultBalance(citizenid, currency, delta)
    citizenid = tostring(citizenid or '')
    currency = tostring(currency or ''):lower()
    delta = roundMoney(delta)
    if citizenid == '' or currency == '' or delta == 0 then
        return false, 0
    end

    if delta > 0 then
        MySQL.insert.await([[
            INSERT INTO node7_bank_currency_balances (citizenid, currency, amount)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount), updated_at = CURRENT_TIMESTAMP
        ]], { citizenid, currency, delta })
    else
        local debit = math.abs(delta)
        local changed = MySQL.update.await([[
            UPDATE node7_bank_currency_balances
            SET amount = amount - ?, updated_at = CURRENT_TIMESTAMP
            WHERE citizenid = ? AND currency = ? AND amount >= ?
        ]], { debit, citizenid, currency, debit })
        if not changed or changed < 1 then
            return false, getVaultBalances(citizenid)[currency] or 0
        end
    end

    local balance = MySQL.scalar.await([[
        SELECT amount FROM node7_bank_currency_balances
        WHERE citizenid = ? AND currency = ? LIMIT 1
    ]], { citizenid, currency })
    return true, roundMoney(balance or 0)
end

local function getOnHandCurrency(source, Player, definition)
    if not definition then return nil, 'invalid_currency' end
    local key = tostring(definition.key or ''):lower()
    local sourceType = tostring(definition.source or 'core'):lower()

    if sourceType == 'cash_exact' then
        local amount, err = exports[(Config.CurrencyBanking or {}).CashItemResource or 'node7-cashitem']:GetCashExact(source)
        if amount == false then return nil, err end
        return roundMoney(amount)
    end

    if sourceType == 'cashitem' then
        local amount, err = exports[(Config.CurrencyBanking or {}).CashItemResource or 'node7-cashitem']:GetCurrency(source, key)
        if amount == false then return nil, err end
        return roundMoney(amount)
    end

    local account = tostring(definition.account or key)
    return roundMoney(Player.Functions.GetMoney(account) or 0)
end

local function removeOnHandCurrency(source, Player, definition, amount, reason)
    local key = tostring(definition.key or ''):lower()
    local sourceType = tostring(definition.source or 'core'):lower()
    local resource = (Config.CurrencyBanking or {}).CashItemResource or 'node7-cashitem'

    if sourceType == 'cash_exact' then
        local success = exports[resource]:RemoveCashExact(source, amount, reason)
        return success == true
    elseif sourceType == 'cashitem' then
        local success = exports[resource]:RemoveCurrency(source, key, amount, reason)
        return success == true
    end

    return Player.Functions.RemoveMoney(tostring(definition.account or key), amount, reason) == true
end

local function addOnHandCurrency(source, Player, definition, amount, reason)
    local key = tostring(definition.key or ''):lower()
    local sourceType = tostring(definition.source or 'core'):lower()
    local resource = (Config.CurrencyBanking or {}).CashItemResource or 'node7-cashitem'

    if sourceType == 'cash_exact' then
        local success = exports[resource]:AddCashExact(source, amount, reason)
        return success == true
    elseif sourceType == 'cashitem' then
        local success = exports[resource]:AddCurrency(source, key, amount, reason)
        return success == true
    end

    local success = Player.Functions.AddMoney(tostring(definition.account or key), amount, reason)
    return success == true
end

local function currencyAccountData(source, Player)
    if not (Config.CurrencyBanking and Config.CurrencyBanking.Enabled) then return {} end

    local citizenid = tostring(Player.PlayerData.citizenid or '')
    local vaultBalances = getVaultBalances(citizenid)
    local output = {}

    for i = 1, #(Config.CurrencyBanking.Currencies or {}) do
        local definition = Config.CurrencyBanking.Currencies[i]
        local key = tostring(definition.key or ''):lower()
        local onHand = getOnHandCurrency(source, Player, definition) or 0
        local banked = key == 'cash'
            and roundMoney(Player.Functions.GetMoney('bank') or 0)
            or roundMoney(vaultBalances[key] or 0)

        output[#output + 1] = {
            key = key,
            label = currencyLabel(definition),
            icon = tostring(definition.icon or key:sub(1, 2):upper()),
            description = tostring(definition.description or ''),
            decimals = tonumber(definition.decimals) or 0,
            onHand = roundMoney(onHand),
            banked = banked,
        }
    end

    return output
end

local function depositPersonalCurrency(source, Player, definition, amount)
    local key = tostring(definition.key or ''):lower()
    local onHand = getOnHandCurrency(source, Player, definition)
    if onHand == nil or onHand < amount then
        return false, locale(key == 'cash' and 'insufficient_cash' or 'currency_insufficient_carried')
    end

    if not removeOnHandCurrency(source, Player, definition, amount, ('bank-%s-deposit'):format(key)) then
        return false, locale('transaction_failed')
    end

    local balanceAfter
    if key == 'cash' then
        local added, newBalance = Player.Functions.AddMoney('bank', amount, 'bank-deposit')
        if not added then
            addOnHandCurrency(source, Player, definition, amount, 'bank-deposit-refund')
            return false, locale('transaction_failed')
        end
        balanceAfter = roundMoney(newBalance or Player.Functions.GetMoney('bank') or 0)
    else
        local added, newBalance = adjustVaultBalance(Player.PlayerData.citizenid, key, amount)
        if not added then
            addOnHandCurrency(source, Player, definition, amount, ('bank-%s-deposit-refund'):format(key))
            return false, locale('transaction_failed')
        end
        balanceAfter = newBalance
    end

    local pdata = Player.PlayerData
    local description = key == 'cash' and 'Physical cash deposit' or (currencyLabel(definition) .. ' deposit')
    recordTransaction(pdata.citizenid, (pdata.charinfo or {}).account, 'deposit', amount, balanceAfter, description, '', transactionReference(), key)
    return true, key == 'cash' and locale('deposit_success') or locale('currency_deposit_success')
end

local function withdrawPersonalCurrency(source, Player, definition, amount)
    local key = tostring(definition.key or ''):lower()
    local debit = amount
    local fee = 0
    local balanceAfter

    if key == 'cash' then
        fee = roundMoney(amount * ((tonumber(Config.WithdrawFeePercent) or 0) / 100))
        debit = roundMoney(amount + fee)
        if (Player.Functions.GetMoney('bank') or 0) < debit then
            return false, locale('insufficient_bank')
        end

        local removed, newBalance = Player.Functions.RemoveMoney('bank', debit, 'bank-withdrawal')
        if not removed then return false, locale('transaction_failed') end
        if not addOnHandCurrency(source, Player, definition, amount, 'bank-withdrawal') then
            Player.Functions.AddMoney('bank', debit, 'bank-withdrawal-refund')
            return false, locale('transaction_failed')
        end
        balanceAfter = roundMoney(newBalance or Player.Functions.GetMoney('bank') or 0)
    else
        local current = getVaultBalances(Player.PlayerData.citizenid)[key] or 0
        if current < amount then return false, locale('currency_insufficient_vault') end

        local removed, newBalance = adjustVaultBalance(Player.PlayerData.citizenid, key, -amount)
        if not removed then return false, locale('currency_insufficient_vault') end
        if not addOnHandCurrency(source, Player, definition, amount, ('bank-%s-withdrawal'):format(key)) then
            adjustVaultBalance(Player.PlayerData.citizenid, key, amount)
            return false, locale('transaction_failed')
        end
        balanceAfter = newBalance
    end

    local pdata = Player.PlayerData
    local description
    if key == 'cash' then
        description = fee > 0 and ('Physical cash withdrawal (fee $%.2f)'):format(fee) or 'Physical cash withdrawal'
    else
        description = currencyLabel(definition) .. ' withdrawal'
    end
    recordTransaction(pdata.citizenid, (pdata.charinfo or {}).account, 'withdrawal', -debit, balanceAfter, description, '', transactionReference(), key)
    return true, key == 'cash' and locale('withdraw_success') or locale('currency_withdraw_success')
end

local function accountData(Player, selectedShared)
    local pdata = Player.PlayerData
    local charinfo = pdata.charinfo or {}
    local source = tonumber(pdata.source) or 0
    local currencies = currencyAccountData(source, Player)
    local cash = roundMoney(Player.Functions.GetMoney('cash') or 0)
    local gold = roundMoney(Player.Functions.GetMoney('gold') or 0)

    for i = 1, #currencies do
        if currencies[i].key == 'cash' then cash = currencies[i].onHand end
        if currencies[i].key == 'gold' then gold = currencies[i].onHand end
    end

    local data = {
        characterName = characterName(Player),
        citizenid = pdata.citizenid,
        accountNumber = tostring(charinfo.account or ''),
        cash = cash,
        bank = roundMoney(Player.Functions.GetMoney('bank') or 0),
        gold = gold,
        currencies = currencies,
        history = getHistory(pdata.citizenid),
        sharedAccounts = accessibleSharedAccounts(Player),
        sharedCreation = {
            enabled = Config.EnableSharedAccounts and Config.AllowPlayerSharedAccountCreation,
            fee = roundMoney(Config.SharedAccountCreationFee),
            maximum = Config.MaxSharedAccountsPerOwner,
        },
        limits = {
            deposit = Config.MaximumDeposit,
            withdrawal = Config.MaximumWithdrawal,
            transfer = Config.MaximumTransfer,
            sharedTransfer = Config.SharedAccountTransferMaximum,
            withdrawFeePercent = Config.WithdrawFeePercent,
            transferFeePercent = Config.TransferFeePercent,
        },
    }
    if selectedShared and selectedShared ~= '' then
        data.sharedAccount = sharedAccountData(Player, selectedShared)
    end
    return data
end

local function refreshClient(source, Player, selectedShared)
    TriggerClientEvent('node7-banking:client:refresh', source, accountData(Player, selectedShared))
end

local function findOfflineAccount(accountNumber)
    return MySQL.single.await([[
        SELECT citizenid, name, money, charinfo
        FROM players
        WHERE JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.account')) = ?
        LIMIT 1
    ]], { tostring(accountNumber or '') })
end

local function offlineCharacterName(row)
    local info = json.decode(row.charinfo or '{}') or {}
    local name = (('%s %s'):format(info.firstname or '', info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or row.name or 'Unknown Character'
end

local function creditOfflinePlayer(row, amount)
    local money = json.decode(row.money or '{}') or {}
    money.bank = roundMoney((tonumber(money.bank) or 0) + amount)
    local updated = MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(money), row.citizenid })
    return updated and updated > 0, money.bank
end

-- Personal banking ----------------------------------------------------------

lib.callback.register('node7-banking:server:getAccount', function(source)
    local Player, failure = requireBankPlayer(source, 'account')
    if not Player then return failure end
    return result(true, nil, accountData(Player))
end)

lib.callback.register('node7-banking:server:deposit', function(source, rawAmount)
    local Player, failure = requireBankPlayer(source, 'deposit')
    if not Player then return failure end
    local definition = currencyDefinition('cash')
    local amount = validCurrencyAmount(definition, rawAmount, Config.MaximumDeposit)
    if not amount then return result(false, locale('invalid_amount')) end

    local success, message = depositPersonalCurrency(source, Player, definition, amount)
    if not success then return result(false, message) end

    local data = accountData(Player)
    refreshClient(source, Player)
    return result(true, message, data)
end)

lib.callback.register('node7-banking:server:withdraw', function(source, rawAmount)
    local Player, failure = requireBankPlayer(source, 'withdraw')
    if not Player then return failure end
    local definition = currencyDefinition('cash')
    local amount = validCurrencyAmount(definition, rawAmount, Config.MaximumWithdrawal)
    if not amount then return result(false, locale('invalid_amount')) end

    local success, message = withdrawPersonalCurrency(source, Player, definition, amount)
    if not success then return result(false, message) end

    local data = accountData(Player)
    refreshClient(source, Player)
    return result(true, message, data)
end)

lib.callback.register('node7-banking:server:depositCurrency', function(source, rawCurrency, rawAmount)
    local Player, failure = requireBankPlayer(source, 'currency_deposit')
    if not Player then return failure end
    if not (Config.CurrencyBanking and Config.CurrencyBanking.Enabled) then return result(false, locale('currency_invalid')) end

    local definition = currencyDefinition(rawCurrency)
    if not definition then return result(false, locale('currency_invalid')) end
    local amount = validCurrencyAmount(definition, rawAmount, Config.MaximumDeposit)
    if not amount then
        return result(false, tonumber(definition.decimals) == 0 and locale('currency_whole_only') or locale('invalid_amount'))
    end

    local success, message = depositPersonalCurrency(source, Player, definition, amount)
    if not success then return result(false, message) end
    local data = accountData(Player)
    refreshClient(source, Player)
    return result(true, message, data)
end)

lib.callback.register('node7-banking:server:withdrawCurrency', function(source, rawCurrency, rawAmount)
    local Player, failure = requireBankPlayer(source, 'currency_withdraw')
    if not Player then return failure end
    if not (Config.CurrencyBanking and Config.CurrencyBanking.Enabled) then return result(false, locale('currency_invalid')) end

    local definition = currencyDefinition(rawCurrency)
    if not definition then return result(false, locale('currency_invalid')) end
    local amount = validCurrencyAmount(definition, rawAmount, Config.MaximumWithdrawal)
    if not amount then
        return result(false, tonumber(definition.decimals) == 0 and locale('currency_whole_only') or locale('invalid_amount'))
    end

    local success, message = withdrawPersonalCurrency(source, Player, definition, amount)
    if not success then return result(false, message) end
    local data = accountData(Player)
    refreshClient(source, Player)
    return result(true, message, data)
end)

lib.callback.register('node7-banking:server:transfer', function(source, rawAccount, rawAmount, rawNote)
    local Sender, failure = requireBankPlayer(source, 'transfer')
    if not Sender then return failure end

    local accountNumber = tostring(rawAccount or ''):gsub('%s+', '')
    local amount = validAmount(rawAmount, Config.MaximumTransfer)
    local note = cleanText(rawNote, 120)
    if accountNumber == '' or not amount then return result(false, locale('invalid_amount')) end

    local senderAccount = tostring((Sender.PlayerData.charinfo or {}).account or '')
    if accountNumber == senderAccount then return result(false, locale('cannot_transfer_self')) end

    local fee = roundMoney(amount * ((tonumber(Config.TransferFeePercent) or 0) / 100))
    local debit = roundMoney(amount + fee)
    if (Sender.Functions.GetMoney('bank') or 0) < debit then return result(false, locale('insufficient_bank')) end

    local Receiver = Node7Core.Functions.GetPlayerByAccount(accountNumber)
    local offlineRow
    if not Receiver then offlineRow = findOfflineAccount(accountNumber) end
    if not Receiver and not offlineRow then return result(false, locale('account_not_found')) end

    local removed, senderBalance = Sender.Functions.RemoveMoney('bank', debit, 'bank-transfer-out')
    if not removed then return result(false, locale('transaction_failed')) end

    local credited, receiverBalance, receiverCitizenid, receiverName
    if Receiver then
        credited, receiverBalance = Receiver.Functions.AddMoney('bank', amount, 'bank-transfer-in')
        receiverCitizenid = Receiver.PlayerData.citizenid
        receiverName = characterName(Receiver)
    else
        credited, receiverBalance = creditOfflinePlayer(offlineRow, amount)
        receiverCitizenid = offlineRow.citizenid
        receiverName = offlineCharacterName(offlineRow)
    end

    if not credited then
        Sender.Functions.AddMoney('bank', debit, 'bank-transfer-refund')
        return result(false, locale('transaction_failed'))
    end

    local reference = transactionReference()
    local senderDescription = note ~= '' and ('Transfer sent: %s'):format(note) or 'Bank transfer sent'
    local receiverDescription = note ~= '' and ('Transfer received: %s'):format(note) or 'Bank transfer received'
    if fee > 0 then senderDescription = ('%s (fee $%.2f)'):format(senderDescription, fee) end

    recordTransaction(Sender.PlayerData.citizenid, senderAccount, 'transfer_out', -debit, senderBalance, senderDescription, receiverName, reference)
    recordTransaction(receiverCitizenid, accountNumber, 'transfer_in', amount, receiverBalance, receiverDescription, characterName(Sender), reference)

    if Receiver then
        refreshClient(Receiver.PlayerData.source, Receiver)
        notify(Receiver.PlayerData.source, ('$%.2f received from %s.'):format(amount, characterName(Sender)), 'money', 'BANK TRANSFER RECEIVED')
    end

    local data = accountData(Sender)
    refreshClient(source, Sender)
    return result(true, locale('transfer_success'), data)
end)

-- Shared and society banking ------------------------------------------------

local function requireSharedAccess(source, action, accountName, permission)
    local Player, failure = requireBankPlayer(source, action)
    if not Player then return nil, nil, nil, failure end
    local account, access = getAccountAccess(Player, accountName)
    if not account or not access then return nil, nil, nil, result(false, locale('shared_access_denied')) end
    if permission and not access.permissions[permission] then
        return nil, nil, nil, result(false, locale('shared_permission_denied'))
    end
    if bool(account.frozen) and action ~= 'shared_get' and not (action == 'shared_deposit' and Config.FrozenAccountsAcceptDeposits) then
        return nil, nil, nil, result(false, locale('shared_frozen'))
    end
    return Player, account, access
end

lib.callback.register('node7-banking:server:getSharedAccount', function(source, accountName)
    local Player, account, _, failure = requireSharedAccess(source, 'shared_get', accountName)
    if not Player then return failure end
    return result(true, nil, {
        sharedAccount = sharedAccountData(Player, account.name),
        sharedAccounts = accessibleSharedAccounts(Player),
    })
end)

lib.callback.register('node7-banking:server:createSharedAccount', function(source, rawLabel)
    local Player, failure = requireBankPlayer(source, 'shared_create')
    if not Player then return failure end
    if not Config.EnableSharedAccounts or not Config.AllowPlayerSharedAccountCreation then
        return result(false, locale('shared_creation_disabled'))
    end

    local label = cleanText(rawLabel, Config.SharedAccountLabelMaxLength)
    if #label < 3 then return result(false, locale('shared_invalid_label')) end

    local citizenid = Player.PlayerData.citizenid
    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM node7_bank_accounts WHERE owner_citizenid = ? AND account_type = ?', { citizenid, 'shared' })) or 0
    if count >= Config.MaxSharedAccountsPerOwner then return result(false, locale('shared_limit_reached')) end

    local fee = roundMoney(Config.SharedAccountCreationFee)
    if fee > 0 and (Player.Functions.GetMoney('bank') or 0) < fee then return result(false, locale('insufficient_bank')) end
    if fee > 0 and not Player.Functions.RemoveMoney('bank', fee, 'shared-account-creation') then
        return result(false, locale('transaction_failed'))
    end

    local name = ('shared_%s_%s'):format(citizenid:lower():gsub('[^%w]', ''):sub(1, 16), math.random(100000, 999999))
    local ok, err = pcall(function()
        ensureSharedAccount(name, label, 'shared', 0, citizenid)
        local permissions = rolePermissions('owner')
        MySQL.insert.await([[
            INSERT INTO node7_bank_account_members
                (account_name, citizenid, member_name, role, can_deposit, can_withdraw, can_transfer, can_manage, created_by)
            VALUES (?, ?, ?, 'owner', ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE member_name = VALUES(member_name), role = 'owner',
                can_deposit = VALUES(can_deposit), can_withdraw = VALUES(can_withdraw),
                can_transfer = VALUES(can_transfer), can_manage = VALUES(can_manage)
        ]], { name, citizenid, characterName(Player), permissions.deposit and 1 or 0, permissions.withdraw and 1 or 0, permissions.transfer and 1 or 0, permissions.manage and 1 or 0, citizenid })
    end)

    if not ok then
        if fee > 0 then Player.Functions.AddMoney('bank', fee, 'shared-account-creation-refund') end
        print(('^1[node7-banking]^7 Shared account creation failed: %s'):format(tostring(err)))
        return result(false, locale('transaction_failed'))
    end

    recordSharedTransaction(name, 'account_created', 0, 0, 'Shared account opened', citizenid, characterName(Player), '', transactionReference())
    return result(true, locale('shared_created'), accountData(Player, name))
end)

lib.callback.register('node7-banking:server:sharedDeposit', function(source, accountName, rawAmount, rawNote)
    local Player, account, _, failure = requireSharedAccess(source, 'shared_deposit', accountName, 'deposit')
    if not Player then return failure end
    local amount = validAmount(rawAmount, Config.MaximumDeposit)
    if not amount then return result(false, locale('invalid_amount')) end
    if (Player.Functions.GetMoney('bank') or 0) < amount then return result(false, locale('insufficient_bank')) end

    local removed = Player.Functions.RemoveMoney('bank', amount, 'shared-bank-deposit')
    if not removed then return result(false, locale('transaction_failed')) end
    local changed = MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance + ? WHERE account_name = ?', { amount, account.name })
    if not changed or changed < 1 then
        Player.Functions.AddMoney('bank', amount, 'shared-bank-deposit-refund')
        return result(false, locale('transaction_failed'))
    end

    local balance = getSharedBalance(account.name)
    local reference = transactionReference()
    recordSharedTransaction(account.name, 'member_deposit', amount, balance, cleanText(rawNote, 120) ~= '' and cleanText(rawNote, 120) or 'Member deposit', Player.PlayerData.citizenid, characterName(Player), '', reference)
    recordTransaction(Player.PlayerData.citizenid, (Player.PlayerData.charinfo or {}).account, 'shared_deposit', -amount, Player.Functions.GetMoney('bank'), ('Deposit to %s'):format(account.label), account.label, reference)
    return result(true, locale('shared_deposit_success'), accountData(Player, account.name))
end)

lib.callback.register('node7-banking:server:sharedWithdraw', function(source, accountName, rawAmount, rawNote)
    local Player, account, _, failure = requireSharedAccess(source, 'shared_withdraw', accountName, 'withdraw')
    if not Player then return failure end
    local amount = validAmount(rawAmount, Config.MaximumWithdrawal)
    if not amount then return result(false, locale('invalid_amount')) end

    local changed = MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance - ? WHERE account_name = ? AND frozen = 0 AND balance >= ?', { amount, account.name, amount })
    if not changed or changed < 1 then return result(false, locale('shared_insufficient_funds')) end

    local added, personalBalance = Player.Functions.AddMoney('bank', amount, 'shared-bank-withdrawal')
    if not added then
        MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance + ? WHERE account_name = ?', { amount, account.name })
        return result(false, locale('transaction_failed'))
    end

    local balance = getSharedBalance(account.name)
    local reference = transactionReference()
    recordSharedTransaction(account.name, 'member_withdrawal', -amount, balance, cleanText(rawNote, 120) ~= '' and cleanText(rawNote, 120) or 'Member withdrawal', Player.PlayerData.citizenid, characterName(Player), characterName(Player), reference)
    recordTransaction(Player.PlayerData.citizenid, (Player.PlayerData.charinfo or {}).account, 'shared_withdrawal', amount, personalBalance, ('Withdrawal from %s'):format(account.label), account.label, reference)
    return result(true, locale('shared_withdraw_success'), accountData(Player, account.name))
end)

lib.callback.register('node7-banking:server:sharedTransfer', function(source, accountName, rawTarget, rawAmount, rawNote)
    local Player, account, _, failure = requireSharedAccess(source, 'shared_transfer', accountName, 'transfer')
    if not Player then return failure end
    local target = tostring(rawTarget or ''):gsub('%s+', '')
    local amount = validAmount(rawAmount, Config.SharedAccountTransferMaximum)
    local note = cleanText(rawNote, 120)
    if target == '' or not amount then return result(false, locale('invalid_amount')) end

    local targetShared = MySQL.single.await('SELECT account_name AS name, account_number AS accountNumber, label FROM node7_bank_accounts WHERE account_number = ? OR account_name = ? LIMIT 1', { target, normalizeAccountName(target) })
    if targetShared and targetShared.name == account.name then return result(false, locale('cannot_transfer_self')) end

    local targetPlayer, offlineRow
    if not targetShared then
        targetPlayer = Node7Core.Functions.GetPlayerByAccount(target)
        if not targetPlayer then offlineRow = findOfflineAccount(target) end
        if not targetPlayer and not offlineRow then return result(false, locale('account_not_found')) end
    end

    local debited = MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance - ? WHERE account_name = ? AND frozen = 0 AND balance >= ?', { amount, account.name, amount })
    if not debited or debited < 1 then return result(false, locale('shared_insufficient_funds')) end

    local credited, recipientBalance, recipientName, recipientCitizenid
    if targetShared then
        local changed = MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance + ? WHERE account_name = ?', { amount, targetShared.name })
        credited = changed and changed > 0
        recipientBalance = credited and getSharedBalance(targetShared.name) or 0
        recipientName = targetShared.label
    elseif targetPlayer then
        credited, recipientBalance = targetPlayer.Functions.AddMoney('bank', amount, 'shared-transfer-in')
        recipientName = characterName(targetPlayer)
        recipientCitizenid = targetPlayer.PlayerData.citizenid
    else
        credited, recipientBalance = creditOfflinePlayer(offlineRow, amount)
        recipientName = offlineCharacterName(offlineRow)
        recipientCitizenid = offlineRow.citizenid
    end

    if not credited then
        MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance + ? WHERE account_name = ?', { amount, account.name })
        return result(false, locale('transaction_failed'))
    end

    local sourceBalance = getSharedBalance(account.name)
    local reference = transactionReference()
    local description = note ~= '' and note or 'Shared account transfer'
    recordSharedTransaction(account.name, 'transfer_out', -amount, sourceBalance, description, Player.PlayerData.citizenid, characterName(Player), recipientName, reference)

    if targetShared then
        recordSharedTransaction(targetShared.name, 'transfer_in', amount, recipientBalance, description, Player.PlayerData.citizenid, characterName(Player), account.label, reference)
    else
        recordTransaction(recipientCitizenid, target, 'shared_transfer_in', amount, recipientBalance, ('Transfer from %s: %s'):format(account.label, description), account.label, reference)
        if targetPlayer then
            refreshClient(targetPlayer.PlayerData.source, targetPlayer)
            notify(targetPlayer.PlayerData.source, ('$%.2f received from %s.'):format(amount, account.label), 'money', 'SOCIETY TRANSFER RECEIVED')
        end
    end

    return result(true, locale('shared_transfer_success'), accountData(Player, account.name))
end)

local function findCharacterByAccount(accountNumber)
    local online = Node7Core.Functions.GetPlayerByAccount(accountNumber)
    if online then
        return online.PlayerData.citizenid, characterName(online)
    end
    local row = findOfflineAccount(accountNumber)
    if row then return row.citizenid, offlineCharacterName(row) end
    return nil, nil
end

lib.callback.register('node7-banking:server:setSharedMember', function(source, accountName, targetAccountNumber, role)
    local Player, account, _, failure = requireSharedAccess(source, 'shared_member', accountName, 'manage')
    if not Player then return failure end
    if account.type ~= 'shared' and not IsPlayerAceAllowed(source, 'node7.banking.admin') then
        return result(false, locale('shared_members_society_managed'))
    end

    role = tostring(role or 'member'):lower()
    if role ~= 'manager' and role ~= 'member' and role ~= 'viewer' then role = 'member' end
    local citizenid, memberName = findCharacterByAccount(tostring(targetAccountNumber or ''):gsub('%s+', ''))
    if not citizenid then return result(false, locale('account_not_found')) end
    if citizenid == account.ownerCitizenid then return result(false, locale('shared_owner_immutable')) end

    local permissions = rolePermissions(role)
    MySQL.insert.await([[
        INSERT INTO node7_bank_account_members
            (account_name, citizenid, member_name, role, can_deposit, can_withdraw, can_transfer, can_manage, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE member_name = VALUES(member_name), role = VALUES(role),
            can_deposit = VALUES(can_deposit), can_withdraw = VALUES(can_withdraw),
            can_transfer = VALUES(can_transfer), can_manage = VALUES(can_manage),
            updated_at = CURRENT_TIMESTAMP
    ]], {
        account.name, citizenid, memberName, role,
        permissions.deposit and 1 or 0,
        permissions.withdraw and 1 or 0,
        permissions.transfer and 1 or 0,
        permissions.manage and 1 or 0,
        Player.PlayerData.citizenid,
    })

    recordSharedTransaction(account.name, 'member_updated', 0, getSharedBalance(account.name), ('%s set as %s'):format(memberName, role), Player.PlayerData.citizenid, characterName(Player), memberName, transactionReference())
    return result(true, locale('shared_member_saved'), accountData(Player, account.name))
end)

lib.callback.register('node7-banking:server:removeSharedMember', function(source, accountName, citizenid)
    local Player, account, _, failure = requireSharedAccess(source, 'shared_member_remove', accountName, 'manage')
    if not Player then return failure end
    if account.type ~= 'shared' and not IsPlayerAceAllowed(source, 'node7.banking.admin') then
        return result(false, locale('shared_members_society_managed'))
    end
    citizenid = cleanText(citizenid, 50)
    if citizenid == '' or citizenid == account.ownerCitizenid then return result(false, locale('shared_owner_immutable')) end

    local row = MySQL.single.await('SELECT member_name FROM node7_bank_account_members WHERE account_name = ? AND citizenid = ? LIMIT 1', { account.name, citizenid })
    if not row then return result(false, locale('shared_member_not_found')) end
    MySQL.update.await('DELETE FROM node7_bank_account_members WHERE account_name = ? AND citizenid = ?', { account.name, citizenid })
    recordSharedTransaction(account.name, 'member_removed', 0, getSharedBalance(account.name), ('Member removed: %s'):format(row.member_name or citizenid), Player.PlayerData.citizenid, characterName(Player), row.member_name or citizenid, transactionReference())
    return result(true, locale('shared_member_removed'), accountData(Player, account.name))
end)

lib.callback.register('node7-banking:server:renameSharedAccount', function(source, accountName, rawLabel)
    local Player, account, _, failure = requireSharedAccess(source, 'shared_rename', accountName, 'manage')
    if not Player then return failure end
    local label = cleanText(rawLabel, Config.SharedAccountLabelMaxLength)
    if #label < 3 then return result(false, locale('shared_invalid_label')) end
    MySQL.update.await('UPDATE node7_bank_accounts SET label = ? WHERE account_name = ?', { label, account.name })
    recordSharedTransaction(account.name, 'account_renamed', 0, getSharedBalance(account.name), ('Account renamed to %s'):format(label), Player.PlayerData.citizenid, characterName(Player), '', transactionReference())
    return result(true, locale('shared_renamed'), accountData(Player, account.name))
end)

-- Shared account exports ----------------------------------------------------

local function setSharedBalance(name, amount, reason)
    name = normalizeAccountName(name)
    amount = roundMoney(amount)
    if name == '' or amount < 0 then return false end
    ensureSharedAccount(name, name, 'society', 0, '')
    MySQL.update.await('UPDATE node7_bank_accounts SET balance = ? WHERE account_name = ?', { amount, name })
    recordSharedTransaction(name, 'set', amount, amount, reason or 'set-balance', '', 'System', '', transactionReference())
    return true, amount
end

local function addSharedMoney(name, amount, reason)
    amount = validAmount(amount, 1000000000.00)
    if not amount then return false end
    name = normalizeAccountName(name)
    ensureSharedAccount(name, name, 'society', 0, '')
    MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance + ? WHERE account_name = ?', { amount, name })
    local balance = getSharedBalance(name)
    recordSharedTransaction(name, 'credit', amount, balance, reason or 'credit', '', 'System', '', transactionReference())
    return true, balance
end

local function removeSharedMoney(name, amount, reason)
    amount = validAmount(amount, 1000000000.00)
    if not amount then return false end
    name = normalizeAccountName(name)
    ensureSharedAccount(name, name, 'society', 0, '')
    local changed = MySQL.update.await('UPDATE node7_bank_accounts SET balance = balance - ? WHERE account_name = ? AND balance >= ?', { amount, name, amount })
    if not changed or changed < 1 then return false end
    local balance = getSharedBalance(name)
    recordSharedTransaction(name, 'debit', -amount, balance, reason or 'debit', '', 'System', '', transactionReference())
    return true, balance
end

exports('CreateAccount', ensureSharedAccount)
exports('GetAccountBalance', getSharedBalance)
exports('GetAccount', function(name) return accountRow(name) end)
exports('GetAccountMembers', sharedMembers)
exports('SetMoney', setSharedBalance)
exports('AddMoney', addSharedMoney)
exports('RemoveMoney', removeSharedMoney)

-- Administration commands --------------------------------------------------

local function adminAllowed(source)
    return source == 0 or IsPlayerAceAllowed(source, 'node7.banking.admin')
end

local function adminReply(source, message, success)
    if source == 0 then
        print(('[node7-banking] %s'):format(message))
    else
        notify(source, message, success and 'success' or 'error', 'BANK ADMIN')
    end
end

RegisterCommand('bankaccountcreate', function(source, args)
    if not adminAllowed(source) then return end
    local name = normalizeAccountName(args[1])
    local accountType = cleanText(args[2] or 'society', 32)
    local label = cleanText(table.concat(args, ' ', 3), Config.SharedAccountLabelMaxLength)
    if name == '' or label == '' then return adminReply(source, 'Usage: /bankaccountcreate [name] [type] [label]', false) end
    ensureSharedAccount(name, label, accountType, 0, '')
    adminReply(source, ('Created or updated account %s (%s).'):format(label, name), true)
end, true)

RegisterCommand('bankaccountset', function(source, args)
    if not adminAllowed(source) then return end
    local success, balance = setSharedBalance(args[1], tonumber(args[2]), 'admin-command')
    adminReply(source, success and ('Account %s set to $%.2f.'):format(args[1], balance) or 'Unable to set account balance.', success)
end, true)

RegisterCommand('bankaccountadd', function(source, args)
    if not adminAllowed(source) then return end
    local success, balance = addSharedMoney(args[1], tonumber(args[2]), 'admin-command')
    adminReply(source, success and ('$%.2f added to %s. Balance: $%.2f'):format(tonumber(args[2]), args[1], balance) or 'Unable to add account money.', success)
end, true)

RegisterCommand('bankaccountremove', function(source, args)
    if not adminAllowed(source) then return end
    local success, balance = removeSharedMoney(args[1], tonumber(args[2]), 'admin-command')
    adminReply(source, success and ('$%.2f removed from %s. Balance: $%.2f'):format(tonumber(args[2]), args[1], balance) or 'Unable to remove account money.', success)
end, true)

RegisterCommand('bankaccountfreeze', function(source, args)
    if not adminAllowed(source) then return end
    local name = normalizeAccountName(args[1])
    local frozen = tostring(args[2] or 'true'):lower()
    frozen = frozen == 'true' or frozen == '1' or frozen == 'yes'
    local changed = MySQL.update.await('UPDATE node7_bank_accounts SET frozen = ? WHERE account_name = ?', { frozen and 1 or 0, name })
    adminReply(source, changed and changed > 0 and ('Account %s %s.'):format(name, frozen and 'frozen' or 'unfrozen') or 'Account not found.', changed and changed > 0)
end, true)

AddEventHandler('playerDropped', function()
    local source = source
    local prefix = tostring(source) .. ':'
    for key in pairs(rateLimits) do
        if key:sub(1, #prefix) == prefix then rateLimits[key] = nil end
    end
end)

-- Database schema and migrations -------------------------------------------

local function databaseColumnExists(tableName, columnName)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })
    return (tonumber(count) or 0) > 0
end

local function databaseIndexExists(tableName, indexName)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    ]], { tableName, indexName })
    return (tonumber(count) or 0) > 0
end

local function ensureColumn(tableName, columnName, definition)
    if databaseColumnExists(tableName, columnName) then return false end
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    print(('^3[node7-banking]^7 Migrated %s: added %s'):format(tableName, columnName))
    return true
end

local function ensureIndex(tableName, indexName, columns, unique)
    if databaseIndexExists(tableName, indexName) then return false end
    MySQL.query.await(('ALTER TABLE `%s` ADD %s INDEX `%s` (%s)'):format(
        tableName,
        unique and 'UNIQUE' or '',
        indexName,
        columns
    ))
    print(('^3[node7-banking]^7 Migrated %s: added index %s'):format(tableName, indexName))
    return true
end

local function copyLegacyTextColumn(tableName, targetColumn, sourceColumn)
    if not databaseColumnExists(tableName, targetColumn) or not databaseColumnExists(tableName, sourceColumn) then
        return
    end

    MySQL.update.await(([[
        UPDATE `%s`
        SET `%s` = CAST(`%s` AS CHAR)
        WHERE (`%s` IS NULL OR `%s` = '') AND `%s` IS NOT NULL
    ]]):format(tableName, targetColumn, sourceColumn, targetColumn, targetColumn, sourceColumn))
end

local function copyLegacyNumberColumn(tableName, targetColumn, sourceColumn)
    if not databaseColumnExists(tableName, targetColumn) or not databaseColumnExists(tableName, sourceColumn) then
        return
    end

    MySQL.update.await(([[
        UPDATE `%s`
        SET `%s` = COALESCE(`%s`, 0)
        WHERE (`%s` IS NULL OR `%s` = 0) AND `%s` IS NOT NULL
    ]]):format(tableName, targetColumn, sourceColumn, targetColumn, targetColumn, sourceColumn))
end

local function repairSharedAccountNumbers()
    local missing = MySQL.query.await([[
        SELECT account_name
        FROM node7_bank_accounts
        WHERE account_number IS NULL OR account_number = ''
    ]]) or {}

    for i = 1, #missing do
        MySQL.update.await(
            'UPDATE node7_bank_accounts SET account_number = ? WHERE account_name = ?',
            { generateSharedAccountNumber(), missing[i].account_name }
        )
    end

    local duplicates = MySQL.query.await([[
        SELECT account_number
        FROM node7_bank_accounts
        WHERE account_number IS NOT NULL AND account_number <> ''
        GROUP BY account_number
        HAVING COUNT(*) > 1
    ]]) or {}

    for i = 1, #duplicates do
        local rows = MySQL.query.await([[
            SELECT account_name
            FROM node7_bank_accounts
            WHERE account_number = ?
            ORDER BY account_name ASC
        ]], { duplicates[i].account_number }) or {}

        for rowIndex = 2, #rows do
            MySQL.update.await(
                'UPDATE node7_bank_accounts SET account_number = ? WHERE account_name = ?',
                { generateSharedAccountNumber(), rows[rowIndex].account_name }
            )
        end
    end
end

local function migrateSchema()
    -- Personal transaction ledger.
    ensureColumn('node7_bank_transactions', 'citizenid', "VARCHAR(50) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_transactions', 'account_number', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_transactions', 'transaction_type', "VARCHAR(32) NOT NULL DEFAULT 'unknown'")
    ensureColumn('node7_bank_transactions', 'currency', "VARCHAR(32) NOT NULL DEFAULT 'cash'")
    ensureColumn('node7_bank_transactions', 'amount', 'DECIMAL(18,2) NOT NULL DEFAULT 0.00')
    ensureColumn('node7_bank_transactions', 'balance_after', 'DECIMAL(18,2) NOT NULL DEFAULT 0.00')
    ensureColumn('node7_bank_transactions', 'description', "VARCHAR(255) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_transactions', 'counterparty', "VARCHAR(128) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_transactions', 'reference', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_transactions', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
    ensureIndex('node7_bank_transactions', 'idx_node7_bank_tx_citizenid', '`citizenid`', false)
    ensureIndex('node7_bank_transactions', 'idx_node7_bank_tx_account', '`account_number`', false)
    ensureIndex('node7_bank_transactions', 'idx_node7_bank_tx_reference', '`reference`', false)
    ensureIndex('node7_bank_transactions', 'idx_node7_bank_tx_currency', '`citizenid`, `currency`', false)

    -- Per-character non-dollar currency vault balances.
    ensureColumn('node7_bank_currency_balances', 'citizenid', "VARCHAR(50) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_currency_balances', 'currency', "VARCHAR(32) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_currency_balances', 'amount', 'DECIMAL(18,2) NOT NULL DEFAULT 0.00')
    ensureColumn('node7_bank_currency_balances', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
    ensureColumn('node7_bank_currency_balances', 'updated_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')
    ensureIndex('node7_bank_currency_balances', 'uq_node7_bank_currency_balance', '`citizenid`, `currency`', true)

    -- Society, gang, and player-created shared accounts. Every column is
    -- migrated before any default/job/gang account insert is attempted.
    ensureColumn('node7_bank_accounts', 'account_name', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_accounts', 'account_number', "VARCHAR(32) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_accounts', 'label', "VARCHAR(128) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_accounts', 'account_type', "VARCHAR(32) NOT NULL DEFAULT 'society'")
    ensureColumn('node7_bank_accounts', 'owner_citizenid', "VARCHAR(50) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_accounts', 'balance', 'DECIMAL(18,2) NOT NULL DEFAULT 0.00')
    ensureColumn('node7_bank_accounts', 'frozen', 'TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('node7_bank_accounts', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
    ensureColumn('node7_bank_accounts', 'updated_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')

    -- Preserve common legacy schemas instead of deleting existing account data.
    copyLegacyTextColumn('node7_bank_accounts', 'account_name', 'name')
    copyLegacyTextColumn('node7_bank_accounts', 'account_name', 'account')
    copyLegacyTextColumn('node7_bank_accounts', 'label', 'account_label')
    copyLegacyTextColumn('node7_bank_accounts', 'label', 'name')
    copyLegacyTextColumn('node7_bank_accounts', 'account_type', 'type')
    copyLegacyNumberColumn('node7_bank_accounts', 'balance', 'money')
    copyLegacyNumberColumn('node7_bank_accounts', 'balance', 'amount')

    MySQL.update.await([[
        UPDATE node7_bank_accounts
        SET account_name = CONCAT('legacy_', REPLACE(UUID(), '-', ''))
        WHERE account_name IS NULL OR account_name = ''
    ]])
    MySQL.update.await([[
        UPDATE node7_bank_accounts
        SET label = account_name
        WHERE label IS NULL OR label = ''
    ]])
    MySQL.update.await([[
        UPDATE node7_bank_accounts
        SET account_type = 'society'
        WHERE account_type IS NULL OR account_type = ''
    ]])

    repairSharedAccountNumbers()
    ensureIndex('node7_bank_accounts', 'idx_node7_shared_name', '`account_name`', true)
    ensureIndex('node7_bank_accounts', 'idx_node7_shared_number', '`account_number`', true)
    ensureIndex('node7_bank_accounts', 'idx_node7_shared_owner', '`owner_citizenid`', false)

    -- Explicit shared-account members.
    ensureColumn('node7_bank_account_members', 'account_name', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_members', 'citizenid', "VARCHAR(50) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_members', 'member_name', "VARCHAR(128) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_members', 'role', "VARCHAR(24) NOT NULL DEFAULT 'member'")
    ensureColumn('node7_bank_account_members', 'can_deposit', 'TINYINT(1) NOT NULL DEFAULT 1')
    ensureColumn('node7_bank_account_members', 'can_withdraw', 'TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('node7_bank_account_members', 'can_transfer', 'TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('node7_bank_account_members', 'can_manage', 'TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('node7_bank_account_members', 'created_by', "VARCHAR(50) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_members', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
    ensureColumn('node7_bank_account_members', 'updated_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')
    ensureIndex('node7_bank_account_members', 'uq_node7_bank_member', '`account_name`, `citizenid`', true)
    ensureIndex('node7_bank_account_members', 'idx_node7_bank_member_citizen', '`citizenid`', false)

    -- Shared-account ledger.
    ensureColumn('node7_bank_account_transactions', 'account_name', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_transactions', 'transaction_type', "VARCHAR(32) NOT NULL DEFAULT 'unknown'")
    ensureColumn('node7_bank_account_transactions', 'amount', 'DECIMAL(18,2) NOT NULL DEFAULT 0.00')
    ensureColumn('node7_bank_account_transactions', 'balance_after', 'DECIMAL(18,2) NOT NULL DEFAULT 0.00')
    ensureColumn('node7_bank_account_transactions', 'description', "VARCHAR(255) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_transactions', 'actor_citizenid', "VARCHAR(50) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_transactions', 'actor_name', "VARCHAR(128) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_transactions', 'counterparty', "VARCHAR(128) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_transactions', 'reference', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('node7_bank_account_transactions', 'created_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
    ensureIndex('node7_bank_account_transactions', 'idx_node7_shared_tx_account', '`account_name`', false)
    ensureIndex('node7_bank_account_transactions', 'idx_node7_shared_tx_reference', '`reference`', false)
end

local function createBaseTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS node7_bank_transactions (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            citizenid VARCHAR(50) NOT NULL,
            account_number VARCHAR(64) NOT NULL DEFAULT '',
            transaction_type VARCHAR(32) NOT NULL,
            currency VARCHAR(32) NOT NULL DEFAULT 'cash',
            amount DECIMAL(18,2) NOT NULL DEFAULT 0.00,
            balance_after DECIMAL(18,2) NOT NULL DEFAULT 0.00,
            description VARCHAR(255) NOT NULL DEFAULT '',
            counterparty VARCHAR(128) NOT NULL DEFAULT '',
            reference VARCHAR(64) NOT NULL DEFAULT '',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_node7_bank_tx_citizenid (citizenid),
            KEY idx_node7_bank_tx_account (account_number),
            KEY idx_node7_bank_tx_reference (reference),
            KEY idx_node7_bank_tx_currency (citizenid, currency)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS node7_bank_currency_balances (
            citizenid VARCHAR(50) NOT NULL,
            currency VARCHAR(32) NOT NULL,
            amount DECIMAL(18,2) NOT NULL DEFAULT 0.00,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (citizenid, currency)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS node7_bank_accounts (
            account_name VARCHAR(64) NOT NULL,
            account_number VARCHAR(32) NOT NULL DEFAULT '',
            label VARCHAR(128) NOT NULL DEFAULT '',
            account_type VARCHAR(32) NOT NULL DEFAULT 'society',
            owner_citizenid VARCHAR(50) NOT NULL DEFAULT '',
            balance DECIMAL(18,2) NOT NULL DEFAULT 0.00,
            frozen TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (account_name),
            UNIQUE KEY idx_node7_shared_number (account_number),
            KEY idx_node7_shared_owner (owner_citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS node7_bank_account_members (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            account_name VARCHAR(64) NOT NULL,
            citizenid VARCHAR(50) NOT NULL,
            member_name VARCHAR(128) NOT NULL DEFAULT '',
            role VARCHAR(24) NOT NULL DEFAULT 'member',
            can_deposit TINYINT(1) NOT NULL DEFAULT 1,
            can_withdraw TINYINT(1) NOT NULL DEFAULT 0,
            can_transfer TINYINT(1) NOT NULL DEFAULT 0,
            can_manage TINYINT(1) NOT NULL DEFAULT 0,
            created_by VARCHAR(50) NOT NULL DEFAULT '',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_node7_bank_member (account_name, citizenid),
            KEY idx_node7_bank_member_citizen (citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS node7_bank_account_transactions (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            account_name VARCHAR(64) NOT NULL,
            transaction_type VARCHAR(32) NOT NULL,
            currency VARCHAR(32) NOT NULL DEFAULT 'cash',
            amount DECIMAL(18,2) NOT NULL DEFAULT 0.00,
            balance_after DECIMAL(18,2) NOT NULL DEFAULT 0.00,
            description VARCHAR(255) NOT NULL DEFAULT '',
            actor_citizenid VARCHAR(50) NOT NULL DEFAULT '',
            actor_name VARCHAR(128) NOT NULL DEFAULT '',
            counterparty VARCHAR(128) NOT NULL DEFAULT '',
            reference VARCHAR(64) NOT NULL DEFAULT '',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_node7_shared_tx_account (account_name),
            KEY idx_node7_shared_tx_reference (reference)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

MySQL.ready(function()
    local ok, err = pcall(function()
        createBaseTables()
        migrateSchema()

        for i = 1, #(Config.DefaultSharedAccounts or {}) do
            local account = Config.DefaultSharedAccounts[i]
            ensureSharedAccount(account.name, account.label, account.account_type, account.starting_balance, account.owner_citizenid)
        end

        if Config.AutoCreateJobAccounts then
            for name, job in pairs((Node7Core.Shared and Node7Core.Shared.Jobs) or {}) do
                if not Config.IgnoredJobAccounts[name] then
                    ensureSharedAccount(name, job.label or name, 'society', 0, '')
                end
            end
        end

        if Config.AutoCreateGangAccounts then
            for name, gang in pairs((Node7Core.Shared and Node7Core.Shared.Gangs) or {}) do
                if not Config.IgnoredGangAccounts[name] then
                    ensureSharedAccount(('gang_%s'):format(name), gang.label or name, 'gang', 0, '')
                end
            end
        end
    end)

    if not ok then
        databaseReady = false
        print(('^1[node7-banking]^7 Database migration failed: %s'):format(tostring(err)))
        print('^1[node7-banking]^7 Banking remains disabled to prevent partial or duplicated transactions.')
        return
    end

    databaseReady = true
    print('^2[node7-banking]^7 Database ready | schema v2.4.0 | physical cash bills/coins | multi-currency vault | personal banking | society accounts | shared accounts | ledgers')
end)
