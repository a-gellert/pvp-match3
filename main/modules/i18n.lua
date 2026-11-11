-- Localization (Russian & English) for Gem Vanguard.
-- Re-run `node tools/gen_font.js` after adding characters so main.font covers every glyph.
local M = {}

M.LANGS = { "ru", "en" }
M.NAMES = { ru = "Русский", en = "English" }

local STRINGS = {
	ru = {
		TITLE = "Gem Vanguard",
		HUB = "Хаб",
		CAMPAIGN = "Кампания",
		PVP = "PvP Бой",
		SHOP = "Магазин",
		FIGHT = "В бой!",
		PLAY = "Играть",
		CONTINUE = "Дальше",
		CLAIM = "Забрать",
		RETRY = "Ещё раз",
		RESUME = "Продолжить",
		PAUSED = "Пауза",
		SETTINGS = "Настройки",
		SOUND = "Звук",
		MUSIC = "Музыка",
		LANGUAGE = "Язык",
		YOUR_TURN = "ТВОЙ ХОД",
		ENEMY_TURN = "ХОД ВРАГА",
		MOVES_FMT = "Ходов: {n}",
		UPGRADE_MOVES = "+1 ход ({g})",
		MAX_MOVES = "Ходы: МАКС (7)",
		HP_LABEL = "HP {c}/{m}",
		PRESTIGE = "Престиж",
		GOLD = "Золото",
		DIAMONDS = "Алмазы",
		SQUAD_SLOTS = "Отряды в бою",
		COLLECTION = "Коллекция отрядов",
		CHESTS = "Сундуки (4 слота)",
		EMPTY_SLOT = "Пусто",
		LOCKED = "Закрыто",
		READY = "Открыть!",
		OPEN = "Открыть",
		START_TIMER = "Таймер",
		RUSH_DIAM = "За {d}",
		BUSY = "Занято",
		UPGRADE = "Улучшить ({g})",
		EQUIP = "В слот",
		EQUIPPED = "В бою",
		BUY_CARD = "Открыть ({d})",
		BUY_GOLD = "Купить ({g})",
		LVL_FMT = "Ур. {n}",
		ATK_FMT = "Урон: {n}",
		MAX = "МАКС",
		RARITY_common = "Обычный",
		RARITY_rare = "Редкий",
		RARITY_epic = "Эпический",
		CHEST_wood = "Деревянный",
		CHEST_silver = "Серебряный",
		CHEST_royal = "Королевский",
		VICTORY = "ПОБЕДА!",
		DEFEAT = "ПОРАЖЕНИЕ",
		DOUBLE_GOLD = "×2 Золото",
		SECOND_CHANCE = "Второй шанс",
		TO_HUB = "В Хаб",
		SURRENDER = "Сдаться",
		PVP_SEARCH = "Поиск соперника...",
		PVP_FOUND = "Соперник найден!",
		STAGE_FMT = "Уровень {n}",
		BOSS = "БОСС",
		TUT_MATCH = "Собери 3 в ряд!",
		TUT_UPGRADE = "Улучши Стражей Склепа!",
		SLOT_red = "Красный (Урон 1)",
		SLOT_yellow = "Жёлтый (Урон 2)",
		SLOT_purple = "Фиолетовый (Урон 3)",
		BOOST_shuffle = "Мешать",
		BOOST_hammer = "Молот",
		BOOST_extra_move = "+1 Ход",
		HAMMER_HINT = "Тапни по кристаллу",
		CHEST_FULL = "Мест для сундуков нет",
		CHEST_OPENED = "Сундук открыт!",
		SQ_red_militia = "Стражи Склепа",
		SQ_red_wolves = "Теневые Волки",
		SQ_red_berserk = "Берсерки",
		SQ_yellow_archers = "Мрачные Лучники",
		SQ_yellow_crossbow = "Охотники",
		SQ_yellow_paladin = "Храмовники",
		SQ_purple_cultists = "Аколиты Тьмы",
		SQ_purple_necro = "Некроманты",
		SQ_purple_golem = "Голем Бездны",
		TRAIT_none = "Надёжный боевой отряд",
		TRAIT_crit = "25% шанс крита ×1.5",
		TRAIT_fury = "+35% урона при HP < 50%",
		TRAIT_pierce = "Пробивает 50% щита",
		TRAIT_bastion = "+4 щита при атаке",
		TRAIT_drain = "Лечит 25% от урона",
		TRAIT_crush = "+35% урона по щиту",
		ENEMY_SCOUT = "Гоблин-разведчик",
		ENEMY_RAIDER = "Налётчик",
		ENEMY_SHAMAN = "Шаман Гоблинов",
		ENEMY_WARCHIEF = "Вождь Орков",
		ENEMY_BONE = "Костяной Страж",
		ENEMY_HUNTER = "Тёмный Ловчий",
		ENEMY_WARLOCK = "Чернокнижник",
		ENEMY_LICH = "Король Лич",
		ENEMY_KNIGHT = "Рыцарь Пепла",
		ENEMY_DARK = "Архимаг Бездны",
		ENEMY_DRAKE = "Повелитель Драконов",
		ENEMY_OVERLORD = "Тёмный Владыка",
		MISS_RES = "Недостаточно ресурсов",
	},
	en = {
		TITLE = "Gem Vanguard",
		HUB = "Hub",
		CAMPAIGN = "Campaign",
		PVP = "PvP Battle",
		SHOP = "Shop",
		FIGHT = "Fight!",
		PLAY = "Play",
		CONTINUE = "Continue",
		CLAIM = "Claim",
		RETRY = "Retry",
		RESUME = "Resume",
		PAUSED = "Paused",
		SETTINGS = "Settings",
		SOUND = "Sound",
		MUSIC = "Music",
		LANGUAGE = "Language",
		YOUR_TURN = "YOUR TURN",
		ENEMY_TURN = "ENEMY TURN",
		MOVES_FMT = "Moves: {n}",
		UPGRADE_MOVES = "+1 Move ({g})",
		MAX_MOVES = "Moves: MAX (7)",
		HP_LABEL = "HP {c}/{m}",
		PRESTIGE = "Prestige",
		GOLD = "Gold",
		DIAMONDS = "Diamonds",
		SQUAD_SLOTS = "Active Squads",
		COLLECTION = "Squad Collection",
		CHESTS = "Chests (4 slots)",
		EMPTY_SLOT = "Empty",
		LOCKED = "Locked",
		READY = "Open!",
		OPEN = "Open",
		START_TIMER = "Unlock",
		RUSH_DIAM = "For {d}",
		BUSY = "Busy",
		UPGRADE = "Upgrade ({g})",
		EQUIP = "Equip",
		EQUIPPED = "Active",
		BUY_CARD = "Unlock ({d})",
		BUY_GOLD = "Buy ({g})",
		LVL_FMT = "Lv.{n}",
		ATK_FMT = "ATK: {n}",
		MAX = "MAX",
		RARITY_common = "Common",
		RARITY_rare = "Rare",
		RARITY_epic = "Epic",
		CHEST_wood = "Wood Chest",
		CHEST_silver = "Silver Chest",
		CHEST_royal = "Royal Chest",
		VICTORY = "VICTORY!",
		DEFEAT = "DEFEAT",
		DOUBLE_GOLD = "x2 Gold",
		SECOND_CHANCE = "Second Chance",
		TO_HUB = "To Hub",
		SURRENDER = "Surrender",
		PVP_SEARCH = "Finding opponent...",
		PVP_FOUND = "Match found!",
		STAGE_FMT = "Stage {n}",
		BOSS = "BOSS",
		TUT_MATCH = "Match 3 gems!",
		TUT_UPGRADE = "Upgrade Crypt Footmen!",
		SLOT_red = "Red (Damage 1)",
		SLOT_yellow = "Yellow (Damage 2)",
		SLOT_purple = "Purple (Damage 3)",
		BOOST_shuffle = "Shuffle",
		BOOST_hammer = "Hammer",
		BOOST_extra_move = "+1 Move",
		HAMMER_HINT = "Tap a gem",
		CHEST_FULL = "Chest slots full",
		CHEST_OPENED = "Chest opened!",
		SQ_red_militia = "Crypt Footmen",
		SQ_red_wolves = "Shadow Hounds",
		SQ_red_berserk = "Berserkers",
		SQ_yellow_archers = "Dusk Archers",
		SQ_yellow_crossbow = "Witch Hunters",
		SQ_yellow_paladin = "Amber Templars",
		SQ_purple_cultists = "Dark Acolytes",
		SQ_purple_necro = "Necromancers",
		SQ_purple_golem = "Void Colossus",
		TRAIT_none = "Reliable battle squad",
		TRAIT_crit = "25% chance for x1.5 crit",
		TRAIT_fury = "+35% damage below 50% HP",
		TRAIT_pierce = "Ignores 50% enemy shield",
		TRAIT_bastion = "+4 shield on attack",
		TRAIT_drain = "Heals 25% of damage",
		TRAIT_crush = "+35% damage vs shield",
		ENEMY_SCOUT = "Goblin Scout",
		ENEMY_RAIDER = "Raider",
		ENEMY_SHAMAN = "Goblin Shaman",
		ENEMY_WARCHIEF = "Orc Warchief",
		ENEMY_BONE = "Bone Guard",
		ENEMY_HUNTER = "Dusk Stalker",
		ENEMY_WARLOCK = "Warlock",
		ENEMY_LICH = "Lich King",
		ENEMY_KNIGHT = "Ash Knight",
		ENEMY_DARK = "Void Archmage",
		ENEMY_DRAKE = "Dragonlord",
		ENEMY_OVERLORD = "Dark Overlord",
		MISS_RES = "Not enough resources",
	},
}

M.lang = "ru"

function M.detect()
	local l = sys.get_sys_info().language or "en"
	l = string.lower(string.sub(l, 1, 2))
	return STRINGS[l] and l or "en"
end

function M.set(lang)
	M.lang = STRINGS[lang] and lang or "ru"
end

function M.t(key, vars)
	local s = (STRINGS[M.lang] and STRINGS[M.lang][key]) or STRINGS.en[key] or key
	if vars then
		for k, v in pairs(vars) do
			s = string.gsub(s, "{" .. k .. "}", tostring(v))
		end
	end
	return s
end

function M.fmt_time(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		local h = math.floor(sec / 3600)
		local m = math.floor((sec % 3600) / 60)
		return string.format("%dh %02dm", h, m)
	elseif sec >= 60 then
		local m = math.floor(sec / 60)
		local s = sec % 60
		return string.format("%d:%02d", m, s)
	end
	return string.format("%ds", sec)
end

return M
