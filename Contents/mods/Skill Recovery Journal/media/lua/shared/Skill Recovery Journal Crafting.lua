local function SkillRecoveryJournalRecipe()

    local sandboxOption = SandboxVars.SkillRecoveryJournal.CraftRecipe or "Notebook/Journal|LeatherStrips=3|[Recipe.GetItemTypes.Glue]|Thread"
    if not sandboxOption or sandboxOption == "" then
        print("SKILL RECOVERY JOURNAL: LOW-WARNING: No sandbox option for `CraftRecipe` set; Journal will be uncraftable.")
        return
    end

    local script = {
        header = "module Base { recipe Bind Journal { ",
        footer = "Category:SkillJournal, Result:Base.SkillRecoveryBoundJournal, Time:150.0, } }",
    }

    local ingredients = ""

    for str in string.gmatch(sandboxOption, "([^|]+)") do

        local action, value = string.match(str, "^(keep)%s+(.*)")
        if not action then action, value = string.match(str, "^(destroy)%s+(.*)") end
        if not action then value = str end

        local functionCall = string.match(value, "^%[(.*)%]$")

        if functionCall then

            local func = _G
            for part in string.gmatch(functionCall, "[^%.]+") do
                func = func[part]
            end

            ---@type ArrayList
            local array = ArrayList.new()
            func(array)
            local concatItems
            for i=0, array:size()-1 do
                local o = array:get(i)
                local oType = o:getFullName()
                concatItems = (concatItems and (concatItems.."/") or "")..oType
            end

            value = concatItems
        else
            local moduleDotValue
            for phrase in string.gmatch(value, "[^/]+") do
                if not string.match(phrase,"%.") then phrase = "Base."..phrase end
                moduleDotValue = (moduleDotValue and moduleDotValue.."/" or "")..phrase
            end
            value = moduleDotValue
        end

        if action then
            ingredients = action.." "..value..", "..ingredients
        else
            ingredients = ingredients..value..", "
        end
    end

    local newScript = script.header .. ingredients .. script.footer
    print("SKILL RECOVERY JOURNAL: Loading script: ", newScript)

    local scriptManager = getScriptManager()
    scriptManager:ParseScript(newScript)

    local recipe = scriptManager:getRecipe("Bind Journal")
    if recipe then
        print("SKILL RECOVERY JOURNAL: Verifying Script Generated: ", recipe and recipe:getOriginalname())
    end

    if ISCraftingCategoryUI and ISCraftingCategoryUI.instance and ISCraftingCategoryUI.instance.craftingUI then ISCraftingCategoryUI.instance.craftingUI:refresh() end
end


Events.OnLoad.Add(SkillRecoveryJournalRecipe)
if isServer() then Events.OnGameBoot.Add(SkillRecoveryJournalRecipe) end

