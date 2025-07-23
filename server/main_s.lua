local RSGCore = exports['rsg-core']:GetCoreObject()
local Database = require 'server/database' -- Esta linha deve ser uma das primeiras

local props = {}
local ChestUsers = {}
local LockpickCooldowns = {}
local TemporaryAccess = {}

-- =================================================================
-- FUNÇÕES AUXILIARES
-- =================================================================

--- Verifica se um jogador tem permissão para acessar um baú (dono, compartilhado ou acesso temporário).
--- @param chestUUID string O UUID do baú.
--- @param playerId number O source ID do jogador.
--- @return boolean
function HasPermission(chestUUID, playerId)
    local prop = props[chestUUID]
    if not prop then return false end

    local Player = RSGCore.Functions.GetPlayer(playerId)
    if not Player or not Player.PlayerData or not Player.PlayerData.citizenid then return false end
    
    local playerCitizenId = Player.PlayerData.citizenid

    -- 1. Verifica se é o dono
    if prop.owner == playerCitizenId then return true end

    -- 2. Verifica se tem acesso compartilhado
    if prop.shared_with then
        for _, sharedData in ipairs(prop.shared_with) do
            if type(sharedData) == 'table' and sharedData.citizenid == playerCitizenId then
                return true
            end
        end
    end

    -- 3. Verifica se tem acesso temporário por arrombamento
    local tempAccess = TemporaryAccess[chestUUID]
    if tempAccess and tempAccess.citizenId == playerCitizenId and os.time() < tempAccess.expires then
        return true
    end

    return false
end

--- Busca o nome completo do dono de um baú.
--- @param citizenid string O citizenid do dono.
--- @return string
function GetChestOwnerName(citizenid)
    local player = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if player and player.PlayerData.charinfo then
        return ("%s %s"):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)
    end
    
    local result = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { citizenid })
    if result and result.charinfo then
        local charinfo = json.decode(result.charinfo)
        if charinfo and charinfo.firstname and charinfo.lastname then
            return ("%s %s"):format(charinfo.firstname, charinfo.lastname)
        end
    end
    
    return Config.Lang['unknown_owner'] or 'Dono Desconhecido'
end

-- =================================================================
-- FUNCIONALIDADE PRINCIPAL (ITEM USÁVEL)
-- =================================================================
RSGCore.Functions.CreateUseableItem(Config.ChestItem, function(source, item)
    TriggerClientEvent('rsg-chest:client:startPlacement', source)
end)

-- =================================================================
-- HANDLERS DE EVENTOS DE REDE
-- =================================================================

RegisterNetEvent('rsg-chest:server:placeChest', function(coords, heading)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = 'Seus dados de jogador não foram carregados.' })
    end
    local citizenId = Player.PlayerData.citizenid
    local chestUUID = Database.CreateChest(citizenId, coords, heading, Config.ChestProp)
    if chestUUID then
        if exports['rsg-inventory']:RemoveItem(src, Config.ChestItem, 1) then
            local initialTier = Config.Tiers[1]
            props[chestUUID] = {
                chest_uuid = chestUUID, owner = citizenId, coords = coords, heading = heading, model = Config.ChestProp, 
                shared_with = {}, tier = 1, max_weight = initialTier.weight, max_slots = initialTier.slots 
            }
            exports['rsg-inventory']:CreateInventory('rsg_chest_' .. chestUUID, {
                label = initialTier.label, maxweight = initialTier.weight, slots = initialTier.slots
            })
            TriggerClientEvent('chest:createProp', -1, chestUUID, props[chestUUID])
            TriggerClientEvent('ox_lib:notify', src, { type = 'success', title = 'Sucesso', description = Config.Lang['chest_placed'] })
        else
            Database.DeleteChest(chestUUID)
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = Config.Lang['item_not_found'] })
        end
    else
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro de Servidor', description = "Falha ao registrar o baú no banco de dados." })
    end
end)

-- Em server/main_s.lua

