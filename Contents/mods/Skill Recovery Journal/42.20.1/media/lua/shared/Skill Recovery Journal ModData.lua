local SRJ_ModDataHandler = {}


function SRJ_ModDataHandler.initStartingXP(id, player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)

	-- Migrate
	if (not pMD.SRJSkillsInit) and type(pMD.SRJTraitSkillsInit) == "table" then
		pMD.SRJSkillsInit = copyTable(pMD.SRJTraitSkillsInit)
		if getDebug() then print("SRJ: migrated SRJTraitSkillsInit -> SRJSkillsInit") end
	elseif pMD.SRJTraitSkillsInit ~= nil and type(pMD.SRJTraitSkillsInit) ~= "table" then
		print("SRJ WARNING: SRJTraitSkillsInit was not a table (" .. type(pMD.SRJTraitSkillsInit) .. "), discarding malformed legacy data")
	end

	---defunct
	pMD.SRJTraitSkillsInit = nil
	pMD.SRJStartingXP = nil
	pMD.SRJPassiveLevelsCaptured = nil
	pMD.readXPDisplay = nil

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
	if type(pMD.deductedXP) ~= "table" then
		if pMD.deductedXP ~= nil then
			print("SRJ WARNING: deductedXP was not a table (" .. type(pMD.deductedXP) .. "), discarding malformed legacy data")
		end
		pMD.deductedXP = {}
	end
	return pMD.deductedXP
end


function SRJ_ModDataHandler.getFlatXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if type(pMD.flatXP) ~= "table" then
		if pMD.flatXP ~= nil then
			print("SRJ WARNING: flatXP was not a table (" .. type(pMD.flatXP) .. "), discarding malformed legacy data")
		end
		pMD.flatXP = {}
	end
	return pMD.flatXP
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


