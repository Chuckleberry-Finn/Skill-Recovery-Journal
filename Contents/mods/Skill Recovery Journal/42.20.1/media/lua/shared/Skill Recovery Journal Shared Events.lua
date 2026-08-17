local SRJmodHandler = require "Skill Recovery Journal ModData"
local SRJledger = require "Skill Recovery Journal Ledger"

local READY_COOLDOWN_MS = 3000
local lastReadyMs = {}   -- routingKey -> timestampMs of last processed 'ready'

local function onCreatePlayer(id, player)
    SRJmodHandler.initStartingXP(id, player)
    if isClient() then
        sendClientCommand(getPlayer(), "SkillRecoveryJournal", "ready", {})
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


local function stablePlayerKey(player)
	local username = player.getUsername and player:getUsername()
	if not username or username == "" then return "sp" end
	return username
end

local function onCharacterDeath(character)
	if not instanceof(character, "IsoPlayer") then return end
	SRJledger.pruneReadXP(character)
end
Events.OnCharacterDeath.Add(onCharacterDeath)


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
		elseif command == "ready" then
			local readyKey = stablePlayerKey(player)
			local now = getTimestampMs()
			local last = lastReadyMs[readyKey]
			if last and (now - last) < READY_COOLDOWN_MS then
				if getDebug() then print("SRJ TRACE: ignoring 'ready' from " .. tostring(readyKey) .. " within cooldown") end
				return
			end
			lastReadyMs[readyKey] = now

			local readXP = SRJledger.getReadXP(player)
			sendServerCommand(player, "SkillRecoveryJournal", "readXP", {data = readXP})
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
