local RSGCore = exports['rsg-core']:GetCoreObject()

-- Variáveis de estado do cliente
local propEntities, localProps, currentOpenChest = {}, {}, nil

-- =================================================================
-- FUNÇÕES DE LÓGICA E INTERFACE
-- =================================================================

--- Pede ao servidor a lista de jogadores próximos com nomes reais para o menu de compartilhamento.
function OpenShareMenu(chestUUID)
    local nearbyPlayerIds = {}
    local playerCoords = GetEntityCoords(PlayerPedId())

    for _, id in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(id)
        if id ~= PlayerId() and DoesEntityExist(targetPed) then
            if #(playerCoords - GetEntityCoords(targetPed)) < (Config.ShareDistance or 5.0) then
                table.insert(nearbyPlayerIds, GetPlayerServerId(id))
            end
        end
    end

    if #nearbyPlayerIds == 0 then
        lib.notify({ type = 'warning', title = 'Aviso', description = 'Nenhum jogador próximo encontrado.' })
        return
    end

    TriggerServerEvent('jx:chest:getNearbyPlayerNames', chestUUID, nearbyPlayerIds)
end

--- Abre o menu para o dono do baú remover o acesso de jogadores compartilhados.
function OpenManageShareMenu(chestUUID)
    local propData = localProps[chestUUID]
    if not propData or not propData.shared_with or #propData.shared_with == 0 then
        lib.notify({ type = 'inform', title = 'Gerenciar Acesso', description = 'Este baú não está compartilhado com ninguém.' })
        return
    end

    local options = {}
    for _, sharedInfo in ipairs(propData.shared_with) do
        table.insert(options, {
            title = sharedInfo.name,
            description = "Citizen ID: " .. sharedInfo.citizenid,
            icon = "fas fa-user-minus",
            onSelect = function()
                if lib.alertDialog({ header = 'Remover Acesso', content = ('Tem certeza que deseja remover o acesso de %s?'):format(sharedInfo.name), centered = true, cancel = true }) == 'confirm' then
                    TriggerServerEvent('jx:chest:unshare', chestUUID, sharedInfo.citizenid)
                end
            end
        })
    end

    lib.registerContext({ id = 'chest_manage_share_menu', title = 'Gerenciar Acesso do Baú', options = options })
    lib.showContext('chest_manage_share_menu')
end

--- Função central para fechar o baú e limpar o estado do cliente.
local function CloseCurrentChest()
    local chestToClose = currentOpenChest
    currentOpenChest = nil
    if not chestToClose then return end
    TriggerServerEvent('jx:chest:closeInventory', chestToClose)
end

--- Limpa todos os props de baús do mundo do jogo.
function ClearAllProps()
    for _, entity in pairs(propEntities) do
        if DoesEntityExist(entity) then
            pcall(function() exports['rsg-target']:RemoveTargetEntity(entity) end)
            DeleteEntity(entity)
        end
    end
    propEntities, localProps = {}, {}
end

--- Adiciona as opções de interação ao rsg-target com base nas permissões do jogador.
function AddTargetToProp(entity, chestUUID)
    local options, PlayerData, propData = {}, RSGCore.Functions.GetPlayerData(), localProps[chestUUID]
    if not PlayerData or not propData then return end
    
    local isOwner = propData.owner == PlayerData.citizenid
    local hasPermission = isOwner
    if not hasPermission and propData.shared_with then
        for _, sharedInfo in ipairs(propData.shared_with) do
            if type(sharedInfo) == 'table' and sharedInfo.citizenid == PlayerData.citizenid then hasPermission = true; break end
        end
    end

    -- Opções para quem tem permissão (dono ou compartilhado)
    if hasPermission then
        table.insert(options, { icon = "fas fa-box-open", label = "Abrir Baú", action = function() TriggerServerEvent('jx:chest:open', chestUUID) end })
    end

    -- Opções exclusivas para o DONO
    if isOwner then
        table.insert(options, { icon = "fas fa-share-alt", label = "Compartilhar Baú", action = function() OpenShareMenu(chestUUID) end })
        table.insert(options, { icon = "fas fa-users-cog", label = "Gerenciar Acesso", action = function() OpenManageShareMenu(chestUUID) end })
        
        local currentTier = propData.tier or 1
        if Config.Tiers[currentTier + 1] then -- Só mostra se houver um próximo nível de upgrade
            table.insert(options, {
                icon = "fas fa-arrow-alt-circle-up", label = "Melhorar Baú",
                action = function()
                    if lib.alertDialog({ header = 'Melhorar Baú', content = 'Deseja usar um kit para melhorar este baú?', centered = true, cancel = true }) == 'confirm' then
                        TriggerServerEvent('jx:chest:upgrade', chestUUID)
                    end
                end
            })
        end

        table.insert(options, { icon = "fas fa-trash-alt", label = "Remover Baú", action = function()
            if lib.alertDialog({ header = 'Remover Baú', content = 'Tem certeza? O baú deve estar vazio.', centered = true, cancel = true }) == 'confirm' then
                if lib.progressBar({ duration = Config.RemovalTime, label = "Removendo baú...", useWhileDead = false, canCancel = true }) then
                    TriggerServerEvent('jx:chest:remove', chestUUID)
                end
            end
        end })
    elseif not hasPermission then -- Opção para quem NÃO tem acesso
        table.insert(options, {
            icon = "fas fa-user-secret", label = "Tentar Arrombar",
            action = function() TriggerServerEvent('jx:chest:requestLockpick', chestUUID) end
        })
    end

    if #options > 0 then exports['rsg-target']:AddTargetEntity(entity, { options = options, distance = 2.0 }) end
