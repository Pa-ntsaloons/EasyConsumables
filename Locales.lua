-- EasyConsumables: tooltip wording per client language.
--
-- The parser in Core.lua understands English phrasing ("61.2 health", "140 to 180 health",
-- "heals 66 damage", "health and mana", "25% of your maximum health"). For other languages,
-- `rules` rewrites the (lowercased) "Use:" text into that phrasing with string.gsub, in order,
-- so the parser itself doesn't change. Put longer / combined phrases before shorter ones.
--
-- Only ASCII letters are lowercased by the game, so non-Latin words are written as they appear
-- mid-sentence in the tooltip. If an item isn't recognised on your client, `/ec debug` prints
-- the text the parser saw.

local _, ns = ...

local N = "([%d%.,]+)" -- a number as it appears in tooltips ("61.2", "61,2", "1,500")

local LOCALES = {}

LOCALES.enUS = {
    minute = "min", -- buff durations ("for 15 min")
    rules = {},
    seated = { "seated", "while eating", "while drinking" },
    wellFed = { "well fed", "experience" },
    healthstone = { "healthstone" },
}
LOCALES.enGB = LOCALES.enUS

LOCALES.deDE = {
    minute = "min", -- buff durations ("for 15 min")
    rules = {
        { N .. " bis " .. N, "%1 to %2" },
        { "punkt%(e%)%s*", "" },
        { "punkte%s+", "" },
        { "gesundheit und mana", "health and mana" },
        { "gesundheit", "health" },
        { "heilt(.-)" .. N .. " schaden", "heals %2 damage" },
    },
    seated = { "sitzen" },
    wellFed = { "satt", "erfahrung" },
    healthstone = { "gesundheitsstein" },
}

LOCALES.frFR = {
    minute = "min", -- buff durations ("for 15 min")
    rules = {
        { N .. " à " .. N, "%1 to %2" },
        { N .. " et " .. N, "%1 to %2" },
        { "points? de vie et de mana", "health and mana" },
        { "points? de vie et mana", "health and mana" },
        { "points? de vie", "health" },
        { "points? de mana", "mana" },
        { "soigne(.-)" .. N .. " points? de dégâts", "heals %2 damage" },
    },
    seated = { "assis" },
    wellFed = { "bien nourri", "expérience" },
    healthstone = { "pierre de soins" },
}

LOCALES.esES = {
    minute = "min", -- buff durations ("for 15 min")
    rules = {
        { N .. " y " .. N, "%1 to %2" },
        { N .. " a " .. N, "%1 to %2" },
        { "p%. de salud y maná", "health and mana" },
        { "puntos de salud y maná", "health and mana" },
        { "salud y maná", "health and mana" },
        { "p%. de salud", "health" },
        { "puntos de salud", "health" },
        { "de salud", "health" },
        { "p%. de maná", "mana" },
        { "puntos de maná", "mana" },
        { "de maná", "mana" },
        { "maná", "mana" },
        { "cura(.-)" .. N .. " p%. de daño", "heals %2 damage" },
        { "cura(.-)" .. N .. " puntos de daño", "heals %2 damage" },
    },
    seated = { "sentado" },
    wellFed = { "bien alimentado", "experiencia" },
    healthstone = { "piedra de salud" },
}
LOCALES.esMX = LOCALES.esES

LOCALES.ptBR = {
    minute = "min", -- buff durations ("for 15 min")
    rules = {
        { N .. " a " .. N, "%1 to %2" },
        { "pontos de vida e mana", "health and mana" },
        { "de vida e mana", "health and mana" },
        { "pontos de vida", "health" },
        { "de vida", "health" },
        { "pontos de mana", "mana" },
        { "de mana", "mana" },
        { "cura(.-)" .. N .. " pontos de dano", "heals %2 damage" },
        { "cura(.-)" .. N .. " de dano", "heals %2 damage" },
    },
    seated = { "sentado" },
    wellFed = { "bem alimentado", "experiência" },
    healthstone = { "pedra de vida", "pedra da vida" },
}

LOCALES.ruRU = {
    minute = "мин", -- buff durations ("for 15 min")
    rules = {
        { N .. " до " .. N, "%1 to %2" },
        { "ед%. здоровья и маны", "health and mana" },
        { "здоровья и маны", "health and mana" },
        { "ед%. здоровья", "health" },
        { "здоровья", "health" },
        { "ед%. маны", "mana" },
        { "маны", "mana" },
        { N .. " ед%. урона", "heals %1 damage" },
    },
    seated = { "сидеть" },
    wellFed = { "сытость", "опыт" },
    healthstone = { "камень здоровья" },
}

LOCALES.zhCN = {
    minute = "分钟", -- buff durations ("for 15 min")
    rules = {
        { N .. "到" .. N, "%1 to %2" },
        { "治疗(.-)" .. N .. "点伤害", "heals %2 damage" },
        { "点生命值和法力值", " health and mana" },
        { "生命值和法力值", " health and mana" },
        { "点生命值", " health" },
        { "点法力值", " mana" },
        { "生命值", " health" },
        { "法力值", " mana" },
    },
    seated = { "坐" },
    wellFed = { "进食充分", "经验" },
    healthstone = { "治疗石" },
}

LOCALES.zhTW = {
    minute = "分鐘", -- buff durations ("for 15 min")
    rules = {
        { N .. "到" .. N, "%1 to %2" },
        { "治療(.-)" .. N .. "點傷害", "heals %2 damage" },
        { "點生命力和法力", " health and mana" },
        { "生命力和法力", " health and mana" },
        { "點生命力", " health" },
        { "點法力", " mana" },
        { "生命力", " health" },
        { "法力", " mana" },
    },
    seated = { "坐" },
    wellFed = { "充分進食", "經驗" },
    healthstone = { "治療石" },
}

-- Korean puts the amount after the resource word ("생명력이 61.2만큼"), so the rules move it in front.
LOCALES.koKR = {
    minute = "분", -- buff durations ("for 15 min")
    rules = {
        { N .. "%s*~%s*" .. N, "%1 to %2" },
        { N .. "의 피해", "heals %1 damage" },
        { "생명력과 마나[^%d]-" .. N, "%1 health and mana" },
        { "생명력[^%d]-([%d%.,]+ to [%d%.,]+)", "%1 health" },
        { "생명력[^%d]-" .. N, "%1 health" },
        { "마나[^%d]-([%d%.,]+ to [%d%.,]+)", "%1 mana" },
        { "마나[^%d]-" .. N, "%1 mana" },
    },
    seated = { "앉아" },
    wellFed = { "포만감", "경험치" },
    healthstone = { "생명석" },
}

local locale = GetLocale and GetLocale() or "enUS"
local L = LOCALES[locale]
ns.localeSupported = L ~= nil
ns.locale = locale
L = L or LOCALES.enUS

-- Seated / Well Fed / Healthstone words: English ones always count too, since some clients
-- leave bits of English in place.
for _, key in ipairs({ "seated", "wellFed", "healthstone" }) do
    if L ~= LOCALES.enUS then
        for _, w in ipairs(LOCALES.enUS[key]) do table.insert(L[key], w) end
    end
end

ns.L = L
