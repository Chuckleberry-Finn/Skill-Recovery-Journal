local contextSRJ = require "Skill Recovery Journal Context"
if contextSRJ then Events.OnPreFillInventoryObjectContextMenu.Add(contextSRJ.doContextMenu) end

local SRJ = require "Skill Recovery Journal Main"
Events.OnCreatePlayer.Add(SRJ.setPassiveLevels)

---Ideally this will be loaded in last
local function loadOnBoot() Events.AddXP.Add(SRJ.checkForDeductedXP) end
Events.OnGameBoot.Add(loadOnBoot)