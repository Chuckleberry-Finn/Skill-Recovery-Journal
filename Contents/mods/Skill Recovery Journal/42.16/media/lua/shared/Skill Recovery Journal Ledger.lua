-- Skill Recovery Journal - Ledger
--
-- A journal uses unique object ID. Every journal (however many a player carries) gets its own independent record,
-- so writing to a "daily carry" journal never touches a "home" journal's data.
-- TODO: Confirm the unique ID for objects is persistent, or assign one using UUID

-- A life is identified by a random stamp minted once per character in Events.OnCreatePlayer and stored on that character's own modData.
-- Since a new IsoPlayer object has no prior modData, death naturally produces a brand new stamp with no special-casing required.
-- TODO: Confirm if this is needed at all- original idea was to use hours survived to confirm the character is younger than who last wrote to the journal
--- this might create a window where you can't write to the journal within the same hour(?)

-- A journal should still use one of the 3 security features to confirm ownership, the stamp is just cross life checking


local SRJ_ModDataHandler = require "Skill Recovery Journal ModData"

local SRJ_Ledger = {}

local LEDGER_PATH = "SRJ/journals.json"

-- { journals = { [journalID] = {
--     writtenByLives = { [lifeStamp] = true, ... },
--     redemption     = { [perkID] = { [lifeStamp] = { granted = X } } },
--     flatRedemption = { [perkID] = { [lifeStamp] = { granted = X } } },
--     sealed         = false, --- true when RecoveryJournalUsed is enabled
--     sealedByLife   = nil,
--     lastInteracted = { date = "", x = 0, y = 0, z = 0 },
-- } } }
local state = { journals = {} }
local loaded = false


-- ===== persistence =====

local function ensureLoaded()
    if loaded or not isServer() then return end
    loaded = true

    local stream = getFileInput(LEDGER_PATH)
    if not stream then
        if getDebug() then print("SRJ Ledger: no journals.json found, starting fresh") end
        return
    end

    local chars = {}
    local b = stream:read()
    while b ~= -1 do
        table.insert(chars, string.char(b))
        b = stream:read()
    end
    stream:close()

    local raw = table.concat(chars)
    if raw == "" then return end

    local ok, parsed = pcall(SRJ_ModDataHandler.jsonDecode, raw)
    if ok and parsed and parsed.journals then
        state = parsed
    elseif getDebug() then
        print("SRJ Ledger: journals.json failed to parse, starting fresh")
    end
end


function SRJ_Ledger.save()
    if not isServer() then return end
    local writer = getFileWriter(LEDGER_PATH, true, false)
    if not writer then
        print("SRJ ERROR: could not open " .. LEDGER_PATH .. " for writing")
        return
    end
    writer:write(SRJ_ModDataHandler.jsonEncode(state))
    writer:close()
    if getDebug() then print("SRJ Ledger: saved journals.json") end
end


-- ===== life identity =====

-- Called from Events.OnCreatePlayer - a brand new character always gets a
-- brand new stamp, unconditionally.
function SRJ_Ledger.mintLifeStamp(player)
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    local seed = (player.getUsername and player:getUsername()) or "sp"
    pMD.SRJLifeStamp = seed .. ":" .. tostring(getTimestampMs()) .. ":" .. tostring(ZombRand(100000, 999999))
    return pMD.SRJLifeStamp
end

-- Fallback getter for characters that predate this system - mints lazily so
-- there's no bootstrapping/migration logic that has to reason about old data.
function SRJ_Ledger.getLifeStamp(player)
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    if not pMD.SRJLifeStamp then
        SRJ_Ledger.mintLifeStamp(player)
    end
    return pMD.SRJLifeStamp
end


-- ===== journal records =====

local function journalID(item)
    return tostring(item:getID())
end


local function getRecord(item)
    ensureLoaded()
    local id = journalID(item)
    state.journals[id] = state.journals[id] or {}
    local rec = state.journals[id]
    rec.writtenByLives = rec.writtenByLives or {}
    rec.redemption = rec.redemption or {}
    rec.flatRedemption = rec.flatRedemption or {}
    rec.lastInteracted = rec.lastInteracted or {}
    return rec
end


-- Stamp this journal as having been written to by the player's current life.
-- Call this once, when a write action is actually going to write something.
function SRJ_Ledger.markWriter(item, player)
    if not isServer() then return end
    local rec = getRecord(item)
    rec.writtenByLives[SRJ_Ledger.getLifeStamp(player)] = true
end


-- Can this player's current life read this journal at all?
-- Returns true, or false + a reason text key.
function SRJ_Ledger.canRead(item, player)
    if not isServer() then return true end
    local rec = getRecord(item)
    local lifeStamp = SRJ_Ledger.getLifeStamp(player)

    if rec.writtenByLives[lifeStamp] then
        return false, "IGUI_PlayerText_DoesntFeelRightToRead"
    end

    if rec.sealed and rec.sealedByLife ~= lifeStamp then
        return false, "IGUI_PlayerText_KnowSkill"
    end

    return true
end


-- Per (journal, perk, reading-life) redemption cap. `flat` selects the
-- flat-XP table instead of the regular skill-XP table.
function SRJ_Ledger.getRedemptionRecord(item, player, perkID, flat)
    local rec = getRecord(item)
    local bucket = flat and rec.flatRedemption or rec.redemption
    bucket[perkID] = bucket[perkID] or {}
    local lifeStamp = SRJ_Ledger.getLifeStamp(player)
    bucket[perkID][lifeStamp] = bucket[perkID][lifeStamp] or { granted = 0 }
    return bucket[perkID][lifeStamp]
end


-- Mark this journal permanently exhausted once the RecoveryJournalUsed
-- sandbox option is on and a grant has actually happened. The life currently
-- reading is exempted so it can keep reading across multiple sessions before
-- the journal is fully drained.
function SRJ_Ledger.sealIfOneTimeUse(item, player)
    if SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed ~= true then return end
    local rec = getRecord(item)
    rec.sealed = true
    rec.sealedByLife = SRJ_Ledger.getLifeStamp(player)
end


function SRJ_Ledger.touchInteraction(item, player)
    if not isServer() then return end
    local rec = getRecord(item)
    -- os.date is not available in PZ's Kahlua sandbox; store a raw ms
    -- timestamp instead (matches getTimestampMs() used elsewhere for the
    -- life stamp). Convert to a readable date client-side/tooling-side if needed.
    rec.lastInteracted.timestampMs = getTimestampMs()
    rec.lastInteracted.x = math.floor(player:getX())
    rec.lastInteracted.y = math.floor(player:getY())
    rec.lastInteracted.z = math.floor(player:getZ())
end


return SRJ_Ledger
