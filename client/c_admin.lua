local RSGCore = exports['rsg-core']:GetCoreObject()
local isPanelOpen = false

-- Comando para abrir/fechar o painel (pode ser usado por admins no F8 ou integrado a um menu admin)
RegisterCommand('adminchest1', function()
    --if not RSGCore.Functions.HasPermission(PlayerId(), 'admin') then return end
    SetPanelVisible(not isPanelOpen)
end, false)

-- Função para controlar a visibilidade e o foco do cursor
function SetPanelVisible(visible)
    isPanelOpen = visible
    SetNuiFocus(visible, visible)
    SendNUIMessage({
        action = visible and 'open' or 'close'
    })
    -- Se estivermos abrindo, pedimos os dados ao servidor
    if visible then
        TriggerServerEvent('rsg-chest:server:getAdminChestData')
    end
end

-- Recebe os dados do servidor e envia para a NUI
RegisterNetEvent('rsg-chest:client:receiveAdminChestData', function(chestData, summary)
    if isPanelOpen then
        SendNUIMessage({
            action = 'openPanel',
            data = { chestData = chestData, summary = summary }
        })
    end
end)

-- Recebe o evento de refresh do servidor e reenvia para a NUI (se necessário)
RegisterNetEvent('rsg-chest:client:refreshAdminPanel', function()
    if isPanelOpen then
        TriggerServerEvent('rsg-chest:server:getAdminChestData')
    end
end)


-- Recebe o comando de teleporte do servidor e executa-o
RegisterNetEvent('rsg-chest:client:teleportToCoords', function(coords)
    local playerPed = PlayerPedId()
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z + 0.5)
end)


-- Callbacks da NUI (quando o JS envia uma mensagem para o Lua)
RegisterNUICallback('closePanel', function(_, cb)
    SetPanelVisible(false)
    cb({ ok = true })
end)

RegisterNUICallback('refreshPanel', function(_, cb)
    TriggerServerEvent('rsg-chest:server:getAdminChestData')
    cb({ ok = true })
end)

RegisterNUICallback('teleportToChest', function(data, cb)
    if data and data.uuid then
        TriggerServerEvent('rsg-chest:server:adminTeleport', data.uuid)
        cb({ ok = true })
    else
        cb({ ok = false })
    end
end)

RegisterNUICallback('removeChest', function(data, cb)
    if data and data.uuid then
        TriggerServerEvent('rsg-chest:server:adminRemove', data.uuid)
        cb({ ok = true })
    else
        cb({ ok = false })
    end
end)