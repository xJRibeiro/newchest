local PlacementMode = false
local PreviewObject = nil
local ActiveChests = {}

local function RequestAndLoadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        local attempts = 0
        while not HasAnimDictLoaded(dict) and attempts < 100 do
            Wait(10)
            attempts = attempts + 1
        end
    end
end


local function DrawText3D(x, y, z, text)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.35, 0.35)
    SetTextFontForCurrentCommand(6)
    SetTextColor(255, 255, 255, 215)
    SetTextCentre(true)
    DisplayText(CreateVarString(10, "LITERAL_STRING", text), 0.0, 0.0)
    ClearDrawOrigin()
end

local function RayCastGamePlayCamera(distance)
    local camRot = GetGameplayCamRot()
    local camCoord = GetGameplayCamCoord()
    local dir = vector3(-math.sin(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
    math.cos(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
    math.sin(math.rad(camRot.x)))
    local dest = camCoord + dir * distance
    local ray = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords = GetShapeTestResult(ray)
    return hit, endCoords
end

local function GetGroundZ(coords)
    local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    return groundZ
end

function StartPlacementMode()
    if PlacementMode then return end
    PlacementMode = true
    TriggerServerEvent('rsg-chest:server:getActiveChests')

    local propModel = joaat(Config.ChestProp)
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do Wait(0) end

    local _, coords = RayCastGamePlayCamera(Config.PlacementDistance)
    if not coords then
        lib.notify({ title = 'Erro', description = 'Mire para um local válido.', type = 'error' })
        PlacementMode = false
        SetModelAsNoLongerNeeded(propModel)
        return
    end

    PreviewObject = CreateObject(propModel, coords, false, false, false)
    SetEntityAlpha(PreviewObject, 180, false)
    SetEntityCollision(PreviewObject, false, false)
    FreezeEntityPosition(PreviewObject, true)

    local heading = GetEntityHeading(PlayerPedId())
    CreateThread(function()
        while PlacementMode do
            Wait(0)
            local currentHit, currentCoords = RayCastGamePlayCamera(Config.PlacementDistance)
            if currentHit and DoesEntityExist(PreviewObject) then
                local groundZ = GetGroundZ(currentCoords)
                SetEntityCoordsNoOffset(PreviewObject, currentCoords.x, currentCoords.y, groundZ, false, false, false, true)
                SetEntityHeading(PreviewObject, heading)
                local isValid = IsValidPlacement(vector3(
                    tonumber(string.format("%.2f", currentCoords.x)),
                    tonumber(string.format("%.2f", currentCoords.y)),
                    tonumber(string.format("%.2f", groundZ))
                ))
                SetEntityAlpha(PreviewObject, isValid and 220 or 100, false)
                local helpText = "~y~Posicione seu baú~s~\n~b~← →~s~ Girar\n"
                helpText = helpText .. (isValid and "~g~ENTER~s~ Confirmar" or "~r~Local Inválido")
                helpText = helpText .. "\n~r~BACKSPACE~s~ Cancelar"
                DrawText3D(currentCoords.x, currentCoords.y, groundZ + 0.5, helpText)
                if IsControlPressed(0, 0xA65EBAB4) then heading = (heading + 1) % 360.0 end
                if IsControlPressed(0, 0xDEB34313) then heading = (heading - 1 + 360.0) % 360.0 end
                if IsControlJustPressed(0, 0xC7B5340A) and isValid then
                    PlaceChest(vector3(
                        tonumber(string.format("%.2f", GetEntityCoords(PreviewObject).x)),
                        tonumber(string.format("%.2f", GetEntityCoords(PreviewObject).y)),
                        tonumber(string.format("%.2f", GetEntityCoords(PreviewObject).z))
                    ), heading)
                    break
                end
            else
                DrawText3D(GetEntityCoords(PlayerPedId()).x, GetEntityCoords(PlayerPedId()).y, GetEntityCoords(PlayerPedId()).z + 1.0, "~r~Mire em um local válido.")
            end
            if IsControlJustPressed(0, 0x156F7119) then
                CancelPlacement()
                break
            end
        end
        PlacementMode = false
        if DoesEntityExist(PreviewObject) then DeleteEntity(PreviewObject); PreviewObject = nil end
        SetModelAsNoLongerNeeded(propModel)
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
        if #(coords - vChest) < Config.MaxDistance then
            return false
        end
    end
    return true
end


function PlaceChest(coords, heading)
    PlacementMode = false
    local ped = PlayerPedId()
    local animScenario = "WORLD_HUMAN_HAMMERING"

    RequestModel(joaat(Config.ChestProp))
    while not HasModelLoaded(joaat(Config.ChestProp)) do Wait(10) end

    FreezeEntityPosition(ped, true)

    -- Inicia a animação de martelar
    TaskStartScenarioInPlace(ped, animScenario, 0, true)
    Wait(500)

    -- Toca som repetidamente durante o tempo da animação
    local duration = Config.PlacementTime
    local interval = 900 -- intervalo entre marteladas
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
        label = Config.Lang['placing_chest'],
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        }
    })

    ClearPedTasks(ped)

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

    FreezeEntityPosition(ped, false)
end








function CancelPlacement()
    PlacementMode = false
    lib.notify({ title = 'Cancelado', description = Config.Lang['placement_cancelled'], type = 'inform' })
    FreezeEntityPosition(ped, false)
end

RegisterNetEvent('rsg-chest:client:receiveActiveChests', function(chests)
    ActiveChests = {}
    for _, chest in pairs(chests) do
        table.insert(ActiveChests, chest.coords)
    end
end)
