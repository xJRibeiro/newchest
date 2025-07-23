local RSGCore = exports['rsg-core']:GetCoreObject()

-- =================================================================
-- VARIÁVEIS E CACHE OTIMIZADOS
-- =================================================================

local propEntities, localProps, currentOpenChest = {}, {}, nil
local PlayerData = {}
local ModelCache = {}

-- =================================================================
-- FUNÇÕES AUXILIARES OTIMIZADAS
-- =================================================================

local function RequestModelSafe(model, timeout)
    timeout = timeout or 10000
    if ModelCache[model] then return true end
    
    RequestModel(model)
    local startTime = GetGameTimer()
    
    while not HasModelLoaded(model) do
        if GetGameTimer() - startTime > timeout then
            print(('[RSG-CHEST][ERROR] Timeout ao carregar modelo: %s'):format(model))
            return false
        end
        Wait(50)
    end
    
    ModelCache[model] = true
    return true
end

local function ValidateDistance(coords1, coords2, maxDistance)
    if not coords1 or not coords2 then return false end
    return #(coords1 - coords2) <= maxDistance
end

local function SafeDeleteEntity(entity)
    if DoesEntityExist(entity) then
        pcall(function() exports['rsg-target']:RemoveTargetEntity(entity) end)
        DeleteEntity(entity)
        return true
    end
    return false
end

-- =================================================================
-- FUNÇÕES PRINCIPAIS MELHORADAS
-- =================================================================

function OpenShareMenu(chestUUID)
    if not chestUUID or not localProps[chestUUID] then
        print(('[RSG-CHEST][WARNING] OpenShareMenu: chestUUID inválido'))
        return
    end
    
    local nearbyPlayerIds = {}
    local playerCoords = GetEntityCoords(PlayerPedId())
    local maxDistance = Config.ShareDistance or 5.0
    
    for _, id in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(id)
        if id ~= PlayerId() and DoesEntityExist(targetPed) then
            if ValidateDistance(playerCoords, GetEntityCoords(targetPed), maxDistance) then
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
                if lib.alertDialog({ 
                    header = 'Remover Acesso', 
                    content = ('Tem certeza que deseja remover o acesso de %s?'):format(sharedInfo.name), 
                    centered = true, 
                    cancel = true 
                }) == 'confirm' then
                    TriggerServerEvent('jx:chest:unshare', chestUUID, sharedInfo.citizenid)
                end
            end
        })
    end

    lib.registerContext({ id = 'chest_manage_share_menu', title = 'Gerenciar Acesso do Baú', options = options })
    lib.showContext('chest_manage_share_menu')
end

local function CloseCurrentChest()
    local chestToClose = currentOpenChest
    currentOpenChest = nil
    if not chestToClose then return end
    TriggerServerEvent('jx:chest:closeInventory', chestToClose)
end

function ClearAllProps()
    for chestUUID, entity in pairs(propEntities) do
        SafeDeleteEntity(entity)
        propEntities[chestUUID] = nil
    end
    localProps = {}
    print('[RSG-CHEST] Props limpos com segurança')
end

