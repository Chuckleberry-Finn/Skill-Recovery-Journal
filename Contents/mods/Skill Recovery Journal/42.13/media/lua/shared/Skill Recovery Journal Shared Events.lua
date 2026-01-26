local SRJmodHandler = require "Skill Recovery Journal ModData"
Events.OnCreatePlayer.Add(SRJmodHandler.setPassiveLevels) -- not invoked on server


-- handle receive data from client
local function SkillRecoveryJournalOnClientCommand(module, command, player, args)
	if module == "SkillRecoveryJournal" then 
		local playerID = player:getOnlineID()
		if command == "rename" then
			if getDebug() then print("SkillRecoveryJournal received rename for item " .. tostring(args.itemID) .. " from player " .. tostring(playerID)) end
			local item = player:getInventory():getItemWithIDRecursiv(args.itemID)
			if item then
				item:setName(args.name)

				local JMD = SRJmodHandler.getItemModData(item)
				if JMD then
					JMD.renamedJournal = true
					JMD.usedRenameOption = nil
				end

				sendItemStats(item)
				syncItemModData(player, item)
			else
				if getDebug() then print("SkillRecoveryJournal rename failed for player " .. tostring(playerID)) end
			end
		end
	end
end

if isServer() then Events.OnClientCommand.Add(SkillRecoveryJournalOnClientCommand) end


---Ideally this will be loaded in last
local function loadOnBoot() Events.AddXP.Add(SRJmodHandler.checkIfDeductedXP) end
Events.OnGameBoot.Add(loadOnBoot)