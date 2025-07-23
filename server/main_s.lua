local RSGCore = exports['rsg-core']:GetCoreObject()
local Database = require 'server/database'

local props = {}
local ChestUsers = {}
local LockpickCooldowns = {}
local TemporaryAccess = {}

-- =================================================================
-- FUNÇÕES AUXILIARES MELHORADAS
-- =================================================================
local function GetItemLabel(itemName)
    if RSGCore.Shared.Items and RSGCore.Shared.Items[itemName] then
        return RSGCore.Shared.Items[itemName].label or itemName
    end
    return itemName
end

local function ValidatePlayerDistance(src, coords, maxDistance)
    if not src or not coords then return false end
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    return #(playerCoords - vector3(coords.x, coords.y, coords.z)) <= maxDistance
end

local function ValidateChestAccess(chestUUID, playerId)
    local prop = props[chestUUID]
    if not prop then return false end

    local Player = RSGCore.Functions.GetPlayer(playerId)
    if not Player or not Player.PlayerData or not Player.PlayerData.citizenid then return false end

    return prop.owner == Player.PlayerData.citizenid
end

local function ValidateItemExists(src, item, amount)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end
    
    local hasItem = exports['rsg-inventory']:GetItemByName(src, item)
    return hasItem and hasItem.amount >= (amount or 1)
end

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
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not Player.PlayerData then return end
    
    TriggerClientEvent('rsg-chest:client:startPlacement', source)
end)

-- =================================================================
-- HANDLERS DE EVENTOS DE REDE MELHORADOS
-- =================================================================

RegisterNetEvent('rsg-chest:server:placeChest', function(coords, heading)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not Player.PlayerData or not Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Seus dados de jogador não foram carregados.' 
        })
    end

    -- Validação de distância para prevenção de exploits
    if not ValidatePlayerDistance(src, coords, 10.0) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você está muito longe do local de colocação.' 
        })
    end

    -- Validação de coordenadas
    if not coords or not coords.x or not coords.y or not coords.z then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Coordenadas inválidas.' 
        })
    end

    -- Validação de item
    if not ValidateItemExists(src, Config.ChestItem, 1) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['item_not_found'] 
        })
    end

    local citizenId = Player.PlayerData.citizenid
    local chestUUID = Database.CreateChest(citizenId, coords, heading, Config.ChestProp)

    if chestUUID then
        if exports['rsg-inventory']:RemoveItem(src, Config.ChestItem, 1) then
            local initialTier = Config.Tiers[1]
            
            props[chestUUID] = {
                chest_uuid = chestUUID, 
                owner = citizenId, 
                coords = coords, 
                heading = heading, 
                model = Config.ChestProp,
                shared_with = {}, 
                tier = 1, 
                max_weight = initialTier.weight, 
                max_slots = initialTier.slots
            }

            exports['rsg-inventory']:CreateInventory('rsg_chest_' .. chestUUID, {
                label = initialTier.label, 
                maxweight = initialTier.weight, 
                slots = initialTier.slots
            })

            TriggerClientEvent('chest:createProp', -1, chestUUID, props[chestUUID])
            TriggerClientEvent('ox_lib:notify', src, { 
                type = 'success', 
                title = 'Sucesso', 
                description = Config.Lang['chest_placed'] 
            })
        else
            Database.DeleteChest(chestUUID)
            TriggerClientEvent('ox_lib:notify', src, { 
                type = 'error', 
                title = 'Erro', 
                description = Config.Lang['item_not_found'] 
            })
        end
    else
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro de Servidor', 
            description = "Falha ao registrar o baú no banco de dados." 
        })
    end
end)

