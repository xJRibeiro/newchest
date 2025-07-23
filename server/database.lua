local RSGCore = exports['rsg-core']:GetCoreObject()

-- =================================================================
-- FUNÇÕES AUXILIARES MELHORADAS
-- =================================================================

local function GenerateRandomString(length)
    local charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    local randomStr = ''
    math.randomseed(os.time() + GetGameTimer())
    
    for i = 1, length do
        local randomIndex = math.random(1, #charset)
        randomStr = randomStr .. charset:sub(randomIndex, randomIndex)
    end
    return randomStr
end

local function GenerateUUID(citizenid)
    if not citizenid then citizenid = 'FALLBACK' end
    local randomPart = GenerateRandomString(8)
    local timestamp = os.time()
    return ('%s-%s-%d'):format(citizenid, randomPart, timestamp)
end

local function NormalizeCoords(coords)
    if not coords or not coords.x or not coords.y or not coords.z then
        print('[RSG-CHEST][ERROR] Coordenadas inválidas fornecidas para normalização')
        return { x = 0.0, y = 0.0, z = 0.0 }
    end
    
    return {
        x = tonumber(string.format("%.2f", coords.x)),
        y = tonumber(string.format("%.2f", coords.y)),
        z = tonumber(string.format("%.2f", coords.z))
    }
end

local function ValidateChestData(owner, coords, heading, model)
    if not owner or type(owner) ~= 'string' or owner == '' then
        return false, 'Owner inválido'
    end
    
    if not coords or type(coords) ~= 'table' then
        return false, 'Coordenadas inválidas'
    end
    
    if not coords.x or not coords.y or not coords.z then
        return false, 'Coordenadas incompletas'
    end
    
    if heading and type(heading) ~= 'number' then
        return false, 'Heading inválido'
    end
    
    if model and type(model) ~= 'string' then
        return false, 'Modelo inválido'
    end
    
    return true, 'Dados válidos'
end

-- =================================================================
-- FUNÇÕES DO BANCO DE DADOS
-- =================================================================

local Database = {}

function Database.CreateChest(owner, coords, heading, model)
    local isValid, errorMsg = ValidateChestData(owner, coords, heading, model)
    if not isValid then
        print(('[RSG-CHEST][ERROR] Falha na validação: %s'):format(errorMsg))
        return nil
    end
    
    coords = NormalizeCoords(coords)
    local chestUUID = GenerateUUID(owner)
    local initialTier = Config.Tiers[1]
    
    if not initialTier then
        print('[RSG-CHEST][ERROR] Configuração de tier inicial não encontrada')
        return nil
    end
    
    local success = pcall(function()
        MySQL.insert.await(
            'INSERT INTO player_chests (chest_uuid, owner, coords, heading, model, items, tier, max_weight, max_slots) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { 
                chestUUID, 
                owner, 
                json.encode(coords), 
                heading or 0.0, 
                model or 'p_chest01x', 
                json.encode({}), 
                1, 
                initialTier.weight, 
                initialTier.slots 
            }
        )
    end)
    
    if success then
        print(('[RSG-CHEST] Baú criado com sucesso: %s para %s'):format(chestUUID, owner))
        return chestUUID
    else
        print(('[RSG-CHEST][ERROR] Falha ao criar baú no banco de dados'))
        return nil
    end
end

function Database.GetChest(chestUUID)
    if not chestUUID or type(chestUUID) ~= 'string' then
        print('[RSG-CHEST][ERROR] UUID de baú inválido fornecido para GetChest')
        return nil
    end
    
    local success, result = pcall(function()
        return MySQL.single.await('SELECT * FROM player_chests WHERE chest_uuid = ?', { chestUUID })
    end)
    
    if not success then
        print(('[RSG-CHEST][ERROR] Erro ao buscar baú %s'):format(chestUUID))
        return nil
    end
    
    if result then
        -- Decodifica dados JSON com tratamento de erro
        local success_decode = pcall(function()
            result.coords = json.decode(result.coords) or {}
            result.shared_with = result.shared_with and json.decode(result.shared_with) or {}
            result.items = result.items and json.decode(result.items) or {}
        end)
        
        if not success_decode then
            print(('[RSG-CHEST][WARNING] Erro ao decodificar dados JSON do baú %s'):format(chestUUID))
            result.coords = {}
            result.shared_with = {}
            result.items = {}
        end
    end
    
    return result