local function utf8Codepoints(s)
	local codepoints = {}
	local i = 1
	local len = #s
	while i <= len do
		local b1 = s:byte(i)
		if b1 < 0x80 then
			codepoints[#codepoints+1] = b1
			i = i + 1
		elseif b1 >= 0xC0 and b1 < 0xE0 and i+1 <= len then
			local b2 = s:byte(i+1)
			codepoints[#codepoints+1] = ((b1 - 0xC0) * 0x40) + (b2 - 0x80)
			i = i + 2
		elseif b1 >= 0xE0 and b1 < 0xF0 and i+2 <= len then
			local b2, b3 = s:byte(i+1), s:byte(i+2)
			codepoints[#codepoints+1] = ((b1 - 0xE0) * 0x1000) + ((b2 - 0x80) * 0x40) + (b3 - 0x80)
			i = i + 3
		elseif b1 >= 0xF0 and b1 < 0xF8 and i+3 <= len then
			local b2, b3, b4 = s:byte(i+1), s:byte(i+2), s:byte(i+3)
			codepoints[#codepoints+1] = ((b1 - 0xF0) * 0x40000) + ((b2 - 0x80) * 0x1000) + ((b3 - 0x80) * 0x40) + (b4 - 0x80)
			i = i + 4
		else
			codepoints[#codepoints+1] = b1
			i = i + 1
		end
	end
	return codepoints
end


local function utf8Encode(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
	elseif cp < 0x10000 then
		return string.char(
			0xE0 + math.floor(cp / 0x1000),
			0x80 + (math.floor(cp / 0x40) % 0x40),
			0x80 + (cp % 0x40)
		)
	else
		return string.char(
			0xF0 + math.floor(cp / 0x40000),
			0x80 + (math.floor(cp / 0x1000) % 0x40),
			0x80 + (math.floor(cp / 0x40) % 0x40),
			0x80 + (cp % 0x40)
		)
	end
end


local function jsonEscapeString(s)
	local codepoints = utf8Codepoints(s)
	local parts = {}
	for _, cp in ipairs(codepoints) do
		if cp < 0x80 then
			parts[#parts+1] = string.char(cp)
		elseif cp <= 0xFFFF then
			parts[#parts+1] = string.format("\\u%04x", cp)
		else
			local cp2 = cp - 0x10000
			local hi = 0xD800 + math.floor(cp2 / 0x400)
			local lo = 0xDC00 + (cp2 % 0x400)
			parts[#parts+1] = string.format("\\u%04x\\u%04x", hi, lo)
		end
	end
	return table.concat(parts)
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
		local escaped = val:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
		return '"'..jsonEscapeString(escaped)..'"'
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
			elseif e=='u'  then
				local hex1 = p.str:sub(p.pos+1, p.pos+4)
				local cp1 = tonumber(hex1, 16)
				if cp1 and cp1 >= 0xD800 and cp1 <= 0xDBFF and p.str:sub(p.pos+5,p.pos+5)=='\\' and p.str:sub(p.pos+6,p.pos+6)=='u' then
					local hex2 = p.str:sub(p.pos+7, p.pos+10)
					local cp2 = tonumber(hex2, 16)
					if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
						local combined = 0x10000 + (cp1 - 0xD800) * 0x400 + (cp2 - 0xDC00)
						parts[#parts+1] = utf8Encode(combined)
						p.pos = p.pos + 10
					else
						parts[#parts+1] = utf8Encode(cp1)
						p.pos = p.pos + 4
					end
				elseif cp1 then
					parts[#parts+1] = utf8Encode(cp1)
					p.pos = p.pos + 4
				else
					parts[#parts+1] = 'u'
				end
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


SRJ_ModDataHandler.jsonEncode = jsonEncode
SRJ_ModDataHandler.jsonDecode = jsonDecode


function SRJ_ModDataHandler.getPlayerModData(player)
    local pMd = player:getModData()
    pMd["SRJ"] = pMd["SRJ"] or {}
    return pMd["SRJ"]
end


function SRJ_ModDataHandler.setPlayerModData(player, newModData)
    local pMd = player:getModData()
    pMd["SRJ"] = newModData
end


function SRJ_ModDataHandler.getDisplayData(item)
    local iMd = item:getModData()
    local srj = iMd["SRJ"]
    local display = (srj and srj.display) or {}
    display.gainedXP = display.gainedXP or {}
    display.flatGainedXP = display.flatGainedXP or {}
    display.learnedRecipeCount = display.learnedRecipeCount or 0
    display.kills = display.kills or {}
    display.pModData = display.pModData or {}
    display.usedXP = display.usedXP or {}
    display.usedXP.flat = display.usedXP.flat or {}
    return display
end


function SRJ_ModDataHandler.getReadXP(player)
    local pMD = SRJ_ModDataHandler.getPlayerModData(player)
    pMD.readXP = pMD.readXP or {}
    pMD.readXP.flat = pMD.readXP.flat or {}
    pMD.readXP.kills = pMD.readXP.kills or {}
    return pMD.readXP
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


function SRJ_ModDataHandler.hasModDataToTransfer(player, journalRecord, doReading)
	local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
	if (not sandbox) or (sandbox == "") then return false end
	if #SRJ_ModDataHandler.customKeys <= 0 then SRJ_ModDataHandler.parseSandBoxOption() end
	local playerData = player:getModData()
	for _, key in pairs(SRJ_ModDataHandler.customKeys) do
		if doReading then
			if journalRecord and journalRecord.pModData and journalRecord.pModData[key] then
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


function SRJ_ModDataHandler.copyDataToPlayer(player, journalRecord)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #SRJ_ModDataHandler.customKeys <= 0 then SRJ_ModDataHandler.parseSandBoxOption() end

    local data = {}

    local playerData = player:getModData()

    for _,key in pairs(SRJ_ModDataHandler.customKeys) do
        local valueFromKey = journalRecord and journalRecord.pModData and journalRecord.pModData[key]
        local value = valueFromKey and copyTable(valueFromKey)
        if value then
            playerData[key] = value
            table.insert(data, key)
        end
    end

    return data
end


function SRJ_ModDataHandler.copyDataToJournal(player, journalRecord)
    local sandbox = SandboxVars.SkillRecoveryJournal.ModDataTrack
    if (not sandbox) or (sandbox == "") then return end

    if #SRJ_ModDataHandler.customKeys <= 0 then SRJ_ModDataHandler.parseSandBoxOption() end

    local data = {}

    local playerData = player:getModData()

    for _,key in pairs(SRJ_ModDataHandler.customKeys) do

        local valueFromKey = playerData and playerData[key]
        local value = valueFromKey and copyTable(valueFromKey)

        if value then
            journalRecord.pModData = journalRecord.pModData or {}
            journalRecord.pModData[key] = value
            table.insert(data, key)
        end
    end

    return data
end

return SRJ_ModDataHandler
