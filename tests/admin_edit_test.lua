local clientPath = "Contents/mods/Skill Recovery Journal/42.20.1/media/lua/client/"
local sharedPath = "Contents/mods/Skill Recovery Journal/42.20.1/media/lua/shared/"

for _, module in ipairs({
    "ISUI/ISCollapsableWindow", "ISUI/ISButton", "ISUI/ISTextEntryBox",
    "ISUI/ISScrollingListBox", "ISUI/ISTickBox", "ISUI/ISLabel",
    "DebugUIs/DebugMenu/ISDebugMenu.lua", "ISUI/AdminPanel/ISAdminPanelUI.lua",
}) do
    package.preload[module] = function() return {} end
end

ISCollapsableWindow = { derive = function() return {} end }
Events = {
    OnServerCommand = { Add = function() end },
    OnClientCommand = { Add = function() end },
}
local savedRecords = {}
package.preload["Skill Recovery Journal Ledger"] = function()
    return {
        adminSaveJournalRecord = function(username, ledgerID, record)
            savedRecords[ledgerID] = record
            return true
        end,
        adminGetJournalRecord = function(username, ledgerID)
            return savedRecords[ledgerID]
        end,
    }
end
local adminEvents = dofile(sharedPath .. "Skill Recovery Journal Admin Events.lua")
package.loaded["Skill Recovery Journal Admin Events"] = adminEvents

isClient = function() return false end
isServer = function() return true end
getDebug = function() return false end
local player = { getAccessLevel = function() return "Admin" end }
getPlayer = function() return player end
local request, response
sendClientCommand = function(player, module, command, args)
    request = { module = module, command = command, args = args }
end
sendServerCommand = function(player, module, command, args)
    response = { command = command, args = args }
end

dofile(clientPath .. "Skill Recovery Journal Admin Panel.lua")

local function textEntry(value)
    return { getText = function() return value end }
end

local panel = setmetatable({
    editingRecord = {
        identity = { username = "Alice" },
        lastInteracted = { timestampMs = 1234 },
        pModData = { character = "Alice" },
    },
    rowEntries = {
        author = textEntry("Alice"),
        renamedJournal = textEntry("true"),
        ["gainedXP.Woodwork"] = textEntry("125"),
        ["flatGainedXP.Fitness"] = textEntry("250"),
        ["learnedRecipes.Base.MakeBread"] = textEntry("true"),
        ["kills.Zombie"] = textEntry("40"),
        ["kills.Survivor"] = textEntry("2"),
        ["usedXP.Woodwork"] = textEntry("50"),
        ["usedXP.flat.Fitness"] = textEntry("75.5"),
        ["usedXP.flat.Strength"] = textEntry("30"),
    },
}, { __index = SRJAdminPanel })

local record = panel:collectEditedRecord()
assert(record.usedXP.flat.Fitness == 75.5, "saving must preserve consumed flat Fitness XP")
assert(record.usedXP.flat.Strength == 30, "saving must preserve consumed flat Strength XP")
assert(record.usedXP["flat.Fitness"] == nil, "flat XP must remain nested")
assert(record.usedXP.Woodwork == 50)
assert(record.gainedXP.Woodwork == 125)
assert(record.flatGainedXP.Fitness == 250)
assert(record.learnedRecipes["Base.MakeBread"] == true)
assert(record.kills.Zombie == 40 and record.kills.Survivor == 2)
assert(record.author == "Alice" and record.renamedJournal == true)
assert(record.identity.username == "Alice")
assert(record.lastInteracted.timestampMs == 1234)
assert(record.pModData.character == "Alice")

local function respondToSave(panel)
    adminEvents.SkillRecoveryJournalAdminOnClientCommand(request.module, request.command, player, request.args)
    assert(response.command == "saveResult" and response.args.success)
    panel:onServerResponse(response.command, response.args)
end

local journalA = { author = "Alice", identity = { username = "Alice" } }
local journalB = { author = "Bob", identity = { username = "Bob" } }
panel.currentUsername = "Alice"
panel.selectedLedgerID = "journalA"
panel.editingRecord = journalA
panel.currentLedger = { journals = { journalA = journalA, journalB = journalB } }
panel.rowEntries = { author = textEntry("Alice edited") }
panel:onSave()

-- Selecting another row is immediate, while the save reply arrives over the network.
panel.selectedLedgerID = "journalB"
panel.editingRecord = journalB
panel.rowEntries = { author = textEntry("Bob") }
respondToSave(panel)
assert(panel.currentLedger.journals.journalA.author == "Alice edited", "a delayed save reply must preserve the submitted journal")
assert(panel.currentLedger.journals.journalA.identity.username == "Alice", "a delayed save reply must not copy another journal's identity")
assert(panel.currentLedger.journals.journalB == journalB)
assert(panel.selectedLedgerID == "journalB" and panel.editingRecord == journalB)

panel:onSave()
panel.rowEntries.author = textEntry("Bob unsaved")
respondToSave(panel)
assert(panel.currentLedger.journals.journalB.author == "Bob", "edits made after Save must not be treated as saved")

panel:onSave()
panel.currentUsername = "Charlie"
panel.currentLedger = { journals = {} }
panel.editingRecord = nil
respondToSave(panel)
assert(next(panel.currentLedger.journals) == nil, "a save reply for another username must not alter the current ledger")

print("admin_edit_test: passed")
