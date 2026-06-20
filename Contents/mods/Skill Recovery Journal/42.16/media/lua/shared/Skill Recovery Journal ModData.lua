local SRJ_ModDataHandler = {}


function SRJ_ModDataHandler.initStartingXP(id, player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)

	-- Migrate
	if (not pMD.SRJSkillsInit) and pMD.SRJTraitSkillsInit then
		pMD.SRJSkillsInit = copyTable(pMD.SRJTraitSkillsInit)
		if getDebug() then print("SRJ: migrated SRJTraitSkillsInit -> SRJSkillsInit") end
	end

	---defunct
	pMD.SRJTraitSkillsInit = nil
	pMD.SRJStartingXP = nil
	pMD.SRJPassiveLevelsCaptured = nil

	if pMD.SRJSkillsInit then return end

	local hoursSurvived = player.getHoursSurvived and player:getHoursSurvived() or 0
	if hoursSurvived >= 1 then
		if getDebug() then print("SRJ: skipped starting-level snapshot for existing character (hours survived: " .. tostring(hoursSurvived) .. ")") end
		return
	end

	pMD.SRJSkillsInit = {}
	for i = 1, Perks.getMaxIndex() - 1 do
		local perk = Perks.fromIndex(i)
		if perk and perk:getParent():getId() ~= "None" then
			local level = player:getPerkLevel(perk)
			if level and level > 0 then
				pMD.SRJSkillsInit[perk:getId()] = level
			end
		end
	end
	if getDebug() then print("SRJ: captured starting levels for new character") end
end


function SRJ_ModDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if not pMD.SRJSkillsInit then
		pMD.SRJSkillsInit = {}

		-- xp granted by profession
		local playerDesc = player:getDescriptor()
		local playerProfessionID = playerDesc:getCharacterProfession()
		local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(playerProfessionID)
		local profXpBoost = transformIntoKahluaTable(profDef:getXpBoosts())
		if profXpBoost then
			for perk,level in pairs(profXpBoost) do
				local perky = tostring(perk)
				local levely = tonumber(tostring(level))
				pMD.SRJSkillsInit[perky] = levely
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
					pMD.SRJSkillsInit[perky] = (pMD.SRJSkillsInit[perky] or 0) + levely
				end
			end
		end


		for i=1, Perks.getMaxIndex()-1 do
			---@type PerkFactory.Perks
			local perks = Perks.fromIndex(i)
			if perks then
				---@type PerkFactory.Perk
				local perk = PerkFactory.getPerk(perks)
				if perk and perk:isPassiv() and tostring(perk:getParent():getType())~="None" then
					local perkID = perk:getId()
					if not pMD.SRJSkillsInit[perkID] then
						local currentLevel = player:getPerkLevel(perk)
						if currentLevel > 0 then
							pMD.SRJSkillsInit[perkID] = currentLevel
						end
					end
				end
			end
		end

		if getDebug() then for k,v in pairs(pMD.SRJSkillsInit) do print(" -- STARTING-LEVEL: "..k.." = "..v) end end
	end

	return pMD.SRJSkillsInit
end


-- deducted xp from radio and tv
function SRJ_ModDataHandler.checkIfDeductedXP(player, perksType, XP)

	SRJ_ModDataHandler.getFreeLevelsFromTraitsAndProfession(player)

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
	return SRJ_ModDataHandler.getFreeLevelsFromTraitsAndProfession(player)
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


local function jsonEncode(val, depth)
	depth = depth or 0
	local t = type(val)
	if val == nil then return "null"
	elseif t == "boolean" then return val and "true" or "false"
	elseif t == "number" then
		if val == math.floor(val) and val == val then return string.format("%.0f", val)
		else return tostring(val) end
	elseif t == "string" then
		return '"'..val:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"'
	elseif t == "table" then
		local n = 0
		for _ in pairs(val) do n = n+1 end
		if n == 0 then return "{}" end
		local indent = string.rep("  ", depth+1)
		local closing = string.rep("  ", depth)
		if n == #val then
			local parts = {}
			for i=1,n do parts[i] = indent..jsonEncode(val[i], depth+1) end
			return "[\n"..table.concat(parts, ",\n").."\n"..closing.."]"
		else
			local parts = {}
			for k,v in pairs(val) do
				table.insert(parts, indent..jsonEncode(tostring(k)).." : "..jsonEncode(v, depth+1))
			end
			return "{\n"..table.concat(parts, ",\n").."\n"..closing.."}"
		end
	end
	return "null"
end


local jp = {}

function jp.skip(p)
	while p.pos <= p.len do
		local b = p.str:byte(p.pos)
		if b==32 or b==9 or b==10 or b==13 then p.pos=p.pos+1 else break end
	end
end