end

-- =================================================================
-- HANDLERS DE EVENTOS DE REDE
-- =================================================================

RegisterNetEvent('chest:updateProps', function(propsFromServer)
    ClearAllProps()
    localProps = propsFromServer
    for chestUUID, propData in pairs(localProps) do
        local propModel = joaat(propData.model)
        RequestModel(propModel); while not HasModelLoaded(propModel) do Wait(10) end
        local prop = CreateObject(propModel, propData.coords.x, propData.coords.y, propData.coords.z, false, false, false)
        SetEntityHeading(prop, propData.heading or 0.0); FreezeEntityPosition(prop, true)
        propEntities[chestUUID] = prop; AddTargetToProp(prop, chestUUID)
    end
end)

RegisterNetEvent('chest:createProp', function(chestUUID, propData)
    if propEntities[chestUUID] and DoesEntityExist(propEntities[chestUUID]) then DeleteEntity(propEntities[chestUUID]) end
    localProps[chestUUID] = propData
    local propModel = joaat(propData.model)
    RequestModel(propModel); while not HasModelLoaded(propModel) do Wait(10) end
    local prop = CreateObject(propModel, propData.coords.x, propData.coords.y, propData.coords.z, false, false, false)
    SetEntityHeading(prop, propData.heading or 0.0); FreezeEntityPosition(prop, true)
    propEntities[chestUUID] = prop; AddTargetToProp(prop, chestUUID)
end)

RegisterNetEvent('chest:removePropClient', function(chestUUID)
    if propEntities[chestUUID] and DoesEntityExist(propEntities[chestUUID]) then
        pcall(function() exports['rsg-target']:RemoveTargetEntity(propEntities[chestUUID]) end)
        DeleteEntity(propEntities[chestUUID])
        propEntities[chestUUID], localProps[chestUUID] = nil, nil
    end
end)

RegisterNetEvent('jx:chest:showShareMenu', function(chestUUID, nearbyPlayers)
    if not nearbyPlayers or #nearbyPlayers == 0 then
        lib.notify({ type = 'warning', title = 'Aviso', description = 'Nenhum jogador próximo encontrado.' })
        return
    end
    local options = {}
    for _, player in ipairs(nearbyPlayers) do
        table.insert(options, {
            title = player.label, description = "Compartilhar acesso com este jogador.", icon = "fas fa-user-plus",
            onSelect = function() TriggerServerEvent('jx:chest:share', chestUUID, player.value) end
        })
    end
    lib.registerContext({ id = 'chest_share_menu', title = 'Compartilhar Baú Com...', options = options })
    lib.showContext('chest_share_menu')
end)

RegisterNetEvent('jx:chest:updateSharedList', function(chestUUID, newSharedList)
    if localProps[chestUUID] then
        localProps[chestUUID].shared_with = newSharedList
        local propEntity = propEntities[chestUUID]
        if propEntity and DoesEntityExist(propEntity) then
            exports['rsg-target']:RemoveTargetEntity(propEntity)
            AddTargetToProp(propEntity, chestUUID)
        end
    end
end)

RegisterNetEvent('jx:chest:startSkillCheck', function(chestUUID)
    local playerPed = PlayerPedId()
    local rounds = Config.LockpickSettings.SkillCheck.Rounds
    local keys = Config.LockpickSettings.SkillCheck.Keys
    local animDict = "script_re@bear_trap"
    local animClip = "action_loot_player"

    lib.playAnim(playerPed, animDict, animClip, 8.0, -8.0, -1, 1)

    -- Verifica se a tabela de teclas foi definida e não está vazia
    local skillCheckKeys = (keys and #keys > 0) and keys or nil
    TaskPlayAnim(playerPed, animDict, animClip, 8.0, -8.0, -1, 1, 0, false, false, false)

    -- ox_lib permite um único callback que retorna 'success' (true ou false)
    local function onComplete(success)
        --print(('Skill check %s for chest %s'):format(success and 'succeeded' or 'failed', chestUUID))
        TriggerServerEvent('jx:chest:resolveLockpick', chestUUID, success)
        StopAnimTask(playerPed, animDict, animClip, 1.0)
    end

    -- Inicia o skill check com os rounds e teclas customizadas
    local success = lib.skillCheck(rounds, skillCheckKeys, onComplete)
    if not success then
        lib.notify({ type = 'error', title = 'Falha no Arrombamento', description = 'Você quebrou seu lockpick.' })
        StopAnimTask(playerPed, animDict, animClip, 1.0)

    else
        lib.notify({ type = 'success', title = 'Sucesso', description = 'Você arrombou o baú!' })
         TriggerServerEvent('jx:chest:resolveLockpick', chestUUID, success)
         StopAnimTask(playerPed, animDict, animClip, 1.0)

    end
end)

RegisterNetEvent('rsg-chest:client:startPlacement', function() if not _G.PlacementMode then StartPlacementMode() end end)
RegisterNetEvent('chest:opened', function(chestUUID) currentOpenChest = chestUUID end)
RegisterNetEvent('inventory:client:closeInventory', function() if currentOpenChest then CloseCurrentChest() end end)

-- =================================================================
-- HANDLERS DE EVENTOS DO JOGO E DO RESOURCE
-- =================================================================

AddEventHandler('RSGCore:Client:OnPlayerLoaded', function() TriggerServerEvent('chest:requestAllProps') end)
AddEventHandler('onResourceStop', function(resourceName) if GetCurrentResourceName() == resourceName then ClearAllProps(); if currentOpenChest then CloseCurrentChest() end end end)