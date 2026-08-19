local SRJ_ModDataHandler = require "Skill Recovery Journal ModData"

local SRJ_Ledger = {}

local function isAuthoritative()
    return not isClient()
end

local LEDGER_NAMESPACE = "SkillRecoveryJournal"

local userStates  = {}   -- username -> { journals }
local loadedUsers = {}   -- username -> true
local existsOnDisk = {}  -- username -> true, ONLY set when a real file was actually found and loaded


local function sanitizeUsername(username)
    if not username or username == "" then return "_unclaimed" end
    local s = tostring(username)
    s = s:gsub("%.%.", "")
    s = s:gsub("[<>:\"/\\|%?%*%c]", "_")
    s = s:gsub("[%s%.]+$", "")
    if s == "" then return "_unclaimed" end
    local reserved = { CON=true, PRN=true, AUX=true, NUL=true }
    for i = 1, 9 do reserved["COM"..i] = true reserved["LPT"..i] = true end
    if reserved[s:upper()] then s = "_" .. s end
    if #s > 100 then s = s:sub(1, 100) end
    return s
end


local function usernameOf(player)
    local username = player.getUsername and player:getUsername()
    if not username or username == "" then return "sp" end
    return username
end


local function fileRoutingIdentity(player)
    if isClient() or isServer() then
        return usernameOf(player)
    end
    return "SinglePlayer"
end


local savePathPrefix