function AddTargetToProp(entity, chestUUID)
    if not DoesEntityExist(entity) or not chestUUID or not localProps[chestUUID] then
        print(('[RSG-CHEST][WARNING] AddTargetToProp: parâmetros inválidos'))
        return false
    end
    
    local options, propData = {}, localProps[chestUUID]
    
    if not PlayerData or not PlayerData.citizenid then
        PlayerData = RSGCore.Functions.GetPlayerData()
        if not PlayerData or not PlayerData.citizenid then
            print(('[RSG-CHEST][WARNING] PlayerData não encontrado'))
            return false
        end
    end
    
    local isOwner = propData.owner == PlayerData.citizenid
    local hasPermission = isOwner
    
    -- Verifica permissão compartilhada
    if not hasPermission and propData.shared_with then
        for _, sharedInfo in ipairs(propData.shared_with) do
            if type(sharedInfo) == 'table' and sharedInfo.citizenid == PlayerData.citizenid then 
                hasPermission = true
                break 
            end
        end
    end
    
    -- Opções baseadas em permissões
    if hasPermission then
        table.insert(options, { 
            icon = "fas fa-box-open", 
            label = "Abrir Baú", 
            action = function() TriggerServerEvent('jx:chest:open', chestUUID) end 
        })
    end
    
    if isOwner then
        table.insert(options, { 
            icon = "fas fa-share-alt", 
            label = "Compartilhar Baú", 
            action = function() OpenShareMenu(chestUUID) end 
        })
        
        table.insert(options, { 
            icon = "fas fa-users-cog", 
            label = "Gerenciar Acesso", 
            action = function() OpenManageShareMenu(chestUUID) end 
        })
        
        local currentTier = propData.tier or 1
        if Config.Tiers[currentTier + 1] then
            table.insert(options, {
                icon = "fas fa-arrow-alt-circle-up", 
                label = "Melhorar Baú",
                action = function()
                    if lib.alertDialog({ 
                        header = 'Melhorar Baú', 
                        content = 'Deseja usar um kit para melhorar este baú?', 
                        centered = true, 
                        cancel = true 
                    }) == 'confirm' then
                        TriggerServerEvent('jx:chest:upgrade', chestUUID)
                    end
                end
            })
        end
        
        table.insert(options, { 
            icon = "fas fa-trash-alt", 
            label = "Remover Baú", 
            action = function()
                if lib.alertDialog({ 
                    header = 'Remover Baú', 
                    content = 'Tem certeza? O baú deve estar vazio.', 
                    centered = true, 
                    cancel = true 
                }) == 'confirm' then
                    if lib.progressBar({ 
                        duration = Config.RemovalTime, 
                        label = "Removendo baú...", 
                        useWhileDead = false, 
                        canCancel = true 
                    }) then
                        TriggerServerEvent('jx:chest:remove', chestUUID)
                    end
                end
            end 
        })
    elseif not hasPermission then
        table.insert(options, {
            icon = "fas fa-user-secret", 
            label = "Tentar Arrombar",
            action = function() TriggerServerEvent('jx:chest:requestLockpick', chestUUID) end
        })
    end
    
    if #options > 0 then 
        exports['rsg-target']:AddTargetEntity(entity, { options = options, distance = 2.0 }) 
        return true
    end
    
    return false
end

-- =================================================================
-- EVENT HANDLERS OTIMIZADOS
-- =================================================================

RegisterNetEvent('chest:updateProps', function(propsFromServer)
    ClearAllProps()
    localProps = propsFromServer
    
    for chestUUID, propData in pairs(localProps) do
        local propModel = joaat(propData.model)
        
        if RequestModelSafe(propModel, 5000) then
            local prop = CreateObject(propModel, propData.coords.x, propData.coords.y, propData.coords.z, false, false, false)
            SetEntityHeading(prop, propData.heading or 0.0)
            FreezeEntityPosition(prop, true)
            
            propEntities[chestUUID] = prop
            AddTargetToProp(prop, chestUUID)
        else
            print(('[RSG-CHEST][ERROR] Falha ao carregar modelo para baú: %s'):format(chestUUID))
        end
    end
end)

RegisterNetEvent('chest:createProp', function(chestUUID, propData)
    if propEntities[chestUUID] and DoesEntityExist(propEntities[chestUUID]) then 
        SafeDeleteEntity(propEntities[chestUUID]) 
    end
    
    localProps[chestUUID] = propData
    local propModel = joaat(propData.model)
    
    if RequestModelSafe(propModel, 5000) then
        local prop = CreateObject(propModel, propData.coords.x, propData.coords.y, propData.coords.z, false, false, false)
        SetEntityHeading(prop, propData.heading or 0.0)
        FreezeEntityPosition(prop, true)
        
        propEntities[chestUUID] = prop
        AddTargetToProp(prop, chestUUID)
    end
end)