RegisterNetEvent('jx:chest:open', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end

    -- Validação de distância para abertura
    local chest = props[chestUUID]
    if not ValidatePlayerDistance(src, chest.coords, 3.0) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você está muito longe do baú.' 
        })
    end

    local hasTempAccess = TemporaryAccess[chestUUID] and TemporaryAccess[chestUUID].citizenId == Player.PlayerData.citizenid

    if hasTempAccess and os.time() > TemporaryAccess[chestUUID].expires then
        hasTempAccess = false
        TemporaryAccess[chestUUID] = nil
    end

    if not HasPermission(chestUUID, src) and not hasTempAccess then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['no_permission'] 
        })
    end

    if ChestUsers[chestUUID] and ChestUsers[chestUUID] ~= src then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['chest_in_use'] 
        })
    end

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

    exports['rsg-inventory']:OpenInventory(src, 'rsg_chest_' .. chestUUID, {
        label = (chest.custom_name or tierData.label) .. (' de %s'):format(ownerName),
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

    -- Validação de propriedade
    if not ValidateChestAccess(chestUUID, src) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['no_permission'] 
        })
    end

    -- Validação de distância
    if not ValidatePlayerDistance(src, chest.coords, 3.0) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você está muito longe do baú.' 
        })
    end

    local inventory = exports['rsg-inventory']:GetInventory('rsg_chest_' .. chestUUID)
    if inventory and inventory.items and next(inventory.items) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'warning', 
            title = 'Aviso', 
            description = 'Esvazie o baú antes de removê-lo.' 
        })
    end

    Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'REMOVE', nil, 'Dono removeu o próprio baú.')

    exports['rsg-inventory']:DeleteInventory('rsg_chest_' .. chestUUID)
    Database.DeleteChest(chestUUID)
    props[chestUUID] = nil

    if exports['rsg-inventory']:AddItem(src, Config.ChestItem, 1) then
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'success', 
            title = 'Sucesso', 
            description = Config.Lang['chest_removed'] 
        })
    else
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Seu inventário está cheio.' 
        })
    end

    TriggerClientEvent('chest:removePropClient', -1, chestUUID)
end)

RegisterNetEvent('jx:chest:getNearbyPlayerNames', function(chestUUID, nearbyPlayerIds)
    local src = source
    
    if not chestUUID or not props[chestUUID] or not ValidateChestAccess(chestUUID, src) then
        return
    end

    local playersWithNames = {}

    if nearbyPlayerIds and #nearbyPlayerIds > 0 then
        for _, targetId in ipairs(nearbyPlayerIds) do
            local TargetPlayer = RSGCore.Functions.GetPlayer(targetId)
            if TargetPlayer and TargetPlayer.PlayerData.charinfo then
                -- Validação de distância adicional
                if ValidatePlayerDistance(targetId, GetEntityCoords(GetPlayerPed(src)), Config.ShareDistance + 2.0) then
                    table.insert(playersWithNames, {
                        label = ('%s %s'):format(TargetPlayer.PlayerData.charinfo.firstname, TargetPlayer.PlayerData.charinfo.lastname),
                        value = targetId
                    })
                end
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
    
    -- Validação de propriedade
    if not ValidateChestAccess(chestUUID, src) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['no_permission'] 
        })
    end

    -- Validação de distância entre jogadores
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(targetPlayerId))) > (Config.ShareDistance or 5.0) + 2.0 then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'O jogador alvo se moveu para muito longe.' 
        })
    end

    local sharedWith = chest.shared_with or {}

    -- Verifica se já está compartilhado
    for _, data in ipairs(sharedWith) do
        if data.citizenid == TargetPlayer.PlayerData.citizenid then
            return TriggerClientEvent('ox_lib:notify', src, { 
                type = 'warning', 
                title = 'Aviso', 
                description = 'Este jogador já tem acesso.' 
            })
        end
    end

    -- Verifica limite de compartilhamentos
    if #sharedWith >= (Config.MaxSharedPlayers or 5) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'warning', 
            title = 'Aviso', 
            description = 'Limite de compartilhamentos atingido.' 
        })
    end

    local targetName = ('%s %s'):format(TargetPlayer.PlayerData.charinfo.firstname, TargetPlayer.PlayerData.charinfo.lastname)

    Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'SHARE', TargetPlayer.PlayerData.citizenid, ('Compartilhou com: %s'):format(targetName))

    table.insert(sharedWith, { citizenid = TargetPlayer.PlayerData.citizenid, name = targetName })
    Database.ShareChest(chestUUID, sharedWith)
    props[chestUUID].shared_with = sharedWith

    TriggerClientEvent('jx:chest:updateSharedList', -1, chestUUID, sharedWith)
    TriggerClientEvent('ox_lib:notify', src, { 
        type = 'success', 
        title = 'Sucesso', 
        description = ('Baú compartilhado com %s.'):format(targetName) 
    })
    TriggerClientEvent('ox_lib:notify', targetPlayerId, { 
        type = 'inform', 
        title = 'Baú Compartilhado', 
        description = ('%s compartilhou um baú com você.'):format(Player.PlayerData.charinfo.firstname) 
    })
