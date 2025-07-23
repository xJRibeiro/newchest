local RSGCore = exports['rsg-core']:GetCoreObject()
local Database = require 'server/database'
local Admin = {}

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
    getPlayerNames = function(citizenIds)
        local playersInfo = {}
        if not citizenIds or #citizenIds == 0 then return playersInfo end
        local query = 'SELECT citizenid, charinfo FROM players WHERE citizenid IN (?' .. string.rep(',?', #citizenIds - 1) .. ')'
        local playersResult = MySQL.query.await(query, citizenIds)
        if playersResult then
            for _, data in ipairs(playersResult) do
                local charinfo = json.decode(data.charinfo)
                if charinfo and charinfo.firstname and charinfo.lastname then
                    playersInfo[data.citizenid] = ('%s %s'):format(charinfo.firstname, charinfo.lastname)
                end
            end
        end
        return playersInfo
    end
}

Admin.Events = {
    getAdminChestData = function(src)
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
                    citizenIdsToFetch[shared.citizenid] = true
                end
            end
        end
        local ownerIdList = {}
        for id in pairs(citizenIdsToFetch) do table.insert(ownerIdList, id) end
        local playersInfo = Admin.Functions.getPlayerNames(ownerIdList)
        local chestData, summary = {}, { totalChests = 0, emptyChests = 0, chestsWithItems = 0, totalItems = 0, totalWeight = 0 }
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
                        table.insert(items, { name = item.name, label = item.label, amount = item.amount, weight = item.weight })
                    end
                end
            end
            summary.totalChests = summary.totalChests + 1
            summary.totalWeight = summary.totalWeight + totalWeight
            if itemCount == 0 then summary.emptyChests = summary.emptyChests + 1 else summary.chestsWithItems = summary.chestsWithItems + 1 end
            local status = _L('admin_status_available')
            if ChestUsers and ChestUsers[chest.chest_uuid] then
                local user = RSGCore.Functions.GetPlayer(ChestUsers[chest.chest_uuid])
                status = user and _L('admin_status_in_use_by') .. ' ' .. playersInfo[user.PlayerData.citizenid] or _L('admin_status_in_use')
            end
            local sharedWith = {}
            if chest.shared_with and next(chest.shared_with) then
                for _, shared in pairs(chest.shared_with) do
                    table.insert(sharedWith, { citizenid = shared.citizenid, name = playersInfo[shared.citizenid] or _L('unknown_player') })
                end
            end
        table.insert(chestData, {
            chest_uuid = chest.chest_uuid, owner = chest.owner, ownerName = ownerName, coords = chest.coords,
            heading = chest.heading or 0.0, model = chest.model, status = status, itemCount = itemCount,
            totalWeight = totalWeight, maxWeight = Config.ChestWeight, slots = Config.ChestSlots, items = items,
            sharedWith = sharedWith, 
            
            -- [[ CORREÇÃO ]]
            -- Passamos os campos já formatados para o cliente.
            created_at = chest.created_at_formatted, 
            updated_at = chest.updated_at_formatted
        })
        end
        TriggerClientEvent('rsg-chest:client:receiveAdminChestData', src, chestData, summary)
    end,

    -- =========================================================================
    -- FUNÇÃO DE TELEPORTE CORRIGIDA
    -- =========================================================================
    adminTeleport = function(src, chestUUID)
        -- CORREÇÃO: Busca os dados do baú diretamente do banco de dados
        -- em vez de usar a variável 'props' que não está disponível neste arquivo.
        local chest = Database.GetChest(chestUUID)

        if not chest then
            Admin.Functions.notify(src, 'error', Admin.Functions._L('error'), Admin.Functions._L('admin_chest_not_found'))
            return
        end

        -- O resto da função continua igual, pois agora 'chest.coords' será encontrado.
        TriggerClientEvent('rsg-chest:client:teleportToCoords', src, chest.coords)
        Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), Admin.Functions._L('admin_teleported_to_chest'))
    end,
    -- =========================================================================

    adminRemove = function(src, chestUUID)
        exports['rsg-inventory']:DeleteInventory('rsg_chest_' .. chestUUID)
        Database.DeleteChest(chestUUID)
        if props then props[chestUUID] = nil end
        if ChestUsers then ChestUsers[chestUUID] = nil end
        TriggerClientEvent('chest:removePropClient', -1, chestUUID)
        Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), Admin.Functions._L('admin_chest_removed'))
        TriggerClientEvent('rsg-chest:client:refreshAdminPanel', src)
    end,
    adminRemoveAll = function(src)
        local allChests = Database.GetAllChests()
        if not allChests or #allChests == 0 then
            Admin.Functions.notify(src, 'info', Admin.Functions._L('success'), Admin.Functions._L('admin_no_chests'))
            return
        end
        for _, chest in ipairs(allChests) do
            exports['rsg-inventory']:DeleteInventory('rsg_chest_' .. chest.chest_uuid)
            Database.DeleteChest(chest.chest_uuid)
            if props then props[chest.chest_uuid] = nil end
            if ChestUsers then ChestUsers[chest.chest_uuid] = nil end
            TriggerClientEvent('chest:removePropClient', -1, chest.chest_uuid)
        end
        Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), Admin.Functions._L('admin_all_chests_removed'))
        TriggerClientEvent('rsg-chest:client:refreshAdminPanel', src)
    end
}

