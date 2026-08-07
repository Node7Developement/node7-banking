local Node7Core = exports['node7-core']:GetCoreObject()
lib.locale()

local RESOURCE = GetCurrentResourceName()
local UI_RESOURCE = 'node7-ui'
local bankOpen = false
local activeBank = nil
local currentData = nil
local selectedShared = nil
local currentModule = 'personal'
local currentScreen = 'overview'
local actionBusy = false
local activeCurrencyKey = nil
local spawnedPeds = {}
local spawnedBlips = {}

local function uiStarted()
    return GetResourceState(UI_RESOURCE) == 'started'
end

local function money(value)
    return ('$%.2f'):format(tonumber(value) or 0)
end

local function currencyDefinition(key)
    key = tostring(key or ''):lower()
    for i = 1, #(((Config.CurrencyBanking or {}).Currencies) or {}) do
        local definition = Config.CurrencyBanking.Currencies[i]
        if tostring(definition.key or ''):lower() == key then return definition end
    end
    return nil
end

local function currencyValue(key, value, decimals)
    key = tostring(key or ''):lower()
    decimals = tonumber(decimals)
    if decimals == nil then
        local definition = currencyDefinition(key)
        decimals = tonumber(definition and definition.decimals) or 0
    end
    if key == 'cash' or key == 'bloodmoney' then
        return money(value)
    end
    if decimals == 0 then
        return ('%d'):format(math.floor((tonumber(value) or 0) + 0.00001))
    end
    return ('%.2f'):format(tonumber(value) or 0)
end

local function clean(value)
    return tostring(value or '')
end

local function yesNo(value)
    return (value == true or value == 1 or value == '1') and 'Yes' or 'No'
end

local function notify(description, notificationType, title)
    if uiStarted() then
        exports[UI_RESOURCE]:ShowToast({
            title = title or 'FRONTIER BANK',
            message = description,
            type = notificationType or 'info',
            duration = 5000,
            standalone = not bankOpen,
        })
        return
    end

    Node7Core.Functions.Notify({
        title = title or 'FRONTIER BANK',
        description = description,
        type = notificationType or 'info',
        duration = 5000,
    })
end

local function isBankOpen()
    if Config.AlwaysOpen then return true end
    local hour = GetClockHours()
    return hour >= Config.OpenTime and hour < Config.CloseTime
end

local function nearestBank(maxDistance)
    local coords = GetEntityCoords(cache.ped or PlayerPedId())
    local nearest, nearestDistance
    for i = 1, #Config.BankLocations do
        local bank = Config.BankLocations[i]
        local distance = #(coords - bank.coords)
        if not nearestDistance or distance < nearestDistance then
            nearest = bank
            nearestDistance = distance
        end
    end
    if nearestDistance and nearestDistance <= (maxDistance or Config.InteractionDistance) then
        return nearest, nearestDistance
    end
    return nil, nearestDistance
end

local function releaseBank()
    bankOpen = false
    activeBank = nil
    currentData = nil
    selectedShared = nil
    currentModule = 'personal'
    currentScreen = 'overview'
    actionBusy = false
    activeCurrencyKey = nil
end

local function closeBank(reason)
    if not bankOpen then return end
    if uiStarted() and exports[UI_RESOURCE]:IsOpen() then
        exports[UI_RESOURCE]:Close(reason or 'bank_closed')
    end
    releaseBank()
end

local function transactionEntry(entry, shared)
    local amount = tonumber(entry.amount) or 0
    local positive = amount >= 0
    local currencyKey = shared and 'cash' or clean(entry.currency ~= '' and entry.currency or 'cash'):lower()
    local definition = currencyDefinition(currencyKey)
    local formattedAmount = shared and money(amount) or currencyValue(currencyKey, amount, definition and definition.decimals)
    local formattedBalance = shared and money(entry.balanceAfter) or currencyValue(currencyKey, entry.balanceAfter, definition and definition.decimals)
    local currencyName = shared and 'Canadian Dollars' or clean((definition and definition.label) or currencyKey)
    return {
        id = ('%s_tx_%s'):format(shared and 'shared' or 'personal', clean(entry.id)),
        entry = clean(entry.description ~= '' and entry.description or entry.type),
        category = clean(entry.type):gsub('_', ' '),
        status = positive and 'Credit' or 'Debit',
        value = formattedAmount,
        balance = formattedBalance,
        counterparty = clean(entry.counterparty or entry.actorName),
        reference = clean(entry.reference),
        createdAt = clean(entry.createdAt),
        label = clean(entry.description ~= '' and entry.description or entry.type),
        description = ('%s · %s · Balance after %s'):format(clean(entry.createdAt), currencyName, formattedBalance),
        badge = positive and 'Credit' or 'Debit',
        type = shared and 'Shared Ledger' or 'Personal Ledger',
        stats = {
            { label = 'Currency', value = currencyName },
            { label = 'Amount', value = formattedAmount },
            { label = 'Balance After', value = formattedBalance },
            { label = 'Counterparty', value = clean(entry.counterparty or entry.actorName or '—') },
            { label = 'Reference', value = clean(entry.reference or '—') },
        },
        actions = {
            { id = 'view_transaction', label = 'View Entry', style = 'primary' },
        },
    }
end

