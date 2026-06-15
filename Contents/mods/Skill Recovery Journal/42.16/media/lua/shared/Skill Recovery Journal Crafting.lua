local function SkillRecoveryJournalRecipe()

    ---need to be learned, allows people to disable recipes in a clearer way + open up add-on mod features
    local needToLearn = SandboxVars.SkillRecoveryJournal.CraftRecipeNeedLearn
    local needToLearnScript = needToLearn and "NeedToBeLearn = ".. tostring(needToLearn == true) ..", " or nil

    ---craft recipe now designed to default to the script file and only load() if needed
    local craftRecipe = SandboxVars.SkillRecoveryJournal.CraftRecipe
    local craftRecipeScript

    if not craftRecipe or craftRecipe:match("^%s*$") then
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
            ---@type ArrayList
            local inputs = journalRecipe:getInputs()
            local ioLines = journalRecipe:getIoLines()

            for i = ioLines:size() - 1, 0, -1 do
                if inputs:contains(ioLines:get(i)) then
                    ioLines:remove(i)
                end
            end

            print("[SRJ] Final Recipe for BindSkillRecoveryJournal: ", newScript)

            inputs:clear()
            journalRecipe:Load("BindSkillRecoveryJournal", newScript)
            journalRecipe:OnPostWorldDictionaryInit()
        else
            print("[SRJ] ERROR: Could not find CraftRecipe 'BindSkillRecoveryJournal'")
        end
    else
        print("[SRJ] No changes made to 'BindSkillRecoveryJournal'")
    end
end

Events.OnGameStart.Add(SkillRecoveryJournalRecipe)