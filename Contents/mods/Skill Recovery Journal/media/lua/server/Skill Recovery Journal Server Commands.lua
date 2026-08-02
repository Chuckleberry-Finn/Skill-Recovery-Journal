local SRJ_JSON = require "Skill Recovery Journal JSON"

local SRJServerCommands = {}
SRJServerCommands.Commands = {}

---Save user journal payload to server JSON file and update master index
function SRJServerCommands.Commands.savePlayerJournalJson(player, args)
    if not args then return end

    local username = args.username or (player and player:getUsername()) or "Unknown"
    local filename = "SkillRecoveryJournal_" .. username .. ".json"

    -- Build record payload
    local record = {
        username = username,
        steamID = args.steamID or (player and player:getSteamID()) or 0,
        author = args.author or (player and player:getFullName()) or username,
        gainedXP = args.gainedXP or {},
        learnedRecipes = args.learnedRecipes or {},
        learnedTraits = args.learnedTraits or {},
        kills = args.kills or {},
        pModData = args.pModData or {},
        timestamp = args.timestamp or getCalendarTime():getTimeInMillis()
    }

    -- Write individual user JSON file
    local fileWriter = getFileWriter(filename, true, false)
    if fileWriter then
        fileWriter:write(SRJ_JSON.encode(record))
        fileWriter:close()
        print("SRJ SERVER: Saved JSON cache for user: " .. username)
    end

    -- Update master index
    local indexMap = {}
    local indexReader = getFileReader("SkillRecoveryJournal_index.json", false)
    if indexReader then
        local content = ""
        local line = indexReader:readLine()
        while line do
            content = content .. line .. "\n"
            line = indexReader:readLine()
        end
        indexReader:close()
        indexMap = SRJ_JSON.decode(content) or {}
    end

    indexMap[username] = {
        username = username,
        steamID = record.steamID,
        author = record.author,
        timestamp = record.timestamp
    }

    local indexWriter = getFileWriter("SkillRecoveryJournal_index.json", true, false)
    if indexWriter then
        indexWriter:write(SRJ_JSON.encode(indexMap))
        indexWriter:close()
    end
end


---Send list of all cached player journal records to admin client
function SRJServerCommands.Commands.requestSavedJournalsList(player, args)
    if not player then return end

    local indexMap = {}
    local indexReader = getFileReader("SkillRecoveryJournal_index.json", false)
    if indexReader then
        local content = ""
        local line = indexReader:readLine()
        while line do
            content = content .. line .. "\n"
            line = indexReader:readLine()
        end
        indexReader:close()
        indexMap = SRJ_JSON.decode(content) or {}
    end

    sendServerCommand(player, "SkillRecoveryJournal", "receiveSavedJournalsList", indexMap)
end


---Send specific player's full JSON record to admin client
function SRJServerCommands.Commands.requestPlayerJournalData(player, args)
    if not player or not args or not args.username then return end

    local username = args.username
    local filename = "SkillRecoveryJournal_" .. username .. ".json"

    local reader = getFileReader(filename, false)
    if reader then
        local content = ""
        local line = reader:readLine()
        while line do
            content = content .. line .. "\n"
            line = reader:readLine()
        end
        reader:close()

        local record = SRJ_JSON.decode(content)
        if record then
            sendServerCommand(player, "SkillRecoveryJournal", "receivePlayerJournalData", record)
        end
    end
end


local function onClientCommand(module, command, player, args)
    if module == "SkillRecoveryJournal" and SRJServerCommands.Commands[command] then
        SRJServerCommands.Commands[command](player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)

return SRJServerCommands