Admin.Commands = {
    cleanOrphanChests = function(src)
        local allChests = Database.GetAllChests()
        if not allChests or #allChests == 0 then
            Admin.Functions.notify(src, 'info', Admin.Functions._L('success'), Admin.Functions._L('admin_orphan_none_found'))
            return
        end
        local ownerIds = {}
        for _, chest in ipairs(allChests) do ownerIds[chest.owner] = true end
        local ownerIdList = {}
        for id in pairs(ownerIds) do table.insert(ownerIdList, id) end
        local playersResult = MySQL.query.await('SELECT citizenid FROM players WHERE citizenid IN (?' .. string.rep(',?', #ownerIdList - 1) .. ')', ownerIdList)
        local existingPlayers = {}
        for _, row in ipairs(playersResult) do existingPlayers[row.citizenid] = true end
        local orphanCount = 0
        for _, chest in ipairs(allChests) do
            if not existingPlayers[chest.owner] then
                exports['rsg-inventory']:DeleteInventory('rsg_chest_' .. chest.chest_uuid)
                Database.DeleteChest(chest.chest_uuid)
                if props then props[chest.chest_uuid] = nil end
                TriggerClientEvent('chest:removePropClient', -1, chest.chest_uuid)
                orphanCount = orphanCount + 1
            end
        end
        Admin.Functions.notify(src, 'success', Admin.Functions._L('success'), Admin.Functions._L('admin_orphan_cleaned', orphanCount))
    end
}

Admin.init = function()
    RegisterNetEvent('rsg-chest:server:getAdminChestData', function()
        local src = source
        if not RSGCore.Functions.HasPermission(src, 'admin') then return end
        Admin.Events.getAdminChestData(src)
    end)
    RegisterNetEvent('rsg-chest:server:adminTeleport', function(chestUUID)
        local src = source
        if not RSGCore.Functions.HasPermission(src, 'admin') then return end
        Admin.Events.adminTeleport(src, chestUUID)
    end)
    RegisterNetEvent('rsg-chest:server:adminRemove', function(chestUUID)
        local src = source
        if not RSGCore.Functions.HasPermission(src, 'admin') then return end
        Admin.Events.adminRemove(src, chestUUID)
    end)
    RegisterNetEvent('rsg-chest:server:adminRemoveAll', function()
        local src = source
        if not RSGCore.Functions.HasPermission(src, 'admin') then return end
        Admin.Events.adminRemoveAll(src)
    end)
    RSGCore.Commands.Add('adminchest', Admin.Functions._L('admin_command_desc'), {}, false, function(source)
        if not RSGCore.Functions.HasPermission(source, 'admin') then
            Admin.Functions.notify(source, 'error', Admin.Functions._L('error'), Admin.Functions._L('no_permission'))
            return
        end
        TriggerClientEvent('rsg-chest:client:openAdminPanel', source)
    end, 'admin')
    RSGCore.Commands.Add('cleanorphanchests', Admin.Functions._L('admin_clean_orphan_desc'), {}, false, function(source)
        if not RSGCore.Functions.HasPermission(source, 'admin') then
            Admin.Functions.notify(source, 'error', Admin.Functions._L('error'), Admin.Functions._L('no_permission'))
            return
        end
        Admin.Commands.cleanOrphanChests(source)
    end, 'admin')
end

RegisterNetEvent('rsg-chest:server:adminOpenChestInventory', function(chestUUID)
    local src = source
    if not RSGCore.Functions.HasPermission(src, 'admin') then return end

    -- Abre o inventário do baú para o admin, sem travas de permissão
    local chest = Database.GetChest(chestUUID)
    if not chest then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Erro',
            description = 'Baú não encontrado!',
            type = 'error'
        })
        return
    end


    local ownerCitizenId = chest.owner
    local playersInfo = Admin.Functions.getPlayerNames({ownerCitizenId})
    local ownerName = playersInfo[ownerCitizenId] or 'Desconhecido'
    local uniqueStashId = 'rsg_chest_' .. chestUUID

    exports['rsg-inventory']:OpenInventory(src, uniqueStashId, {
        -- A 'label' agora usará a variável ownerName, que contém o nome completo.
        label = ("[ADMIN] Baú de %s"):format(ownerName),
        maxweight = Config.ChestWeight,
        slots = Config.ChestSlots
    })
end)

Admin.init()