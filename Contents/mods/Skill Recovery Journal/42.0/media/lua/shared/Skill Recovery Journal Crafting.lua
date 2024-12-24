local function SkillRecoveryJournalRecipe()

    local sandboxOption = SandboxVars.SkillRecoveryJournal.CraftRecipe or "item 1 [Base.Notebook;Base.Journal] flags[Prop2] mode:destroy| item 1 tags[Glue] flags[Prop1]| item 3 [Base.LeatherStrips;Base.LeatherStripsDirty] mode:destroy| item 1 [Base.Thread;Base.Yarn]"
    if not sandboxOption or sandboxOption == "" then return end

    local script = {
        header = "timedAction = Making, Time = 150, Tags = InHandCraft, category = Skill Journal, inputs { ",
        footer = " } outputs { item 1 Base.SkillRecoveryBoundJournal, }",

        --header = "{ inputs {",
        --footer = "} }",
    }

    local modified_option = string.gsub(sandboxOption, "|", ",")
    local newScript = script.header .. modified_option .. script.footer

    print("SCRIPT: ", newScript)

    local scriptManager = getScriptManager()
    local journalRecipe = CraftRecipe.new()--scriptManager:getCraftRecipe("BindSkillRecoveryJournal")
    journalRecipe:setModule(scriptManager:getModule("Base"))
    journalRecipe:InitLoadPP("BindSkillRecoveryJournal")
    journalRecipe:Load("Base.BindSkillRecoveryJournal", newScript)

    --local scriptManager = getScriptManager()
    --scriptManager:ParseScript(newScript)
end


Events.OnLoad.Add(SkillRecoveryJournalRecipe)
if isServer() then Events.OnGameBoot.Add(SkillRecoveryJournalRecipe) end