RegisterNetEvent('jx:chest:open', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not chestUUID or not props[chestUUID] then return end

    local hasTempAccess = TemporaryAccess[chestUUID] and TemporaryAccess[chestUUID].citizenId == Player.PlayerData.citizenid
    if hasTempAccess and os.time() > TemporaryAccess[chestUUID].expires then
        hasTempAccess = false
        TemporaryAccess[chestUUID] = nil
    end

    if not HasPermission(chestUUID, src) and not hasTempAccess then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = Config.Lang['no_permission'] })
    end

    if ChestUsers[chestUUID] and ChestUsers[chestUUID] ~= src then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = Config.Lang['chest_in_use'] })
    end
    
    local chest = props[chestUUID]
    if not hasTempAccess then 
        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'OPEN', nil, ('Abriu o baú de %s'):format(chest.owner)) 
    end
    
    ChestUsers[chestUUID] = src
    local ownerName = GetChestOwnerName(chest.owner)

    local tierId = chest.tier or 1
    local tierData = Config.Tiers[tierId]

    if not tierData then
        print(('[RSG-CHEST][WARNING] Tentativa de abrir baú %s com tier inválido (%s). Usando Nível 1 como padrão.'):format(chestUUID, tostring(chest.tier)))
        tierData = Config.Tiers[1]
    end
    -- [[ FIM DA CORREÇÃO ]]

    exports['rsg-inventory']:OpenInventory(src, 'rsg_chest_' .. chestUUID, {
        label = tierData.label .. (' de %s'):format(ownerName), -- Agora é seguro acessar tierData.label
        maxweight = chest.max_weight,
        slots = chest.max_slots
    })
    
    if hasTempAccess then TemporaryAccess[chestUUID] = nil end
    TriggerClientEvent('chest:opened', src, chestUUID)
end)

RegisterNetEvent('jx:chest:closeInventory', function(chestUUID)
    local src = source
    if chestUUID and ChestUsers[chestUUID] and ChestUsers[chestUUID] == src then
        ChestUsers[chestUUID] = nil
        TriggerClientEvent('rsg-chest:client:updateChestStatus', -1, chestUUID, false)
    end
end)

RegisterNetEvent('jx:chest:remove', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData then return end
    local chest = props[chestUUID]
    if not chest then return end
    if chest.owner ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = Config.Lang['no_permission'] })
    end
    local inventory = exports['rsg-inventory']:GetInventory('rsg_chest_' .. chestUUID)
    if inventory and inventory.items and next(inventory.items) then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'warning', title = 'Aviso', description = 'Esvazie o baú antes de removê-lo.' })
    end

    Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'REMOVE', nil, 'Dono removeu o próprio baú.')
    exports['rsg-inventory']:DeleteInventory('rsg_chest_' .. chestUUID)
    Database.DeleteChest(chestUUID)
    props[chestUUID] = nil
    if exports['rsg-inventory']:AddItem(src, Config.ChestItem, 1) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'success', title = 'Sucesso', description = Config.Lang['chest_removed'] })
    else
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = 'Seu inventário está cheio.' })
    end
    TriggerClientEvent('chest:removePropClient', -1, chestUUID)
end)

RegisterNetEvent('jx:chest:getNearbyPlayerNames', function(chestUUID, nearbyPlayerIds)
    local src = source
    local playersWithNames = {}
    if nearbyPlayerIds and #nearbyPlayerIds > 0 then
        for _, targetId in ipairs(nearbyPlayerIds) do
            local TargetPlayer = RSGCore.Functions.GetPlayer(targetId)
            if TargetPlayer and TargetPlayer.PlayerData.charinfo then
                table.insert(playersWithNames, {
                    label = ('%s %s'):format(TargetPlayer.PlayerData.charinfo.firstname, TargetPlayer.PlayerData.charinfo.lastname),
                    value = targetId
                })
            end
        end
    end
    TriggerClientEvent('jx:chest:showShareMenu', src, chestUUID, playersWithNames)
end)