end)

RegisterNetEvent('jx:chest:unshare', function(chestUUID, targetCitizenId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end

    local chest = props[chestUUID]
    
    -- Validação de propriedade
    if not ValidateChestAccess(chestUUID, src) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['no_permission'] 
        })
    end

    local sharedWith = chest.shared_with or {}
    local newSharedList, playerRemoved, removedPlayerName = {}, false, ''

    for _, data in ipairs(sharedWith) do
        if data.citizenid == targetCitizenId then 
            playerRemoved, removedPlayerName = true, data.name 
        else 
            table.insert(newSharedList, data) 
        end
    end

    if playerRemoved then
        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'UNSHARE', targetCitizenId, ('Removeu acesso de: %s'):format(removedPlayerName))
        Database.ShareChest(chestUUID, newSharedList)
        props[chestUUID].shared_with = newSharedList

        TriggerClientEvent('jx:chest:updateSharedList', -1, chestUUID, newSharedList)
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'success', 
            title = 'Sucesso', 
            description = ('Acesso de %s removido.'):format(removedPlayerName) 
        })

        local TargetPlayer = RSGCore.Functions.GetPlayerByCitizenId(targetCitizenId)
        if TargetPlayer then
            TriggerClientEvent('ox_lib:notify', TargetPlayer.PlayerData.source, { 
                type = 'inform', 
                title = 'Acesso Removido', 
                description = 'Seu acesso a um baú foi revogado.' 
            })
        end
    end
end)

RegisterNetEvent('jx:chest:upgrade', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end

    local chest = props[chestUUID]
    
    -- Validação de propriedade
    if chest.owner ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['no_permission'] 
        })
    end

    -- Validação de distância
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local chestCoords = vector3(chest.coords.x, chest.coords.y, chest.coords.z)
    
    if #(playerCoords - chestCoords) > 3.0 then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você está muito longe do baú.' 
        })
    end

    local currentTier = chest.tier or 1
    local nextTier = currentTier + 1

    if not Config.Tiers[nextTier] then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'inform', 
            title = 'Aviso', 
            description = Config.Lang['max_tier_reached'] 
        })
    end

    -- Validação de item de upgrade
    local hasUpgradeItem = exports['rsg-inventory']:GetItemByName(src, Config.UpgradeItem)
    if not hasUpgradeItem or hasUpgradeItem.amount < 1 then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você não possui o item necessário para melhorar este baú.'
        })
    end

    -- ✅ TRIGGER EVENTO CLIENTE PARA ANIMAÇÃO
    TriggerClientEvent('jx:chest:startUpgradeAnimation', src, chestUUID)
end)