local function getSavePathPrefix()
    if savePathPrefix then return savePathPrefix end
    savePathPrefix = ""

    if type(getCurrentSaveName) ~= "function" or type(getFileSeparator) ~= "function" then
        if getDebug() then print("SRJ ERROR: getCurrentSaveName/getFileSeparator not available, ledger will not be save-scoped") end
        return savePathPrefix
    end

    local fullPath = getCurrentSaveName()
    if not fullPath or fullPath == "" then
        if getDebug() then print("SRJ ERROR: getCurrentSaveName returned nothing, ledger will not be save-scoped") end
        return savePathPrefix
    end

    local sep = getFileSeparator()
    local parts = {}
    for part in fullPath:gmatch("[^%" .. sep .. "]+") do
        table.insert(parts, part)
    end

    if #parts < 2 then
        return savePathPrefix
    end

    savePathPrefix = parts[#parts - 1] .. sep .. parts[#parts] .. sep
    return savePathPrefix
end


local function filePathWithExt(username, ext)
    local sep = (type(getFileSeparator) == "function" and getFileSeparator()) or "/"
    return LEDGER_NAMESPACE .. sep .. getSavePathPrefix() .. sanitizeUsername(username) .. "." .. ext
end

local function filePath(username)
    return filePathWithExt(username, "json")
end

local function legacyFilePath(username)
    return filePathWithExt(username, "txt")
end


local function readAllAndClose(reader)
    if not reader then return nil end
    local lines = {}
    local i = 0
    local line = reader:readLine()
    while line ~= nil do
        i = i + 1
        lines[i] = line
        line = reader:readLine()
    end
    reader:close()
    local raw = table.concat(lines, "\n")
    if raw == "" then return nil end
    return raw
end


local function freshUserState()
    return { journals = {} }
end


local function saveUsername(username)
    local u = userStates[username]
    if not u then return end

    local encoded = SRJ_ModDataHandler.jsonEncode(u)
    local writer = getFileWriter(filePath(username), true, false)
    if not writer then
        print("SRJ ERROR: could not open " .. filePath(username) .. " for writing")
        return
    end
    writer:write(encoded)
    writer:close()
    if getDebug() then print("SRJ Ledger: saved " .. filePath(username)) end
end


local function ensureUserLoaded(username)
    if loadedUsers[username] then return userStates[username] end

    -- legacy .txt takes priority if present (pre-migration state); falls back to .json (already-migrated or brand new)
    local legacyPath = legacyFilePath(username)
    local currentPath = filePath(username)

    local okRead, raw = pcall(readAllAndClose, getFileReader(legacyPath, false))
    local sourcePath = legacyPath

    if not (okRead and raw) then
        okRead, raw = pcall(readAllAndClose, getFileReader(currentPath, false))
        sourcePath = currentPath
    end

    if okRead and raw then
        local okParse, parsed = pcall(SRJ_ModDataHandler.jsonDecode, raw)
        if okParse and parsed and parsed.journals then
            userStates[username] = parsed
            loadedUsers[username] = true
            existsOnDisk[username] = true
            if getDebug() then print("SRJ Ledger: loaded " .. sourcePath) end

            if sourcePath == legacyPath then
                saveUsername(username)
                local neutralWriter = getFileWriter(legacyPath, true, false)
                if neutralWriter then
                    neutralWriter:write(SRJ_ModDataHandler.jsonEncode({journals = {}, migrated = true}))
                    neutralWriter:close()
                end
                if getDebug() then print("SRJ Ledger: migrated " .. legacyPath .. " -> " .. currentPath .. ", legacy file neutralized") end
            end

            return userStates[username]
        elseif not okParse then
            print("SRJ ERROR: exception parsing " .. sourcePath .. ": " .. tostring(parsed))
        elseif getDebug() then
            print("SRJ Ledger: " .. sourcePath .. " failed to parse, starting fresh")
        end
    elseif not okRead then
        print("SRJ ERROR: exception reading " .. sourcePath .. ": " .. tostring(raw))
    end

    userStates[username] = freshUserState()
    loadedUsers[username] = true
    return userStates[username]
end


function SRJ_Ledger.save(player)
    print("SRJ SAVE DEBUG: save() called, isAuthoritative=" .. tostring(isAuthoritative()) .. " isClient=" .. tostring(isClient()))
    if not isAuthoritative() then
        print("SRJ SAVE DEBUG: aborting, isAuthoritative() was false")
        return
    end
    saveUsername(fileRoutingIdentity(player))
    print("SRJ SAVE DEBUG: saveUsername completed for " .. tostring(fileRoutingIdentity(player)))
end


function SRJ_Ledger.saveAll()
    if not isAuthoritative() then return end
    for username in pairs(userStates) do
        saveUsername(username)
    end
end


function SRJ_Ledger.migrateReadXPIfNeeded(player)
    if not isAuthoritative() then return end
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)

    local routingKey = fileRoutingIdentity(player)
    local u = ensureUserLoaded(routingKey)

    if not u.readXP then return end
    local found = false
    for _,_ in pairs(u.readXP) do
        found = true
        break
    end
    if not found then return end

    local merged = { flat = {}, kills = {} }

    if type(pMD.readXP) == "table" then
        for skill, val in pairs(pMD.readXP) do
            if skill == "flat" or skill == "kills" then
                if type(val) == "table" then
                    for subKey, subVal in pairs(val) do
                        if type(subVal) == "number" then
                            merged[skill][subKey] = math.max(merged[skill][subKey] or 0, subVal)
                        end
                    end
                end
            elseif type(val) == "number" then
                merged[skill] = math.max(merged[skill] or 0, val)
            end
        end
    end

    if u.readXP then
        local stampCount = 0
        for stampKey, rec in pairs(u.readXP) do
            if type(rec) == "table" then
                stampCount = stampCount + 1
                for skill, val in pairs(rec) do
                    if skill == "flat" or skill == "kills" then
                        if type(val) == "table" then
                            for subKey, subVal in pairs(val) do
                                if type(subVal) == "number" then
                                    merged[skill][subKey] = math.max(merged[skill][subKey] or 0, subVal)
                                end
                            end
                        end
                    elseif type(val) == "number" then
                        merged[skill] = math.max(merged[skill] or 0, val)
                    end
                end
            end
        end
        if getDebug() then print("SRJ Ledger: merged " .. stampCount .. " legacy readXP stamp(s) from " .. filePath(routingKey) .. " into player ModData") end
    end

    pMD.readXP = merged
    pMD.SRJLifeStamp = nil

    if u.readXP then
        u.readXP = nil
        saveUsername(routingKey)
        if getDebug() then print("SRJ Ledger: cleared legacy readXP block from " .. filePath(routingKey)) end
    end
