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

    local playerData = player:getModData()
    for _,key in pairs(modDataCapture.keys) do
        local value = modDataCapture.copyKey(journal, key)
        if value then
            playerData[key] = value
        end
    end
end


function modDataCapture.copyDataToJournal(player, journal)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #modDataCapture.keys <= 0 then modDataCapture.parseSandBoxOption() end

    local data = {}

    local journalData = journal:getModData()
    for _,key in pairs(modDataCapture.keys) do
        local value = modDataCapture.copyKey(player, key)
        if value then
            journalData.pModData = journalData.pModData or {}
            journalData.pModData[key] = value
            table.insert(data, key)
        end
    end

    return data
end


function modDataCapture.copyKey(object, key)
    local modData = object:getModData()
    local keyValue = modData and modData[key]
    return keyValue and copyTable(keyValue)
end


return modDataCapture