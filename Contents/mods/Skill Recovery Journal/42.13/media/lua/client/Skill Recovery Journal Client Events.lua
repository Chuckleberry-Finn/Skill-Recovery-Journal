local contextSRJ = require "Skill Recovery Journal Context"
if contextSRJ then
    Events.OnPreFillInventoryObjectContextMenu.Add(contextSRJ.doContextMenu)
    Events.OnFillInventoryObjectContextMenu.Add(contextSRJ.postContextMenu)
end