-- ✅ NOVO EVENTO: Processar upgrade após animação
RegisterNetEvent('jx:chest:processUpgrade', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end

    local chest = props[chestUUID]
    
    -- Revalidar tudo
    if chest.owner ~= Player.PlayerData.citizenid then return end
    
    local currentTier = chest.tier or 1
    local nextTier = currentTier + 1
    
    if not Config.Tiers[nextTier] then return end

    -- Remove o item e processa o upgrade
    if exports['rsg-inventory']:RemoveItem(src, Config.UpgradeItem, 1) then
        local newTierData = Config.Tiers[nextTier]

        MySQL.update.await('UPDATE player_chests SET tier = ?, max_weight = ?, max_slots = ? WHERE chest_uuid = ?', { 
            nextTier, newTierData.weight, newTierData.slots, chestUUID 
        })

        props[chestUUID].tier = nextTier
        props[chestUUID].max_weight = newTierData.weight
        props[chestUUID].max_slots = newTierData.slots

        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'UPGRADE', nil, ('Melhorou para o Nível %d'):format(nextTier))

        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'success', 
            title = 'Sucesso', 
            description = string.format('Baú melhorado para %s!', newTierData.label)
        })
        
        TriggerClientEvent('jx:chest:updateSharedList', -1, chestUUID, props[chestUUID].shared_with)
    else
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Falha ao processar upgrade do baú.'
        })
    end
end)


RegisterNetEvent('jx:chest:requestLockpick', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID then return end

    -- Verifica cooldown
    if LockpickCooldowns[Player.PlayerData.citizenid] and os.time() < LockpickCooldowns[Player.PlayerData.citizenid] then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Aguarde', 
            description = Config.LockpickSettings.CooldownMessage
        })
    end

    -- Verifica se o baú existe
    local chest = props[chestUUID]
    if not chest then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Baú não encontrado.' 
        })
    end

    -- Validação de distância
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local chestCoords = vector3(chest.coords.x, chest.coords.y, chest.coords.z)
    
    if #(playerCoords - chestCoords) > 3.0 then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você está muito longe do baú.' 
        })
    end

    -- Verifica se tem lockpick
    local hasLockpick = exports['rsg-inventory']:GetItemByName(src, Config.LockpickItem)
    if not hasLockpick or hasLockpick.amount < 1 then
        local itemLabel = GetItemLabel(Config.LockpickItem)
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = ('Você não possui um %s.'):format(itemLabel)
        })
    end

    -- Remove o lockpick (será perdido em caso de falha)
    if exports['rsg-inventory']:RemoveItem(src, Config.LockpickItem, 1) then
        -- Log da tentativa
        Database.LogAction(chestUUID, '', 'LOCKPICK_ATTEMPT', chest.owner, 
            'Iniciou Tentativa de Saquear Baú')
        
        -- Inicia o minigame de lockpick
        TriggerClientEvent('jx:chest:startSkillCheck', src, chestUUID)
    else
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Falha ao usar o lockpick.' 
        })
    end
end)


RegisterNetEvent('jx:chest:resolveLockpick', function(chestUUID, success)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end

    local chest = props[chestUUID]

    -- Validação de distância final
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local chestCoords = vector3(chest.coords.x, chest.coords.y, chest.coords.z)
    
    if #(playerCoords - chestCoords) > 3.0 then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você se moveu muito longe do baú.' 
        })
    end

    if success then
        -- ✅ SUCESSO NO LOCKPICK
        Database.LogAction(chestUUID, '', 'LOCKPICK_SUCCESS', chest.owner, 
            'Baú arrombado!')
        
        -- Concede acesso temporário
        TemporaryAccess[chestUUID] = { 
            citizenId = Player.PlayerData.citizenid, 
            expires = os.time() + 120 -- 2 minutos de acesso
        }

        -- Alerta à polícia
        if Config.LockpickSettings.PoliceAlert then
            local alertData = { 
                title = "Arrombamento de Baú", 
                coords = chest.coords, 
                description = "Um baú foi arrombado com sucesso usando lockpick.", 
                sprite = 516, 
                color = 1, 
                scale = 1.2, 
                duration = 5000 
            }
            TriggerClientEvent('rsg-dispatch:client:CreateAlert', -1, alertData, { 'police' })
        end

        -- Abre o baú automaticamente
        local tierId = chest.tier or 1
        local tierData = Config.Tiers[tierId]
        
        if not tierData then
            tierData = Config.Tiers[1]
        end

        local ownerName = GetChestOwnerName(chest.owner)

        exports['rsg-inventory']:OpenInventory(src, 'rsg_chest_' .. chestUUID, {
            label = (chest.custom_name or tierData.label) .. (' de %s'):format(ownerName),
            maxweight = chest.max_weight,
            slots = chest.max_slots
        })

        ChestUsers[chestUUID] = src
        TriggerClientEvent('chest:opened', src, chestUUID)

    else
        -- ❌ FALHA NO LOCKPICK
        Database.LogAction(chestUUID, Player.PlayerData.ciudenid, 'LOCKPICK_FAIL', chest.owner,
            'Falhou ao tentar arrombar o baú com rsg-lockpick')
        
        -- Aplica cooldown
        LockpickCooldowns[Player.PlayerData.citizenid] = os.time() + Config.LockpickSettings.Cooldown
        
        -- Lockpick já foi removido, não precisa fazer nada mais
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Falha', 
            description = Config.LockpickSettings.FailMessage
        })
    end
