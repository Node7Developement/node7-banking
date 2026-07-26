local Node7Core = exports['node7-core']:GetCoreObject()
lib.locale()
local bankOpen = false
local spawnedPeds = {}
local spawnedBlips = {}

local function notify(description, notificationType, title)
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

local function closeBank()
    if not bankOpen then return end
    bankOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openBank()
    if bankOpen then return end
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

    bankOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        bankName = bank.name,
        data = response.data,
    })
end

RegisterNetEvent('node7-banking:client:open', openBank)
RegisterNetEvent('node7-banking:client:refresh', function(data)
    if bankOpen then
        SendNUIMessage({ action = 'refresh', data = data })
    end
end)

RegisterCommand(Config.Command, function()
    openBank()
end, false)

RegisterNUICallback('close', function(_, cb)
    closeBank()
    cb({ success = true })
end)

RegisterNUICallback('deposit', function(data, cb)
    local result = lib.callback.await('node7-banking:server:deposit', false, data.amount)
    if result and result.message then notify(result.message, result.success and 'success' or 'error') end
    cb(result or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('withdraw', function(data, cb)
    local result = lib.callback.await('node7-banking:server:withdraw', false, data.amount)
    if result and result.message then notify(result.message, result.success and 'success' or 'error') end
    cb(result or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('transfer', function(data, cb)
    local result = lib.callback.await('node7-banking:server:transfer', false, data.account, data.amount, data.note)
    if result and result.message then notify(result.message, result.success and 'success' or 'error') end
    cb(result or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('refresh', function(_, cb)
    local result = lib.callback.await('node7-banking:server:getAccount', false)
    cb(result or { success = false })
end)


RegisterNUICallback('sharedAccount', function(data, cb)
    local response = lib.callback.await('node7-banking:server:getSharedAccount', false, data.account)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('createSharedAccount', function(data, cb)
    local response = lib.callback.await('node7-banking:server:createSharedAccount', false, data.label)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('sharedDeposit', function(data, cb)
    local response = lib.callback.await('node7-banking:server:sharedDeposit', false, data.account, data.amount, data.note)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('sharedWithdraw', function(data, cb)
    local response = lib.callback.await('node7-banking:server:sharedWithdraw', false, data.account, data.amount, data.note)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('sharedTransfer', function(data, cb)
    local response = lib.callback.await('node7-banking:server:sharedTransfer', false, data.account, data.target, data.amount, data.note)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('setSharedMember', function(data, cb)
    local response = lib.callback.await('node7-banking:server:setSharedMember', false, data.account, data.memberAccount, data.role)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('removeSharedMember', function(data, cb)
    local response = lib.callback.await('node7-banking:server:removeSharedMember', false, data.account, data.citizenid)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
end)

RegisterNUICallback('renameSharedAccount', function(data, cb)
    local response = lib.callback.await('node7-banking:server:renameSharedAccount', false, data.account, data.label)
    if response and response.message then notify(response.message, response.success and 'success' or 'error') end
    cb(response or { success = false, message = locale('transaction_failed') })
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
