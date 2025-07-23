local RSGCore = exports['rsg-core']:GetCoreObject()

-- Variáveis globais do sistema de placement
local PlacementMode = false
local PreviewObject = nil
local ActiveChests = {}
local confirmed = false
local heading = 0.0

-- Sistema de prompts nativo do RedM
local PromptPlacerGroup = GetRandomIntInRange(0, 0xffffff)
local SetPrompt, CancelPrompt, RotateLeftPrompt, RotateRightPrompt

-- =================================================================
-- FUNÇÕES DE CONTROLE DE PROMPTS NATIVOS
-- =================================================================

-- Criar prompts de controle na inicialização
CreateThread(function()
    CreateSetPrompt()
    CreateCancelPrompt()
    CreateRotateLeftPrompt()
    CreateRotateRightPrompt()
end)

function CreateSetPrompt()
    CreateThread(function()
        local str = 'Confirmar Posição'
        SetPrompt = PromptRegisterBegin()
        PromptSetControlAction(SetPrompt, 0xC7B5340A) -- ENTER
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(SetPrompt, str)
        PromptSetEnabled(SetPrompt, true)
        PromptSetVisible(SetPrompt, true)
        PromptSetHoldMode(SetPrompt, true)
        PromptSetGroup(SetPrompt, PromptPlacerGroup)
        PromptRegisterEnd(SetPrompt)
    end)
end

function CreateCancelPrompt()
    CreateThread(function()
        local str = 'Cancelar'
        CancelPrompt = PromptRegisterBegin()
        PromptSetControlAction(CancelPrompt, 0x156F7119) -- BOTÃO DIREITO DO MOUSE
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(CancelPrompt, str)
        PromptSetEnabled(CancelPrompt, true)
        PromptSetVisible(CancelPrompt, true)
        PromptSetHoldMode(CancelPrompt, true)
        PromptSetGroup(CancelPrompt, PromptPlacerGroup)
        PromptRegisterEnd(CancelPrompt)
    end)
end

function CreateRotateLeftPrompt()
    CreateThread(function()
        local str = 'Girar para Esquerda'
        RotateLeftPrompt = PromptRegisterBegin()
        PromptSetControlAction(RotateLeftPrompt, 0xA65EBAB4) -- LEFT ARROW
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(RotateLeftPrompt, str)
        PromptSetEnabled(RotateLeftPrompt, true)
        PromptSetVisible(RotateLeftPrompt, true)
        PromptSetStandardMode(RotateLeftPrompt, true)
        PromptSetGroup(RotateLeftPrompt, PromptPlacerGroup)
        PromptRegisterEnd(RotateLeftPrompt)
    end)
end

function CreateRotateRightPrompt()
    CreateThread(function()
        local str = 'Girar para Direita'
        RotateRightPrompt = PromptRegisterBegin()
        PromptSetControlAction(RotateRightPrompt, 0xDEB34313) -- RIGHT ARROW
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(RotateRightPrompt, str)
        PromptSetEnabled(RotateRightPrompt, true)
        PromptSetVisible(RotateRightPrompt, true)
        PromptSetStandardMode(RotateRightPrompt, true)
        PromptSetGroup(RotateRightPrompt, PromptPlacerGroup)
        PromptRegisterEnd(RotateRightPrompt)
    end)
end

-- =================================================================
-- FUNÇÕES AUXILIARES DE RAYCAST E VISUALIZAÇÃO MELHORADAS
-- =================================================================

function RotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

-- ✅ NOVA FUNÇÃO: Texto 3D Melhorado com Cores
function DrawText3D(coords, text, color)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 1.0)
    local camCoords = GetGameplayCamCoord()
    local distance = #(camCoords - coords)
    local scale = (1 / distance) * 2
    local fov = (1 / GetGameplayCamFov()) * 100
    scale = scale * fov
    
    if onScreen then
        SetTextScale(0.0 * scale, 0.35 * scale)
        SetTextFontForCurrentCommand(6)
        SetTextColor(color.r, color.g, color.b, color.a)
        SetTextCentre(true)
        DisplayText(CreateVarString(10, "LITERAL_STRING", text), _x, _y)
    end
end