end)

-- =================================================================
-- EVENTO PARA TENTAR UPGRADE COM VERIFICAÇÃO DE ITEM
-- =================================================================

RegisterNetEvent('jx:chest:attemptUpgrade', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end

    local chest = props[chestUUID]
    
    -- Verifica se é o dono
    if chest.owner ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['no_permission'] 
        })
    end

    -- Validação de distância
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local chestCoords = vector3(chest.coords.x, chest.coords.y, chest.coords.z)
    
    if #(playerCoords - chestCoords) > 3.0 then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você está muito longe do baú.' 
        })
    end

    local currentTier = chest.tier or 1
    local nextTier = currentTier + 1

    if not Config.Tiers[nextTier] then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'inform', 
            title = 'Aviso', 
            description = Config.Lang['max_tier_reached'] 
        })
    end

    -- ✅ VERIFICA SE TEM O ITEM DE UPGRADE
    local hasUpgradeItem = exports['rsg-inventory']:GetItemByName(src, Config.UpgradeItem)
    if not hasUpgradeItem or hasUpgradeItem.amount < 1 then
        local itemLabel = GetItemLabel(Config.UpgradeItem)
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Item Necessário', 
            description = ('Você precisa de um %s para melhorar este baú.'):format(itemLabel)
        })
    end

    -- Confirma se quer usar o item
    local itemLabel = GetItemLabel(Config.UpgradeItem)
    TriggerClientEvent('jx:chest:confirmUpgrade', src, chestUUID, hasUpgradeItem.amount, itemLabel)
end)
-- =================================================================
-- EVENTO PARA RENOMEAR BAÚ
-- =================================================================

RegisterNetEvent('jx:chest:rename', function(chestUUID, newName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end
    
    local chest = props[chestUUID]
    
    -- Verifica se é o dono
    if chest.owner ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = Config.Lang['no_permission'] 
        })
    end
    
    -- Validação do nome
    if not newName or type(newName) ~= 'string' then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Nome inválido fornecido.' 
        })
    end
    
    -- Remove espaços extras e valida tamanho
    newName = newName:gsub("^%s*(.-)%s*$", "%1")
    if #newName < 3 or #newName > 50 then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'O nome deve ter entre 3 e 50 caracteres.' 
        })
    end
    
    -- Filtra caracteres inválidos (opcional)
    local filteredName = newName:gsub("[<>\"'&]", "")
    if filteredName ~= newName then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'O nome contém caracteres não permitidos.' 
        })
    end
    
    -- Atualiza no banco de dados
    if Database.RenameChest(chestUUID, filteredName) then
        -- Atualiza no cache local
        props[chestUUID].custom_name = filteredName
        
        -- Log da ação
        Database.LogAction(chestUUID, Player.PlayerData.citizenid, 'RENAME', nil, 
            ('Renomeou o baú para: %s'):format(filteredName))
        
        -- Notifica sucesso
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'success', 
            title = 'Sucesso', 
            description = ('Baú renomeado para "%s" com sucesso!'):format(filteredName)
        })
        
        -- Atualiza a lista de props para todos os clientes
        TriggerClientEvent('chest:updateProps', -1, props)
    else
        TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Falha ao renomear o baú. Tente novamente.' 
        })
    end
