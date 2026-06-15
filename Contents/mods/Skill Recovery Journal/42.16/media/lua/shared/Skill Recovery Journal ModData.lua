local SRJ_ModDataHandler = {}


function SRJ_ModDataHandler.initStartingXP(id, player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if pMD.SRJStartingXP then return end
	pMD.SRJStartingXP = {}
	for i = 1, Perks.getMaxIndex() - 1 do
		local perk = Perks.fromIndex(i)
		if perk and perk:getParent():getId() ~= "None" then
			local xp = player:getXp():getXP(perk)
			if xp and xp > 0 then
				pMD.SRJStartingXP[perk:getId()] = xp
			end
		end
	end
	if getDebug() then print("SRJ: captured SRJStartingXP for new character") end
end


function SRJ_ModDataHandler.getStartingXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	return pMD.SRJStartingXP
end


-- store initial skill levels from traits and profession in player mod data
--- kept for fallback in calculateGainedSkill and tooltip
function SRJ_ModDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if not pMD.SRJTraitSkillsInit then
		pMD.SRJTraitSkillsInit = {}

		-- xp granted by profession
		local playerDesc = player:getDescriptor()
		local playerProfessionID = playerDesc:getCharacterProfession()
		local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(playerProfessionID)
		local profXpBoost = transformIntoKahluaTable(profDef:getXpBoosts())
		if profXpBoost then
			for perk,level in pairs(profXpBoost) do
				local perky = tostring(perk)
				local levely = tonumber(tostring(level))
				pMD.SRJTraitSkillsInit[perky] = levely
			end
		end

		-- xp granted by trait
		local playerTraits = player:getCharacterTraits()
		for i=0, playerTraits:getKnownTraits():size()-1 do
			local traitTrait = playerTraits:getKnownTraits():get(i)
			local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitTrait)
			local traitXpBoost = transformIntoKahluaTable(traitDef:getXpBoosts())
			if traitXpBoost then
				for perk,level in pairs(traitXpBoost) do
					local perky = tostring(perk)
					local levely = tonumber(tostring(level))
					pMD.SRJTraitSkillsInit[perky] = (pMD.SRJTraitSkillsInit[perky] or 0) + levely
				end
			end
		end
	end

	return pMD.SRJTraitSkillsInit
end


