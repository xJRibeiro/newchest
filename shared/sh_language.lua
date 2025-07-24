-- =================================================================
-- Sistema Global de Linguagem 
-- Define a função _L() que estará disponível no client e no server
-- =================================================================
-- Global Language System
-- Function _L() will be available on client and server
-- =================================================================

_L = function(key, ...)
    -- Pega a string traduzida baseada no locale definido em config.lua 
    -- Get the translated string based on the locale defined in config.lua
    local str = Config.Lang[Config.Locale] and Config.Lang[Config.Locale][key]

    -- Se a chave não for encontrada no locale atual, tenta no locale padrão (en) como fallback.
    -- If the key is not found in the current locale, try the default locale (en) as a fallback.
    if not str then
        str = Config.Lang['en'] and Config.Lang['en'][key] or key
    end

    -- Se houver argumentos adicionais, formata a string.
    -- If there are additional arguments, format the string.
    if select('#', ...) > 0 then
        return str:format(...)
    end
    
    return str
end