local SRJledger = require "Skill Recovery Journal Ledger"

local adminEvents = {}

local function isSinglePlayer()
	return not isClient() and not isServer()
end


adminEvents.spResponseHandler = nil

local function sendAdminResponse(player, command, args)
	if isSinglePlayer() and adminEvents.spResponseHandler then
		adminEvents.spResponseHandler(command, args)
		return
	end
	sendServerCommand(player, "SkillRecoveryJournalAdmin", command, args)
end


function adminEvents.isAdmin(player)
	if not player then return false end
	if isSinglePlayer() then return true end
	local level = player.getAccessLevel and player:getAccessLevel()
	return (level == "Admin") or getDebug()
end

function adminEvents.processCommand(player, command, args)
	sendClientCommand(player, "SkillRecoveryJournalAdmin", command, args)
end

function adminEvents.warnUnauthorized(player, command)
	local name = (player and player.getUsername and player:getUsername()) or "?"
	print("SRJ ADMIN WARNING: non-admin '" .. tostring(name) .. "' attempted admin command '" .. tostring(command) .. "'")
end


local function SkillRecoveryJournalAdminOnClientCommand(module, command, player, args)
	if module ~= "SkillRecoveryJournalAdmin" then return end

	if not adminEvents.isAdmin(player) then
		adminEvents.warnUnauthorized(player, command)
		return
	end

	if command == "lookup" then
		local username = args.username
		if type(username) ~= "string" or username == "" then return end

		local ledger = SRJledger.adminGetFullLedger(username)
		sendAdminResponse(player, "ledgerData", {
			username = username,
			ledger = ledger,
		})

	elseif command == "saveJournal" then
		local username = args.username
		local ledgerID = args.ledgerID
		local record = args.record
		if type(username) ~= "string" or type(ledgerID) ~= "string" or type(record) ~= "table" then return end

		local ok, reason = SRJledger.adminSaveJournalRecord(username, ledgerID, record)
		sendAdminResponse(player, "saveResult", {
			username = username,
			ledgerID = ledgerID,
			success = ok,
			reason = reason,
		})

	elseif command == "deleteJournal" then
		local username = args.username
		local ledgerID = args.ledgerID
		if type(username) ~= "string" or type(ledgerID) ~= "string" then return end

		local ok = SRJledger.adminDeleteJournalRecord(username, ledgerID)
		sendAdminResponse(player, "deleteResult", {
			username = username,
			ledgerID = ledgerID,
			success = ok,
		})

	elseif command == "spawnJournal" then
		local username = args.username
		local ledgerID = args.ledgerID
		if type(username) ~= "string" or type(ledgerID) ~= "string" then return end

		local record = SRJledger.adminGetJournalRecord(username, ledgerID)
		if not record then
			sendAdminResponse(player, "spawnResult", {success = false, reason = "not_found"})
			return
		end

		local item = player:getInventory():AddItem("Base.SkillRecoveryBoundJournal")
		if not item then
			sendAdminResponse(player, "spawnResult", {success = false, reason = "spawn_failed"})
			return
		end

		local iMd = item:getModData()
		iMd["SRJ"] = {
			ledgerID = ledgerID,
			routingKey = username,
			owner = username,
		}

		SRJledger.syncDisplay(item, player)
		sendItemStats(item)
		if player.flagForHotSave then player:flagForHotSave() end

		sendAdminResponse(player, "spawnResult", {success = true, ledgerID = ledgerID})
		print("SRJ ADMIN: " .. tostring(player:getUsername()) .. " spawned journal linked to " .. username .. "/" .. ledgerID)
	end
end

adminEvents.SkillRecoveryJournalAdminOnClientCommand = SkillRecoveryJournalAdminOnClientCommand
Events.OnClientCommand.Add(SkillRecoveryJournalAdminOnClientCommand)

return adminEvents