local function transactionRows(history, shared)
    local rows = {}
    for i = 1, #(history or {}) do
        rows[#rows + 1] = transactionEntry(history[i], shared)
    end
    return rows
end

local function personalServiceItems(data)
    return {
        {
            id = 'deposit', label = 'Deposit Cash', icon = '$', category = 'personal',
            value = money(data.cash), badge = 'Cash Available',
            description = 'Move carried cash safely into your personal bank account.',
            stats = {
                { label = 'Cash Available', value = money(data.cash) },
                { label = 'Deposit Limit', value = money(data.limits and data.limits.deposit) },
                { label = 'Fee', value = '$0.00' },
            },
            actions = { { id = 'personal_deposit', label = 'Make Deposit', style = 'primary' } },
        },
        {
            id = 'withdraw', label = 'Withdraw Cash', icon = 'W', category = 'personal',
            value = money(data.bank), badge = 'Bank Available',
            description = 'Withdraw funds from your personal bank account into carried cash.',
            stats = {
                { label = 'Bank Available', value = money(data.bank) },
                { label = 'Withdrawal Limit', value = money(data.limits and data.limits.withdrawal) },
                { label = 'Fee', value = ('%.2f%%'):format(tonumber(data.limits and data.limits.withdrawFeePercent) or 0) },
            },
            actions = { { id = 'personal_withdraw', label = 'Make Withdrawal', style = 'primary' } },
        },
        {
            id = 'transfer', label = 'Wire Transfer', icon = 'T', category = 'personal',
            value = money(data.bank), badge = 'Account Transfer',
            description = 'Send bank funds to another character using their account number.',
            stats = {
                { label = 'Bank Available', value = money(data.bank) },
                { label = 'Transfer Limit', value = money(data.limits and data.limits.transfer) },
                { label = 'Fee', value = ('%.2f%%'):format(tonumber(data.limits and data.limits.transferFeePercent) or 0) },
            },
            actions = { { id = 'personal_transfer', label = 'Start Transfer', style = 'primary' } },
        },
        {
            id = 'refresh', label = 'Refresh Ledger', icon = 'R', category = 'personal',
            value = clean(data.accountNumber), badge = 'Live Account',
            description = 'Request the latest balances, transactions, and shared-account access.',
            actions = { { id = 'refresh_bank', label = 'Refresh Banking', style = 'primary' } },
        },
    }
end

local function currencyVaultItems(data)
    local items = {}
    for i = 1, #(data.currencies or {}) do
        local currency = data.currencies[i]
        local key = clean(currency.key):lower()
        local decimals = tonumber(currency.decimals) or 0
        local physicalNote = key == 'cash' and ' Accepts every physical $1, $5, $10, $20, $50, and $100 bill plus quarters, dimes, nickels, and pennies.' or ''
        items[#items + 1] = {
            id = 'currency_' .. key,
            currencyKey = key,
            decimals = decimals,
            label = clean(currency.label),
            icon = clean(currency.icon),
            category = 'currency',
            value = currencyValue(key, currency.banked, decimals),
            badge = 'Deposited',
            description = clean(currency.description) .. physicalNote,
            stats = {
                { label = 'On Hand', value = currencyValue(key, currency.onHand, decimals) },
                { label = 'Deposited', value = currencyValue(key, currency.banked, decimals) },
            },
            actions = {
                { id = 'currency_deposit', label = 'Deposit', style = 'primary' },
                { id = 'currency_withdraw', label = 'Withdraw', style = 'secondary' },
            },
        }
    end
    return items
end

local function sharedAccountItems(data)
    local items = {}
    for i = 1, #(data.sharedAccounts or {}) do
        local account = data.sharedAccounts[i]
        items[#items + 1] = {
            id = clean(account.name),
            accountName = clean(account.name),
            label = clean(account.label),
            icon = clean(account.type):sub(1, 2):upper(),
            category = clean(account.type),
            value = money(account.balance),
            badge = account.frozen and 'Frozen' or clean(account.role),
            description = ('Account %s · %s access'):format(clean(account.accountNumber), clean(account.role)),
            stats = {
                { label = 'Balance', value = money(account.balance) },
                { label = 'Account Number', value = clean(account.accountNumber) },
                { label = 'Role', value = clean(account.role) },
                { label = 'State', value = account.frozen and 'Frozen' or 'Active' },
            },
            actions = { { id = 'open_shared', label = 'Open Account', style = 'primary' } },
        }
    end

    if data.sharedCreation and data.sharedCreation.enabled then
        items[#items + 1] = {
            id = 'create_shared', label = 'Open Shared Account', icon = '+', category = 'shared',
            value = money(data.sharedCreation.fee), badge = 'Creation Fee',
            description = ('Create a private shared account. Maximum owned accounts: %s.'):format(clean(data.sharedCreation.maximum)),
            actions = { { id = 'create_shared', label = 'Create Account', style = 'primary' } },
        }
    end

    return items
end

local function sharedServiceItems(account)
    if not account then
        return {
            {
                id = 'select_shared', label = 'Select a Shared Account', icon = 'SA', category = 'shared',
                value = 'Required', badge = 'No Account Selected',
                description = 'Choose an accessible society, gang, or private shared account first.',
                actions = { { id = 'go_shared_accounts', label = 'Browse Accounts', style = 'primary' } },
            },
        }
    end

    local permissions = account.permissions or {}
    local items = {}
    if permissions.deposit then
        items[#items + 1] = {
            id = 'shared_deposit', label = 'Fund Shared Account', icon = '$+', category = 'shared',
            value = money(account.balance), badge = 'Deposit Allowed',
            description = 'Move funds from your personal bank balance into this shared account.',
            actions = { { id = 'shared_deposit', label = 'Deposit Funds', style = 'primary' } },
        }
    end
    if permissions.withdraw then
        items[#items + 1] = {
            id = 'shared_withdraw', label = 'Withdraw Shared Funds', icon = '$-', category = 'shared',
            value = money(account.balance), badge = account.frozen and 'Frozen' or 'Withdrawal Allowed',
            description = account.frozen and 'This account is frozen and cannot release funds.' or 'Move shared funds into your personal bank account.',
            actions = { { id = account.frozen and 'shared_frozen' or 'shared_withdraw', label = account.frozen and 'Account Frozen' or 'Withdraw Funds', style = 'primary' } },
        }
    end
    if permissions.transfer then
        items[#items + 1] = {
            id = 'shared_transfer', label = 'Shared Transfer', icon = 'ST', category = 'shared',
            value = money(account.balance), badge = account.frozen and 'Frozen' or 'Transfer Allowed',
            description = account.frozen and 'This account is frozen and cannot send transfers.' or 'Send shared funds to another personal or shared account number.',
            actions = { { id = account.frozen and 'shared_frozen' or 'shared_transfer', label = account.frozen and 'Account Frozen' or 'Start Transfer', style = 'primary' } },
        }
    end
    if permissions.manage then
        items[#items + 1] = {
            id = 'rename_shared', label = 'Rename Account', icon = 'RN', category = 'management',
            value = clean(account.label), badge = 'Management',
            description = 'Change the public label shown for this shared account.',
            actions = { { id = 'rename_shared', label = 'Rename Account', style = 'primary' } },
        }
        if clean(account.type) == 'shared' then
            items[#items + 1] = {
                id = 'add_member', label = 'Add or Update Member', icon = 'M+', category = 'management',
                value = tostring(#(account.members or {})), badge = 'Member Management',
                description = 'Grant manager, member, or viewer access using a character account number.',
                actions = { { id = 'add_shared_member', label = 'Manage Member', style = 'primary' } },
            }
        end
    end

    return items
end

local function memberItems(account)
    local items = {}
    for i = 1, #((account and account.members) or {}) do
        local member = account.members[i]
        local isOwner = clean(member.role) == 'owner'
        items[#items + 1] = {
            id = clean(member.citizenid),
            citizenid = clean(member.citizenid),
            label = clean(member.memberName or member.citizenid),
            icon = clean(member.role):sub(1, 2):upper(),
            category = 'members',
            value = clean(member.role),
            badge = isOwner and 'Owner' or 'Managed Member',
            description = ('Deposit %s · Withdraw %s · Transfer %s · Manage %s'):format(
                yesNo(member.canDeposit),
                yesNo(member.canWithdraw),
                yesNo(member.canTransfer),
                yesNo(member.canManage)
            ),
            stats = {
                { label = 'Role', value = clean(member.role) },
                { label = 'Citizen ID', value = clean(member.citizenid) },
                { label = 'Can Withdraw', value = yesNo(member.canWithdraw) },
                { label = 'Can Manage', value = yesNo(member.canManage) },
            },
            actions = isOwner and {
                { id = 'member_owner', label = 'Account Owner', style = 'secondary' },
            } or {
                { id = 'remove_shared_member', label = 'Remove Member', style = 'primary' },
            },
        }
    end
    return items
end

local function buildPayload(moduleId, screenId)
    local data = currentData or {}
    local account = data.sharedAccount
    local personalRows = transactionRows(data.history, false)
    local sharedRows = transactionRows(account and account.history or {}, true)
    local sharedAccounts = sharedAccountItems(data)
    local currencyItems = currencyVaultItems(data)
    local members = memberItems(account)

    return {
        id = 'node7-banking',
        title = activeBank and activeBank.name or 'NODE7 FRONTIER BANK',
        subtitle = ('%s · Account %s'):format(clean(data.characterName), clean(data.accountNumber)),
        cursor = true,
        statusLeft = { label = 'Personal Bank', value = money(data.bank) },
        statusRight = { label = 'Carried Cash', value = money(data.cash) },
        controls = {
            { key = 'Q / E', label = 'Banking Section' },
            { key = '← / →', label = 'Page' },
            { key = '↑ / ↓', label = 'Select' },
            { key = 'ENTER', label = 'Use' },
            { key = 'ESC', label = 'Close' },
        },
        startModule = moduleId or currentModule,
        startScreen = screenId or currentScreen,
        modules = {
            {
                id = 'personal', label = 'Personal Banking', screens = {
                    {
                        id = 'overview', label = 'Account Overview', title = 'Personal Account',
                        description = 'Review balances and your registered frontier account information.',
                        view = 'dashboard', categories = { { id = 'all', label = 'Overview' } },
                        metrics = {
                            { id = 'bank_balance', label = 'Bank Balance', value = money(data.bank), progress = 78, badge = 'Personal Bank', description = 'Funds secured in your personal bank account.', actions = { { id = 'personal_withdraw', label = 'Withdraw', style = 'primary' } } },
                            { id = 'cash_balance', label = 'Carried Cash', value = money(data.cash), progress = 52, badge = 'On Hand', description = 'Cash currently carried by your character.', actions = { { id = 'personal_deposit', label = 'Deposit', style = 'primary' } } },
                            { id = 'gold_balance', label = 'Gold', value = money(data.gold), progress = 34, badge = 'Reserve', description = 'Current personal gold balance.', actions = { { id = 'refresh_bank', label = 'Refresh', style = 'primary' } } },
                            { id = 'account_number', label = 'Account Number', value = clean(data.accountNumber), progress = 100, badge = 'Identity', description = 'Use this number when another player sends you a transfer.', actions = { { id = 'view_account_number', label = 'View Number', style = 'primary' } } },
                        },
                    },
                    {
                        id = 'services', label = 'Bank Services', title = 'Personal Services',
                        description = 'Deposit, withdraw, transfer, or refresh your personal account.',
                        view = 'grid', categories = { { id = 'all', label = 'All Services' } }, items = personalServiceItems(data),
                    },
                    {
                        id = 'ledger', label = 'Personal Ledger', title = 'Transaction History',
                        description = 'Recent personal account credits, debits, withdrawals, deposits, and transfers.',
                        view = 'table', categories = { { id = 'all', label = 'All Entries' } },
                        table = { columns = {
                            { key = 'entry', label = 'Description' }, { key = 'category', label = 'Type' },
                            { key = 'status', label = 'Direction' }, { key = 'value', label = 'Amount' },
                        }, rows = personalRows },
                    },
                    {
                        id = 'identity', label = 'Account Identity', title = 'Registered Account',
                        description = 'Personal identifiers and configured transaction limits.',
                        view = 'list', categories = { { id = 'all', label = 'Account Details' } }, items = {
                            { id = 'holder', label = 'Account Holder', value = clean(data.characterName), badge = 'Character', description = clean(data.citizenid), actions = { { id = 'view_account_number', label = 'Inspect', style = 'primary' } } },
                            { id = 'number', label = 'Account Number', value = clean(data.accountNumber), badge = 'Transfer Number', description = 'Other players use this number for personal transfers.', actions = { { id = 'view_account_number', label = 'Inspect', style = 'primary' } } },
                            { id = 'deposit_limit', label = 'Maximum Deposit', value = money(data.limits and data.limits.deposit), badge = 'Limit', description = 'Maximum amount accepted in one deposit.', actions = { { id = 'personal_deposit', label = 'Deposit', style = 'primary' } } },
                            { id = 'transfer_limit', label = 'Maximum Transfer', value = money(data.limits and data.limits.transfer), badge = 'Limit', description = 'Maximum amount sent in one personal transfer.', actions = { { id = 'personal_transfer', label = 'Transfer', style = 'primary' } } },
                        },
                    },
                },
            },
            {
                id = 'currencies', label = 'Currency Vault', screens = {
                    {
                        id = 'vault', label = 'Currency Vault', title = 'Deposited Currencies',
                        description = 'Deposit or withdraw physical cash, gold, tokens, vouchers, Outlaw Marks, Company Scrip, and other supported NODE7 currencies.',
                        view = 'grid', categories = { { id = 'all', label = 'All Currencies' } }, items = currencyItems,
                    },
                    {
                        id = 'currency_ledger', label = 'Currency Ledger', title = 'Currency Transactions',
                        description = 'Personal ledger entries include the currency used for each deposit or withdrawal.',
                        view = 'table', categories = { { id = 'all', label = 'All Entries' } },
                        table = { columns = {
                            { key = 'entry', label = 'Description' }, { key = 'category', label = 'Type' },
                            { key = 'status', label = 'Direction' }, { key = 'value', label = 'Amount' },
                        }, rows = personalRows },
                    },
                },
            },
            {
                id = 'shared', label = 'Shared Banking', screens = {
                    {
                        id = 'accounts', label = 'Shared Accounts', title = 'Accessible Accounts',
                        description = 'Open a society, gang, or private shared account available to your character.',
                        view = 'grid', categories = { { id = 'all', label = 'All Accounts' } }, items = sharedAccounts,
                    },
                    {
                        id = 'shared_overview', label = 'Shared Overview', title = account and clean(account.label) or 'No Shared Account Selected',
                        description = account and ('Account %s · Role %s'):format(clean(account.accountNumber), clean(account.role)) or 'Select an account from the Shared Accounts page.',
                        view = 'dashboard', categories = { { id = 'all', label = 'Overview' } }, metrics = account and {
                            { id = 'shared_balance', label = 'Shared Balance', value = money(account.balance), progress = 82, badge = account.frozen and 'Frozen' or 'Active', description = 'Current funds held in the selected shared account.', actions = { { id = 'go_shared_services', label = 'Manage Funds', style = 'primary' } } },
                            { id = 'shared_number', label = 'Account Number', value = clean(account.accountNumber), progress = 100, badge = clean(account.type), description = 'Use this account number for incoming shared transfers.', actions = { { id = 'view_shared_number', label = 'View Account', style = 'primary' } } },
                            { id = 'shared_role', label = 'Your Role', value = clean(account.role), progress = 65, badge = 'Permissions', description = 'Your current role for the selected account.', actions = { { id = 'go_shared_services', label = 'View Services', style = 'primary' } } },
                            { id = 'shared_members', label = 'Managed Members', value = tostring(#(account.members or {})), progress = 45, badge = 'Access', description = 'Members visible to account managers.', actions = { { id = 'go_shared_members', label = 'View Members', style = 'primary' } } },
                        } or {
                            { id = 'none', label = 'Shared Account', value = 'Not Selected', progress = 0, badge = 'Required', description = 'Choose an accessible account first.', actions = { { id = 'go_shared_accounts', label = 'Browse Accounts', style = 'primary' } } },
                        },
                    },
                    {
                        id = 'shared_services', label = 'Shared Services', title = account and ('Services · ' .. clean(account.label)) or 'Shared Services',
                        description = 'Available actions are based on your account role and the account state.',
                        view = 'grid', categories = { { id = 'all', label = 'Available Actions' } }, items = sharedServiceItems(account),
                    },
                    {
                        id = 'shared_ledger', label = 'Shared Ledger', title = account and ('Ledger · ' .. clean(account.label)) or 'Shared Ledger',
                        description = 'Recent activity for the selected shared account.',
                        view = 'table', categories = { { id = 'all', label = 'All Entries' } },
                        table = { columns = {
                            { key = 'entry', label = 'Description' }, { key = 'category', label = 'Type' },
                            { key = 'status', label = 'Direction' }, { key = 'value', label = 'Amount' },
                        }, rows = sharedRows },
                    },
                },
            },
            {
                id = 'management', label = 'Account Management', screens = {
                    {
                        id = 'members', label = 'Members', title = account and ('Members · ' .. clean(account.label)) or 'Shared Members',
                        description = 'Owners and managers can review or remove members from private shared accounts.',
                        view = 'grid', categories = { { id = 'all', label = 'All Members' } }, items = members,
                    },
                    {
                        id = 'management_actions', label = 'Management Actions', title = 'Shared Account Administration',
                        description = 'Create accounts, add members, rename accounts, and refresh access data.',
                        view = 'grid', categories = { { id = 'all', label = 'Management' } }, items = {
                            { id = 'create_account', label = 'Create Shared Account', icon = '+', value = money(data.sharedCreation and data.sharedCreation.fee), badge = data.sharedCreation and data.sharedCreation.enabled and 'Available' or 'Disabled', description = 'Open a private account shared with invited members.', actions = { { id = data.sharedCreation and data.sharedCreation.enabled and 'create_shared' or 'creation_disabled', label = data.sharedCreation and data.sharedCreation.enabled and 'Create Account' or 'Creation Disabled', style = 'primary' } } },
                            { id = 'add_member', label = 'Add or Update Member', icon = 'M+', value = account and clean(account.label) or 'Select Account', badge = 'Private Shared Accounts', description = 'Assign manager, member, or viewer access.', actions = { { id = 'add_shared_member', label = 'Manage Member', style = 'primary' } } },
                            { id = 'rename_account', label = 'Rename Selected Account', icon = 'RN', value = account and clean(account.label) or 'Select Account', badge = 'Management', description = 'Update the public account label.', actions = { { id = 'rename_shared', label = 'Rename', style = 'primary' } } },
                            { id = 'refresh_access', label = 'Refresh Banking Access', icon = 'R', value = tostring(#(data.sharedAccounts or {})), badge = 'Accessible Accounts', description = 'Reload account access, balances, history, and members.', actions = { { id = 'refresh_bank', label = 'Refresh', style = 'primary' } } },
                        },
                    },
                },
            },
        },
    }
end

local function renderBank(moduleId, screenId, freshOpen)
    if not bankOpen or not currentData or not uiStarted() then return end
    currentModule = moduleId or currentModule
    currentScreen = screenId or currentScreen
    local payload = buildPayload(currentModule, currentScreen)
    if freshOpen or not exports[UI_RESOURCE]:IsOpen() then
        exports[UI_RESOURCE]:Open(payload)
    else
        exports[UI_RESOURCE]:Update(payload)
    end
end

local function applyResponse(response, successModule, successScreen)
    actionBusy = false
    if not response then
        notify(locale('transaction_failed'), 'error')
        return false
    end
    if response.message then
        notify(response.message, response.success and 'success' or 'error')
    end
    if response.data then
        currentData = response.data
        if response.data.sharedAccount then
            selectedShared = clean(response.data.sharedAccount.name)
        end
    end
    renderBank(successModule or currentModule, successScreen or currentScreen, false)
    return response.success == true
end

local function awaitCallback(name, ...)
    if actionBusy then
        notify('A banking request is already being processed.', 'warning')
        return nil
    end
    actionBusy = true
    return lib.callback.await(name, false, ...)
end

local function showDepositModal()
    exports[UI_RESOURCE]:ShowModal({
        id = 'personal_deposit', badge = 'Personal Banking', title = 'Deposit Cash',
        message = ('Cash available: %s. Funds will be moved into your bank account.'):format(money(currentData.cash)),
        fields = {
            { id = 'amount', label = 'Deposit Amount', type = 'number', min = Config.MinimumAmount, max = Config.MaximumDeposit, step = 0.01, required = true, placeholder = '0.00' },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_deposit', label = 'Deposit Funds', style = 'primary' } },
    })
end

local function showWithdrawModal()
    exports[UI_RESOURCE]:ShowModal({
        id = 'personal_withdraw', badge = 'Personal Banking', title = 'Withdraw Cash',
        message = ('Bank available: %s. Withdrawal fee: %.2f%%.'):format(money(currentData.bank), tonumber(currentData.limits and currentData.limits.withdrawFeePercent) or 0),
        fields = {
            { id = 'amount', label = 'Withdrawal Amount', type = 'number', min = Config.MinimumAmount, max = Config.MaximumWithdrawal, step = 0.01, required = true, placeholder = '0.00' },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_withdraw', label = 'Withdraw Funds', style = 'primary' } },
    })
end

local function showCurrencyModal(entry, mode)
    if type(entry) ~= 'table' then return end
    local key = clean(entry.currencyKey):lower()
    local currency
    for i = 1, #((currentData and currentData.currencies) or {}) do
        if clean(currentData.currencies[i].key):lower() == key then
            currency = currentData.currencies[i]
            break
        end
    end
    if not currency then
        notify('That currency is not available.', 'error')
        return
    end

    activeCurrencyKey = key
    local decimals = tonumber(currency.decimals) or 0
    local step = decimals == 0 and 1 or 0.01
    local depositing = mode == 'deposit'
    local available = depositing and currency.onHand or currency.banked
    exports[UI_RESOURCE]:ShowModal({
        id = depositing and 'currency_deposit' or 'currency_withdraw',
        badge = clean(currency.label),
        title = (depositing and 'Deposit ' or 'Withdraw ') .. clean(currency.label),
        message = ('On hand: %s · Deposited: %s.%s'):format(
            currencyValue(key, currency.onHand, decimals),
            currencyValue(key, currency.banked, decimals),
            key == 'cash' and ' Physical bills and coins are handled automatically by node7-cashitem.' or ''
        ),
        fields = {
            {
                id = 'amount',
                label = depositing and 'Deposit Amount' or 'Withdrawal Amount',
                type = 'number',
                min = decimals == 0 and 1 or Config.MinimumAmount,
                max = depositing and Config.MaximumDeposit or Config.MaximumWithdrawal,
                step = step,
                required = true,
                placeholder = decimals == 0 and '1' or '0.00',
            },
        },
        summary = {
            title = clean(currency.label),
            rows = {
                { label = 'On Hand', value = currencyValue(key, currency.onHand, decimals) },
                { label = 'Deposited', value = currencyValue(key, currency.banked, decimals) },
                { label = 'Available', value = currencyValue(key, available, decimals) },
            },
        },
        actions = {
            { id = 'cancel', label = 'Cancel', validate = false },
            { id = depositing and 'confirm_currency_deposit' or 'confirm_currency_withdraw', label = depositing and 'Deposit Currency' or 'Withdraw Currency', style = 'primary' },
        },
    })
end

local function showTransferModal()
    exports[UI_RESOURCE]:ShowModal({
        id = 'personal_transfer', badge = 'Personal Banking', title = 'Wire Transfer',
        message = ('Bank available: %s. Enter the recipient account number exactly.'):format(money(currentData.bank)),
        fields = {
            { id = 'account', label = 'Recipient Account Number', type = 'text', required = true, maxLength = 64, placeholder = 'Account number' },
            { id = 'amount', label = 'Transfer Amount', type = 'number', min = Config.MinimumAmount, max = Config.MaximumTransfer, step = 0.01, required = true, placeholder = '0.00' },
            { id = 'note', label = 'Transfer Note', type = 'textarea', maxLength = 120, placeholder = 'Optional note' },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_transfer', label = 'Send Transfer', style = 'primary' } },
    })
end

local function requireShared()
    local account = currentData and currentData.sharedAccount
    if not account then
        notify('Select a shared account first.', 'warning')
        renderBank('shared', 'accounts', false)
        return nil
    end
    return account
end

local function showSharedDepositModal()
    local account = requireShared(); if not account then return end
    exports[UI_RESOURCE]:ShowModal({
        id = 'shared_deposit', badge = clean(account.label), title = 'Fund Shared Account',
        message = ('Personal bank available: %s. Shared balance: %s.'):format(money(currentData.bank), money(account.balance)),
        fields = {
            { id = 'amount', label = 'Deposit Amount', type = 'number', min = Config.MinimumAmount, max = Config.MaximumDeposit, step = 0.01, required = true, placeholder = '0.00' },
            { id = 'note', label = 'Ledger Note', type = 'textarea', maxLength = 120, placeholder = 'Optional note' },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_shared_deposit', label = 'Deposit Funds', style = 'primary' } },
    })
end

local function showSharedWithdrawModal()
    local account = requireShared(); if not account then return end
    exports[UI_RESOURCE]:ShowModal({
        id = 'shared_withdraw', badge = clean(account.label), title = 'Withdraw Shared Funds',
        message = ('Shared balance available: %s. Funds will enter your personal bank account.'):format(money(account.balance)),
        fields = {
            { id = 'amount', label = 'Withdrawal Amount', type = 'number', min = Config.MinimumAmount, max = Config.MaximumWithdrawal, step = 0.01, required = true, placeholder = '0.00' },
            { id = 'note', label = 'Ledger Note', type = 'textarea', maxLength = 120, placeholder = 'Optional note' },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_shared_withdraw', label = 'Withdraw Funds', style = 'primary' } },
    })
end

local function showSharedTransferModal()
    local account = requireShared(); if not account then return end
    exports[UI_RESOURCE]:ShowModal({
        id = 'shared_transfer', badge = clean(account.label), title = 'Shared Account Transfer',
        message = ('Shared balance available: %s. Send to a personal or shared account number.'):format(money(account.balance)),
        fields = {
            { id = 'target', label = 'Destination Account Number', type = 'text', required = true, maxLength = 64, placeholder = 'Account number' },
            { id = 'amount', label = 'Transfer Amount', type = 'number', min = Config.MinimumAmount, max = Config.SharedAccountTransferMaximum, step = 0.01, required = true, placeholder = '0.00' },
            { id = 'note', label = 'Ledger Note', type = 'textarea', maxLength = 120, placeholder = 'Optional note' },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_shared_transfer', label = 'Send Transfer', style = 'primary' } },
    })
end

local function showCreateSharedModal()
    if not currentData.sharedCreation or not currentData.sharedCreation.enabled then
        notify('Private shared-account creation is disabled.', 'error')
        return
    end
    exports[UI_RESOURCE]:ShowModal({
        id = 'create_shared', badge = 'Shared Banking', title = 'Create Shared Account',
        message = ('Creation fee: %s. Maximum owned accounts: %s.'):format(money(currentData.sharedCreation.fee), clean(currentData.sharedCreation.maximum)),
        fields = {
            { id = 'label', label = 'Account Label', type = 'text', required = true, maxLength = Config.SharedAccountLabelMaxLength, placeholder = 'Company or group name' },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_create_shared', label = 'Create Account', style = 'primary' } },
    })
end

local function showMemberModal()
    local account = requireShared(); if not account then return end
    if clean(account.type) ~= 'shared' then
        notify('Society and gang membership is managed by the framework job or gang system.', 'warning')
        return
    end
    exports[UI_RESOURCE]:ShowModal({
        id = 'add_shared_member', badge = clean(account.label), title = 'Add or Update Member',
        message = 'Use the character account number and select the access role.',
        fields = {
            { id = 'memberAccount', label = 'Character Account Number', type = 'text', required = true, maxLength = 64, placeholder = 'Account number' },
            { id = 'role', label = 'Member Role', type = 'choice', value = 'member', required = true, options = {
                { value = 'manager', label = 'Manager' }, { value = 'member', label = 'Member' }, { value = 'viewer', label = 'Viewer' },
            } },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_shared_member', label = 'Save Member', style = 'primary' } },
    })
end

local function showRenameModal()
    local account = requireShared(); if not account then return end
    exports[UI_RESOURCE]:ShowModal({
        id = 'rename_shared', badge = clean(account.label), title = 'Rename Shared Account',
        message = 'Enter the new public label for this account.',
        fields = {
            { id = 'label', label = 'New Account Label', type = 'text', value = clean(account.label), required = true, maxLength = Config.SharedAccountLabelMaxLength },
        },
        actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_rename_shared', label = 'Rename Account', style = 'primary' } },
    })
end

local function showTransaction(entry)
    exports[UI_RESOURCE]:ShowModal({
        id = 'transaction_view', badge = clean(entry.badge), title = clean(entry.label),
        message = clean(entry.description),
        fields = {},
        summary = {
            title = clean(entry.type),
            rows = {
                { label = 'Amount', value = clean(entry.value) },
                { label = 'Balance After', value = clean(entry.balance) },
                { label = 'Counterparty', value = clean(entry.counterparty ~= '' and entry.counterparty or '—') },
                { label = 'Reference', value = clean(entry.reference ~= '' and entry.reference or '—') },
            },
        },
        actions = { { id = 'cancel', label = 'Close', validate = false } },
    })
end

local function refreshAccount(moduleId, screenId)
    local response = awaitCallback('node7-banking:server:getAccount')
    if response and response.data and selectedShared then
        local shared = lib.callback.await('node7-banking:server:getSharedAccount', false, selectedShared)
        if shared and shared.success then response = shared end
    end
    applyResponse(response, moduleId or currentModule, screenId or currentScreen)
end

local function openBank()
    if bankOpen then return end
    if not uiStarted() then
        notify('node7-ui must be started before node7-banking.', 'error')
        return
    end

    local bank = nearestBank(Config.InteractionDistance + 1.0)
    if not bank then
        notify(locale('not_near_bank'), 'error')
        return
    end
    if not isBankOpen() then
        notify(locale('bank_closed'), 'error')
        return
    end

    local response = lib.callback.await('node7-banking:server:getAccount', false)
    if not response or not response.success then
        notify(response and response.message or locale('transaction_failed'), 'error')
        return
    end

    activeBank = bank
    currentData = response.data
    bankOpen = true
    selectedShared = nil
    currentModule = 'personal'
    currentScreen = 'overview'
    renderBank('personal', 'overview', true)
end

RegisterNetEvent('node7-banking:client:open', openBank)
RegisterNetEvent('node7-banking:client:refresh', function(data)
    if not bankOpen or type(data) ~= 'table' then return end
    currentData = data
    if data.sharedAccount then selectedShared = clean(data.sharedAccount.name) end
    renderBank(currentModule, currentScreen, false)
end)

RegisterCommand(Config.Command, function()
    openBank()
end, false)

AddEventHandler('node7-ui:client:closed', function()
    if bankOpen then releaseBank() end
end)

AddEventHandler('node7-ui:client:action', function(data)
    if not bankOpen or type(data) ~= 'table' or clean(data.payloadId) ~= 'node7-banking' then return end
    local actionId = clean(data.actionId)
    local entry = type(data.entry) == 'table' and data.entry or {}
    local fields = type(data.fields) == 'table' and data.fields or {}

    if actionId == 'personal_deposit' then showDepositModal()
    elseif actionId == 'personal_withdraw' then showWithdrawModal()
    elseif actionId == 'personal_transfer' then showTransferModal()
    elseif actionId == 'currency_deposit' then showCurrencyModal(entry, 'deposit')
    elseif actionId == 'currency_withdraw' then showCurrencyModal(entry, 'withdraw')
    elseif actionId == 'refresh_bank' then refreshAccount(currentModule, currentScreen)
    elseif actionId == 'view_account_number' then
        exports[UI_RESOURCE]:ShowModal({ id = 'account_number', badge = 'Personal Account', title = 'Account Number', message = clean(currentData.accountNumber), actions = { { id = 'cancel', label = 'Close', validate = false } } })
    elseif actionId == 'open_shared' then
        local response = awaitCallback('node7-banking:server:getSharedAccount', entry.accountName or entry.id)
        if response and response.success then selectedShared = clean(entry.accountName or entry.id) end
        applyResponse(response, 'shared', 'shared_overview')
    elseif actionId == 'go_shared_accounts' then renderBank('shared', 'accounts', false)
    elseif actionId == 'go_shared_services' then renderBank('shared', 'shared_services', false)
    elseif actionId == 'go_shared_members' then renderBank('management', 'members', false)
    elseif actionId == 'view_shared_number' then
        local account = requireShared()
        if account then exports[UI_RESOURCE]:ShowModal({ id = 'shared_number', badge = clean(account.label), title = 'Shared Account Number', message = clean(account.accountNumber), actions = { { id = 'cancel', label = 'Close', validate = false } } }) end
    elseif actionId == 'shared_deposit' then showSharedDepositModal()
    elseif actionId == 'shared_withdraw' then showSharedWithdrawModal()
    elseif actionId == 'shared_transfer' then showSharedTransferModal()
    elseif actionId == 'shared_frozen' then notify('This shared account is frozen.', 'warning')
    elseif actionId == 'create_shared' then showCreateSharedModal()
    elseif actionId == 'creation_disabled' then notify('Private shared-account creation is disabled.', 'error')
    elseif actionId == 'add_shared_member' then showMemberModal()
    elseif actionId == 'rename_shared' then showRenameModal()
    elseif actionId == 'remove_shared_member' then
        local account = requireShared(); if not account then return end
        exports[UI_RESOURCE]:ShowModal({
            id = 'remove_shared_member', badge = clean(account.label), title = 'Remove Shared Member',
            message = ('Remove %s from this shared account?'):format(clean(entry.label)), entry = entry,
            actions = { { id = 'cancel', label = 'Cancel', validate = false }, { id = 'confirm_remove_shared_member', label = 'Remove Member', style = 'primary' } },
        })
    elseif actionId == 'member_owner' then notify('The account owner cannot be removed.', 'warning')
    elseif actionId == 'view_transaction' then showTransaction(entry)
    elseif actionId == 'confirm_deposit' then
        applyResponse(awaitCallback('node7-banking:server:deposit', fields.amount), 'personal', 'overview')
    elseif actionId == 'confirm_withdraw' then
        applyResponse(awaitCallback('node7-banking:server:withdraw', fields.amount), 'personal', 'overview')
    elseif actionId == 'confirm_currency_deposit' then
        applyResponse(awaitCallback('node7-banking:server:depositCurrency', activeCurrencyKey, fields.amount), 'currencies', 'vault')
    elseif actionId == 'confirm_currency_withdraw' then
        applyResponse(awaitCallback('node7-banking:server:withdrawCurrency', activeCurrencyKey, fields.amount), 'currencies', 'vault')
    elseif actionId == 'confirm_transfer' then
        applyResponse(awaitCallback('node7-banking:server:transfer', fields.account, fields.amount, fields.note), 'personal', 'ledger')
    elseif actionId == 'confirm_shared_deposit' then
        local account = requireShared(); if account then applyResponse(awaitCallback('node7-banking:server:sharedDeposit', account.name, fields.amount, fields.note), 'shared', 'shared_overview') end
    elseif actionId == 'confirm_shared_withdraw' then
        local account = requireShared(); if account then applyResponse(awaitCallback('node7-banking:server:sharedWithdraw', account.name, fields.amount, fields.note), 'shared', 'shared_overview') end
    elseif actionId == 'confirm_shared_transfer' then
        local account = requireShared(); if account then applyResponse(awaitCallback('node7-banking:server:sharedTransfer', account.name, fields.target, fields.amount, fields.note), 'shared', 'shared_ledger') end
    elseif actionId == 'confirm_create_shared' then
        local response = awaitCallback('node7-banking:server:createSharedAccount', fields.label)
        if response and response.data and response.data.sharedAccount then selectedShared = clean(response.data.sharedAccount.name) end
        applyResponse(response, 'shared', 'shared_overview')
    elseif actionId == 'confirm_shared_member' then
        local account = requireShared(); if account then applyResponse(awaitCallback('node7-banking:server:setSharedMember', account.name, fields.memberAccount, fields.role), 'management', 'members') end
    elseif actionId == 'confirm_rename_shared' then
        local account = requireShared(); if account then applyResponse(awaitCallback('node7-banking:server:renameSharedAccount', account.name, fields.label), 'shared', 'shared_overview') end
    elseif actionId == 'confirm_remove_shared_member' then
        local account = requireShared()
        local modalEntry = type(data.entry) == 'table' and data.entry or entry
        if account then applyResponse(awaitCallback('node7-banking:server:removeSharedMember', account.name, modalEntry.citizenid), 'management', 'members') end
    end
end)

CreateThread(function()
    Wait(1000)
    local promptKey = (Node7Core.Shared.Keybinds and Node7Core.Shared.Keybinds[Config.Keybind]) or 0xCEFD9220
    for i = 1, #Config.BankLocations do
        local bank = Config.BankLocations[i]
        exports['node7-core']:createPrompt(
            ('node7_bank_%s'):format(bank.id),
            bank.coords,
            promptKey,
            Config.PromptText,
            {
                type = 'client',
                event = 'node7-banking:client:open',
            }
        )

        if Config.ShowBlips and bank.showblip ~= false then
            local blip = BlipAddForCoords(1664425300, bank.coords)
            SetBlipSprite(blip, joaat(Config.BlipSprite), true)
            SetBlipScale(blip, Config.BlipScale)
            SetBlipName(blip, bank.name)
            spawnedBlips[#spawnedBlips + 1] = blip
        end
    end
end)

local function spawnBanker(bank)
    local model = joaat(bank.npcmodel)
    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(50) end
    if not HasModelLoaded(model) then
        print(('[node7-banking] Failed to load banker model at %s'):format(bank.name))
        return nil
    end

    local c = bank.npccoords
    local ped = CreatePed(model, c.x, c.y, c.z - 1.0, c.w, false, false, 0, 0)
    if not DoesEntityExist(ped) then return nil end

    if Config.FadePeds then SetEntityAlpha(ped, 0, false) end
    SetRandomOutfitVariation(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanBeTargetted(ped, false)

    if Config.FadePeds then
        CreateThread(function()
            for alpha = 0, 255, 51 do
                if not DoesEntityExist(ped) then break end
                SetEntityAlpha(ped, alpha, false)
                Wait(40)
            end
        end)
    end
    SetModelAsNoLongerNeeded(model)
    return ped
end

if Config.SpawnBankers then
    CreateThread(function()
        while true do
            local waitTime = 1000
            local playerCoords = GetEntityCoords(cache.ped or PlayerPedId())
            for i = 1, #Config.BankLocations do
                local bank = Config.BankLocations[i]
                local distance = #(playerCoords - bank.npccoords.xyz)
                if distance < Config.PedSpawnDistance and not spawnedPeds[i] then
                    spawnedPeds[i] = spawnBanker(bank)
                elseif distance >= Config.PedSpawnDistance and spawnedPeds[i] then
                    DeletePed(spawnedPeds[i])
                    spawnedPeds[i] = nil
                end
                if distance < 10.0 then waitTime = 250 end
            end
            Wait(waitTime)
        end
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    closeBank()
    for _, ped in pairs(spawnedPeds) do
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    for i = 1, #spawnedBlips do
        RemoveBlip(spawnedBlips[i])
    end
    for i = 1, #Config.BankLocations do
        exports['node7-core']:deletePrompt(('node7_bank_%s'):format(Config.BankLocations[i].id))
    end
end)