end

function Database.RenameChest(chestUUID, customName)
    if not chestUUID or type(chestUUID) ~= 'string' then
        print('[RSG-CHEST][ERROR] UUID inválido fornecido para RenameChest')
        return false
    end
    
    if not customName or type(customName) ~= 'string' then
        print('[RSG-CHEST][ERROR] Nome inválido fornecido para RenameChest')
        return false
    end
    
    local success = pcall(function()
        MySQL.update.await(
            'UPDATE player_chests SET custom_name = ?, updated_at = CURRENT_TIMESTAMP WHERE chest_uuid = ?',
            { customName, chestUUID }
        )
    end)
    
    if success then
        print(('[RSG-CHEST] Baú %s renomeado para: %s'):format(chestUUID, customName))
        return true
    else
        print(('[RSG-CHEST][ERROR] Falha ao renomear baú %s'):format(chestUUID))
        return false
    end
end


function Database.GetAllChests()
    local query = [[
        SELECT *, 
               DATE_FORMAT(created_at, '%d/%m/%Y %H:%i:%s') AS created_at_formatted, 
               DATE_FORMAT(updated_at, '%d/%m/%Y %H:%i:%s') AS updated_at_formatted
        FROM player_chests
    ]]
    
    local result = MySQL.query.await(query)
    if result then
        for i = 1, #result do
            result[i].coords = json.decode(result[i].coords)
            result[i].shared_with = result[i].shared_with and json.decode(result[i].shared_with) or {}
            result[i].items = result[i].items and json.decode(result[i].items) or {}
            -- custom_name já vem diretamente do banco, não precisa decodificar
        end
    end
    return result
end


function Database.ShareChest(chestUUID, sharedWith)
    if not chestUUID or not sharedWith then
        print('[RSG-CHEST][ERROR] Parâmetros inválidos para ShareChest')
        return false
    end
    
    local success = pcall(function()
        MySQL.update.await(
            'UPDATE player_chests SET shared_with = ?, updated_at = CURRENT_TIMESTAMP WHERE chest_uuid = ?', 
            { json.encode(sharedWith), chestUUID }
        )
    end)
    
    if success then
        print(('[RSG-CHEST] Compartilhamento atualizado para baú %s'):format(chestUUID))
        return true
    else
        print(('[RSG-CHEST][ERROR] Falha ao atualizar compartilhamento do baú %s'):format(chestUUID))
        return false
    end
end

function Database.DeleteChest(chestUUID)
    if not chestUUID or type(chestUUID) ~= 'string' then
        print('[RSG-CHEST][ERROR] UUID inválido fornecido para DeleteChest')
        return false
    end
    
    local success = pcall(function()
        MySQL.query.await('DELETE FROM player_chests WHERE chest_uuid = ?', { chestUUID })
    end)
    
    if success then
        print(('[RSG-CHEST] Baú %s deletado com sucesso'):format(chestUUID))
        return true
    else
        print(('[RSG-CHEST][ERROR] Falha ao deletar baú %s'):format(chestUUID))
        return false
    end
end

-- =================================================================
-- FUNÇÕES DE LOGS - ATUALIZADAS PARA SUA TABELA
-- =================================================================

