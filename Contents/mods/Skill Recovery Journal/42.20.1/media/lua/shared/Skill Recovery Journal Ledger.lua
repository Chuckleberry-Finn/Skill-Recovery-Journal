local SRJ_ModDataHandler = require "Skill Recovery Journal ModData"

local SRJ_Ledger = {}

local function isAuthoritative()
    return not isClient()
end

local LEDGER_NAMESPACE = "SkillRecoveryJournal"

local userStates  = {}   -- username -> { readXP, journals }
local loadedUsers = {}   -- username -> true


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


local function filePath(username)
    local sep = (type(getFileSeparator) == "function" and getFileSeparator()) or "/"
    return LEDGER_NAMESPACE .. sep .. getSavePathPrefix() .. sanitizeUsername(username) .. ".txt"
end


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


local function freshUserState()
    return { readXP = {}, journals = {} }
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
    loadedUsers[username] = true

    local raw = readAllAndClose(getFileInput(filePath(username)))
    if raw then
        local parsed = SRJ_ModDataHandler.jsonDecode(raw)
        if parsed and parsed.journals then
            parsed.readXP = parsed.readXP or {}
            userStates[username] = parsed
            if getDebug() then print("SRJ Ledger: loaded " .. filePath(username)) end
            return userStates[username]
        elseif getDebug() then
            print("SRJ Ledger: " .. filePath(username) .. " failed to parse, starting fresh")
        end
    end

    userStates[username] = freshUserState()
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


function SRJ_Ledger.mintLifeStamp(player)
    if not isAuthoritative() then return nil end
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    pMD.SRJLifeStamp = fileRoutingIdentity(player) .. ":" .. tostring(getTimestampMs()) .. ":" .. tostring(ZombRand(100000, 999999))
    return pMD.SRJLifeStamp
end


function SRJ_Ledger.getLifeStamp(player)
    if not isAuthoritative() then return nil end
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    if not pMD.SRJLifeStamp then
        SRJ_Ledger.mintLifeStamp(player)
    end
    return pMD.SRJLifeStamp
end


function SRJ_Ledger.pruneReadXP(player)
    if not isAuthoritative() then return end
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    local lifeStamp = pMD.SRJLifeStamp
    if not lifeStamp then return end

    local routingKey = fileRoutingIdentity(player)
    local u = ensureUserLoaded(routingKey)
    if u.readXP[lifeStamp] then
        u.readXP[lifeStamp] = nil
        saveUsername(routingKey)
        if getDebug() then print("SRJ Ledger: pruned readXP for dead life " .. lifeStamp) end
    end
end


function SRJ_Ledger.getReadXP(player)
    if not isAuthoritative() then return nil end
    local routingKey = fileRoutingIdentity(player)
    local u = ensureUserLoaded(routingKey)
    local lifeStamp = SRJ_Ledger.getLifeStamp(player)

    u.readXP[lifeStamp] = u.readXP[lifeStamp] or {}
    local rec = u.readXP[lifeStamp]
    rec.flat = rec.flat or {}
    rec.kills = rec.kills or {}
    return rec
end


function SRJ_Ledger.getReadXPAny(player)
    if isAuthoritative() then return SRJ_Ledger.getReadXP(player) end
    return SRJ_ModDataHandler.getReadXPDisplay(player)
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

    if not isAuthoritative() then
        return nil, nil
    end

    -- old-style journal: content lives directly on the item already
    if srj.gainedXP or srj.author or srj.ID then
        return migrateLegacyJournal(item, player, srj)
    end

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
    srj.display = {
        author = rec.author,
        identity = rec.identity,
        gainedXP = rec.gainedXP,
        flatGainedXP = rec.flatGainedXP,
        learnedRecipes = rec.learnedRecipes,
        kills = rec.kills,
        pModData = rec.pModData,
        usedXP = rec.usedXP,
        renamedJournal = rec.renamedJournal,
    }
    syncItemModData(player, item)
end


return SRJ_Ledger
