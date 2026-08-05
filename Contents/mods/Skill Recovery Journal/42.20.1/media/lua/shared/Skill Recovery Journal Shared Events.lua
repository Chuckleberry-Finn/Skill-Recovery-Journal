local SRJmodHandler = require "Skill Recovery Journal ModData"
local SRJledger = require "Skill Recovery Journal Ledger"

local function onCreatePlayer(id, player)
	SRJmodHandler.initStartingXP(id, player)
end
Events.OnCreatePlayer.Add(onCreatePlayer)


local function SkillRecoveryJournalOnClientCommand(module, command, player, args)
	if module == "SkillRecoveryJournal" then 
		local playerID = player:getOnlineID()
		if command == "rename" then
			if getDebug() then print("SkillRecoveryJournal received rename for item " .. tostring(args.itemID) .. " from player " .. tostring(playerID)) end
			local item = player:getInventory():getItemWithIDRecursiv(args.itemID)
			if item then
				item:setName(args.name)

				local JMD = SRJledger.getJournalRecord(item, player)
				JMD.renamedJournal = true
				JMD.usedRenameOption = nil

				sendItemStats(item)
				SRJledger.syncDisplay(item, player)
				SRJledger.save(player)
			else
				if getDebug() then print("SkillRecoveryJournal rename failed for player " .. tostring(playerID)) end
			end
		end
	end
end

Events.OnClientCommand.Add(SkillRecoveryJournalOnClientCommand)

local function onSave()
	SRJledger.saveAll()
end

Events.OnSave.Add(onSave)


---Ideally this will be loaded in last
local function loadOnBoot()
    Events.AddXP.Add(SRJmodHandler.checkIfDeductedXP)
    SRJmodHandler.initFlatXPHook()
end
Events.OnGameBoot.Add(loadOnBoot)

if isClient() then
    local function onGameStart()
        sendClientCommand(getPlayer(), "SkillRecoveryJournal", "ready", {})
    end
    Events.OnGameStart.Add(onGameStart)
end
