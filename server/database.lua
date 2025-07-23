local RSGCore = exports['rsg-core']:GetCoreObject()

-- Funções Auxiliares
local function GenerateRandomString(length)
    local charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    local randomStr = ''
    for i = 1, length do
        local randomIndex = math.random(1, #charset)
        randomStr = randomStr .. charset:sub(randomIndex, randomIndex)
    end
    return randomStr
end

local function GenerateUUID(citizenid)
    if not citizenid then citizenid = 'FALLBACK' end
    local randomPart = GenerateRandomString(8)
    return ('%s-%s'):format(citizenid, randomPart)
end

local function NormalizeCoords(coords)
    return {
        x = tonumber(string.format("%.2f", coords.x)),
        y = tonumber(string.format("%.2f", coords.y)),
        z = tonumber(string.format("%.2f", coords.z))
    }
end

-- A tabela é inicializada antes de qualquer função ser adicionada a ela
local Database = {}

-- Funções do Banco de Dados
function Database.CreateChest(owner, coords, heading, model)
    coords = NormalizeCoords(coords)
    local chestUUID = GenerateUUID(owner)
    local initialTier = Config.Tiers[1]
    MySQL.insert.await(
        'INSERT INTO player_chests (chest_uuid, owner, coords, heading, model, items, tier, max_weight, max_slots) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { chestUUID, owner, json.encode(coords), heading or 0.0, model or 'p_chest01x', json.encode({}), 1, initialTier.weight, initialTier.slots }
    )
    return chestUUID
end

function Database.GetChest(chestUUID)
    local result = MySQL.single.await('SELECT * FROM player_chests WHERE chest_uuid = ?', { chestUUID })
    if result then
        result.coords = json.decode(result.coords)
        result.shared_with = result.shared_with and json.decode(result.shared_with) or {}
        result.items = result.items and json.decode(result.items) or {}
    end
    return result
end

function Database.GetAllChests()
    local query = [[
        SELECT *, DATE_FORMAT(created_at, '%d/%m/%Y %H:%i:%s') AS created_at_formatted, DATE_FORMAT(updated_at, '%d/%m/%Y %H:%i:%s') AS updated_at_formatted
        FROM player_chests
    ]]
    local result = MySQL.query.await(query)
    if result then
        for i = 1, #result do
            result[i].coords = json.decode(result[i].coords)
            result[i].shared_with = result[i].shared_with and json.decode(result[i].shared_with) or {}
            result[i].items = result[i].items and json.decode(result[i].items) or {}
        end
    end
    return result
end

function Database.ShareChest(chestUUID, sharedWith)
    MySQL.update.await('UPDATE player_chests SET shared_with = ?, updated_at = CURRENT_TIMESTAMP WHERE chest_uuid = ?', { json.encode(sharedWith), chestUUID })
end

function Database.DeleteChest(chestUUID)
    MySQL.query.await('DELETE FROM player_chests WHERE chest_uuid = ?', { chestUUID })
end

function Database.LogAction(chestUUID, actorCitizenId, actionType, targetCitizenId, details)
    MySQL.insert.await(
        'INSERT INTO player_chests_logs (chest_uuid, actor_citizenid, target_citizenid, action_type, details) VALUES (?, ?, ?, ?, ?)',
        {chestUUID, actorCitizenId, targetCitizenId, actionType, details}
    )
end

return Database