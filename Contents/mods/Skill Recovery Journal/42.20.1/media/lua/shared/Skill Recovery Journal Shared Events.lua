local SRJmodHandler = require "Skill Recovery Journal ModData"
local SRJledger = require "Skill Recovery Journal Ledger"
require "Skill Recovery Journal Admin Events"

local function onCreatePlayer(id, player)
    SRJmodHandler.initStartingXP(id, player)
    if not isClient() then
        local readXP = SRJledger.getReadXP(player)
        sendServerCommand(player, "SkillRecoveryJournal", "readXP", {data = readXP})
        player:flagForHotSave()
    end
end


local function onCreateBuffer(playerIndex, player)
    local playerCreateBuffer = 2
    local function OnTickFunc()
        if playerCreateBuffer <= 0 then
            onCreatePlayer(nil, player)
            Events.OnTick.Remove(OnTickFunc)
        end
        playerCreateBuffer = playerCreateBuffer - 1
    end
    Events.OnTick.Add(OnTickFunc)
end
Events.OnCreatePlayer.Add(onCreateBuffer)


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
Events.OnClientCommand.Add(SkillRecoveryJournalOnClientCommand)--what the server gets from the client


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