-- ✅ MELHORADA: Função de eixos com cores baseadas na validade
function DrawPropAxes(prop, isValid)
    if not DoesEntityExist(prop) then return end
    
    local propForward, propRight, propUp, propCoords = GetEntityMatrix(prop)
    
    -- Cores baseadas na validade
    local axisIntensity = isValid and 255 or 150
    local mainColor = isValid and {0, 255, 0} or {255, 0, 0} -- Verde válido, Vermelho inválido
    
    -- Eixos de visualização
    local propXAxisEnd = propCoords + propRight * 1.5
    local propYAxisEnd = propCoords + propForward * 1.5
    local propZAxisEnd = propCoords + propUp * 1.5
    
    -- Desenhar linhas dos eixos com cores da validade
    DrawLine(propCoords.x, propCoords.y, propCoords.z + 0.1, propXAxisEnd.x, propXAxisEnd.y, propXAxisEnd.z, 
             mainColor[1], mainColor[2], mainColor[3], axisIntensity)
    DrawLine(propCoords.x, propCoords.y, propCoords.z + 0.1, propYAxisEnd.x, propYAxisEnd.y, propYAxisEnd.z, 
             mainColor[1], mainColor[2], mainColor[3], axisIntensity)
    DrawLine(propCoords.x, propCoords.y, propCoords.z + 0.1, propZAxisEnd.x, propZAxisEnd.y, propZAxisEnd.z, 
             mainColor[1], mainColor[2], mainColor[3], axisIntensity)
end

-- ✅ NOVA FUNÇÃO: Círculo no chão para indicar área de influência
function DrawGroundCircle(coords, radius, isValid)
    local color = isValid and {0, 255, 0, 100} or {255, 0, 0, 100}
    
    -- Desenhar círculo no chão com múltiplas linhas
    local segments = 32
    local lastX, lastY = nil, nil
    
    for i = 0, segments do
        local angle = (i / segments) * (2 * math.pi)
        local x = coords.x + math.cos(angle) * radius
        local y = coords.y + math.sin(angle) * radius
        local z = coords.z + 0.05
        
        if lastX and lastY then
            DrawLine(lastX, lastY, z, x, y, z, color[1], color[2], color[3], color[4])
        end
        
        lastX, lastY = x, y
    end
end

-- ✅ NOVA FUNÇÃO: Efeito de "pulso" visual
function DrawValidationPulse(coords, isValid, gameTime)
    local pulseIntensity = math.abs(math.sin(gameTime * 0.005)) * 0.5 + 0.5
    local color = isValid and {0, 255, 0} or {255, 0, 0}
    local alpha = math.floor(pulseIntensity * 150)
    
    -- Desenhar esferas de diferentes tamanhos para criar efeito de pulso
    DrawMarker(28, coords.x, coords.y, coords.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
               0.5, 0.5, 0.5, color[1], color[2], color[3], alpha, false, true, 2, false, nil, nil, false)
end

function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = {
        x = cameraCoord.x + direction.x * distance,
        y = cameraCoord.y + direction.y * distance,
        z = cameraCoord.z + direction.z * distance
    }
    local a, b, c, d, e = GetShapeTestResult(StartShapeTestRay(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, -1, PlayerPedId(), 0))
    return b, c, e
end

local function GetGroundZ(coords)
    local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    return groundZ
end

local function RequestModelSafe(model, timeout)
    timeout = timeout or 10000
    RequestModel(model)
    local startTime = GetGameTimer()
    
    while not HasModelLoaded(model) do
        if GetGameTimer() - startTime > timeout then
            print(('[RSG-CHEST][ERROR] Timeout ao carregar modelo: %s'):format(model))
            return false
        end
        Wait(50)
    end
    return true
end

-- =================================================================
-- FUNÇÕES PRINCIPAIS DE PLACEMENT COM FEEDBACK VISUAL
-- =================================================================