RegisterNetEvent('chest:removePropClient', function(chestUUID)
    if propEntities[chestUUID] and DoesEntityExist(propEntities[chestUUID]) then
        SafeDeleteEntity(propEntities[chestUUID])
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
            title = player.label, 
            description = "Compartilhar acesso com este jogador.", 
            icon = "fas fa-user-plus",
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
    
    if not DoesEntityExist(playerPed) or not chestUUID then
        print(('[RSG-CHEST][ERROR] Skill check: parâmetros inválidos'))
        return
    end
    
    local rounds = Config.LockpickSettings.SkillCheck.Rounds
    local keys = Config.LockpickSettings.SkillCheck.Keys
    local animDict = "script_re@bear_trap"
    local animClip = "action_loot_player"
    
    -- Carrega animação com segurança
    if not HasAnimDictLoaded(animDict) then
        RequestAnimDict(animDict)
        local timeout = GetGameTimer() + 5000
        while not HasAnimDictLoaded(animDict) and GetGameTimer() < timeout do
            Wait(50)
        end
        
        if not HasAnimDictLoaded(animDict) then
            print(('[RSG-CHEST][ERROR] Falha ao carregar animação: %s'):format(animDict))
            return
        end
    end
    
    TaskPlayAnim(playerPed, animDict, animClip, 8.0, -8.0, -1, 1, 0, false, false, false)
    
    -- Skill check com timeout
    local function onComplete(success)
        StopAnimTask(playerPed, animDict, animClip, 1.0)
        
        if success then
            lib.notify({ type = 'success', title = 'Sucesso', description = 'Você arrombou o baú!' })
        else
            lib.notify({ type = 'error', title = 'Falha no Arrombamento', description = 'Você quebrou seu lockpick.' })
        end
        
        TriggerServerEvent('jx:chest:resolveLockpick', chestUUID, success)
    end
    
    -- Timeout de segurança para o skill check
    CreateThread(function()
        Wait(30000) -- 30 segundos timeout
        StopAnimTask(playerPed, animDict, animClip, 1.0)
    end)
    
    local skillCheckKeys = (keys and #keys > 0) and keys or nil
    lib.skillCheck(rounds, skillCheckKeys, onComplete)
end)

RegisterNetEvent('rsg-chest:client:startPlacement', function() 
    if not _G.PlacementMode then StartPlacementMode() end 
end)

RegisterNetEvent('chest:opened', function(chestUUID) currentOpenChest = chestUUID end)

RegisterNetEvent('inventory:client:closeInventory', function() 
    if currentOpenChest then CloseCurrentChest() end 
end)

-- =================================================================
-- EVENT HANDLERS MODERNIZADOS PARA RSG CORE
-- =================================================================

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    PlayerData = RSGCore.Functions.GetPlayerData()
    TriggerServerEvent('chest:requestAllProps')
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    PlayerData = {}
    ClearAllProps()
    if currentOpenChest then CloseCurrentChest() end
end)

RegisterNetEvent('RSGCore:Player:SetPlayerData', function(val)
    PlayerData = val
end)

-- =================================================================
-- CLEANUP AUTOMÁTICO DE RECURSOS
-- =================================================================

CreateThread(function()
    while true do
        Wait(300000) -- 5 minutos
        for model, _ in pairs(ModelCache) do
            if HasModelLoaded(model) then
                SetModelAsNoLongerNeeded(model)
            end
        end
        ModelCache = {}
        collectgarbage("collect")
        print('[RSG-CHEST] Cache de modelos limpo automaticamente')
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        ClearAllProps()
        if currentOpenChest then CloseCurrentChest() end
        
        -- Cleanup final
        for model, _ in pairs(ModelCache) do
            if HasModelLoaded(model) then
                SetModelAsNoLongerNeeded(model)
            end
        end
        
        print('[RSG-CHEST] Recursos limpos na parada do resource')
    end
end)
