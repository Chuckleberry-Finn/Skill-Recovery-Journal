local modDataCapture = {}

modDataCapture.keys = {}

function modDataCapture.parseSandBoxOption()
    local option = SandboxVars.SkillRecoveryJournal.ModDataTrack
    for key in string.gmatch(option, "([^|]+)") do table.insert(modDataCapture.keys, key) end
end

function modDataCapture.copyDataToJournal(player, journal)
    if #modDataCapture.keys <= 0 then modDataCapture.parseSandBoxOption() end
    
    local journalData = journal:getModData()
    for _,key in pairs(modDataCapture.keys) do
        local value = modDataCapture.copyKey(player, key)
        journalData.pModData = journalData.pModData or {}
        journalData.pModData[key] = value
    end
end

---@param player IsoPlayer|IsoGameCharacter|IsoObject
function modDataCapture.copyKey(player, key)
    local modData = player:getModData()
    local keyValue = modData and modData[key]
    return keyValue and copyTable(keyValue)
end

return modDataCapture