-- Run from the repository root: lua tests/action_progress_test.lua
local shared = "Contents/mods/Skill Recovery Journal/42.20.1/media/lua/shared/"
package.path = shared .. "?.lua;" .. package.path

local server = false
function isClient() return false end
function isServer() return server end
function getDebug() return false end
function getText(key) return key end
function getActivatedMods() return { contains = function() return true end } end
function round(value, places)
    local scale = 10 ^ places
    return math.floor(value * scale + 0.5) / scale
end
Events = { OnGameTimeLoaded = { Add = function() end } }
UIFont = { Dialogue = "Dialogue" }
Perks = {}
CharacterTrait = { ILLITERATE = "Illiterate" }

local halos, commands = {}, {}
HaloTextHelper = {
    getColorWhite = function() return {} end,
    addText = function(_, text) table.insert(halos, text) end,
}
function sendServerCommand(_, _, command, args)
    table.insert(commands, { command = command, args = args })
end

local record
package.preload["Skill Recovery Journal XP"] = function() return {} end
package.preload["Skill Recovery Journal ModData"] = function()
    return {
        hasModDataToTransfer = function() return false end,
        copyDataToJournal = function() end,
        copyDataToPlayer = function() end,
    }
end
package.preload["Skill Recovery Journal Ledger"] = function()
    return {
        getJournalRecord = function() return record end,
        getReadXPAny = function() return {} end,
        getReadXP = function() return {} end,
        syncDisplay = function() end,
        save = function() end,
    }
end
ISBaseTimedAction = { derive = function() return {} end }
package.preload["TimedActions/ISBaseTimedAction"] = function() return ISBaseTimedAction end

local SRJ = require "Skill Recovery Journal Main"
require "Skill Recovery Journal Calc"
require "Skill Recovery Journal Action Util"
require "Skill Recovery Journal Action"

local player = {
    hasTrait = function() return false end,
    Say = function() end,
}
local now = 100
SRJ.gameTime = { getWorldAgeHours = function() return now end }

local function newRecipeAction(count, speed)
    halos, commands = {}, {}
    SandboxVars = { SkillRecoveryJournal = { TranscribeSpeed = speed, KillsTrack = 0 } }
    record = { learnedRecipes = {}, gainedXP = {}, kills = {} }
    local recipes = {}
    for i = 1, count do recipes[i] = "Recipe" .. i end
    local item = { setJobDelta = function() end }
    local action = setmetatable({
        isAllowed = true,
        character = player,
        item = item,
        doReading = false,
        gainedRecipes = recipes,
        durationData = SRJ.calculateReadWriteRates(player, item, 1, recipes, nil, nil, false, 10 / 3600),
        changesBeingMade = {},
        changesBeingMadeIndex = {},
        updates = -1,
        updateTime = now,
        updateInterval = 10 / 3600,
        lastUpdateTime = 0,
        forceStop = function(self) self.stopped = true end,
    }, { __index = SkillRecoveryJournalAction })
    return action
end

local function runAction(action)
    for _ = 1, 100 do
        now = now + 10 / 3600
        action:updateTick()
        if action.stopped then return end
    end
    error("recipe action did not finish")
end

local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("PASS: " .. name)
    else
        failures = failures + 1
        print("FAIL: " .. name .. ": " .. tostring(err))
    end
end

test("fractional recipe speeds use the same chunk size for duration and processing", function()
    local action = newRecipeAction(9, 1.9)
    runAction(action)
    assert(action.updates <= action.durationData.intervals,
        "action exceeded its estimated duration: " .. action.updates .. "/" .. action.durationData.intervals)
    for i = 1, 9 do assert(record.learnedRecipes["Recipe" .. i]) end
    for _, text in ipairs(halos) do
        local percent = tonumber(text:match("%((%d+)%%%)"))
        assert(percent and percent <= 100, "invalid progress: " .. text)
    end
end)