-- store initial passive levels in player mod data
-- kept for legacy fallback
function SRJ_ModDataHandler.setPassiveLevels(id, player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if not pMD.SRJPassiveSkillsInit then
		pMD.SRJPassiveSkillsInit = {}
		for i=1, Perks.getMaxIndex()-1 do
			---@type PerkFactory.Perks
			local perks = Perks.fromIndex(i)
			if perks then
				---@type PerkFactory.Perk
				local perk = PerkFactory.getPerk(perks)
				if perk and perk:isPassiv() and tostring(perk:getParent():getType())~="None" then
					local currentLevel = player:getPerkLevel(perk)
					if currentLevel > 0 then
						local perkType = tostring(perk:getType())
						pMD.SRJPassiveSkillsInit[perkType] = currentLevel
					end
				end
			end
		end
		if getDebug() then for k,v in pairs(pMD.SRJPassiveSkillsInit) do print(" -- PASSIVE-INIT: "..k.." = "..v) end end
	end
end


-- deducted xp from radio and tv
function SRJ_ModDataHandler.checkIfDeductedXP(player, perksType, XP)
	SRJ_ModDataHandler.setPassiveLevels(_, player)

	local fN, lCF = nil, getCoroutineCallframeStack(getCurrentCoroutine(), 0)
	local fD = lCF ~= nil and lCF and getFilenameOfCallframe(lCF)
	local i = fD and fD:match('^.*()/')
	fN = i and fD:sub(i+1):gsub(".lua", "")

	local perkID = perksType:getId()

	if fN and fN == "ISRadioInteractions" then
		local deductibleXP = SRJ_ModDataHandler.getDeductedXP(player)
		deductibleXP[perkID] = (deductibleXP[perkID] or 0) + XP
	end
end


function SRJ_ModDataHandler.getDeductedXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	pMD.deductedXP = pMD.deductedXP or {}
	return pMD.deductedXP
end


function SRJ_ModDataHandler.getFlatXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	pMD.flatXP = pMD.flatXP or {}
	return pMD.flatXP
end


function SRJ_ModDataHandler.getReadFlatXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	pMD.readFlatXP = pMD.readFlatXP or {}
	return pMD.readFlatXP
end


local SRJ_ADDING_FLAT_XP = false

function SRJ_ModDataHandler.setSRJAddingFlatXP(state)
	SRJ_ADDING_FLAT_XP = state
end

function SRJ_ModDataHandler.initFlatXPHook()
	local original = addXpNoMultiplier
	addXpNoMultiplier = function(character, perk, xp)
		if not SRJ_ADDING_FLAT_XP and instanceof(character, "IsoGameCharacter") then
			local perkID = (type(perk) == "string" and perk) or perk:getId()
			local flatXP = SRJ_ModDataHandler.getFlatXP(character)
			flatXP[perkID] = (flatXP[perkID] or 0) + xp
		end
		original(character, perk, xp)
	end
end


function SRJ_ModDataHandler.getPassiveLevels(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if not pMD.SRJPassiveSkillsInit then
		SRJ_ModDataHandler.setPassiveLevels(_, player)
	end
	return pMD.SRJPassiveSkillsInit
end


function SRJ_ModDataHandler.getReadXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if not pMD.recoveryJournalXpLog then
		pMD.recoveryJournalXpLog = {}
	end
	if not pMD.recoveryJournalXpLog.kills then
		pMD.recoveryJournalXpLog.kills = {}
	end
	return pMD.recoveryJournalXpLog
end


local SRJ_ServerLedger = {}


local function getLedgerPath(steamID)
	return "SRJ/ledger_" .. tostring(steamID) .. ".json"
end


function SRJ_ModDataHandler.getServerReadXP(steamID, journalID)
	SRJ_ServerLedger[steamID] = SRJ_ServerLedger[steamID] or {}
	SRJ_ServerLedger[steamID][journalID] = SRJ_ServerLedger[steamID][journalID] or {}
	SRJ_ServerLedger[steamID][journalID].kills = SRJ_ServerLedger[steamID][journalID].kills or {}
	return SRJ_ServerLedger[steamID][journalID]
end


function SRJ_ModDataHandler.buildJournalID(JMD)
	local id = JMD and JMD["ID"]
	if not id then return "unkeyed" end
	local steam = tostring(id["steamID"] or "nosteam")
	local user  = tostring(id["username"] or "nouser")
	return steam .. "|" .. user
end


function SRJ_ModDataHandler.loadServerLedger(player)
	if not isServer() then return end
	local steamID = tostring(player:getSteamID())
	local path = getLedgerPath(steamID)

	local stream = getFileInput(path)
	if not stream then
		SRJ_ServerLedger[steamID] = {}
		if getDebug() then print("SRJ: no ledger file found for " .. steamID .. ", starting fresh") end
		return
	end

	local chars = {}
	local ok, err = pcall(function()
		local b = stream:read()
		while b ~= -1 do
			table.insert(chars, string.char(b))
			b = stream:read()
		end
	end)
	stream:close()

	if not ok then
		print("SRJ ERROR: failed reading ledger for " .. steamID .. ": " .. tostring(err))
		SRJ_ServerLedger[steamID] = {}
		return
	end

	local raw = table.concat(chars)
	if raw == "" then
		SRJ_ServerLedger[steamID] = {}
		return
	end

	local parsed = json.parse(raw)
	SRJ_ServerLedger[steamID] = parsed or {}

	if getDebug() then print("SRJ: loaded ledger for " .. steamID) end
end


function SRJ_ModDataHandler.saveServerLedger(player)
	if not isServer() then return end
	local steamID = tostring(player:getSteamID())
	local data = SRJ_ServerLedger[steamID]
	if not data then return end

	local path = getLedgerPath(steamID)
	local writer = getFileWriter(path, true, false)
	if not writer then
		print("SRJ ERROR: could not open ledger file for writing: " .. path)
		return
	end

	local ok, err = pcall(function()
		writer:write(json.stringify(data))
	end)
	writer:close()

	if not ok then
		print("SRJ ERROR: failed writing ledger for " .. steamID .. ": " .. tostring(err))
	elseif getDebug() then
		print("SRJ: saved ledger for " .. steamID)
	end
end



function SRJ_ModDataHandler.getPlayerModData(player)
    local pMd = player:getModData()
    pMd["SRJ"] = pMd["SRJ"] or {}
    return pMd["SRJ"]
end


function SRJ_ModDataHandler.setPlayerModData(player, newModData)
    local pMd = player:getModData()
    pMd["SRJ"] = newModData
end


function SRJ_ModDataHandler.getItemModData(item)
    local iMd = item:getModData()
	if not iMd["SRJ"] then
		iMd["SRJ"] = {}
		iMd["SRJ"]["gainedXP"] = {}
		iMd["SRJ"]["flatGainedXP"] = {}
		iMd["SRJ"]["learnedRecipes"] = {}
		iMd["SRJ"]["kills"] = {}
	end
	if not iMd["SRJ"]["kills"] then
		iMd["SRJ"]["kills"] = {}
	end
	if not iMd["SRJ"]["flatGainedXP"] then
		iMd["SRJ"]["flatGainedXP"] = {}
	end
    return iMd["SRJ"]
end


function SRJ_ModDataHandler.setItemModData(item, newModdata)
    local iMd = item:getModData()
    iMd["SRJ"] = newModdata
end


function SRJ_ModDataHandler.migrateJournalIfNeeded(item, player)
	local JMD = SRJ_ModDataHandler.getItemModData(item)
	local dirty = false

	if not JMD["ID"] or not JMD["ID"]["steamID"] then
		JMD["ID"] = JMD["ID"] or {}
		local steamID = player:getSteamID()
		local username = player:getUsername()
		local protections = SandboxVars.SkillRecoveryJournal.SecurityFeatures or 1
		if steamID and steamID ~= 0 and protections <= 2 then
			JMD["ID"]["steamID"] = steamID
			dirty = true
		end
		if username and protections == 1 then
			JMD["ID"]["username"] = username
			dirty = true
		end
		if dirty and getDebug() then print("SRJ migrate: stamped identity on old journal") end
	end

	if not JMD["flatGainedXP"] then
		JMD["flatGainedXP"] = {}
		dirty = true
		if getDebug() then print("SRJ migrate: created missing flatGainedXP table") end
	end

	if not JMD["kills"] then
		JMD["kills"] = {}
		dirty = true
	end

	if dirty and isServer() then
		syncItemModData(player, item)
	end

	return JMD
end


SRJ_ModDataHandler.customKeys = {}
function SRJ_ModDataHandler.parseSandBoxOption()
    local option = SandboxVars.SkillRecoveryJournal.ModDataTrack
    for key in string.gmatch(option, "([^|]+)") do table.insert(SRJ_ModDataHandler.customKeys, key) end
end


function SRJ_ModDataHandler.returnCapturedKeys(journalData)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #SRJ_ModDataHandler.customKeys <= 0 then SRJ_ModDataHandler.parseSandBoxOption() end

    local data = {}
    for _,key in pairs(SRJ_ModDataHandler.customKeys) do
        local valueFromKey = journalData and journalData.pModData and journalData.pModData[key]
        if valueFromKey then
            table.insert(data, key)
        end
    end

    return data
end


function SRJ_ModDataHandler.hasModDataToTransfer(player, item, doReading)
	local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
	if (not sandbox) or (sandbox == "") then return false end
	if #SRJ_ModDataHandler.customKeys <= 0 then SRJ_ModDataHandler.parseSandBoxOption() end
	local journalData = SRJ_ModDataHandler.getItemModData(item)
	local playerData = player:getModData()
	for _, key in pairs(SRJ_ModDataHandler.customKeys) do
		if doReading then
			if journalData and journalData.pModData and journalData.pModData[key] then
				return true
			end
		else
			if playerData and playerData[key] then
				return true
			end
		end
	end
	return false
end


function SRJ_ModDataHandler.copyDataToPlayer(player, journal)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #SRJ_ModDataHandler.customKeys <= 0 then SRJ_ModDataHandler.parseSandBoxOption() end

    local data = {}

    local playerData = player:getModData()
    local journalData = SRJ_ModDataHandler.getItemModData(journal)

    for _,key in pairs(SRJ_ModDataHandler.customKeys) do
        local valueFromKey = journalData and journalData.pModData and journalData.pModData[key]
        local value = valueFromKey and copyTable(valueFromKey)
        if value then
            playerData[key] = value
            table.insert(data, key)
        end
    end

    return data
end


function SRJ_ModDataHandler.copyDataToJournal(player, journal)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #SRJ_ModDataHandler.customKeys <= 0 then SRJ_ModDataHandler.parseSandBoxOption() end

    local data = {}

    local journalData = SRJ_ModDataHandler.getItemModData(journal)
    local playerData = player:getModData()

    for _,key in pairs(SRJ_ModDataHandler.customKeys) do

        local valueFromKey = playerData and playerData[key]
        local value = valueFromKey and copyTable(valueFromKey)

        if value then
            journalData.pModData = journalData.pModData or {}
            journalData.pModData[key] = value
            table.insert(data, key)
        end
    end

    return data
end

return SRJ_ModDataHandler
