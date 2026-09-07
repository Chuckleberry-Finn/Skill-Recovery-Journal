local shared = "Contents/mods/Skill Recovery Journal/42.20.1/media/lua/shared/"
package.path = shared .. "?.lua;" .. package.path
local modData = require "Skill Recovery Journal ModData"

local currentPath = "SkillRecoveryJournal/Sandbox/Test/alice.json"
local legacyPath = "SkillRecoveryJournal/Sandbox/Test/alice.txt"

local function setup(files, blockedPath)
    isClient = function() return false end
    isServer = function() return true end
    getDebug = function() return false end
    getCurrentSaveName = function() return "Sandbox/Test" end
    getFileSeparator = function() return "/" end
    getTimestampMs = function() return 1000 end
    ZombRand = function() return 123 end
    getFileReader = function(path)
        if files[path] == nil then return nil end
        local unread = files[path]
        return {
            readLine = function()
                local line = unread
                unread = nil
                return line
            end,
            close = function() end,
        }
    end
    getFileWriter = function(path)
        if path == blockedPath then return nil end
        files[path] = ""
        return {
            write = function(_, text) files[path] = files[path] .. text end,
            close = function() end,
        }
    end
    return dofile(shared .. "Skill Recovery Journal Ledger.lua"), function() blockedPath = nil end
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

test("a newly saved journal can be edited without restarting", function()
    local files = {}
    local ledger = setup(files)
    local player = {getUsername = function() return "alice" end}
    local itemData = {}
    local item = {getModData = function() return itemData end}
    local record = ledger.getJournalRecord(item, player)
    record.gainedXP.Woodwork = 100
    ledger.save(player)
    assert(files[currentPath], "normal journal save must create its ledger")
    assert(ledger.adminLedgerExists("alice"), "saved ledger was reported as nonexistent")
    local edited = ledger.adminGetJournalRecord("alice", itemData.SRJ.ledgerID)
    edited.gainedXP.Woodwork = 200
    local ok, reason = ledger.adminSaveJournalRecord("alice", itemData.SRJ.ledgerID, edited)
    assert(ok, tostring(reason))
    local saved = modData.jsonDecode(files[currentPath])
    assert(saved.journals[itemData.SRJ.ledgerID].gainedXP.Woodwork == 200)
end)

test("lookup alone does not authorize creating an arbitrary ledger", function()
    local ledger = setup({})
    ledger.adminGetFullLedger("alice")
    local ok, reason = ledger.adminSaveJournalRecord("alice", "invented", {gainedXP = {}})
    assert(not ok and reason == "no_existing_ledger")
end)

test("failed migration preserves the legacy journal file", function()
    local original = modData.jsonEncode({journals = {journal = {gainedXP = {Woodwork = 100}}}})
    local files = {[legacyPath] = original}
    local ledger = setup(files, currentPath)
    local loaded = ledger.adminGetJournalRecord("alice", "journal")
    assert(loaded.gainedXP.Woodwork == 100)
    assert(files[legacyPath] == original, "migration erased the only saved copy")
    assert(files[currentPath] == nil)

    local reloaded = setup(files).adminGetJournalRecord("alice", "journal")
    assert(reloaded and reloaded.gainedXP.Woodwork == 100, "journal was lost after restart")
end)

test("successful migration retires the legacy file and survives restart", function()
    local files = {[legacyPath] = modData.jsonEncode({journals = {journal = {gainedXP = {Woodwork = 100}}}})}
    local ledger = setup(files)
    local record = ledger.adminGetJournalRecord("alice", "journal")
    assert(files[legacyPath] == "")
    assert(modData.jsonDecode(files[currentPath]).journals.journal.gainedXP.Woodwork == 100)
    record.gainedXP.Woodwork = 200
    assert(ledger.adminSaveJournalRecord("alice", "journal", record))
    local reloaded = setup(files).adminGetJournalRecord("alice", "journal")
    assert(reloaded.gainedXP.Woodwork == 200, "stale legacy data replaced the latest journal")
end)

test("a later normal save completes migration after a failed initial write", function()
    local original = modData.jsonEncode({journals = {journal = {gainedXP = {Woodwork = 100}}}})
    local files = {[legacyPath] = original}
    local ledger, unblock = setup(files, currentPath)
    local player = {getUsername = function() return "alice" end}
    local itemData = {SRJ = {ledgerID = "journal", routingKey = "alice"}}
    local item = {getModData = function() return itemData end}
    local record = ledger.getJournalRecord(item, player)
    assert(files[legacyPath] == original)
    assert(files[currentPath] == nil)
    record.gainedXP.Woodwork = 200
    unblock()
    ledger.save(player)
    assert(files[legacyPath] == "", "successful retry must retire the stale legacy ledger")
    local reloaded = setup(files).adminGetJournalRecord("alice", "journal")
    assert(reloaded.gainedXP.Woodwork == 200, "later save was overwritten with stale legacy data")
end)

test("legacy retirement is retried if its writer was temporarily unavailable", function()
    local original = modData.jsonEncode({journals = {journal = {gainedXP = {Woodwork = 100}}}})
    local files = {[legacyPath] = original}
    local ledger, unblock = setup(files, legacyPath)
    local record = ledger.adminGetJournalRecord("alice", "journal")
    assert(files[legacyPath] == original)
    assert(files[currentPath], "the new ledger should have been saved")
    record.gainedXP.Woodwork = 200
    unblock()
    assert(ledger.adminSaveJournalRecord("alice", "journal", record))
    assert(files[legacyPath] == "", "later saves must retry retiring the legacy file")
    local reloaded = setup(files).adminGetJournalRecord("alice", "journal")
    assert(reloaded.gainedXP.Woodwork == 200)
end)

test("failed admin save reports failure and preserves the record", function()
    local original = modData.jsonEncode({journals = {journal = {gainedXP = {Woodwork = 100}}}})
    local files = {[currentPath] = original}
    local ledger = setup(files, currentPath)
    local edited = ledger.adminGetJournalRecord("alice", "journal")
    edited.gainedXP.Woodwork = 200
    local ok, reason = ledger.adminSaveJournalRecord("alice", "journal", edited)
    assert(not ok and reason == "save_failed", "failed write was reported as saved")
    assert(ledger.adminGetJournalRecord("alice", "journal").gainedXP.Woodwork == 100)
    assert(files[currentPath] == original)
end)

test("failed admin delete reports failure and preserves the record", function()
    local original = modData.jsonEncode({journals = {journal = {gainedXP = {Woodwork = 100}}}})
    local files = {[currentPath] = original}
    local ledger = setup(files, currentPath)
    assert(not ledger.adminDeleteJournalRecord("alice", "journal"), "failed write was reported as deleted")
    assert(ledger.adminGetJournalRecord("alice", "journal").gainedXP.Woodwork == 100)
    assert(files[currentPath] == original)
end)

assert(failures == 0, tostring(failures) .. " ledger persistence regression(s) failed")