test("completion sends recipe progress buffered inside the halo interval", function()
    local action = newRecipeAction(2, 1)
    runAction(action)
    local reported = 0
    for _, text in ipairs(halos) do
        reported = reported + (tonumber(text:match("%+(%d+) IGUI_Tooltip_Recipe")) or 0)
    end
    assert(reported == 2, "reported " .. reported .. " of 2 transcribed recipes")
end)

test("a single recipe reports completion instead of zero percent", function()
    local action = newRecipeAction(1, 1)
    runAction(action)
    assert(halos[#halos]:find("(100%)", 1, true), halos[#halos])
end)

test("recipe duration counts the first chunk on tick zero", function()
    local action = newRecipeAction(2, 1)
    runAction(action)
    assert(halos[#halos]:find("(100%)", 1, true), halos[#halos])
end)

test("server completion sends the last progress chunk to the client", function()
    local action = newRecipeAction(2, 1)
    server = true
    runAction(action)
    server = false
    local reported = 0
    for _, command in ipairs(commands) do
        if command.command == "write_changes" then
            for _, change in ipairs(command.args.changesBeingMade) do
                if type(change) == "number" then reported = reported + change end
            end
        end
    end
    assert(reported == 2, "server reported " .. reported .. " of 2 transcribed recipes")
end)

test("halo percentages stay bounded when work exceeds the estimate", function()
    halos = {}
    SRJ.showHaloProgressText(player, { "IGUI_perks_Woodwork" }, 12, 10, "IGUI_Tooltip_Transcribing")
    assert(halos[1]:find("(100%)", 1, true), halos[1])
end)

test("kill transcription stops at the configured recovery percentage", function()
    SandboxVars.SkillRecoveryJournal.KillsTrack = 50
    local char = {
        getZombieKills = function() return 20 end,
        getSurvivorKills = function() return 10 end,
    }
    local journal = { kills = { Zombie = 0, Survivor = 0 } }
    local duration = { rates = { zKills = 3, sKills = 2 } }
    for _ = 1, 12 do SRJ.handleKills(duration, char, journal, false) end
    assert(journal.kills.Zombie == 10, "recorded " .. journal.kills.Zombie .. " instead of 10 zombie kills")
    assert(journal.kills.Survivor == 5, "recorded " .. journal.kills.Survivor .. " instead of 5 survivor kills")
end)

test("reading an older journal cannot reduce current kill counts", function()
    SandboxVars.SkillRecoveryJournal.KillsTrack = 100
    local zombies, survivors = 20, 10
    local char = {
        getZombieKills = function() return zombies end,
        getSurvivorKills = function() return survivors end,
        setZombieKills = function(_, value) zombies = value end,
        setSurvivorKills = function(_, value) survivors = value end,
    }
    local journal = { kills = { Zombie = 10, Survivor = 5 } }
    local duration = { rates = { zKills = 3, sKills = 2 } }
    SRJ.handleKills(duration, char, journal, true)
    assert(zombies == 20 and survivors == 10, "reading reduced earned kill counts")
    local zRemaining, sRemaining = SRJ.calculateGainedKills(journal, char, true)
    assert(zRemaining == 0 and sRemaining == 0, "duration still counts already recovered kills")
end)

test("kill recovery finishes at the stored totals and accounts for existing kills", function()
    SandboxVars.SkillRecoveryJournal.KillsTrack = 100
    local zombies, survivors = 4, 3
    local char = {
        getZombieKills = function() return zombies end,
        getSurvivorKills = function() return survivors end,
        setZombieKills = function(_, value) zombies = value end,
        setSurvivorKills = function(_, value) survivors = value end,
    }
    local journal = { kills = { Zombie = 10, Survivor = 5 } }
    local zRemaining, sRemaining = SRJ.calculateGainedKills(journal, char, true)
    assert(zRemaining == 6 and sRemaining == 2, "duration includes existing kills")
    local duration = { rates = { zKills = 3, sKills = 2 } }
    for _ = 1, 5 do SRJ.handleKills(duration, char, journal, true) end
    assert(zombies == 10 and survivors == 5)
    assert(SRJ.calculateGainedKills(journal, char, true) == 0)
end)

assert(failures == 0, tostring(failures) .. " action progress regression(s)")
