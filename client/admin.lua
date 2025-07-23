local RSGCore = exports['rsg-core']:GetCoreObject()

local AdminPanel = {}

AdminPanel.State = {
    chestData = {},
    summary = {}
}

function AdminPanel._L(key, ...)
    local str = Config.Lang[key] or key
    if select('#', ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

AdminPanel.Network = {
    fetchAdminData = function()
        TriggerServerEvent('rsg-chest:server:getAdminChestData')
    end,
    teleportToChest = function(chestUUID)
        TriggerServerEvent('rsg-chest:server:adminTeleport', chestUUID)
    end,
    removeChest = function(chestUUID)
        TriggerServerEvent('rsg-chest:server:adminRemove', chestUUID)
    end,
    removeAllChests = function()
        TriggerServerEvent('rsg-chest:server:adminRemoveAll')
    end
}

AdminPanel.Formatters = {
    shortUUID = function(uuid)
        return uuid:sub(1, 8) .. '...'
    end,
    formatWeightKg = function(grams)
        return string.format('%.1f', (grams or 0) / 1000)
    end,
    formatCoords = function(coords)
        return string.format('X:%.1f Y:%.1f Z:%.1f', coords.x, coords.y, coords.z)
    end,
    getSharedWithText = function(chest)
        if chest.sharedWith and #chest.sharedWith > 0 then
            local sharedEntries = {}
            for _, shared in ipairs(chest.sharedWith) do
                table.insert(sharedEntries, '• ' .. shared.name .. ' (' .. shared.citizenid .. ')')
            end
            return '\n\n**' .. AdminPanel._L('admin_shared_with') .. '**\n' .. table.concat(sharedEntries, '\n')
        end
        return '\n\n**' .. AdminPanel._L('admin_shared_with') .. '** ' .. AdminPanel._L('admin_nobody')
    end
}

AdminPanel.UI = {
    createMenu = function(id, title, options)
        lib.registerContext({ id = id, title = title, options = options })
        lib.showContext(id)
    end,
    createBackButton = function(onSelectCallback)
        return { title = AdminPanel._L('admin_back'), icon = 'arrow-left', onSelect = onSelectCallback }
    end,
    openMainAdminMenu = function()
        local summary = AdminPanel.State.summary
        local options = {
            {
                title = AdminPanel._L('admin_system_overview'),
                description = string.format(AdminPanel._L('admin_overview_desc'),
                    summary.totalChests or 0, summary.chestsWithItems or 0, summary.emptyChests or 0,
                    summary.totalItems or 0, math.floor((summary.totalWeight or 0) / 1000)),
                icon = 'chart-pie', disabled = true
            },
            { title = AdminPanel._L('admin_refresh_data'), description = AdminPanel._L('admin_refresh_desc'), icon = 'sync-alt', onSelect = AdminPanel.Network.fetchAdminData },
            { title = AdminPanel._L('admin_chest_list'), description = AdminPanel._L('admin_chest_list_desc'), icon = 'list', onSelect = AdminPanel.UI.openChestListMenu },
            { title = AdminPanel._L('admin_search_chest'), description = AdminPanel._L('admin_search_desc'), icon = 'search', onSelect = AdminPanel.UI.openSearchMenu },
            {
                title = AdminPanel._L('admin_remove_all_chests'), description = AdminPanel._L('admin_remove_all_chests_desc'), icon = 'trash',
                onSelect = function()
                    local alert = lib.alertDialog({ header = AdminPanel._L('admin_confirm_removal_all'), content = AdminPanel._L('admin_removal_all_warning'), centered = true, cancel = true })
                    if alert == 'confirm' then AdminPanel.Network.removeAllChests() end
                end
            }
        }
        AdminPanel.UI.createMenu('chest_admin_main', AdminPanel._L('admin_panel_title'), options)
    end,
    openChestListMenu = function()
        local options = {}
        local chests = AdminPanel.State.chestData
        if not chests or #chests == 0 then
            table.insert(options, { title = AdminPanel._L('admin_no_chests'), disabled = true, icon = 'inbox' })
        else
            for _, chest in ipairs(chests) do
                local statusIcon = string.find(chest.status, AdminPanel._L('admin_status_in_use')) and '🔴' or '🟢'
                local weightPercent = chest.maxWeight > 0 and math.floor((chest.totalWeight / chest.maxWeight) * 100) or 0
                table.insert(options, {
                    title = string.format('%s %s - %s', statusIcon, AdminPanel.Formatters.shortUUID(chest.chest_uuid), chest.ownerName),
                    description = string.format('%s | %s: %d/%d (%d%%) | %s', AdminPanel.Formatters.formatCoords(chest.coords),
                        AdminPanel._L('admin_items'), chest.itemCount, chest.slots, weightPercent, chest.status),
                    icon = 'box',
                    metadata = {
                        { label = AdminPanel._L('admin_owner'), value = chest.ownerName },
                        { label = AdminPanel._L('admin_items'), value = chest.itemCount .. '/' .. chest.slots },
                        { label = AdminPanel._L('admin_weight'), value = string.format('%s/%s kg', AdminPanel.Formatters.formatWeightKg(chest.totalWeight), AdminPanel.Formatters.formatWeightKg(chest.maxWeight)) }
                    },
                    onSelect = function() AdminPanel.UI.openChestDetailsMenu(chest) end
                })
            end
        end
        table.insert(options, AdminPanel.UI.createBackButton(AdminPanel.UI.openMainAdminMenu))
        AdminPanel.UI.createMenu('chest_list_menu', AdminPanel._L('admin_chest_list') .. ' (' .. #chests .. ')', options)
    end,
    openChestDetailsMenu = function(chest)
        local options = {
            { title = AdminPanel._L('admin_chest_info'), description = AdminPanel._L('admin_chest_info_desc'), icon = 'info-circle', onSelect = function() AdminPanel.UI.showChestDetailedInfo(chest) end },
            {
                title = AdminPanel._L('admin_view_inventory'), description = AdminPanel._L('admin_view_inventory_desc'), icon = 'boxes',
                onSelect = function()
                    TriggerServerEvent('rsg-chest:server:adminOpenChestInventory', chest.chest_uuid)
                    lib.hideContext()
                end
            },
            {
                title = AdminPanel._L('admin_teleport_to_chest'), description = AdminPanel._L('admin_teleport_desc'), icon = 'map-marker-alt',
                onSelect = function()
                    AdminPanel.Network.teleportToChest(chest.chest_uuid)
                    lib.hideContext()
                end
            },
            {
                title = AdminPanel._L('admin_remove_chest'), description = AdminPanel._L('admin_remove_warning'), icon = 'trash-alt',
                onSelect = function()
                    local alert = lib.alertDialog({ header = AdminPanel._L('admin_confirm_removal'), content = string.format(AdminPanel._L('admin_removal_warning'), AdminPanel.Formatters.shortUUID(chest.chest_uuid), chest.ownerName), centered = true, cancel = true })
                    if alert == 'confirm' then AdminPanel.Network.removeChest(chest.chest_uuid) end
                end
            }
        }
        table.insert(options, AdminPanel.UI.createBackButton(AdminPanel.UI.openChestListMenu))
        AdminPanel.UI.createMenu('chest_details_menu', AdminPanel._L('admin_chest_details') .. ' #' .. AdminPanel.Formatters.shortUUID(chest.chest_uuid), options)
    end,
    showChestDetailedInfo = function(chest)
        local f = AdminPanel.Formatters
        -- [[ CORREÇÃO ]]
        -- As variáveis chest.created_at e chest.updated_at agora contêm a data já formatada.
        -- Removemos a função de formatação do cliente e usamos os valores diretamente.
        local content = {
            string.format('**%s:** %s (%s)\n', AdminPanel._L('admin_owner'), chest.ownerName, chest.owner),
            string.format('**%s:** %s\n', AdminPanel._L('admin_status'), chest.status),
            string.format('**%s:** %d/%d slots\n', AdminPanel._L('admin_inventory'), chest.itemCount, chest.slots),
            string.format('**%s:** %s/%s kg (%.1f%%)\n', AdminPanel._L('admin_weight'), f.formatWeightKg(chest.totalWeight), f.formatWeightKg(chest.maxWeight), (chest.totalWeight / chest.maxWeight) * 100),
            string.format('**%s:** %s\n', AdminPanel._L('admin_created'), chest.created_at or AdminPanel._L('admin_unknown')),
        }
        lib.alertDialog({
            header = AdminPanel._L('admin_chest_info') .. ' #' .. f.shortUUID(chest.chest_uuid),
            content = table.concat(content, '\n'),
            centered = true, size = 'lg'
        })
    end,
    showChestItems = function(chest)
        local options = {}
        if chest.itemCount > 0 then
            for _, item in ipairs(chest.items) do
                table.insert(options, {
                    title = item.label or item.name,
                    description = string.format('%s: %d | %s: %.1f kg', AdminPanel._L('admin_quantity'), item.amount, AdminPanel._L('admin_weight'), (item.weight * item.amount) / 1000),
                    icon = 'cube', disabled = true
                })
            end
        else
            table.insert(options, { title = AdminPanel._L('admin_no_items'), disabled = true, icon = 'inbox' })
        end
        table.insert(options, AdminPanel.UI.createBackButton(function() AdminPanel.UI.openChestDetailsMenu(chest) end))
        AdminPanel.UI.createMenu('chest_items_menu', AdminPanel._L('admin_chest_items') .. ' (' .. chest.itemCount .. ')', options)
    end,
    openSearchMenu = function()
        local input = lib.inputDialog(AdminPanel._L('admin_search_chest'), {
            { type = 'input', label = AdminPanel._L('admin_search_by'), placeholder = AdminPanel._L('admin_search_placeholder'), required = true }
        })
        if not (input and input[1]) then return end
        local searchTerm = input[1]:lower()
        local results = {}
        for _, chest in ipairs(AdminPanel.State.chestData) do
            if chest.ownerName:lower():find(searchTerm) or chest.owner:lower():find(searchTerm) or chest.chest_uuid:lower():find(searchTerm) then
                table.insert(results, chest)
            end
        end
        AdminPanel.UI.showSearchResults(results, searchTerm)
    end,
    showSearchResults = function(results, searchTerm)
        local options = {}
        if #results == 0 then
            table.insert(options, { title = AdminPanel._L('admin_no_results'), disabled = true, icon = 'search' })
        else
            for _, chest in ipairs(results) do
                table.insert(options, {
                    title = chest.ownerName .. ' - ' .. AdminPanel.Formatters.shortUUID(chest.chest_uuid),
                    description = string.format('%s | %s: %d', AdminPanel.Formatters.formatCoords(chest.coords), AdminPanel._L('admin_items'), chest.itemCount),
                    icon = 'box',
                    onSelect = function() AdminPanel.UI.openChestDetailsMenu(chest) end
                })
            end
        end
        table.insert(options, AdminPanel.UI.createBackButton(AdminPanel.UI.openMainAdminMenu))
        AdminPanel.UI.createMenu('search_results_menu', AdminPanel._L('admin_search_results') .. ' "' .. searchTerm .. '" (' .. #results .. ')', options)
    end
}

AdminPanel.Events = {
    register = function()
        RegisterNetEvent('rsg-chest:client:openAdminPanel', function()
            AdminPanel.Network.fetchAdminData()
        end)
        RegisterNetEvent('rsg-chest:client:receiveAdminChestData', function(data, summaryData)
            AdminPanel.State.chestData = data
            AdminPanel.State.summary = summaryData
            AdminPanel.UI.openMainAdminMenu()
        end)
        RegisterNetEvent('rsg-chest:client:refreshAdminPanel', function()
            AdminPanel.Network.fetchAdminData()
        end)
    end
}

AdminPanel.Events.register()

RegisterNetEvent('rsg-chest:client:teleportToCoords', function(coords)
    local playerPed = PlayerPedId()
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z + 0.5)
end)