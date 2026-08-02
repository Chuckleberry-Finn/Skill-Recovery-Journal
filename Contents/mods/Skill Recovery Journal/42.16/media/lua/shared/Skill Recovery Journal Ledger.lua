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

local LEDGER_PATH_JSON = "SRJ/journals.json"
local LEDGER_PATH_TXT  = "SRJ/journals.txt"

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


local function readAllAndClose(stream)
    if not stream then return nil end
    local chars = {}
    local b = stream:read()
    while b ~= -1 do
        table.insert(chars, string.char(b))
        b = stream:read()
    end
    stream:close()
    local raw = table.concat(chars)
    if raw == "" then return nil end
    return raw
end


local function ensureLoaded()
    if loaded or not isServer() then return end
    loaded = true

    -- Prefer .json, fall back to .txt
    local raw = readAllAndClose(getFileInput(LEDGER_PATH_JSON))
    local source = LEDGER_PATH_JSON
    if not raw then
        raw = readAllAndClose(getFileInput(LEDGER_PATH_TXT))
        source = LEDGER_PATH_TXT
    end

    if not raw then
        if getDebug() then print("SRJ Ledger: no journals.json/.txt found, starting fresh") end
        return
    end

    local ok, parsed = pcall(SRJ_ModDataHandler.jsonDecode, raw)
    if ok and parsed and parsed.journals then
        state = parsed
    elseif getDebug() then
        print("SRJ Ledger: " .. source .. " failed to parse, starting fresh")
    end
end


function SRJ_Ledger.save()
    if not isServer() then return end
    local encoded = SRJ_ModDataHandler.jsonEncode(state)

    -- Try .json first, fall back to .txt
    local ok = false
    local writer = getFileWriter(LEDGER_PATH_JSON, true, false)
    if writer then
        ok = pcall(function()
            writer:write(encoded)
            writer:close()
        end)
    end

    if ok then
        if getDebug() then print("SRJ Ledger: saved journals.json") end
        return
    end

    if getDebug() then print("SRJ Ledger: could not save journals.json, falling back to journals.txt") end

    local txtWriter = getFileWriter(LEDGER_PATH_TXT, true, false)
    if not txtWriter then
        print("SRJ ERROR: could not open " .. LEDGER_PATH_JSON .. " or " .. LEDGER_PATH_TXT .. " for writing")
        return
    end
    local txtOk = pcall(function()
        txtWriter:write(encoded)
        txtWriter:close()
    end)
    if not txtOk then
        print("SRJ ERROR: failed to write " .. LEDGER_PATH_TXT)
        return
    end
    if getDebug() then print("SRJ Ledger: saved journals.txt") end
end


function SRJ_Ledger.mintLifeStamp(player)
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    local seed = (player.getUsername and player:getUsername()) or "sp"
    pMD.SRJLifeStamp = seed .. ":" .. tostring(getTimestampMs()) .. ":" .. tostring(ZombRand(100000, 999999))
    return pMD.SRJLifeStamp
end


function SRJ_Ledger.getLifeStamp(player)
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    if not pMD.SRJLifeStamp then
        SRJ_Ledger.mintLifeStamp(player)
    end
    return pMD.SRJLifeStamp
end


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


function SRJ_Ledger.markWriter(item, player)
    if not isServer() then return end
    local rec = getRecord(item)
    rec.writtenByLives[SRJ_Ledger.getLifeStamp(player)] = true
end


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


function SRJ_Ledger.getRedemptionRecord(item, player, perkID, flat)
    local rec = getRecord(item)
    local bucket = flat and rec.flatRedemption or rec.redemption
    bucket[perkID] = bucket[perkID] or {}
    local lifeStamp = SRJ_Ledger.getLifeStamp(player)
    bucket[perkID][lifeStamp] = bucket[perkID][lifeStamp] or { granted = 0 }
    return bucket[perkID][lifeStamp]
end


function SRJ_Ledger.sealIfOneTimeUse(item, player)
    if SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed ~= true then return end
    local rec = getRecord(item)
    rec.sealed = true
    rec.sealedByLife = SRJ_Ledger.getLifeStamp(player)
end


function SRJ_Ledger.touchInteraction(item, player)
    if not isServer() then return end
    local rec = getRecord(item)
    rec.lastInteracted.timestampMs = getTimestampMs()
    rec.lastInteracted.x = math.floor(player:getX())
    rec.lastInteracted.y = math.floor(player:getY())
    rec.lastInteracted.z = math.floor(player:getZ())
end


return SRJ_Ledger
