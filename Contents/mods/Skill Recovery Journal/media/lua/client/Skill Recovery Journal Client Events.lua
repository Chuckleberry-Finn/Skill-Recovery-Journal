local contextSRJ = require "Skill Recovery Journal Context"
Events.OnPreFillInventoryObjectContextMenu.Add(contextSRJ.doContextMenu)