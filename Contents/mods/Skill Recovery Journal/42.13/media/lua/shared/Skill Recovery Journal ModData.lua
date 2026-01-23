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
	-- check if passive levels are init (workaround for mp server)
	SRJ_ModDataHandler.setPassiveLevels(_, player)

	local fN, lCF = nil, getCoroutineCallframeStack(getCurrentCoroutine(),0)
	local fD = lCF ~= nil and lCF and getFilenameOfCallframe(lCF)
	local i = fD and fD:match('^.*()/')
	fN = i and fD:sub(i+1):gsub(".lua", "")

	if fN and fN=="ISRadioInteractions" then
		--if getDebug() then print("deductibleXP: `",fN,"` \n (",perksType,", ",XP," )") end
		local perkID = perksType:getId()
		local deductibleXP = SRJ_ModDataHandler.getDeductedXP(player)
		deductibleXP[perkID] = (deductibleXP[perkID] or 0) + XP
	end
end


function SRJ_ModDataHandler.getDeductedXP(player)
	local pMD = SRJ_ModDataHandler.getPlayerModData(player)
	pMD.deductedXP = pMD.deductedXP or {}
	return pMD.deductedXP
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
		-- init new journal mod data
    	iMd["SRJ"] = {}
		iMd["SRJ"]["gainedXP"] = {}
		iMd["SRJ"]["learnedRecipes"] = {}
		iMd["SRJ"]["kills"] = {}
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


-- handle receive data from client
local function SkillRecoveryJournalOnClientCommand(module, command, player, args)
	if module == "SkillRecoveryJournal" then 
		local playerID = player:getOnlineID()
		if command == "rename" then
			if getDebug() then print("SkillRecoveryJournal received rename for item " .. tostring(args.itemID) .. " from player " .. tostring(playerID)) end
			local item = player:getInventory():getItemWithIDRecursiv(args.itemID)
			if item then
				item:setName(args.name)

				local JMD = SRJ_ModDataHandler.getItemModData(item)
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

return SRJ_ModDataHandler