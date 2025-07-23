Config = {}

-- Configurações do Baú
Config.ChestItem = 'personal_chest'
Config.ChestProp = 'p_chest01x'
Config.MaxDistance = 2.0
Config.PlacementDistance = 5.0
Config.ShareDistance = 5.0 -- Distância máxima em metros para poder compartilhar.
Config.UpgradeItem = 'canteen0'-- 'chest_upgrade_kit' -- Item usado para melhorar o baú.
Config.LockpickItem = 'lockpick'          -- Item usado para tentar arrombar baús.
Config.Tiers = {
    -- Nível 1 (Padrão)
    [1] = { weight = 100000, slots = 50, label = "Baú Pequeno" },
    -- Nível 2
    [2] = { weight = 150000, slots = 75, label = "Baú Médio" },
    -- Nível 3 (Máximo)
    [3] = { weight = 250000, slots = 100, label = "Baú Grande" },
}

Config.LockpickSettings = {
    Cooldown = 0, -- Tempo em segundos que um jogador deve esperar após uma falha
    PoliceAlert = false, -- Se true, um alerta será enviado para a polícia em caso de sucesso
    
    -- Configurações de notificação
    SuccessMessage = 'Você conseguiu arrombar o baú!',
    FailMessage = 'Você falhou em arrombar o baú e quebrou seu lockpick.',
    CooldownMessage = 'Você precisa esperar um pouco antes de tentar arrombar outro baú.',
    
    -- Configurações de experiência (opcional)
    SuccessSound = 'success_sound', -- Som customizado para sucesso
    FailSound = 'fail_sound', -- Som customizado para falha
}

-- Configurações do Inventário
Config.ChestSlots = 50
Config.ChestWeight = 100000


-- Configurações de Permissões
Config.MaxSharedPlayers = 5

-- Configurações de Animação
Config.PlacementTime = 3000
Config.RemovalTime = 2000

