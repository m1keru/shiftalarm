-- Проверка ShiftAlarm без игры: lua tests/mock.lua ShiftAlarm.lua (из папки аддона).
-- Мана в бою отдаётся как таблица-«секрет»: любое сравнение маны в коде аддона упадёт.
-- Заглушки WoW API: мана в бою отдаётся как «секрет» (таблица) — любое сравнение в коде упадёт.
local SECRET = {}
local function secret(n) return setmetatable({ v = n }, SECRET) end
function issecretvalue(x) return getmetatable(x) == SECRET end
local function plain(x) return issecretvalue(x) and x.v or x end

local frames = {}
local function newRegion()
  local r = { shown = true, points = {} }
  local mt = {}
  mt.__index = function(t, k)
    return mt[k] or function() end
  end
  function mt.SetShown(self, s) self.shown = s end
  function mt.Show(self) self.shown = true end
  function mt.Hide(self) self.shown = false end
  function mt.IsShown(self) return self.shown end
  function mt.SetMinMaxValues(self, a, b) self.min, self.max = a, b end
  function mt.SetValue(self, v) self.value = plain(v) end
  function mt.GetStatusBarTexture(self) local t = rawget(self, "tex") or newRegion(); rawset(self, "tex", t); return t end
  function mt.CreateTexture() return newRegion() end
  function mt.CreateFontString() return newRegion() end
  function mt.GetFrameLevel() return 1 end
  function mt.GetPoint(self) return "CENTER", nil, "CENTER", 10, 20 end
  function mt.RegisterEvent(self, e) local t = rawget(self, "evs") or {}; rawset(self, "evs", t); t[e] = true end
  function mt.RegisterUnitEvent(self, e) local t = rawget(self, "evs") or {}; rawset(self, "evs", t); t[e] = true end
  function mt.SetScript(self, k, f) rawset(self, k, f) end
  return setmetatable(r, mt)
end
function CreateFrame(kind) local f = newRegion(); f.kind = kind; frames[#frames + 1] = f; return f end
UIParent = newRegion()
Enum = { PowerType = { Mana = 0 } }
STANDARD_TEXT_FONT = "x"
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) LAST_MSG = m end }
SlashCmdList = {}
local combat, mana = false, 2000
function UnitClass() return "Друид", "DRUID" end
function InCombatLockdown() return combat end
function UnitPower() return combat and secret(mana) or mana end
function IsPlayerSpell(id) return id == 5189 or id == 5185 end
local COST = { [768] = 413, [5189] = 350, [8936] = 280 }
C_Spell = {
  GetSpellPowerCost = function(id) if combat then return secret(0) end; return COST[id] and { { type = 0, cost = COST[id] } } or {} end,
  GetSpellInfo = function(x) if x == "Восстановление" or x == 8936 then return { spellID = 8936 } end end,
}

dofile(arg[1])
local ev = frames[1]
ev.OnEvent(ev, "PLAYER_LOGIN")
local bars = {}
for _, f in ipairs(frames) do if f.kind == "StatusBar" then bars[#bars + 1] = f end end
local yellow, red = bars[1], bars[2]
local root = frames[2]
local function open(b) return root.shown and b.shown and rawget(b, "value") < rawget(b, "max") end
local function check(name, m, wantRed, wantYellow)
  mana = m
  ev.OnEvent(ev, "UNIT_POWER_FREQUENT", "player")
  assert(open(red) == wantRed, name .. ": red " .. tostring(open(red)))
  assert(open(yellow) == wantYellow, name .. ": yellow " .. tostring(open(yellow)))
  print("ok", name)
end

assert(not root.shown, "вне боя скрыто по умолчанию")
combat = true; ev.OnEvent(ev, "PLAYER_REGEN_DISABLED")
check("полно маны", 2000, false, false)
check("на хил не хватит", 700, false, true)   -- 413+350=763
check("ровно на кошку+хил", 763, false, false)
check("ровно на кошку", 413, false, true)
check("на кошку не хватит", 412, true, true)
check("ноль", 0, true, true)
-- смена хила в бою не ломается и не считает секреты
SlashCmdList.SHIFTALARM("heal Восстановление")
check("хил сменён в бою, старый порог", 700, false, true)
combat = false; ev.OnEvent(ev, "PLAYER_REGEN_ENABLED")
assert(not root.shown, "после боя скрыто")
combat = true; ev.OnEvent(ev, "PLAYER_REGEN_DISABLED")
check("новый хил 280: 700 хватает", 700, false, false)
check("новый хил 280: 690 нет", 690, false, true)
SlashCmdList.SHIFTALARM("heal off")
combat = false; ev.OnEvent(ev, "PLAYER_REGEN_ENABLED"); combat = true; ev.OnEvent(ev, "PLAYER_REGEN_DISABLED")
check("жёлтое выключено", 500, false, false)
SlashCmdList.SHIFTALARM("unlock")
assert(open(red) and open(yellow) and root.shown, "unlock показывает обе рамки")
SlashCmdList.SHIFTALARM("lock")
check("после lock снова по мане", 2000, false, false)
SlashCmdList.SHIFTALARM("")
print("status:", LAST_MSG)

-- /reload посреди боя: стоимости секретны, пороги берутся из сохранённых настроек.
SlashCmdList.SHIFTALARM("heal")
combat = false; ev.OnEvent(ev, "PLAYER_REGEN_ENABLED")
for k in pairs(frames) do frames[k] = nil end
combat = true
dofile(arg[1])
ev = frames[1]
ev.OnEvent(ev, "PLAYER_LOGIN")
bars = {}
for _, f in ipairs(frames) do if f.kind == "StatusBar" then bars[#bars + 1] = f end end
yellow, red, root = bars[1], bars[2], frames[2]
check("reload в бою: жёлтое по запомненному хилу", 700, false, true)
check("reload в бою: красное", 400, true, true)