RegisterNetEvent('jx:chest:share', function(chestUUID, targetPlayerId)
    local src = source
    local Player, TargetPlayer = RSGCore.Functions.GetPlayer(src), RSGCore.Functions.GetPlayer(targetPlayerId)
    if not Player or not TargetPlayer or not chestUUID or not props[chestUUID] then return end
    local chest = props[chestUUID]
    if chest.owner ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = Config.Lang['no_permission'] })
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(targetPlayerId))) > (Config.ShareDistance or 5.0) + 2.0 then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = 'O jogador alvo se moveu para muito longe.' })
    end
    local sharedWith = chest.shared_with or {}
    for _, data in ipairs(sharedWith) do
        if data.citizenid == TargetPlayer.PlayerData.citizenid then
            return TriggerClientEvent('ox_lib:notify', src, { type = 'warning', title = 'Aviso', description = 'Este jogador já tem acesso.' })
        end
    end
    if #sharedWith >= (Config.MaxSharedPlayers or 5) then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'warning', title = 'Aviso', description = 'Limite de compartilhamentos atingido.' })
    end
    local targetName = ('%s %s'):format(TargetPlayer.PlayerData.charinfo.firstname, TargetPlayer.PlayerData.charinfo.lastname)
    Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'SHARE', TargetPlayer.PlayerData.citizenid, ('Compartilhou com: %s'):format(targetName))
    table.insert(sharedWith, { citizenid = TargetPlayer.PlayerData.citizenid, name = targetName })
    Database.ShareChest(chestUUID, sharedWith)
    props[chestUUID].shared_with = sharedWith
    TriggerClientEvent('jx:chest:updateSharedList', -1, chestUUID, sharedWith)
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', title = 'Sucesso', description = ('Baú compartilhado com %s.'):format(targetName) })
    TriggerClientEvent('ox_lib:notify', targetPlayerId, { type = 'inform', title = 'Baú Compartilhado', description = ('%s compartilhou um baú com você.'):format(Player.PlayerData.charinfo.firstname) })
end)

RegisterNetEvent('jx:chest:unshare', function(chestUUID, targetCitizenId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not chestUUID or not props[chestUUID] then return end
    local chest = props[chestUUID]
    if chest.owner ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = Config.Lang['no_permission'] })
    end
    local sharedWith = chest.shared_with or {}
    local newSharedList, playerRemoved, removedPlayerName = {}, false, ''
    for _, data in ipairs(sharedWith) do
        if data.citizenid == targetCitizenId then playerRemoved, removedPlayerName = true, data.name else table.insert(newSharedList, data) end
    end
    if playerRemoved then
        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'UNSHARE', targetCitizenId, ('Removeu acesso de: %s'):format(removedPlayerName))
        Database.ShareChest(chestUUID, newSharedList)
        props[chestUUID].shared_with = newSharedList
        TriggerClientEvent('jx:chest:updateSharedList', -1, chestUUID, newSharedList)
        TriggerClientEvent('ox_lib:notify', src, { type = 'success', title = 'Sucesso', description = ('Acesso de %s removido.'):format(removedPlayerName) })
        local TargetPlayer = RSGCore.Functions.GetPlayerByCitizenId(targetCitizenId)
        if TargetPlayer then
            TriggerClientEvent('ox_lib:notify', TargetPlayer.PlayerData.source, { type = 'inform', title = 'Acesso Removido', description = 'Seu acesso a um baú foi revogado.' })
        end
    end
end)

RegisterNetEvent('jx:chest:upgrade', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not chestUUID or not props[chestUUID] then return end
    local chest = props[chestUUID]
    if chest.owner ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = Config.Lang['no_permission'] })
    end
    local currentTier = chest.tier or 1
    local nextTier = currentTier + 1
    if not Config.Tiers[nextTier] then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'inform', title = 'Aviso', description = Config.Lang['max_tier_reached'] })
    end
    if exports['rsg-inventory']:RemoveItem(src, Config.UpgradeItem, 1) then
        local newTierData = Config.Tiers[nextTier]
        MySQL.update.await('UPDATE player_chests SET tier = ?, max_weight = ?, max_slots = ? WHERE chest_uuid = ?', { nextTier, newTierData.weight, newTierData.slots, chestUUID })
        props[chestUUID].tier, props[chestUUID].max_weight, props[chestUUID].max_slots = nextTier, newTierData.weight, newTierData.slots
        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'UPGRADE', nil, ('Melhorou para o Nível %d'):format(nextTier))
        TriggerClientEvent('ox_lib:notify', src, { type = 'success', title = 'Sucesso', description = Config.Lang['chest_upgraded'] })
        TriggerClientEvent('jx:chest:updateSharedList', -1, chestUUID, props[chestUUID].shared_with)
    else
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = ('Você não possui um %s.'):format(Config.UpgradeItem) })
    end
end)

