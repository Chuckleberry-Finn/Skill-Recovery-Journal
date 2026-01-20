local SRJmodHandler = require "Skill Recovery Journal ModData"
Events.OnCreatePlayer.Add(SRJmodHandler.setPassiveLevels) -- not invoked on server

---Ideally this will be loaded in last
local function loadOnBoot() Events.AddXP.Add(SRJmodHandler.checkIfDeductedXP) end
Events.OnGameBoot.Add(loadOnBoot)