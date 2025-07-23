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

-- ✅ FUNÇÃO ADDTARGETTOPROP ATUALIZADA COM VERIFICAÇÃO DE ITEM
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
        
        -- ✅ NOVA OPÇÃO: Ver Registros (para quem tem permissão)
        table.insert(options, {
            icon = "fas fa-history",
            label = "Ver Registros",
            action = function() 
                TriggerServerEvent('jx:chest:requestPlayerLogs', chestUUID)
            end
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
        
        -- ✅ NOVA OPÇÃO: Renomear Baú
        table.insert(options, {
            icon = "fas fa-edit",
            label = "Renomear Baú",
            action = function()
                local input = lib.inputDialog('Renomear Baú', {
                    {
                        type = 'input',
                        label = 'Nome do Baú',
                        description = 'Digite o novo nome para seu baú',
                        placeholder = propData.custom_name or 'Meu Baú',
                        required = true,
                        min = 3,
                        max = 50
                    }
                })
                
                if input and input[1] then
                    local newName = input[1]:gsub("^%s*(.-)%s*$", "%1") -- Remove espaços extras
                    if #newName >= 3 and #newName <= 50 then
                        TriggerServerEvent('jx:chest:rename', chestUUID, newName)
                    else
                        lib.notify({ 
                            type = 'error', 
                            title = 'Erro', 
                            description = 'O nome deve ter entre 3 e 50 caracteres.' 
                        })
                    end
                end
            end
        })
        
        local currentDurability = propData.durability or 100
            if currentDurability < 100 then
                table.insert(options, {
                    disable = true,
                    icon = "fas fa-wrench",
                    label = string.format("Durabildade (%d/100)", currentDurability),
                  
                })
            end
        
        -- ✅ OPÇÃO: Reparar Baú (só aparece se durabilidade < 100)
        local currentDurability = propData.durability or 100
        if currentDurability < 100 then
            table.insert(options, {
                icon = "fas fa-tools",
                label = "Reparar Baú",
                action = function() 
                    ShowRepairMenu(chestUUID, currentDurability)
                end
            })
        end

        local currentTier = propData.tier or 1
        if Config.Tiers[currentTier + 1] then
            table.insert(options, {
                icon = "fas fa-arrow-alt-circle-up", 
                label = "Melhorar Baú",
                action = function()
                    local nextTier = currentTier + 1
                    local nextTierData = Config.Tiers[nextTier]
                    local currentTierData = Config.Tiers[currentTier]
                    
                    -- Converter peso de gramas para kg
                    local currentWeightKg = string.format("%.1f", currentTierData.weight / 1000)
                    local nextWeightKg = string.format("%.1f", nextTierData.weight / 1000)
                    
                    local upgradeContent = string.format(
                        'Deseja melhorar seu baú para **%s**?\n\n' ..
                        '**Upgrade:**\n' ..
                        '\nPeso: %s kg → **%s kg**\n' ..
                        '\nSlots: %d → **%d**\n\n' ..
                        'Esta ação consumirá um kit de upgrade.',
                        nextTierData.label,
                        currentWeightKg, nextWeightKg,
                        currentTierData.slots, nextTierData.slots
                    )
                    
                    if lib.alertDialog({ 
                        header = 'Melhorar Baú', 
                        content = upgradeContent,
                        centered = true, 
                        cancel = true,
                        size = 'md'
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
                    -- ✅ IMPLEMENTAR ANIMAÇÃO DE REMOÇÃO
                    RemoveChestWithAnimation(chestUUID)
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
-- CONFIRMAÇÃO DE REPARO
-- =================================================================

RegisterNetEvent('jx:chest:confirmRepair', function(chestUUID, currentDurability)
    local repairCost = 1
    local estimatedRepair = math.random(30, 50)
    local finalDurability = math.min(100, currentDurability + estimatedRepair)
    
    local confirmDialog = lib.alertDialog({
        header = 'Reparar Baú',
        content = string.format(
            '**Durabilidade Atual:** %d/100\n' ..
            '**Durabilidade Estimada:** %d/100\n\n' ..
            '**Custo:** %d x Kit de Reparo\n\n' ..
            'Deseja prosseguir com o reparo?',
            currentDurability,
            finalDurability,
            repairCost
        ),
        centered = true,
        cancel = true,
        size = 'md'
    })
    
    if confirmDialog == 'confirm' then
        TriggerServerEvent('jx:chest:performRepair', chestUUID)
    end
end)

-- =================================================================
-- FUNÇÃO PARA MOSTRAR REGISTROS DO JOGADOR
-- =================================================================

function ShowPlayerChestLogs(chestUUID, logs, stats)
    local options = {}
    
    -- Cabeçalho com estatísticas
    if stats and stats.totalLogs > 0 then
        table.insert(options, {
            title = '📊 Estatísticas do Baú',
            description = string.format('Total de ações: %d\nÚltima ação: %s', 
                stats.totalLogs, 
                stats.lastAction and stats.lastAction or 'Nunca'
            ),
            icon = 'chart-bar',
            disabled = true
        })
        

    end
    
    if not logs or #logs == 0 then
        table.insert(options, { 
            title = 'Nenhum registro encontrado', 
            description = 'Este baú não possui histórico de ações',
            disabled = true, 
            icon = 'inbox' 
        })
    else
        for _, log in ipairs(logs) do
            local title = string.format('%s %s', log.icon, log.action_description)
            local description = string.format('%s\n%s', log.actor_name, log.formatted_date)
            
            if log.target_name then
                description = description .. ' → ' .. log.target_name
            end
            
            table.insert(options, {
                title = title,
                description = description,
                icon = 'file-alt',
                disabled = true,
                metadata = log.details and {
                    { label = 'Detalhes', value = log.details }
                } or nil
            })
        end
    end
    
    -- Botão para fechar
    table.insert(options, {
        title = 'Fechar',
        icon = 'times',
        onSelect = function()
            lib.hideContext()
        end
    })
    
    lib.registerContext({ 
        id = 'player_chest_logs_menu', 
        title = 'Registros do Baú (' .. (stats and stats.totalLogs or 0) .. ')', 
        options = options 
    })
    lib.showContext('player_chest_logs_menu')
end

-- =================================================================
-- CONFIRMAÇÃO DE UPGRADE
-- =================================================================
RegisterNetEvent('jx:chest:confirmUpgrade', function(chestUUID, itemAmount, itemLabel)
    local currentTier = localProps[chestUUID] and localProps[chestUUID].tier or 1
    local nextTier = currentTier + 1
    local nextTierData = Config.Tiers[nextTier]
    
    if not nextTierData then return end
    
    local confirmDialog = lib.alertDialog({
        header = 'Melhorar Baú',
        content = string.format(
            'Deseja melhorar seu baú para **%s**?\n\n' ..
            '**Melhorias:**\n\n' ..
            'Peso: %s kg\n' ..
            '\nSlots: %d',
            nextTierData.label,
            string.format('%.1f', nextTierData.weight / 1000),
            nextTierData.slots
        ),
        centered = true,
        cancel = true,
        size = 'md'
    })
    
    if confirmDialog == 'confirm' then
        TriggerServerEvent('jx:chest:upgrade', chestUUID)
    end
end)

-- =================================================================
-- FUNÇÃO DE UPGRADE COM ANIMAÇÃO
-- =================================================================

function UpgradeChestWithAnimation(chestUUID)
    local ped = PlayerPedId()
    
    -- ✅ ANIMAÇÃO ESPECÍFICA PARA UPGRADE
    local animDict = "amb_work@world_human_crouch_inspect@male_a@base"
    local animName = "base"
    
    -- Animações de fallback
    local animations = {
        {dict = animDict, anim = animName},
        {dict = "script_re@craft@crafting_fallback", anim = "craft_trans_kneel_to_squat"},
        {dict = "amb_work@world_human_hammer@male_a@base", anim = "base"}
    }
    
    local animLoaded = false

    FreezeEntityPosition(ped, true)

    -- ✅ CARREGAR ANIMAÇÃO ESPECIFICADA
    for _, animData in ipairs(animations) do
        RequestAnimDict(animData.dict)
        local attempts = 0
        while not HasAnimDictLoaded(animData.dict) and attempts < 50 do
            Wait(10)
            attempts = attempts + 1
        end
        
        if HasAnimDictLoaded(animData.dict) then
            TaskPlayAnim(ped, animData.dict, animData.anim, 8.0, -8.0, -1, 1, 0, false, false, false)
            animLoaded = true
            print(('[RSG-CHEST] Animação de upgrade carregada: %s -> %s'):format(animData.dict, animData.anim))
            break
        end
    end
    
    -- ✅ FALLBACK PARA CENÁRIO SE ANIMAÇÕES FALHAREM
    if not animLoaded then
        print('[RSG-CHEST] Usando cenário como fallback para upgrade')
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CROUCH_INSPECT", 0, true)
    end

    Wait(500) -- Tempo para animação começar

    -- ✅ SOM DE TRABALHO/UPGRADE
    local duration = 3000 -- 3 segundos para upgrade
    local interval = 800
    local elapsed = 0

    CreateThread(function()
        while elapsed < duration do
            -- Som de ferramentas/trabalho
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "hammer", 0.4)
            Wait(interval)
            elapsed = elapsed + interval
        end
    end)

    -- ✅ PROGRESS BAR COM POSSIBILIDADE DE CANCELAR
    local success = lib.progressBar({
        duration = duration,
        label = "Melhorando baú...",
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        }
    })

    -- ✅ LIMPEZA DAS ANIMAÇÕES
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    StopAnimTask(ped, "", "", 1.0)
    FreezeEntityPosition(ped, false)

    -- ✅ PROCESSAR RESULTADO
    if success then
        TriggerServerEvent('jx:chest:processUpgrade', chestUUID)
    else
        lib.notify({ 
            type = 'inform', 
            title = 'Cancelado', 
            description = 'Upgrade do baú cancelado.' 
        })
    end
end

-- ✅ REGISTRAR EVENTO PARA INICIAR ANIMAÇÃO
RegisterNetEvent('jx:chest:startUpgradeAnimation', function(chestUUID)
    UpgradeChestWithAnimation(chestUUID)
end)


-- =================================================================
-- FUNÇÃO DE REMOÇÃO COM ANIMAÇÃO
-- =================================================================

function RemoveChestWithAnimation(chestUUID)
    local ped = PlayerPedId()
    
    -- ✅ ANIMAÇÕES TESTADAS PARA REMOÇÃO/DESMONTAGEM
    local animations = {

        {dict = "amb_work@world_human_crouch_inspect@male_a@base", anim = "base"},
    }
    
    local animLoaded = false

    FreezeEntityPosition(ped, true)

    -- ✅ TENTAR CARREGAR ANIMAÇÕES EM ORDEM DE PREFERÊNCIA
    for _, animData in ipairs(animations) do
        RequestAnimDict(animData.dict)
        local attempts = 0
        while not HasAnimDictLoaded(animData.dict) and attempts < 50 do
            Wait(10)
            attempts = attempts + 1
        end
        
        if HasAnimDictLoaded(animData.dict) then
            TaskPlayAnim(ped, animData.dict, animData.anim, 8.0, -8.0, -1, 1, 0, false, false, false)
            animLoaded = true
            print(('[RSG-CHEST] Animação de remoção carregada: %s -> %s'):format(animData.dict, animData.anim))
            break
        end
    end
    
    -- ✅ FALLBACK PARA CENÁRIO SE ANIMAÇÕES FALHAREM
    if not animLoaded then
        print('[RSG-CHEST] Usando cenário como fallback para remoção')
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CROUCH_INSPECT", 0, true)
    end

    Wait(100) -- Dar tempo para a animação começar

    -- ✅ SOM DE MARTELO/DESMONTAGEM DURANTE A REMOÇÃO
    local duration = Config.RemovalTime or 2000
    local interval = 800 -- Intervalo entre marteladas
    local elapsed = 0

    CreateThread(function()
        while elapsed < duration do
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "hammer", 0.5)
            Wait(interval)
            elapsed = elapsed + interval
        end
    end)

    -- ✅ PROGRESS BAR SEM CONFLITO COM ANIMAÇÃO
    local success = lib.progressBar({
        duration = duration,
        label = "Removendo baú...",
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        }
    })

    -- ✅ LIMPEZA COMPLETA DAS ANIMAÇÕES
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    StopAnimTask(ped, "", "", 1.0)
    FreezeEntityPosition(ped, false)

    -- ✅ PROCESSAR RESULTADO
    if success then
        TriggerServerEvent('jx:chest:remove', chestUUID)
    else
        lib.notify({ 
            type = 'inform', 
            title = 'Cancelado', 
            description = 'Remoção do baú cancelada.' 
        })
    end
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
    
    -- Animação de lockpick
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
    
    -- Inicia animação
    TaskPlayAnim(playerPed, animDict, animClip, 8.0, -8.0, -1, 1, 0, false, false, false)
    
    -- ✅ USAR RSG-LOCKPICK COM EXPORT FUNCTION
    CreateThread(function()
        local success = exports['rsg-lockpick']:start()
        
        -- Para a animação
        StopAnimTask(playerPed, animDict, animClip, 1.0)
        
        -- Processa o resultado
        if success then
            lib.notify({ 
                type = 'success', 
                title = 'Sucesso', 
                description = Config.LockpickSettings.SuccessMessage or 'Você conseguiu arrombar o baú!' 
            })
        else
            lib.notify({ 
                type = 'error', 
                title = 'Falhou', 
                description = Config.LockpickSettings.FailMessage or 'Você falhou em arrombar o baú e quebrou seu lockpick.' 
            })
        end
        
        -- Envia resultado para o servidor
        TriggerServerEvent('jx:chest:resolveLockpick', chestUUID, success)
    end)
end)

-- Event handler para receber os logs
RegisterNetEvent('jx:chest:showPlayerLogs', function(chestUUID, logs, stats)
    ShowPlayerChestLogs(chestUUID, logs, stats)
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

-- =================================================================
-- SISTEMA DE REPARO
-- =================================================================

function ShowRepairMenu(chestUUID, currentDurability)
    local options = {
        {
            title = 'Estado Atual',
            description = ('Durabilidade: %d%%'):format(currentDurability),
            icon = 'info-circle',
            disabled = true
        },

        {
            title = 'Kit Básico de Reparo',
            description = 'Restaura 15% de durabilidade',
            icon = 'hammer',
            onSelect = function()
                TriggerServerEvent('jx:chest:repairChest', chestUUID, 'basic')
            end
        },
        {
            title = 'Kit Avançado de Reparo',
            description = 'Restaura 35% de durabilidade',
            icon = 'wrench',
            onSelect = function()
                TriggerServerEvent('jx:chest:repairChest', chestUUID, 'advanced')
            end
        },
        {
            title = 'Kit Profissional de Reparo',
            description = 'Restaura 60% de durabilidade',
            icon = 'cogs',
            onSelect = function()
                TriggerServerEvent('jx:chest:repairChest', chestUUID, 'master')
            end
        }
    }
    
    lib.registerContext({
        id = 'chest_repair_menu',
        title = 'Reparar Baú',
        options = options
    })
    lib.showContext('chest_repair_menu')
end

-- Event handler para atualizar durabilidade
RegisterNetEvent('jx:chest:updateChestDurability', function(chestUUID, newDurability)
    if localProps[chestUUID] then
        localProps[chestUUID].durability = newDurability
        
        -- Atualiza visualmente se necessário
        local propEntity = propEntities[chestUUID]
        if propEntity and DoesEntityExist(propEntity) then
            -- Aplicar efeito visual baseado na durabilidade
            ApplyDurabilityVisualEffect(propEntity, newDurability)
        end
    end
end)

function ApplyDurabilityVisualEffect(entity, durability)
    if not DoesEntityExist(entity) then return end
    
    -- Efeito visual baseado na durabilidade
    if durability <= 10 then
        -- Muito danificado - transparência e efeito vermelho
        SetEntityAlpha(entity, 180, false)
    elseif durability <= 25 then
        -- Danificado - transparência leve
        SetEntityAlpha(entity, 200, false)
    else
        -- Normal
        SetEntityAlpha(entity, 255, false)
    end
end

-- =================================================================
-- SISTEMA DE REPARO
-- =================================================================

function ShowRepairMenu(chestUUID, currentDurability)
    local options = {
        {
            title = 'Estado Atual',
            description = ('Durabilidade: %d%%'):format(currentDurability),
            icon = 'info-circle',
            disabled = true
        },

        {
            title = 'Kit Básico de Reparo',
            description = 'Restaura 15% de durabilidade',
            icon = 'hammer',
            onSelect = function()
                TriggerServerEvent('jx:chest:repairChest', chestUUID, 'basic')
            end
        },
        {
            title = 'Kit Avançado de Reparo',
            description = 'Restaura 35% de durabilidade',
            icon = 'wrench',
            onSelect = function()
                TriggerServerEvent('jx:chest:repairChest', chestUUID, 'advanced')
            end
        },
        {
            title = 'Kit Profissional de Reparo',
            description = 'Restaura 60% de durabilidade',
            icon = 'cogs',
            onSelect = function()
                TriggerServerEvent('jx:chest:repairChest', chestUUID, 'master')
            end
        }
    }
    
    lib.registerContext({
        id = 'chest_repair_menu',
        title = 'Reparar Baú',
        options = options
    })
    lib.showContext('chest_repair_menu')
end

-- Event handler para atualizar durabilidade
RegisterNetEvent('jx:chest:updateChestDurability', function(chestUUID, newDurability)
    if localProps[chestUUID] then
        localProps[chestUUID].durability = newDurability
        
        -- Atualiza visualmente se necessário
        local propEntity = propEntities[chestUUID]
        if propEntity and DoesEntityExist(propEntity) then
            -- Aplicar efeito visual baseado na durabilidade
            ApplyDurabilityVisualEffect(propEntity, newDurability)
        end
    end
end)

function ApplyDurabilityVisualEffect(entity, durability)
    if not DoesEntityExist(entity) then return end
    
    -- Efeito visual baseado na durabilidade
    if durability <= 10 then
        -- Muito danificado - transparência e efeito vermelho
        SetEntityAlpha(entity, 180, false)
    elseif durability <= 25 then
        -- Danificado - transparência leve
        SetEntityAlpha(entity, 200, false)
    else
        -- Normal
        SetEntityAlpha(entity, 255, false)
    end
end


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
