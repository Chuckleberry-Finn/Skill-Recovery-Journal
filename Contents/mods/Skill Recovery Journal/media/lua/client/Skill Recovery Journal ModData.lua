local modDataCapture = {}

modDataCapture.keys = {}

function modDataCapture.parseSandBoxOption()
    local option = SandboxVars.SkillRecoveryJournal.ModDataTrack
    for key in string.gmatch(option, "([^|]+)") do table.insert(modDataCapture.keys, key) end
end


function modDataCapture.copyDataToPlayer(player, journal)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #modDataCapture.keys <= 0 then modDataCapture.parseSandBoxOption() end

    local data = {}

    local playerData = player:getModData()
    local journalData = journal:getModData()

    for _,key in pairs(modDataCapture.keys) do
        print("key: ", key)
        local valueFromKey = journalData and journalData.pModData and journalData.pModData[key]
        local value = valueFromKey and copyTable(valueFromKey)
        if value then
            print(" -- key: ", key)
            playerData[key] = value
            table.insert(data, key)
        end
    end

    return data
end


function modDataCapture.copyDataToJournal(player, journal)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #modDataCapture.keys <= 0 then modDataCapture.parseSandBoxOption() end

    local data = {}

    local journalData = journal:getModData()
    local playerData = player:getModData()

    for _,key in pairs(modDataCapture.keys) do

        local valueFromKey = playerData and playerData[key]
        local value = valueFromKey and copyTable(valueFromKey)

        if value then
            journalData.pModData = journalData.pModData or {}
            journalData.pModData[key] = value
            table.insert(data, key)
        end
    end

    return data
end


return modDataCapture