local RSGCore = exports['rsg-core']:GetCoreObject()
local Database = require 'server/database'

local Admin = {}

-- =================================================================
-- FUNÇÕES AUXILIARES MELHORADAS
-- =================================================================

Admin.Functions = {
    _L = function(key, ...)
        local str = Config.Lang[key] or key
        return select('#', ...) > 0 and string.format(str, ...) or str
    end,

    notify = function(src, pType, title, description)
        TriggerClientEvent('ox_lib:notify', src, {
            title = title,
            description = description,
            type = pType
        })
    end,

    validateAdmin = function(src)
        if not src or not RSGCore.Functions.HasPermission(src, 'admin') then
            return false
        end
        return true
    end,

    getPlayerNames = function(citizenIds)
        local playersInfo = {}
        if not citizenIds or #citizenIds == 0 then return playersInfo end

        local success, playersResult = pcall(function()
            local query = 'SELECT citizenid, charinfo FROM players WHERE citizenid IN (?' .. string.rep(',?', #citizenIds - 1) .. ')'
            return MySQL.query.await(query, citizenIds)
        end)

        if success and playersResult then
            for _, data in ipairs(playersResult) do
                local decode_success, charinfo = pcall(json.decode, data.charinfo)
                if decode_success and charinfo and charinfo.firstname and charinfo.lastname then
                    playersInfo[data.citizenid] = ('%s %s'):format(charinfo.firstname, charinfo.lastname)
                end
            end
        else
            print('[RSG-CHEST][ERROR] Falha ao buscar nomes dos jogadores')
        end

        return playersInfo
    end,

    validateChestUUID = function(chestUUID)
        if not chestUUID or type(chestUUID) ~= 'string' or chestUUID == '' then
            return false
        end
        return true
    end
}

-- =================================================================
-- EVENTOS ADMINISTRATIVOS MELHORADOS
-- =================================================================

Admin.Events = {
    getAdminChestData = function(src)
        if not Admin.Functions.validateAdmin(src) then return end

        local _L = Admin.Functions._L
        local allChests = Database.GetAllChests()
        
        if not allChests then
            TriggerClientEvent('rsg-chest:client:receiveAdminChestData', src, {}, {})
            return
        end

        local citizenIdsToFetch = {}
        for _, chest in ipairs(allChests) do
            citizenIdsToFetch[chest.owner] = true
            if chest.shared_with and next(chest.shared_with) then
                for _, shared in pairs(chest.shared_with) do
                    if shared.citizenid then
                        citizenIdsToFetch[shared.citizenid] = true
                    end
                end
            end
        end

        local ownerIdList = {}
        for id in pairs(citizenIdsToFetch) do table.insert(ownerIdList, id) end

        local playersInfo = Admin.Functions.getPlayerNames(ownerIdList)
        local chestData, summary = {}, { 
            totalChests = 0, 
            emptyChests = 0, 
            chestsWithItems = 0, 
            totalItems = 0, 
            totalWeight = 0 
        }

        for _, chest in ipairs(allChests) do
            local ownerName = playersInfo[chest.owner] or _L('unknown_player')
            local inventory = exports['rsg-inventory']:GetInventory('rsg_chest_' .. chest.chest_uuid)
            local itemCount, totalWeight, items = 0, 0, {}

            if inventory and inventory.items then
                for _, item in pairs(inventory.items) do
                    if item then
                        itemCount = itemCount + 1
                        totalWeight = totalWeight + (item.weight * item.amount)
                        summary.totalItems = summary.totalItems + item.amount
                        table.insert(items, { 
                            name = item.name, 
                            label = item.label, 
                            amount = item.amount, 
                            weight = item.weight 
                        })
                    end
                end
            end

            summary.totalChests = summary.totalChests + 1
            summary.totalWeight = summary.totalWeight + totalWeight

            if itemCount == 0 then 
                summary.emptyChests = summary.emptyChests + 1 
            else 
                summary.chestsWithItems = summary.chestsWithItems + 1 
            end

            local status = _L('admin_status_available')
            if ChestUsers and ChestUsers[chest.chest_uuid] then
                local user = RSGCore.Functions.GetPlayer(ChestUsers[chest.chest_uuid])
                status = user and _L('admin_status_in_use_by') .. ' ' .. playersInfo[user.PlayerData.citizenid] or _L('admin_status_in_use')
            end

            local sharedWith = {}
            if chest.shared_with and next(chest.shared_with) then
                for _, shared in pairs(chest.shared_with) do
                    table.insert(sharedWith, { 
                        citizenid = shared.citizenid, 
                        name = playersInfo[shared.citizenid] or _L('unknown_player') 
                    })
                end
            end

            table.insert(chestData, {
                chest_uuid = chest.chest_uuid,
                owner = chest.owner,
                ownerName = ownerName,
                coords = chest.coords,
                heading = chest.heading or 0.0,
                model = chest.model,
                status = status,
                itemCount = itemCount,
                totalWeight = totalWeight,
                maxWeight = chest.max_weight or Config.ChestWeight,
                slots = chest.max_slots or Config.ChestSlots,
                items = items,
                sharedWith = sharedWith,
                created_at = chest.created_at_formatted,
                updated_at = chest.updated_at_formatted,
                tier = chest.tier or 1
            })
        end

        TriggerClientEvent('rsg-chest:client:receiveAdminChestData', src, chestData, summary)
    end,

    adminTeleport = function(src, chestUUID)
        if not Admin.Functions.validateAdmin(src) then return end
        if not Admin.Functions.validateChestUUID(chestUUID) then
            Admin.Functions.notify(src, 'error', Admin.Functions._L('error'), 'UUID de baú inválido')
            return
        end

        local chest = Database.GetChest(chestUUID)
        if not chest then
            Admin.Functions.notify(src, 'error', Admin.Functions._L('error'), Admin.Functions._L('admin_chest_not_found'))
            return
        end

        TriggerClientEvent('rsg-chest:client:teleportToCoords', src, chest.coords)
        Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), Admin.Functions._L('admin_teleported_to_chest'))
    end,

    adminRemove = function(src, chestUUID)
        if not Admin.Functions.validateAdmin(src) then return end
        if not Admin.Functions.validateChestUUID(chestUUID) then
            Admin.Functions.notify(src, 'error', Admin.Functions._L('error'), 'UUID de baú inválido')
            return
        end

        -- Remove do inventário primeiro
        exports['rsg-inventory']:DeleteInventory('rsg_chest_' .. chestUUID)
        
        -- Remove do banco de dados
        if Database.DeleteChest(chestUUID) then
            -- Limpa do cache se existir
            if props then props[chestUUID] = nil end
            if ChestUsers then ChestUsers[chestUUID] = nil end

            -- Remove do cliente
            TriggerClientEvent('chest:removePropClient', -1, chestUUID)
            print(('[RSG-CHEST][ADMIN] Baú removido: %s'):format(chestUUID))
            
            Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), Admin.Functions._L('admin_chest_removed'))
            TriggerClientEvent('rsg-chest:client:refreshAdminPanel', src)
        else
            Admin.Functions.notify(src, 'error', Admin.Functions._L('error'), 'Falha ao remover baú do banco de dados')
        end
    end,

    adminRemoveAll = function(src)
        if not Admin.Functions.validateAdmin(src) then return end

        local allChests = Database.GetAllChests()
        if not allChests or #allChests == 0 then
            Admin.Functions.notify(src, 'info', Admin.Functions._L('success'), Admin.Functions._L('admin_no_chests'))
            return
        end

        local removedCount = 0
        for _, chest in ipairs(allChests) do
            exports['rsg-inventory']:DeleteInventory('rsg_chest_' .. chest.chest_uuid)
            
            if Database.DeleteChest(chest.chest_uuid) then
                if props then props[chest.chest_uuid] = nil end
                if ChestUsers then ChestUsers[chest.chest_uuid] = nil end
                TriggerClientEvent('chest:removePropClient', -1, chest.chest_uuid)
                removedCount = removedCount + 1
            end
        end

        Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), 
            string.format('%s: %d baús removidos', Admin.Functions._L('admin_all_chests_removed'), removedCount))
        TriggerClientEvent('rsg-chest:client:refreshAdminPanel', src)
    end,

    adminOpenChestInventory = function(src, chestUUID)
        if not Admin.Functions.validateAdmin(src) then return end
        if not Admin.Functions.validateChestUUID(chestUUID) then
            Admin.Functions.notify(src, 'error', Admin.Functions._L('error'), 'UUID de baú inválido')
            return
        end

        local chest = Database.GetChest(chestUUID)
        if not chest then
            Admin.Functions.notify(src, 'error', 'Erro', 'Baú não encontrado!')
            return
        end

        local playersInfo = Admin.Functions.getPlayerNames({chest.owner})
        local ownerName = playersInfo[chest.owner] or 'Desconhecido'

        exports['rsg-inventory']:OpenInventory(src, 'rsg_chest_' .. chestUUID, {
            label = ("[ADMIN] Baú de %s"):format(ownerName),
            maxweight = chest.max_weight or Config.ChestWeight,
            slots = chest.max_slots or Config.ChestSlots
        })
    end
}