function Database.LogAction(chestUUID, actorCitizenId, actionType, targetCitizenId, details)
    if not chestUUID or not actorCitizenId or not actionType then
        print('[RSG-CHEST][WARNING] Parâmetros obrigatórios em falta para LogAction')
        return false
    end
    
    local success = pcall(function()
        -- ATUALIZADO: Usando os nomes corretos dos campos da sua tabela
        -- log_id é AUTO_INCREMENT, então não precisa ser especificado
        -- timestamp será definido automaticamente
        MySQL.insert.await(
            'INSERT INTO player_chests_logs (chest_uuid, actor_citizenid, action_type, target_citizenid, details) VALUES (?, ?, ?, ?, ?)',
            { chestUUID, actorCitizenId, actionType, targetCitizenId, details or '' }
        )
    end)
    
    if success then
        print(('[RSG-CHEST] Ação logada: %s por %s no baú %s'):format(actionType, actorCitizenId, chestUUID))
        return true
    else
        print(('[RSG-CHEST][ERROR] Falha ao logar ação para baú %s'):format(chestUUID))
        return false
    end
end

function Database.GetChestLogs(chestUUID, limit)
    if not chestUUID or type(chestUUID) ~= 'string' then
        print('[RSG-CHEST][ERROR] UUID inválido fornecido para GetChestLogs')
        return {}
    end
    
    limit = limit or 50 -- Limite padrão de 50 registros
    
    local success, result = pcall(function()
        -- ATUALIZADO: Usando os nomes corretos dos campos da sua tabela
        return MySQL.query.await([[
            SELECT 
                pcl.log_id,
                pcl.chest_uuid,
                pcl.actor_citizenid,
                pcl.action_type,
                pcl.target_citizenid,
                pcl.details,
                DATE_FORMAT(pcl.timestamp, '%d/%m/%Y %H:%i:%s') AS formatted_date,
                p1.charinfo as actor_charinfo,
                p2.charinfo as target_charinfo
            FROM player_chests_logs pcl
            LEFT JOIN players p1 ON pcl.actor_citizenid = p1.citizenid
            LEFT JOIN players p2 ON pcl.target_citizenid = p2.citizenid
            WHERE pcl.chest_uuid = ?
            ORDER BY pcl.timestamp DESC
            LIMIT ?
        ]], { chestUUID, limit })
    end)
    
    if not success then
        print(('[RSG-CHEST][ERROR] Erro ao buscar logs do baú %s'):format(chestUUID))
        return {}
    end
    
    if result then
        for i = 1, #result do
            local log = result[i]
            
            -- Decodifica informações do ator
            if log.actor_charinfo then
                local success_decode, actor_info = pcall(json.decode, log.actor_charinfo)
                if success_decode and actor_info and actor_info.firstname and actor_info.lastname then
                    log.actor_name = ('%s %s'):format(actor_info.firstname, actor_info.lastname)
                else
                    log.actor_name = 'Desconhecido'
                end
            else
                log.actor_name = 'Desconhecido'
            end
            
            -- Decodifica informações do alvo (se existir)
            if log.target_citizenid and log.target_charinfo then
                local success_decode, target_info = pcall(json.decode, log.target_charinfo)
                if success_decode and target_info and target_info.firstname and target_info.lastname then
                    log.target_name = ('%s %s'):format(target_info.firstname, target_info.lastname)
                else
                    log.target_name = 'Desconhecido'
                end
            end
        end
    end
    
    return result or {}
end

function Database.GetChestLogStats(chestUUID)
    if not chestUUID or type(chestUUID) ~= 'string' then
        print('[RSG-CHEST][ERROR] UUID inválido fornecido para GetChestLogStats')
        return { totalLogs = 0, lastAction = nil, mostActiveUser = nil }
    end
    
    local success, stats = pcall(function()
        -- ATUALIZADO: Usando o campo 'timestamp' correto da sua tabela
        local result = MySQL.single.await([[
            SELECT 
                COUNT(*) as total_logs,
                DATE_FORMAT(MAX(timestamp), '%d/%m/%Y %H:%i:%s') as last_action_date,
                (SELECT actor_citizenid FROM player_chests_logs 
                 WHERE chest_uuid = ? 
                 GROUP BY actor_citizenid 
                 ORDER BY COUNT(*) DESC LIMIT 1) as most_active_user
            FROM player_chests_logs 
            WHERE chest_uuid = ?
        ]], { chestUUID, chestUUID })
        return result
    end)
    
    if success and stats then
        return {
            totalLogs = stats.total_logs or 0,
            lastAction = stats.last_action_date,
            mostActiveUser = stats.most_active_user
        }
    else
        print(('[RSG-CHEST][ERROR] Falha ao obter estatísticas dos logs do baú %s'):format(chestUUID))
        return { totalLogs = 0, lastAction = nil, mostActiveUser = nil }
    end
