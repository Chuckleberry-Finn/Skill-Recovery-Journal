local function SkillRecoveryJournalRecipe()

    local defaultRecipe = "item 1 [Base.Notebook;Base.Journal;Base.Diary1;Base.Diary2;Base.Notepad] flags[Prop2] mode:destroy, item 1 tags[Glue] flags[Prop1], item 3 [Base.LeatherStrips;Base.LeatherStripsDirty] mode:destroy, item 1 [Base.Thread;Base.Yarn],"
    local sandboxOption = SandboxVars.SkillRecoveryJournal.CraftRecipe
    local needToLearn = SandboxVars.SkillRecoveryJournal.CraftRecipeNeedLearn
    local newScript

    if not sandboxOption or sandboxOption == "" then
        newScript = "{ NeedToBeLearn = ".. tostring(needToLearn == true) ..", inputs { " .. defaultRecipe .. " } }"
    else
        local modified_option = string.gsub(sandboxOption, "|", ",")
        if getDebug() then print("Add SRF custom crafting recipe with inputs " .. modified_option) end
        newScript = "{ NeedToBeLearn = ".. tostring(needToLearn == true) ..", inputs { " .. modified_option .. " } }"
    end

    if newScript then
        local scriptManager = getScriptManager()
        local journalRecipe = scriptManager:getCraftRecipe("BindSkillRecoveryJournal")
        journalRecipe:Load("BindSkillRecoveryJournal", newScript)
    end
end

Events.OnGameBoot.Add(SkillRecoveryJournalRecipe)