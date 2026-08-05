local SRJmodHandler = require "Skill Recovery Journal ModData"

local function onCreatePlayer(id, player)
	SRJmodHandler.initStartingXP(id, player)
end
Events.OnCreatePlayer.Add(onCreatePlayer)


local function SkillRecoveryJournalOnClientCommand(module, command, player, args)
	if module == "SkillRecoveryJournal" then 
		local playerID = player:getOnlineID()
		if command == "ready" then
			SRJmodHandler.loadServerLedger(player)
			if getDebug() then print("SRJ: loaded ledger for player " .. tostring(playerID)) end
		elseif command == "rename" then
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

if isServer() then

	local function onSave()
		local players = getOnlinePlayers()
		for i = 0, players:size() - 1 do
			local p = players:get(i)
			if p then SRJmodHandler.saveServerLedger(p) end
		end
	end

	Events.OnSave.Add(onSave)

end


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