end

function Database.UpdateChestTier(chestUUID, tier, maxWeight, maxSlots)
    if not chestUUID or not tier or not maxWeight or not maxSlots then
        print('[RSG-CHEST][ERROR] Parâmetros inválidos para UpdateChestTier')
        return false
    end
    
    local success = pcall(function()
        MySQL.update.await(
            'UPDATE player_chests SET tier = ?, max_weight = ?, max_slots = ?, updated_at = CURRENT_TIMESTAMP WHERE chest_uuid = ?',
            { tier, maxWeight, maxSlots, chestUUID }
        )
    end)
    
    if success then
        print(('[RSG-CHEST] Tier do baú %s atualizado para %d'):format(chestUUID, tier))
        return true
    else
        print(('[RSG-CHEST][ERROR] Falha ao atualizar tier do baú %s'):format(chestUUID))
        return false
    end
end

-- =================================================================
-- FUNÇÕES DE MANUTENÇÃO
-- =================================================================

function Database.CleanupOrphanChests()
    local success, orphanCount = pcall(function()
        local result = MySQL.query.await([[
            DELETE pc FROM player_chests pc
            LEFT JOIN players p ON pc.owner = p.citizenid
            WHERE p.citizenid IS NULL
        ]])
        return result.affectedRows or 0
    end)
    
    if success then
        print(('[RSG-CHEST] Limpeza de baús órfãos concluída: %d removidos'):format(orphanCount))
        return orphanCount
    else
        print('[RSG-CHEST][ERROR] Falha na limpeza de baús órfãos')
        return 0
    end
end

function Database.GetChestStats()
    local success, stats = pcall(function()
        local result = MySQL.single.await([[
            SELECT 
                COUNT(*) as total_chests,
                COUNT(CASE WHEN shared_with != '[]' AND shared_with IS NOT NULL THEN 1 END) as shared_chests,
                AVG(tier) as avg_tier
            FROM player_chests
        ]])
        return result
    end)
    
    if success and stats then
        return {
            totalChests = stats.total_chests or 0,
            sharedChests = stats.shared_chests or 0,
            averageTier = math.floor((stats.avg_tier or 0) * 100) / 100
        }
    else
        print('[RSG-CHEST][ERROR] Falha ao obter estatísticas dos baús')
        return { totalChests = 0, sharedChests = 0, averageTier = 0 }
    end
end

-- =================================================================
-- INICIALIZAÇÃO E VERIFICAÇÕES
-- =================================================================

CreateThread(function()
    Wait(1000)
    
    -- Verifica se as tabelas necessárias existem
    local success = pcall(function()
        MySQL.query.await('SELECT 1 FROM player_chests LIMIT 1')
        MySQL.query.await('SELECT 1 FROM player_chests_logs LIMIT 1')
    end)
    
    if success then
        print('[RSG-CHEST] Database inicializado com sucesso')
        
        -- Executa limpeza automática se configurada
        if Config.AutoCleanupOrphans then
            Database.CleanupOrphanChests()
        end
    else
        print('[RSG-CHEST][ERROR] Tabelas do banco de dados não encontradas!')
        print('[RSG-CHEST][INFO] Certifique-se de que as tabelas player_chests e player_chests_logs existem')
    end
end)

return Database
