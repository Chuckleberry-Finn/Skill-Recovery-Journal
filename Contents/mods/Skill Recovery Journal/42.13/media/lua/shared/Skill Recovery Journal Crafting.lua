local function SkillRecoveryJournalRecipe()

    local sandboxOption = SandboxVars.SkillRecoveryJournal.CraftRecipe or "item 1 [Base.Notebook;Base.Journal] flags[Prop2] mode:destroy| item 1 tags[Glue] flags[Prop1]| item 3 [Base.LeatherStrips;Base.LeatherStripsDirty] mode:destroy| item 1 [Base.Thread;Base.Yarn]"
    local newScript

    if not sandboxOption or sandboxOption == "" then
        newScript = "{ needTobeLearn = true, }"
    else
        local modified_option = string.gsub(sandboxOption, "|", ",")
        newScript = "{ inputs { " .. modified_option .. " } }"
    end

    if newScript then
        local scriptManager = getScriptManager()
        local journalRecipe = scriptManager:getCraftRecipe("BindSkillRecoveryJournal")
        journalRecipe:Load("BindSkillRecoveryJournal", newScript)
    end
end

if isServer() then 
    Events.OnGameBoot.Add(SkillRecoveryJournalRecipe) 
else 
    Events.OnInitWorld.Add(SkillRecoveryJournalRecipe)
end