function StartPlacementMode()
    if PlacementMode then return end

    PlacementMode = true
    confirmed = false
    heading = 0.0
    
    -- Solicita lista de baús ativos para validação
    TriggerServerEvent('rsg-chest:server:getActiveChests')

    local propModel = joaat(Config.ChestProp)
    
    if not RequestModelSafe(propModel, 5000) then
        lib.notify({ title = 'Erro', description = 'Falha ao carregar modelo do baú.', type = 'error' })
        PlacementMode = false
        return
    end

    -- Raycast inicial para posição
    local hit, coords, entity = RayCastGamePlayCamera(Config.PlacementDistance or 1000.0)
    
    if not hit or not coords then
        lib.notify({ title = 'Erro', description = 'Mire para um local válido.', type = 'error' })
        PlacementMode = false
        SetModelAsNoLongerNeeded(propModel)
        return
    end

    -- Ajustar coordenadas ao chão
    local groundZ = GetGroundZ(coords)
    coords = vector3(coords.x, coords.y, groundZ)

    -- Criar objeto de preview
    PreviewObject = CreateObject(propModel, coords.x, coords.y, coords.z, true, false, true)
    SetEntityAlpha(PreviewObject, 150, false)
    SetEntityCollision(PreviewObject, false, false)
    FreezeEntityPosition(PreviewObject, true)

    -- Thread principal de placement com feedback visual aprimorado
    CreateThread(function()
        while PlacementMode and not confirmed do
            local hit, coords, entity = RayCastGamePlayCamera(Config.PlacementDistance or 1000.0)
            local gameTime = GetGameTimer()
            
            if hit and coords and DoesEntityExist(PreviewObject) then
                local groundZ = GetGroundZ(coords)
                local finalCoords = vector3(coords.x, coords.y, groundZ)
                
                SetEntityCoordsNoOffset(PreviewObject, coords.x, coords.y, groundZ, false, false, false, true)
                SetEntityHeading(PreviewObject, heading)
                
                -- Validar se a posição é válida
                local normalizedCoords = vector3(
                    tonumber(string.format("%.2f", coords.x)),
                    tonumber(string.format("%.2f", coords.y)),
                    tonumber(string.format("%.2f", groundZ))
                )
                
                local isValid = IsValidPlacement(normalizedCoords)
                
                -- ✅ FEEDBACK VISUAL MELHORADO
                -- 1. Transparência e cor do objeto
                if isValid then
                    SetEntityAlpha(PreviewObject, 220, false)
                    -- Aplicar cor verde (válido)
                    SetEntityProofs(PreviewObject, false, false, false, false, false, false, 0, false)
                else
                    SetEntityAlpha(PreviewObject, 120, false)
                    -- Aplicar cor vermelha (inválido) - usando alpha diferente para simular cor
                end
                
                -- 2. Desenhar eixos com cores da validade
              --  DrawPropAxes(PreviewObject, isValid)
                
                -- 3. Círculo no chão indicando área
                DrawGroundCircle(finalCoords, Config.MaxDistance or 2.0, isValid)
                
                -- 4. Efeito de pulso visual
                DrawValidationPulse(finalCoords, isValid, gameTime)
                
                -- 5. Texto 3D indicando status
                local statusText = isValid and "~g~LOCAL VÁLIDO~s~" or "~r~LOCAL INVÁLIDO~s~"
                local textColor = isValid and {r = 0, g = 255, b = 0, a = 255} or {r = 255, g = 0, b = 0, a = 255}
                DrawText3D(finalCoords, statusText, textColor)
                
               
                -- Mostrar prompts nativos
                local PropPlacerGroupName = CreateVarString(10, 'LITERAL_STRING', 'Posicionar Baú')
                PromptSetActiveGroupThisFrame(PromptPlacerGroup, PropPlacerGroupName)
                
                -- Controle de rotação
                if IsControlPressed(1, 0xA65EBAB4) then -- Seta esquerda
                    heading = heading + 1.0
                    if heading > 360.0 then heading = 0.0 end
                elseif IsControlPressed(1, 0xDEB34313) then -- Seta direita
                    heading = heading - 1.0
                    if heading < 0.0 then heading = 360.0 end
                end
                
                -- Confirmar posição
                if PromptHasHoldModeCompleted(SetPrompt) and isValid then
                    confirmed = true
                    PlaceChest(normalizedCoords, heading)
                    break
                elseif PromptHasHoldModeCompleted(SetPrompt) and not isValid then
                    lib.notify({ 
                        title = 'Local Inválido', 
                        description = 'Não é possível colocar o baú neste local. Muito próximo de outro baú.', 
                        type = 'error' 
                    })
                end
                
                -- Cancelar placement
                if PromptHasHoldModeCompleted(CancelPrompt) then
                    CancelPlacement()
                    break
                end
            else
                -- Feedback quando não está mirando em local válido
                local playerCoords = GetEntityCoords(PlayerPedId())
                DrawText3D(vector3(playerCoords.x, playerCoords.y, playerCoords.z + 2.0), 
                          "~r~Mire para um local válido~s~", 
                          {r = 255, g = 0, b = 0, a = 255})
            end
            
            Wait(0)
        end
        
        -- Cleanup
        if DoesEntityExist(PreviewObject) then
            DeleteObject(PreviewObject)
            PreviewObject = nil
        end
        SetModelAsNoLongerNeeded(propModel)
        PlacementMode = false
    end)