-- Mensagens
Config.Lang = {
    -- pt-br
    ['chest_placed'] = 'Baú colocado com sucesso!', -- 'Chest placed successfully!',
    ['chest_removed'] = 'Baú removido com sucesso!', -- 'Chest removed successfully!',
    ['chest_shared'] = 'Baú compartilhado com %s!', -- 'Chest shared with %s!',
    ['player_not_found'] = 'Jogador não encontrado!', -- 'Player not found!',
    ['no_permission'] = 'Você não tem permissão para isso!', -- 'You do not have permission for this!',
    ['chest_in_use'] = 'Baú está sendo usado por outro jogador!', -- 'Chest is being used by another player!',
    ['placement_cancelled'] = 'Colocação do baú cancelada!', -- 'Chest placement cancelled!',
    ['invalid_location'] = 'Local inválido para colocar o baú!', -- 'Invalid location to place chest!',
    ['chest_full'] = 'Baú está cheio!', -- 'Chest is full!',
    ['placing_chest'] = 'Colocando baú...', -- 'Placing chest...',
    ['removing_chest'] = 'Removendo baú...', -- 'Removing chest...'
    ['chest_upgraded'] = 'Seu baú foi melhorado com sucesso!',
    ['max_tier_reached'] = 'Este baú já está no nível máximo.',
    ['lockpick_failed'] = 'Você falhou em arrombar a fechadura e quebrou seu lockpick.',
    ['lockpick_success'] = 'Você conseguiu arrombar o baú!',
    ['lockpick_cooldown'] = 'Você precisa esperar um pouco antes de tentar arrombar outro baú.',
     -- Admin System
    ['admin_command_desc'] = 'Abrir painel administrativo de baús',
    ['admin_panel_title'] = 'Painel Administrativo de Baús',
    ['admin_system_overview'] = 'Visão Geral do Sistema',
    ['admin_overview_desc'] = 'Total: %d | Com itens: %d | Vazios: %d | Itens: %d | Peso: %d kg',
    ['admin_refresh_data'] = 'Atualizar Dados',
    ['admin_refresh_desc'] = 'Recarregar informações dos baús',
    ['admin_chest_list'] = 'Lista de Baús',
    ['admin_chest_list_desc'] = 'Ver todos os baús do servidor',
    ['admin_search_chest'] = 'Buscar Baús',
    ['admin_search_desc'] = 'Buscar baús por dono ou UUID',
    ['admin_no_chests'] = 'Nenhum baú encontrado',
    ['admin_back'] = 'Voltar',
    ['admin_chest_details'] = 'Detalhes do Baú',
    ['admin_chest_info'] = 'Informações Completas',
    ['admin_chest_info_desc'] = 'Ver todas as informações do baú',
    ['admin_view_items'] = 'Ver Itens',
    ['admin_view_items_desc'] = 'Listar itens dentro do baú',
    ['admin_teleport_to_chest'] = 'Teleportar para Baú',
    ['admin_teleport_desc'] = 'Teleportar para a localização do baú',
    ['admin_remove_chest'] = 'Remover Baú',
    ['admin_remove_warning'] = 'AÇÃO PERMANENTE!',
    ['admin_confirm_removal'] = 'Confirmar Remoção',
    ['admin_removal_warning'] = 'Tem certeza que deseja remover permanentemente o baú %s de %s?',
    ['admin_chest_uuid'] = 'UUID do Baú',
    ['admin_owner'] = 'Proprietário',
    ['admin_model'] = 'Modelo',
    ['admin_location'] = 'Localização',
    ['admin_heading'] = 'Rotação',
    ['admin_status'] = 'Status',
    ['admin_inventory'] = 'Inventário',
    ['admin_weight'] = 'Peso',
    ['admin_created'] = 'Criado em',
    ['admin_updated'] = 'Atualizado em',
    ['admin_shared_with'] = 'Compartilhado com',
    ['admin_nobody'] = 'Ninguém',
    ['admin_chest_items'] = 'Itens do Baú',
    ['admin_no_items'] = 'Nenhum item no baú',
    ['admin_quantity'] = 'Quantidade',
    ['admin_search_by'] = 'Buscar por nome ou UUID',
    ['admin_search_placeholder'] = 'Digite o nome do jogador ou UUID...',
    ['admin_search_results'] = 'Resultados da Busca',
    ['admin_no_results'] = 'Nenhum resultado encontrado',
    ['admin_status_available'] = 'Disponível',
    ['admin_status_in_use'] = 'Em uso',
    ['admin_status_in_use_by'] = 'Em uso por',
    ['admin_chest_not_found'] = 'Baú não encontrado!',
    ['admin_teleported_to_chest'] = 'Teleportado para o baú!',
    ['admin_chest_removed'] = 'Baú removido com sucesso!',
    ['admin_clean_orphan_desc'] = 'Limpar baús de jogadores que não existem mais',
    ['admin_orphan_cleaned'] = 'Baús órfãos removidos:',
    ['admin_items'] = 'Itens',
    ['unknown_player'] = 'Jogador Desconhecido',
    ['admin_unknown'] = 'Desconhecido',
    ['admin_remove_all_chests'] = 'Remover Todos os Baús',
    ['admin_remove_all_chests_desc'] = 'Exclui todos os baús do servidor permanentemente.',
    ['admin_confirm_removal_all'] = 'Confirmar Remoção de Todos',
    ['admin_removal_all_warning'] = 'Tem certeza que deseja remover TODOS os baús? Esta ação é irreversível!',
    ['admin_all_chests_removed'] = 'Todos os baús foram removidos com sucesso!',
    ['admin_view_inventory'] = 'Ver Inventário',
    ['admin_view_inventory_desc'] = 'Visualizar todos os itens do baú selecionado.',

    ['admin_view_logs'] = 'Ver Registros',
    ['admin_view_logs_desc'] = 'Visualizar histórico de ações no baú',
    ['admin_chest_logs_title'] = 'Registros do Baú',
    ['admin_no_logs'] = 'Nenhum registro encontrado',
    ['admin_no_logs_desc'] = 'Este baú não possui histórico de ações',
    ['admin_log_statistics'] = 'Estatísticas dos Registros',
    ['admin_log_stats_desc'] = 'Total de ações: %d | Última ação: %s',
    ['admin_details'] = 'Detalhes',
    ['admin_never'] = 'Nunca',

    ['admin_action_rename'] = 'Renomear Baú',
    ['admin_action_rename_desc'] = 'Renomear o baú para um novo nome.',
    ['admin_rename_input'] = 'Digite o novo nome do baú:',
    ['admin_rename_success'] = 'Baú renomeado com sucesso!',
    ['admin_rename_failed'] = 'Falha ao renomear o baú. Verifique se o nome é válido.',
    
    -- Tipos de ações (para tradução)
    ['admin_action_open'] = 'Abertura',
    ['admin_action_share'] = 'Compartilhamento',
    ['admin_action_unshare'] = 'Remoção de Acesso',
    ['admin_action_remove'] = 'Remoção',
    ['admin_action_upgrade'] = 'Melhoria',
    ['admin_action_lockpick_success'] = 'Arrombamento (Sucesso)',
    ['admin_action_lockpick_fail'] = 'Arrombamento (Falhou)',

       -- Renomeação
    ['chest_renamed'] = 'Baú renomeado com sucesso!',
    ['rename_chest'] = 'Renomear Baú',
    ['chest_name_label'] = 'Nome do Baú',
    ['chest_name_placeholder'] = 'Digite o novo nome...',
    ['invalid_name_length'] = 'O nome deve ter entre 3 e 50 caracteres.',
    ['invalid_characters'] = 'O nome contém caracteres não permitidos.',
    ['rename_failed'] = 'Falha ao renomear o baú.',

    ['admin_action_lockpick'] = 'Arrombamento',
    ['admin_action_lockpick_desc'] = 'Registrar uma Tentativa de Saquear Baú no baú.',
    ['admin_lockpick_success'] = 'Arrombamento registrado com sucesso!',
    ['admin_lockpick_fail'] = 'Falha ao registrar o arrombamento. Verifique os dados.',
}

    
