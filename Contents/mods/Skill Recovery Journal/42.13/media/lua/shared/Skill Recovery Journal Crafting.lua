local function SkillRecoveryJournalRecipe()

    local defaultRecipe = "item 1 [Base.Notebook;Base.Journal;Base.Diary1;Base.Diary2;Base.Notepad] flags[Prop2] mode:destroy, item 1 tags[Glue] flags[Prop1], item 3 [Base.LeatherStrips;Base.LeatherStripsDirty] mode:destroy, item 1 [Base.Thread;Base.Yarn;Base.Twine],"
    local sandboxOption = SandboxVars.SkillRecoveryJournal.CraftRecipe
    local needToLearn = SandboxVars.SkillRecoveryJournal.CraftRecipeNeedLearn

    --- Maybe a way to validate the recipe would be possible?
    --correct old sandbox options
    local modified_option = sandboxOption and string.gsub(sandboxOption, "|", ",")
    --add missing comma that might be default for some older saves
    if modified_option and modified_option:sub(-1) ~= "," then modified_option = modified_option .. "," end

    local inputs = (not sandboxOption or sandboxOption == "") and defaultRecipe or modified_option

    local newScript = "{ NeedToBeLearn = ".. tostring(needToLearn == true) ..", inputs { " .. inputs .. " } }"

    if getDebug() then print("[SRJ] Final Recipe Script: " .. newScript) end

    if newScript then
        local scriptManager = getScriptManager()
        local journalRecipe = scriptManager:getCraftRecipe("BindSkillRecoveryJournal")
        if journalRecipe then
            journalRecipe:Load("BindSkillRecoveryJournal", newScript)
        else
            print("[SRJ] ERROR: Could not find CraftRecipe 'BindSkillRecoveryJournal'")
        end
    end
end

Events.OnGameBoot.Add(SkillRecoveryJournalRecipe)