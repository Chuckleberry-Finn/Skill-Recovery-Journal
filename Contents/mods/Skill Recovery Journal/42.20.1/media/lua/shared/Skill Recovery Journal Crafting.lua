local function applyRecipeScript(journalRecipe, script, expectInputs)
    local inputs = journalRecipe:getInputs()
    local ioLines = journalRecipe:getIoLines()

    local removedLines = {}
    for i = ioLines:size() - 1, 0, -1 do
        local line = ioLines:get(i)
        if inputs:contains(line) then
            table.insert(removedLines, 1, line)
            ioLines:remove(i)
        end
    end

    inputs:clear()
    journalRecipe:Load("BindSkillRecoveryJournal", script)
    journalRecipe:OnPostWorldDictionaryInit()

    if not expectInputs or inputs:size() > 0 then
        return true
    end

    for _, line in ipairs(removedLines) do
        ioLines:add(line)
        inputs:add(line)
    end
    journalRecipe:OnPostWorldDictionaryInit()

    return false
end

local function SkillRecoveryJournalRecipe()

    ---need to be learned, allows people to disable recipes in a clearer way + open up add-on mod features
    local needToLearn = SandboxVars.SkillRecoveryJournal.CraftRecipeNeedLearn
    local needToLearnScript = needToLearn and "NeedToBeLearn = ".. tostring(needToLearn == true) ..", " or nil

    ---craft recipe now designed to default to the script file and only load() if needed
    local craftRecipe = SandboxVars.SkillRecoveryJournal.CraftRecipe
    local craftRecipeScript

    if craftRecipe and not craftRecipe:match("^%s*$") then
        local modified_option = string.gsub(craftRecipe, "|", ",")
        modified_option = modified_option:match("^(.-)%s*$")
        if modified_option:sub(-1) ~= "," then modified_option = modified_option .. "," end
        craftRecipeScript = "inputs { " .. modified_option .. " }, "
    end

    local newScript = (craftRecipeScript or needToLearnScript) and "{ ".. (needToLearnScript or "") .. (craftRecipeScript or "") .. " }"

    if newScript then
        local scriptManager = getScriptManager()
        local journalRecipe = scriptManager:getCraftRecipe("BindSkillRecoveryJournal")
        if journalRecipe then
            if applyRecipeScript(journalRecipe, newScript, craftRecipeScript ~= nil) then
                print("[SRJ] Final Recipe for BindSkillRecoveryJournal: ", newScript)
            else
                print("[SRJ] ERROR: CraftRecipe setting produced an invalid recipe, kept original inputs for 'BindSkillRecoveryJournal'")
            end
        else
            print("[SRJ] ERROR: Could not find CraftRecipe 'BindSkillRecoveryJournal'")
        end
    else
        print("[SRJ] No changes made to 'BindSkillRecoveryJournal'")
    end
end

Events.OnGameStart.Add(SkillRecoveryJournalRecipe)
if isServer() then Events.OnGameBoot.Add(SkillRecoveryJournalRecipe) end