end)


RegisterNetEvent('chest:requestAllProps', function() 
    TriggerClientEvent('chest:updateProps', source, props) 
end)

RegisterNetEvent('rsg-chest:server:getActiveChests', function()
    local src = source
    local activeChests = {}
    
    for _, chest in pairs(props) do
        table.insert(activeChests, { coords = chest.coords })
    end
    
    TriggerClientEvent('rsg-chest:client:receiveActiveChests', src, activeChests)
end)

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

-- =================================================================
-- EVENTO PARA JOGADORES VEREM SEUS PRÓPRIOS REGISTROS
-- =================================================================

RegisterNetEvent('jx:chest:requestPlayerLogs', function(chestUUID)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not chestUUID or not props[chestUUID] then return end
    
    -- Verifica se o jogador tem permissão (dono ou compartilhado)
    if not HasPermission(chestUUID, src) then
        return TriggerClientEvent('ox_lib:notify', src, { 
            type = 'error', 
            title = 'Erro', 
            description = 'Você não tem permissão para ver os registros deste baú.' 
        })
    end
    
    local logs = Database.GetChestLogs(chestUUID, 50) -- Últimos 50 registros
    local stats = Database.GetChestLogStats(chestUUID)
    
    if not logs or #logs == 0 then
        TriggerClientEvent('jx:chest:showPlayerLogs', src, chestUUID, {}, stats)
        return
    end

    -- Processa os logs para adicionar informações visuais
    local processedLogs = {}
    for _, log in ipairs(logs) do
        local actionIcon = '📝'
        local actionDescription = 'Ação Desconhecida'
        
        -- Define ícones e descrições baseados no tipo de ação
        if log.action_type == 'OPEN' then
            actionIcon = '📦'
            actionDescription = 'Abertura do Baú'
        elseif log.action_type == 'SHARE' then
            actionIcon = '🤝'
            actionDescription = 'Compartilhamento'
        elseif log.action_type == 'UNSHARE' then
            actionIcon = '🚫'
            actionDescription = 'Remoção de Acesso'
        elseif log.action_type == 'REMOVE' then
            actionIcon = '🗑️'
            actionDescription = 'Remoção do Baú'
        elseif log.action_type == 'UPGRADE' then
            actionIcon = '⬆️'
            actionDescription = 'Melhoria do Baú'
        elseif log.action_type == 'LOCKPICK_SUCCESS' then
            actionIcon = '🔓'
            actionDescription = 'Bau saqueado!'
        elseif log.action_type == 'LOCKPICK_ATTEMPT' then
            actionIcon = '🔒'
            actionDescription = 'Tentativa de Saquear Baú'
        elseif log.action_type == 'RENAME' then
            actionIcon = '🏷️'
            actionDescription = 'Baú renomeado'
        end
        
        table.insert(processedLogs, {
            id = log.id,
            action_type = log.action_type,
            action_description = actionDescription,
            actor_name = log.actor_name,
            actor_citizenid = log.actor_citizenid,
            target_name = log.target_name,
            target_citizenid = log.target_citizenid,
            details = log.details,
            formatted_date = log.formatted_date,
            icon = actionIcon
        })
    end

    TriggerClientEvent('jx:chest:showPlayerLogs', src, chestUUID, processedLogs, stats)
end)


-- Cleanup automático de acessos temporários expirados
CreateThread(function()
    while true do
        Wait(60000) -- 1 minuto
        local currentTime = os.time()
        
        for chestUUID, accessData in pairs(TemporaryAccess) do
            if currentTime > accessData.expires then
                TemporaryAccess[chestUUID] = nil
            end
        end
        
        -- Cleanup de cooldowns expirados
        for citizenId, cooldownTime in pairs(LockpickCooldowns) do
            if currentTime > cooldownTime then
                LockpickCooldowns[citizenId] = nil
            end
        end
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
