-- ShiftAlarm: крупное предупреждение посреди экрана, когда маны не хватит вернуться в облик кошки.
--
-- В бою мана — секретное значение: его можно отдать виджету, но нельзя сравнить в коде. Поэтому
-- каждое предупреждение лежит в пустой части невидимой StatusBar с порогом ровно в стоимость:
-- маны хватает — полоса полная, окно с предупреждением нулевой ширины; не хватает — полоса пустая,
-- окно во всю ширину. Сравнивает движок, а не код. Тот же приём использует Formwise.

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local CAT_FORM = 768
-- Целительное прикосновение, ранги 1-11: по умолчанию берётся старший изученный.
local HEALING_TOUCH = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DEFAULTS = { point = "CENTER", x = 0, y = -150, combatOnly = true }

local db
local root, red, yellow
local inCombat, unlocked = false, false
local catCost, healCost

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0aShiftAlarm|r: " .. msg)
end

-- Мана за заклинание; nil, если клиент не говорит (секрет в бою, заклинание неизвестно).
local function manaCost(spell)
    if not (spell and C_Spell and C_Spell.GetSpellPowerCost) then
        return nil
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spell)
    if not ok or isSecret(costs) or type(costs) ~= "table" then
        return nil
    end
    for _, c in ipairs(costs) do
        if not isSecret(c.type) and c.type == MANA and not isSecret(c.cost) then
            return c.cost
        end
    end
    return nil
end

local function known(spellID)
    local ok, v = pcall(IsPlayerSpell, spellID)
    return ok and not isSecret(v) and v == true
end

local function defaultHeal()
    for i = #HEALING_TOUCH, 1, -1 do
        if known(HEALING_TOUCH[i]) then
            return HEALING_TOUCH[i]
        end
    end
    return nil
end

-- Стоимости читаются только вне боя (в бою они могут быть секретом) и запоминаются.
local function refreshCosts()
    local cat = manaCost(CAT_FORM)
    if not cat and FormwiseCharDB and FormwiseCharDB.costs then
        cat = FormwiseCharDB.costs.cat
    end
    catCost = cat or db.catCost
    db.catCost = catCost
    healCost = manaCost(db.heal or defaultHeal())
    if not healCost and db.heal ~= 0 then
        healCost = db.healCost -- после /reload в бою стоимость секретна: берём запомненную
    end
    db.healCost = healCost
end

-- Предупреждение: невидимая полоса на весь root и окно от конца её заливки до правого края.
local function newAlert(level, r, g, b, bgAlpha, label)
    local bar = CreateFrame("StatusBar", nil, root)
    bar:SetAllPoints()
    bar:SetFrameLevel(root:GetFrameLevel() + level)
    bar:SetStatusBarTexture(WHITE)
    bar:GetStatusBarTexture():SetAlpha(0)

    local window = CreateFrame("Frame", nil, bar)
    window:SetClipsChildren(true)
    window:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT")
    window:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")

    local box = CreateFrame("Frame", nil, window)
    box:SetAllPoints(root) -- во всю ширину root, видна только часть внутри окна
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, bgAlpha)
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 4 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 4 },
        { "TOPLEFT", "BOTTOMLEFT", 4, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 4, nil },
    }
    for _, e in ipairs(edges) do
        local t = box:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, 1)
        t:SetPoint(e[1])
        t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
    end
    local text = box:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, 26, "OUTLINE")
    text:SetTextColor(r, g, b)
    text:SetPoint("CENTER")
    text:SetText(label)
    return bar
end

-- threshold: мана, ниже которой предупреждение видно; nil — не показывать.
local function setThreshold(bar, threshold, mana)
    if not threshold or threshold <= 0 then
        bar:Hide()
        return
    end
    bar:SetMinMaxValues(threshold - 1, threshold)
    bar:SetValue(mana)
    bar:Show()
end

local function update()
    if unlocked then
        return
    end
    root:SetShown(inCombat or not db.combatOnly)
    local mana = UnitPower("player", MANA)
    setThreshold(red, catCost, mana)
    setThreshold(yellow, catCost and healCost and catCost + healCost, mana)
end

local function savePosition()
    local point, _, relPoint, x, y = root:GetPoint()
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

local function setUnlocked(on)
    unlocked = on
    root:EnableMouse(on)
    root:SetMovable(on)
    if on then
        root:Show()
        -- Оба предупреждения открыты: полоса с порогом 1 и значением 0 пустая.
        for _, bar in ipairs({ red, yellow }) do
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            bar:Show()
        end
        print("перетащи рамку мышью, потом /sal lock")
    else
        update()
    end
end

local function build()
    root = CreateFrame("Frame", "ShiftAlarmFrame", UIParent)
    root:SetSize(340, 64)
    root:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x, db.y)
    root:SetFrameStrata("HIGH")
    root:SetClampedToScreen(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", root.StartMoving)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    yellow = newAlert(1, 1, 0.82, 0, 0.6, "НА ХИЛ НЕ ХВАТИТ")
    red = newAlert(3, 1, 0.15, 0.15, 1, "НЕ ВЫХОДИ ИЗ ОБЛИКА") -- над жёлтым и закрывает его
end

local function status()
    print(string.format("кошка %s маны, хил %s маны (%s), %s",
        catCost and tostring(catCost) or "?",
        healCost and tostring(healCost) or "?",
        db.heal == 0 and "жёлтое выключено" or db.heal and ("заклинание " .. tostring(db.heal))
            or "старшее Целительное прикосновение",
        db.combatOnly and "только в бою" or "всегда"))
    print("/sal unlock | lock | heal <id или название | off> | always | reset")
end

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "unlock" then
        setUnlocked(true)
    elseif cmd == "lock" then
        setUnlocked(false)
    elseif cmd == "always" then
        db.combatOnly = not db.combatOnly
        update()
        status()
    elseif cmd == "heal" then
        if arg == "off" then
            db.heal = 0 -- ни одно заклинание: жёлтое предупреждение выключено
        elseif arg == "" then
            db.heal = nil
        else
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(tonumber(arg) or arg)
            if not info then
                print("заклинание не найдено: " .. arg)
                return
            end
            db.heal = info.spellID
        end
        if inCombat then
            print("стоимость пересчитается после боя")
        else
            refreshCosts()
            update()
        end
        status()
    elseif cmd == "reset" then
        db.point, db.relPoint, db.x, db.y = DEFAULTS.point, nil, DEFAULTS.x, DEFAULTS.y
        root:ClearAllPoints()
        root:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    else
        status()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "DRUID" then
            return
        end
        ShiftAlarmDB = ShiftAlarmDB or {}
        db = ShiftAlarmDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        build()
        SLASH_SHIFTALARM1, SLASH_SHIFTALARM2 = "/sal", "/shiftalarm"
        SlashCmdList.SHIFTALARM = slash
        inCombat = InCombatLockdown() == true
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_LEVEL_UP",
            "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
            self:RegisterEvent(e)
        end
        self:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        self:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        refreshCosts()
        update()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        update()
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
        update()
    else
        if event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
        end
        if not inCombat then
            refreshCosts()
        end
        update()
    end
end)
