local function SkillRecoveryJournalRecipe()

    local sandboxOption = SandboxVars.SkillRecoveryJournal.CraftRecipe
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

Events.OnInitWorld.Add(SkillRecoveryJournalRecipe)
if isServer() then Events.OnGameBoot.Add(SkillRecoveryJournalRecipe) end