-- =================================================================
-- COMANDOS ADMINISTRATIVOS MELHORADOS
-- =================================================================

Admin.Commands = {
    cleanOrphanChests = function(src)
        if not Admin.Functions.validateAdmin(src) then return end

        local orphanCount = Database.CleanupOrphanChests()
        
        if orphanCount > 0 then
            Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), 
                Admin.Functions._L('admin_orphan_cleaned', orphanCount))
        else
            Admin.Functions.notify(src, 'info', Admin.Functions._L('success'), 
                Admin.Functions._L('admin_orphan_none_found'))
        end
    end,

    getChestStats = function(src)
        if not Admin.Functions.validateAdmin(src) then return end

        local stats = Database.GetChestStats()
        local message = string.format(
            'Estatísticas dos Baús:\n• Total: %d\n• Compartilhados: %d\n• Tier médio: %.2f',
            stats.totalChests, stats.sharedChests, stats.averageTier
        )
        
        Admin.Functions.notify(src, 'inform', 'Estatísticas', message)
    end
}

-- =================================================================
-- INICIALIZAÇÃO DOS EVENTOS E COMANDOS
-- =================================================================

Admin.init = function()
    -- Eventos de rede
    RegisterNetEvent('rsg-chest:server:getAdminChestData', function()
        Admin.Events.getAdminChestData(source)
    end)

    RegisterNetEvent('rsg-chest:server:adminTeleport', function(chestUUID)
        Admin.Events.adminTeleport(source, chestUUID)
    end)

    RegisterNetEvent('rsg-chest:server:adminRemove', function(chestUUID)
        Admin.Events.adminRemove(source, chestUUID)
    end)

    RegisterNetEvent('rsg-chest:server:adminRemoveAll', function()
        Admin.Events.adminRemoveAll(source)
    end)

    RegisterNetEvent('rsg-chest:server:adminOpenChestInventory', function(chestUUID)
        Admin.Events.adminOpenChestInventory(source, chestUUID)
    end)

    -- Comandos
    RSGCore.Commands.Add('adminchest', Admin.Functions._L('admin_command_desc'), {}, false, function(source)
        if not Admin.Functions.validateAdmin(source) then
            Admin.Functions.notify(source, 'error', Admin.Functions._L('error'), Admin.Functions._L('no_permission'))
            return
        end
        TriggerClientEvent('rsg-chest:client:openAdminPanel', source)
    end, 'admin')

    RSGCore.Commands.Add('cleanorphanchests', Admin.Functions._L('admin_clean_orphan_desc'), {}, false, function(source)
        Admin.Commands.cleanOrphanChests(source)
    end, 'admin')

    RSGCore.Commands.Add('cheststats', 'Ver estatísticas dos baús', {}, false, function(source)
        Admin.Commands.getChestStats(source)
    end, 'admin')

    print('[RSG-CHEST] Sistema administrativo inicializado com sucesso')
end

Admin.init()