end

exports('StartPlacementMode', StartPlacementMode)

function IsValidPlacement(coords)
    for _, chestCoords in pairs(ActiveChests) do
        local vChest = vector3(
            tonumber(string.format("%.2f", chestCoords.x)),
            tonumber(string.format("%.2f", chestCoords.y)),
            tonumber(string.format("%.2f", chestCoords.z))
        )

        if #(coords - vChest) < (Config.MaxDistance or 2.0) then
            return false
        end
    end
    return true
end

function PlaceChest(coords, heading)
    PlacementMode = false
    local ped = PlayerPedId()
    
    -- ✅ ANIMAÇÕES QUE FUNCIONAM NO RDR3
    local animations = {
        {dict = "amb_work@world_human_crouch_inspect@male_a@base", anim = "base"},

    }
    
    local animLoaded = false

    RequestModel(joaat(Config.ChestProp))
    while not HasModelLoaded(joaat(Config.ChestProp)) do Wait(10) end

    FreezeEntityPosition(ped, true)

    -- ✅ TENTAR CARREGAR ANIMAÇÕES EM ORDEM
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
            break
        end
    end
    
    -- ✅ FALLBACK PARA CENÁRIO SE ANIMAÇÕES FALHAREM
    if not animLoaded then
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CROUCH_INSPECT", 0, true)
    end

    Wait(500) -- Dar tempo para a animação começar

    -- Som de martelada
    local duration = Config.PlacementTime or 3000
    local interval = 900
    local elapsed = 0

    CreateThread(function()
        while elapsed < duration do
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "hammer", 0.6)
            Wait(interval)
            elapsed = elapsed + interval
        end
    end)

    local success = lib.progressBar({
        duration = duration,
        label = Config.Lang['placing_chest'] or 'Colocando baú...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        }
    })

    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    StopAnimTask(ped, "", "", 1.0)
    FreezeEntityPosition(ped, false)

    if success then
        local normCoords = {
            x = tonumber(string.format("%.2f", coords.x)),
            y = tonumber(string.format("%.2f", coords.y)),
            z = tonumber(string.format("%.2f", coords.z))
        }
        TriggerServerEvent('rsg-chest:server:placeChest', normCoords, heading)
    else
        CancelPlacement()
    end
end


function CancelPlacement()
    PlacementMode = false
    confirmed = false
    
    lib.notify({ 
        title = 'Cancelado', 
        description = Config.Lang['placement_cancelled'] or 'Colocação do baú cancelada.', 
        type = 'inform' 
    })
    
    local ped = PlayerPedId()
    if ped then
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
    end
    
    if DoesEntityExist(PreviewObject) then
        DeleteObject(PreviewObject)
        PreviewObject = nil
    end
end

-- =================================================================
-- EVENT HANDLERS
-- =================================================================

RegisterNetEvent('rsg-chest:client:receiveActiveChests', function(chests)
    ActiveChests = {}
    for _, chest in pairs(chests) do
        table.insert(ActiveChests, chest.coords)
    end
end)

-- =================================================================
-- CLEANUP E SEGURANÇA
-- =================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if DoesEntityExist(PreviewObject) then
            DeleteObject(PreviewObject)
        end
        PlacementMode = false
        confirmed = false
    end
end)