end


function SRJ_Ledger.getReadXP(player)
    if not isAuthoritative() then return nil end
    SRJ_Ledger.migrateReadXPIfNeeded(player)
    return SRJ_ModDataHandler.getReadXP(player)
end


function SRJ_Ledger.getReadXPAny(player)
    if isAuthoritative() then return SRJ_Ledger.getReadXP(player) end
    return SRJ_ModDataHandler.getReadXP(player)
end


local function mintJournalID(player)
    return fileRoutingIdentity(player) .. "-" .. tostring(getTimestampMs()) .. "-" .. tostring(ZombRand(1, 2147483647))
end


local function migrateLegacyJournal(item, player, srj)
    local ledgerID = mintJournalID(player)
    local routingKey = fileRoutingIdentity(player)
    local owner = usernameOf(player)
    local u = ensureUserLoaded(routingKey)

    local rec = {
        identity = srj["ID"] or {},
        author = srj.author,
        gainedXP = srj.gainedXP or {},
        flatGainedXP = srj.flatGainedXP or {},
        learnedRecipes = srj.learnedRecipes or {},
        kills = srj.kills or {},
        pModData = srj.pModData or {},
        renamedJournal = srj.renamedJournal,
        lastInteracted = {},
        usedXP = { flat = {} },
    }

    u.journals[ledgerID] = rec

    local readXP = SRJ_Ledger.getReadXP(player)
    if readXP then
        for perkID, xp in pairs(rec.gainedXP) do
            readXP[perkID] = math.max(readXP[perkID] or 0, xp)
        end
        for perkID, xp in pairs(rec.flatGainedXP) do
            readXP.flat[perkID] = math.max(readXP.flat[perkID] or 0, xp)
        end
    end

    srj.ledgerID = ledgerID
    srj.routingKey = routingKey
    srj.owner = owner
    srj.gainedXP = nil
    srj.flatGainedXP = nil
    srj.learnedRecipes = nil
    srj.kills = nil
    srj.pModData = nil
    srj.author = nil
    srj.ID = nil
    srj.renamedJournal = nil
    srj.recoveryJournalXpLog = nil

    if getDebug() then print("SRJ Ledger: migrated legacy journal " .. tostring(item:getID()) .. " -> " .. ledgerID) end

    return ledgerID, routingKey
end


local function ensureJournalIdentity(item, player)
    local iMd = item:getModData()
    iMd["SRJ"] = iMd["SRJ"] or {}
    local srj = iMd["SRJ"]

    if srj.ledgerID then
        if not srj.routingKey then
            srj.routingKey = fileRoutingIdentity(player)
            if getDebug() then print("SRJ Ledger: backfilled routingKey for " .. tostring(srj.ledgerID)) end
        end
        return srj.ledgerID, srj.routingKey
    end

    if not isAuthoritative() then return nil, nil end
    if srj.gainedXP or srj.author or srj.ID then return migrateLegacyJournal(item, player, srj) end

    local ledgerID = mintJournalID(player)
    local routingKey = fileRoutingIdentity(player)
    srj.ledgerID = ledgerID
    srj.routingKey = routingKey
    srj.owner = usernameOf(player)
    return ledgerID, routingKey
end


