require "recipecode"

if not Recipe.GetItemTypes.Write then
    function Recipe.GetItemTypes.Write(scriptItems)
        scriptItems:addAll(getScriptManager():getItemsTag("Write"))
    end
end