local SRJ_ModDataHandler = {}

-- player mod data

-- store initial skill levels from traits and profession in player mod data
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
		-- on the rare chance it was not init before, check again
		-- can happen if on mp server and player uses SRJ before gaining xp
		SRJ_ModDataHandler.setPassiveLevels(_, player)
	end
	return pMD.SRJPassiveSkillsInit
end


function SRJ_ModDataHandler.getReadXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	if not pMD.recoveryJournalXpLog then
		pMD.recoveryJournalXpLog = {}
	end
	if not pMD.recoveryJournalXpLog.kills then -- for pre-existing journals
		pMD.recoveryJournalXpLog.kills = {}
	end
	return pMD.recoveryJournalXpLog
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


-- item mod data
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


-- modData capture --
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