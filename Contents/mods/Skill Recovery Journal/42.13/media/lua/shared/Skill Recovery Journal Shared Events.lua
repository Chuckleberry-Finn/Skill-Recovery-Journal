local SRJmodHandler = require "Skill Recovery Journal ModData"
Events.OnCreatePlayer.Add(SRJmodHandler.setPassiveLevels)

---Ideally this will be loaded in last
local function loadOnBoot() Events.AddXP.Add(SRJmodHandler.checkForDeductedXP) end
Events.OnGameBoot.Add(loadOnBoot)