local ChestData = {}

-- Cache interno dos baús
local props = {}

-- Carrega todos os baús do banco no cache
function ChestData.LoadChests(allChests)
    props = {}
    for _, chest in ipairs(allChests) do
        props[chest.chest_uuid] = chest
    end
end

-- Adiciona ou atualiza um baú no cache
function ChestData.SetChest(uuid, data)
    props[uuid] = data
end

-- Remove um baú do cache
function ChestData.RemoveChest(uuid)
    props[uuid] = nil
end

-- Retorna todos os baús do cache
function ChestData.GetAllChests()
    return props
end

-- Monta cache de nomes dos donos dos baús
function ChestData.BuildOwnerNameCache()
    local ownerIds = {}
    for _, chest in pairs(props) do
        ownerIds[chest.owner] = true
    end
    local ownerIdList = {}
    for id, _ in pairs(ownerIds) do
        table.insert(ownerIdList, id)
    end
    local nameCache = {}
    if #ownerIdList > 0 then
        local query = 'SELECT citizenid, charinfo FROM players WHERE citizenid IN (?' .. string.rep(',?', #ownerIdList - 1) .. ')'
        local playersResult = MySQL.query.await(query, ownerIdList)
        if playersResult then
            for _, playerData in ipairs(playersResult) do
                local charinfo = json.decode(playerData.charinfo)
                if charinfo and charinfo.firstname and charinfo.lastname then
                    nameCache[playerData.citizenid] = charinfo.firstname .. ' ' .. charinfo.lastname
                end
            end
        end
    end
    return nameCache
end

-- Imprime os dados dos baús no console
function ChestData.PrintChestData()
    local nameCache = ChestData.BuildOwnerNameCache()
    print('--- Dados dos Baús Carregados ---')
    for uuid, chest in pairs(props) do
        local ownerName = nameCache[chest.owner] or 'Desconhecido'
        print(string.format('%s (%s)', ownerName, chest.owner))
        print('  UUID: ' .. uuid)
        print(string.format('  Coordenadas: X=%.2f, Y=%.2f, Z=%.2f', chest.coords.x or 0, chest.coords.y or 0, chest.coords.z or 0))
        print('  Heading: ' .. (chest.heading or 0))
        print('  Modelo: ' .. (chest.model or 'Desconhecido'))
        local sharedCount = chest.shared_with and #chest.shared_with or 0
        print('  Compartilhado com: ' .. sharedCount .. ' jogadores')
        print('-----------------------------')
    end
end

return ChestData