RegisterNetEvent('jx:chest:requestLockpick', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not chestUUID then return end
    if LockpickCooldowns[Player.PlayerData.citizenid] and os.time() < LockpickCooldowns[Player.PlayerData.citizenid] then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Aguarde', description = Config.Lang['lockpick_cooldown'] })
    end
    if exports['rsg-inventory']:RemoveItem(src, Config.LockpickItem, 1) then
        
        TriggerClientEvent('jx:chest:startSkillCheck', src, chestUUID)
    else
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Erro', description = ('Você não possui um %s.'):format(Config.LockpickItem) })
    end
end)

-- Em server/main_s.lua

-- Em server/main_s.lua

RegisterNetEvent('jx:chest:resolveLockpick', function(chestUUID, success)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not chestUUID or not props[chestUUID] then return end

    local chest = props[chestUUID]
    success = true
    if success then
        -- Conseguiu arrombar
        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'LOCKPICK_SUCCESS', chest.owner)
        TemporaryAccess[chestUUID] = { citizenId = Player.PlayerData.citizenid, expires = os.time() + 120 }
       -- TriggerClientEvent('ox_lib:notify', src, { type = 'success', title = 'Sucesso', description = Config.Lang['lockpick_success'] })

        -- Alerta a polícia
        if Config.LockpickSettings.PoliceAlert then
            local alertData = { title = "Arrombamento de Baú", coords = chest.coords, description = "Um baú foi arrombado.", sprite = 516, color = 1, scale = 1.2, duration = 3000 }
            TriggerClientEvent('rsg-dispatch:client:CreateAlert', -1, alertData, { 'police' })
        end

        -- [[ INÍCIO DA CORREÇÃO ]]
        -- Adicionada a lógica robusta para obter os dados do tier, prevenindo erros.
        local tierId = chest.tier or 1
        local tierData = Config.Tiers[tierId]

        if not tierData then
            print(('[RSG-CHEST][WARNING] Lockpick em baú %s com tier inválido (%s). Usando Nível 1 como padrão.'):format(chestUUID, tostring(chest.tier)))
            tierData = Config.Tiers[1]
        end
        -- [[ FIM DA CORREÇÃO ]]

        local ownerName = GetChestOwnerName(chest.owner)
        exports['rsg-inventory']:OpenInventory(src, 'rsg_chest_' .. chestUUID, {
            label = tierData.label .. (' de %s'):format(ownerName),
            maxweight = chest.max_weight,
            slots = chest.max_slots
        })

        ChestUsers[chestUUID] = src
        TriggerClientEvent('chest:opened', src, chestUUID)
    else
        -- Falhou no arrombamento
        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'LOCKPICK_FAIL', chest.owner)
        LockpickCooldowns[Player.PlayerData.citizenid] = os.time() + Config.LockpickSettings.Cooldown
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Falha', description = Config.Lang['lockpick_failed'] })
    end
end)

RegisterNetEvent('chest:requestAllProps', function() TriggerClientEvent('chest:updateProps', source, props) end)

-- =================================================================
-- THREADS E EVENTOS DO SERVIDOR
-- =================================================================

CreateThread(function()
    Wait(2000)
    local allChests = Database.GetAllChests()
    if allChests then
        for _, chest in ipairs(allChests) do
            props[chest.chest_uuid] = chest

            local tierId = chest.tier or 1
            local tierData = Config.Tiers[tierId]

   
            if not tierData then
                print(('[RSG-CHEST][WARNING] Baú %s possui um tier inválido (%s) no banco. Usando Nível 1 como padrão.'):format(chest.chest_uuid, tostring(chest.tier)))
                tierData = Config.Tiers[1]
            end

            exports['rsg-inventory']:CreateInventory('rsg_chest_' .. chest.chest_uuid, {
                label = tierData.label,
                maxweight = chest.max_weight,
                slots = chest.max_slots
            })
        end
        print(('[RSG-CHEST] %d baús carregados do banco de dados.'):format(#allChests))
        TriggerClientEvent('chest:updateProps', -1, props)
        print('[RSG-CHEST] Lista de baús sincronizada com os clientes.')
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    for chestUUID, userId in pairs(ChestUsers) do
        if userId == src then
            ChestUsers[chestUUID] = nil
            TriggerClientEvent('rsg-chest:client:updateChestStatus', -1, chestUUID, false)
        end
    end
end)