function SRJ_Ledger.getJournalRecord(item, player)
    local ledgerID, routingKey = ensureJournalIdentity(item, player)

    if not ledgerID then
        return {
            identity = {}, gainedXP = {}, flatGainedXP = {}, learnedRecipes = {},
            kills = {}, pModData = {}, lastInteracted = {},
            usedXP = { flat = {} },
        }
    end

    local u = ensureUserLoaded(routingKey)

    u.journals[ledgerID] = u.journals[ledgerID] or {}
    local rec = u.journals[ledgerID]
    rec.identity = rec.identity or {}
    rec.gainedXP = rec.gainedXP or {}
    rec.flatGainedXP = rec.flatGainedXP or {}
    rec.learnedRecipes = rec.learnedRecipes or {}
    rec.kills = rec.kills or {}
    rec.pModData = rec.pModData or {}
    rec.lastInteracted = rec.lastInteracted or {}
    rec.usedXP = rec.usedXP or {}
    rec.usedXP.flat = rec.usedXP.flat or {}

    return rec
end


function SRJ_Ledger.canRead(item, player)
    if not isAuthoritative() then return true end
    return true
end



function SRJ_Ledger.touchInteraction(item, player)
    if not isAuthoritative() then return end
    local rec = SRJ_Ledger.getJournalRecord(item, player)
    rec.lastInteracted.timestampMs = getTimestampMs()
    rec.lastInteracted.x = math.floor(player:getX())
    rec.lastInteracted.y = math.floor(player:getY())
    rec.lastInteracted.z = math.floor(player:getZ())
end


function SRJ_Ledger.syncDisplay(item, player)
    if not isAuthoritative() then return end
    local rec = SRJ_Ledger.getJournalRecord(item, player)
    local srj = item:getModData()["SRJ"]

    local recipeCount = 0
    for _ in pairs(rec.learnedRecipes) do recipeCount = recipeCount + 1 end

    srj.display = {
        author = rec.author,
        identity = rec.identity,
        gainedXP = rec.gainedXP,
        flatGainedXP = rec.flatGainedXP,
        learnedRecipeCount = recipeCount,
        kills = rec.kills,
        pModData = rec.pModData,
        usedXP = rec.usedXP,
        renamedJournal = rec.renamedJournal,
    }
    syncItemModData(player, item)
end


---ADMIN TOOLING (server-side only, callers MUST verify admin access before calling any of these)

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deepCopy(v)
    end
    return copy
end


function SRJ_Ledger.adminGetFullLedger(username)
    if not isAuthoritative() then return nil end
    local u = ensureUserLoaded(username)
    return deepCopy(u)
end


function SRJ_Ledger.adminLedgerExists(username)
    if not isAuthoritative() then return false end
    ensureUserLoaded(username)
    return existsOnDisk[username] == true
end


function SRJ_Ledger.adminSaveJournalRecord(username, ledgerID, record)
    if not isAuthoritative() then return false, "not_authoritative" end
    if type(ledgerID) ~= "string" or type(record) ~= "table" then return false, "bad_args" end

    local u = ensureUserLoaded(username)
    if not existsOnDisk[username] then
        if getDebug() then print("SRJ Admin: refused save for '" .. tostring(username) .. "' - no existing ledger found, will not create a new one") end
        return false, "no_existing_ledger"
    end
    if not u.journals[ledgerID] then
        if getDebug() then print("SRJ Admin: refused save for '" .. tostring(username) .. "/" .. ledgerID .. "' - no existing journal record, will not create a new one") end
        return false, "no_existing_record"
    end

    u.journals[ledgerID] = deepCopy(record)
    saveUsername(username)
    if getDebug() then print("SRJ Admin: saved journal " .. ledgerID .. " for " .. username) end
    return true
end


function SRJ_Ledger.adminDeleteJournalRecord(username, ledgerID)
    if not isAuthoritative() then return false end
    if type(ledgerID) ~= "string" then return false end

    local u = ensureUserLoaded(username)
    if not u.journals[ledgerID] then return false end

    u.journals[ledgerID] = nil
    saveUsername(username)
    if getDebug() then print("SRJ Admin: deleted journal " .. ledgerID .. " for " .. username) end
    return true
end


function SRJ_Ledger.adminGetJournalRecord(username, ledgerID)
    if not isAuthoritative() then return nil end
    local u = ensureUserLoaded(username)
    return deepCopy(u.journals[ledgerID])
end


return SRJ_Ledger