function jp.parseString(p)
	p.pos = p.pos+1
	local parts = {}
	while p.pos <= p.len do
		local c = p.str:sub(p.pos,p.pos)
		if c == '"' then p.pos=p.pos+1 return table.concat(parts)
		elseif c == '\\' then
			p.pos = p.pos+1
			local e = p.str:sub(p.pos,p.pos)
			if     e=='"'  then parts[#parts+1]='"'
			elseif e=='\\'then parts[#parts+1]='\\'
			elseif e=='/'  then parts[#parts+1]='/'
			elseif e=='n'  then parts[#parts+1]='\n'
			elseif e=='r'  then parts[#parts+1]='\r'
			elseif e=='t'  then parts[#parts+1]='\t'
			else                parts[#parts+1]=e end
			p.pos = p.pos+1
		else parts[#parts+1]=c p.pos=p.pos+1 end
	end
	error("unterminated string")
end

function jp.parseObject(p)
	p.pos = p.pos+1
	local t = {}
	jp.skip(p)
	if p.str:sub(p.pos,p.pos)=='}' then p.pos=p.pos+1 return t end
	while p.pos <= p.len do
		jp.skip(p)
		local key = jp.parseString(p)
		jp.skip(p)
		p.pos = p.pos+1
		jp.skip(p)
		t[key] = jp.parseValue(p)
		jp.skip(p)
		local c = p.str:sub(p.pos,p.pos)
		p.pos = p.pos+1
		if c=='}' then return t elseif c~=',' then error("expected ',' or '}'") end
	end
	error("unterminated object")
end

function jp.parseArray(p)
	p.pos = p.pos+1
	local t = {}
	jp.skip(p)
	if p.str:sub(p.pos,p.pos)==']' then p.pos=p.pos+1 return t end
	while p.pos <= p.len do
		jp.skip(p)
		t[#t+1] = jp.parseValue(p)
		jp.skip(p)
		local c = p.str:sub(p.pos,p.pos)
		p.pos = p.pos+1
		if c==']' then return t elseif c~=',' then error("expected ',' or ']'") end
	end
	error("unterminated array")
end

function jp.parseValue(p)
	jp.skip(p)
	local c = p.str:sub(p.pos,p.pos)
	if c=='"' then return jp.parseString(p)
	elseif c=='{' then return jp.parseObject(p)
	elseif c=='[' then return jp.parseArray(p)
	elseif p.str:sub(p.pos,p.pos+3)=="null"  then p.pos=p.pos+4 return nil
	elseif p.str:sub(p.pos,p.pos+3)=="true"  then p.pos=p.pos+4 return true
	elseif p.str:sub(p.pos,p.pos+4)=="false" then p.pos=p.pos+5 return false
	else
		local numStr = p.str:match("^-?%d+%.?%d*[eE]?[+%-]?%d*", p.pos)
		if numStr then p.pos=p.pos+#numStr return tonumber(numStr) end
		error("unexpected character '"..c.."' at pos "..p.pos)
	end
end

local function jsonDecode(str)
	if not str or str == "" then return nil end
	local p = {str=str, pos=1, len=#str}
	return jp.parseValue(p)
end



local SRJ_ServerLedger = {}


function SRJ_ModDataHandler.getLedgerKey(player)
	local username = player:getUsername()
	if username and username ~= "" then
		return username
	end

	return "sp"
end


local function getLedgerPath(ledgerKey)
	return "SRJ/ledger_" .. ledgerKey .. ".json"
end


function SRJ_ModDataHandler.getServerReadXP(ledgerKey, journalID)
	SRJ_ServerLedger[ledgerKey] = SRJ_ServerLedger[ledgerKey] or {}
	SRJ_ServerLedger[ledgerKey][journalID] = SRJ_ServerLedger[ledgerKey][journalID] or {}
	SRJ_ServerLedger[ledgerKey][journalID].kills = SRJ_ServerLedger[ledgerKey][journalID].kills or {}
	return SRJ_ServerLedger[ledgerKey][journalID]
end


function SRJ_ModDataHandler.buildJournalID(JMD)
	local id = JMD and JMD["ID"]
	if not id then return "unkeyed" end
	local user = tostring(id["username"] or "nouser")
	return user
end


function SRJ_ModDataHandler.loadServerLedger(player)
	if not isServer() then return end
	local ledgerKey = SRJ_ModDataHandler.getLedgerKey(player)
	local path = getLedgerPath(ledgerKey)

	local stream = getFileInput(path)
	if not stream then
		SRJ_ServerLedger[ledgerKey] = {}
		if getDebug() then print("SRJ: no ledger file found for " .. ledgerKey .. ", starting fresh") end
		return
	end

	local chars = {}
	local b = stream:read()
	while b ~= -1 do
		table.insert(chars, string.char(b))
		b = stream:read()
	end
	stream:close()

	local raw = table.concat(chars)
	if raw == "" then
		SRJ_ServerLedger[ledgerKey] = {}
		return
	end

	local parsed = jsonDecode(raw)
	SRJ_ServerLedger[ledgerKey] = parsed or {}

	if getDebug() then print("SRJ: loaded ledger for " .. ledgerKey) end
end


function SRJ_ModDataHandler.saveServerLedger(player)
	if not isServer() then return end
	local ledgerKey = SRJ_ModDataHandler.getLedgerKey(player)
	local data = SRJ_ServerLedger[ledgerKey]
	if not data then return end

	local path = getLedgerPath(ledgerKey)
	local writer = getFileWriter(path, true, false)
	if not writer then
		print("SRJ ERROR: could not open ledger file for writing: " .. path)
		return
	end

	writer:write(jsonEncode(data))
	writer:close()

	if getDebug() then print("SRJ: saved ledger for " .. ledgerKey) end
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
