SRJ = {}

Events.OnGameBoot.Add(print("Skill Recovery Journal: ver:0.3-transcribeOverTime-LANG-HOTFIX"))

function SRJ.CleanseFalseSkills(gainedXP)
	for skill,xp in pairs(gainedXP) do

		local perkList = PerkFactory.PerkList
		local junk = true

		if xp>1 then
			for i=0, perkList:size()-1 do
				---@type PerkFactory.Perk
				local perk = perkList:get(i)
				if perk and tostring(perk:getType()) == skill then
					junk = false
				end
			end
		end

		if junk then
			gainedXP[skill] = nil
		end
	end
end


---@param journal InventoryItem | Literature
---@param player IsoGameCharacter | IsoPlayer
function SRJ.generateTooltip(journal, player)

	local journalModData = journal:getModData()
	local JMD = journalModData["SRJ"]

	local blankJournalTooltip = getText("IGUI_Tooltip_Empty")

	if not JMD then
		return blankJournalTooltip
	end

	journal:setNumberOfPages(-1)
	journal:setCanBeWrite(false)

	local gainedXP = JMD["gainedXP"]
	if not gainedXP then
		return blankJournalTooltip
	else
		SRJ.CleanseFalseSkills(JMD["gainedXP"])
	end

	local skillsRecord = ""
	for skill,xp in pairs(gainedXP) do
		local perk = PerkFactory.getPerk(Perks[skill])
		local perkName = perk:getName()
		local xpBasedOnPlayer = xp
		skillsRecord = skillsRecord..perkName.." ("..xpBasedOnPlayer.." xp)".."\n"
	end

	local learnedRecipes = JMD["learnedRecipes"] or {}
	local recipeNum = 0
	for k,v in pairs(learnedRecipes) do
		recipeNum = recipeNum+1
	end
	if recipeNum>0 then
		local properPlural = getText("IGUI_Tooltip_Recipe")
		if recipeNum>1 then
			properPlural = getText("IGUI_Tooltip_Recipes")
		end
		skillsRecord = skillsRecord..recipeNum.." "..properPlural..".".."\n"
	end

	skillsRecord = "\n"..getText("IGUI_Tooltip_Start").." "..JMD["author"]..getText("IGUI_Tooltip_End").."\n"..skillsRecord

	return skillsRecord
end


ISToolTipInv_setItem = ISToolTipInv.setItem
function ISToolTipInv:setItem(item)
	if item:getType() == "SkillRecoveryJournal" then
		item:setTooltip(SRJ.generateTooltip(item, self.tooltip:getCharacter()))
	end
	ISToolTipInv_setItem(self, item)
end



SRJOVERWRITE_ISReadABook_update = ISReadABook.update
function ISReadABook:update()
	SRJOVERWRITE_ISReadABook_update(self)

	---@type Literature
	local journal = self.item

	if journal:getType() == "SkillRecoveryJournal" then
		---@type IsoGameCharacter | IsoPlayer
		local player = self.character

		local journalModData = journal:getModData()
		local JMD = journalModData["SRJ"]
		local gainedXp = false

		local delayedStop = false
		local sayText
		local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}

		local pSteamID = player:getSteamID()

		if (not JMD) then
			delayedStop = true
			sayText = "IGUI_PlayerText_NothingWritten"

		elseif self.character:HasTrait("Illiterate") then
			delayedStop = true

		elseif pSteamID ~= 0 then
			JMD["ID"] = JMD["ID"] or {}
			local journalID = JMD["ID"]
			if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
				delayedStop = true
				sayText = getText("IGUI_PlayerText_DoesntFeelRightToRead")
			end
		end

		if not delayedStop then

			local learnedRecipes = JMD["learnedRecipes"] or {}
			for recipeID,_ in pairs(learnedRecipes) do
				if not player:isRecipeKnown(recipeID) then
					player:learnRecipe(recipeID)
					gainedXp = true
				end
			end

			local gainedXP = JMD["gainedXP"]

			local maxXP = 0

			for skill,xp in pairs(gainedXP) do
				if skill and skill~="NONE" or skill~="MAX" then
					if xp > maxXP then
						maxXP = xp
					end
				else
					gainedXP[skill] = nil
				end
			end

			local XpMultiplier = SandboxVars.XpMultiplier or 1
			local xpRate = (maxXP/self.maxTime)/XpMultiplier

			local minutesPerPage = 1
			if isClient() then
				minutesPerPage = getServerOptions():getFloat("MinutesPerPage") or 1
			end
			xpRate = minutesPerPage / minutesPerPage

			for skill,xp in pairs(gainedXP) do
				local currentXP = player:getXp():getXP(Perks[skill])

				if currentXP < xp then
					local perkLevel = player:getPerkLevel(Perks[skill])+1
					local perPerkXpRate = math.floor(((xpRate^perkLevel)*(10*perkLevel))*1000)/1000
					if perkLevel == 11 then
						perPerkXpRate=0
					end
					print ("TESTING:  perPerkXpRate:"..perPerkXpRate.."  perkLevel:"..perkLevel.."  xpStored:"..xp.."  currentXP:"..currentXP)
					if currentXP+perPerkXpRate > xp then
						perPerkXpRate = (xp-(currentXP-0.01))
						print(" --xp overflowed, capped at:"..perPerkXpRate)
					end

					if perPerkXpRate>0 then
						player:getXp():AddXP(Perks[skill], perPerkXpRate)
						gainedXp = true
						self:resetJobDelta()
					end
				end
			end

			if not gainedXp then
				delayedStop = true
				sayTextChoices = {"IGUI_PlayerText_KnowSkill","IGUI_PlayerText_BookObsolete"}
				sayText = getText(sayTextChoices[ZombRand(#sayTextChoices)+1])
			--else
			--	self:resetJobDelta()
			end
		end

		if delayedStop then
			if self.pageTimer >= self.maxTime then
				self.pageTimer = 0
				self.maxTime = 0
				if sayText then
					player:Say(sayText, 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
				end
				self:forceStop()
			end
		end
	end
end


SRJOVERWRITE_ISCraftAction_perform = ISCraftAction.perform
function ISCraftAction:perform()
	if self.recipe and self.recipe:getOriginalname() == "Transcribe Journal" and self.item:getType() == "SkillRecoveryJournal" then
		if not self.character:HasTrait("Illiterate") then
			if self.changesMade and self.changesMade==true then
				self.character:Say(getText("IGUI_PlayerText_AllDoneWithJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
			else
				self.character:Say(getText("IGUI_PlayerText_NothingToAddToJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
			end
		end
	end
	SRJOVERWRITE_ISCraftAction_perform(self)
end


SRJOVERWRITE_ISCraftAction_update = ISCraftAction.update
function ISCraftAction:update()
	SRJOVERWRITE_ISCraftAction_update(self)

	if self.recipe and self.recipe:getOriginalname() == "Transcribe Journal" and self.item:getType() == "SkillRecoveryJournal" then

		local journalModData = self.item:getModData()
		journalModData["SRJ"] = journalModData["SRJ"] or {}
		local JMD = journalModData["SRJ"]
		local journalID = JMD["ID"]
		local pSteamID = self.character:getSteamID()

		local writing = true

		if pSteamID ~= 0 and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
			writing = false
		end

		local recoverableXP = SRJ.calculateGainedSkills(self.character)
		if recoverableXP == nil then
			writing = false
		end

		JMD["gainedXP"] = JMD["gainedXP"] or {}
		local gainedXP = JMD["gainedXP"]
		--local debug_text = "ISCraftAction:update - "

		if writing and gainedXP then
			for skill,xp in pairs(recoverableXP) do
				if xp > 0 then
					--debug_text = debug_text.." xp:"..xp
					gainedXP[skill] = gainedXP[skill] or 0
					if xp > gainedXP[skill] then
						local xpAdd = math.floor(xp/self.maxTime)+1
						--debug_text = debug_text.." adding:"..xpAdd
						self.changesMade = true
						gainedXP[skill] = math.min(xp, gainedXP[skill]+xpAdd)
					end
				end
			end
		end

		--print(debug_text)
	end
end

SRJOVERWRITE_ISCraftAction_new = ISCraftAction.new
---@param character IsoGameCharacter
function ISCraftAction:new(character, item, time, recipe, container, containers)
	local o = SRJOVERWRITE_ISCraftAction_new(self, character, item, time, recipe, container, containers)

	if recipe and recipe:getOriginalname() == "Transcribe Journal" then

		local oldJournal = item
		local journalModData = oldJournal:getModData()
		journalModData["SRJ"] = journalModData["SRJ"] or {}
		local JMD = journalModData["SRJ"]

		local writingToolSound = "PenWriteSounds"
		if character:getInventory():contains("Pencil") then
			writingToolSound = "PencilWriteSounds"
		end
		o.craftSound = writingToolSound

		local knownRecipesCount = character:getKnownRecipes():size()
		local storedRecipesCount = 0
		local storedJournalXP

		if JMD then
			if JMD["learnedRecipes"] then
				storedRecipesCount = #JMD["learnedRecipes"]
			end
			storedJournalXP = JMD["gainedXP"]
		end

		local recipeDiff = math.max(0, knownRecipesCount-storedRecipesCount)
		local gainedSkills = SRJ.calculateGainedSkills(character)
		local willWrite = true
		local sayText

		if gainedSkills == nil then
			sayText=getText("IGUI_PlayerText_DontHaveAnyXP"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
			willWrite = false
		else
			JMD["ID"] = JMD["ID"] or {}
			local journalID = JMD["ID"]
			JMD["author"] = character:getFullName()
			local pSteamID = character:getSteamID()
			local pOnlineID = character:getOnlineID()
			print("-- SRJ INFO:".." pSteamID: "..pSteamID.." pOnlineID: "..pOnlineID.." --")

			if pSteamID ~= 0 then
				if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
					sayText=getText("IGUI_PlayerText_DoesntFeelRightToWrite"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
					willWrite = false
				end
				journalID["steamID"] = pSteamID
			end
			journalID["onlineID"] = pOnlineID
		end

		if character:HasTrait("Illiterate") then
			local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}
			sayText=getText(sayTextChoices[ZombRand(#sayTextChoices)+1]).." ("..getText("UI_trait_Illiterate")..")"
			willWrite = false
		end

		if sayText then
			character:Say(sayText)
		end

		local xpDiff = 0
		if willWrite then
			for i=1, Perks.getMaxIndex()-1 do
				---@type PerkFactory.Perks
				local perks = Perks.fromIndex(i)

				if perks ~= Perks.Strength and perks ~= Perks.Fitness then

					---@type IsoGameCharacter.PerkInfo
					local perkInfo = character:getPerkInfo(perks)
					if perkInfo then

						local perk = PerkFactory.getPerk(perks)
						local perkType = tostring(perk:getType())

						local storedXPForPerk = 0
						if storedJournalXP then
							storedXPForPerk = storedJournalXP[perkType] or 0
						end
						local currentXP = 0
						if gainedSkills then
							currentXP = gainedSkills[perkType] or 0
						end
						--print("JOURNAL: xpDiff:"..(math.sqrt(math.max(0,currentXP-storedXPForPerk))*2).."  currentXP:"..currentXP.." storedXPForPerk:"..storedXPForPerk)
						xpDiff = xpDiff + (math.sqrt(math.max(0,currentXP-storedXPForPerk))*2)
					end
				end
			end
		end
		o.maxTime = o.maxTime+(xpDiff)+(math.floor(math.sqrt(recipeDiff)+0.5)*50)
	end

	return o
end


SRJOVERWRITE_ISReadABook_new = ISReadABook.new
function ISReadABook:new(player, item, time)
	local o = SRJOVERWRITE_ISReadABook_new(self, player, item, time)

	if o and item:getType() == "SkillRecoveryJournal" then
		o.loopedAction = false
		o.useProgressBar = false
		o.maxTime = 100

		local journalModData = item:getModData()
		local JMD = journalModData["SRJ"]
		if JMD then
			local gainedXP = JMD["gainedXP"]
			if gainedXP then
				SRJ.CleanseFalseSkills(JMD["gainedXP"])
			end
		end

	end

	return o
end


---@param player IsoGameCharacter | IsoPlayer
function SRJ.writingJournal(recipe, player, item)
	if item and (item:getType() == "SkillRecoveryJournal") then
		return true
	end
	return false
end

---@param recipe InventoryItem | Literature
---@param player IsoGameCharacter | IsoPlayer
function SRJ.writtenJournal(recipe, result, player)

	if not player then
		return
	end

	---@type InventoryItem | Literature
	local oldJournal
	if recipe then
		for i=0, recipe:size()-1 do
			local item = recipe:get(i)
			if (item:getType() == "SkillRecoveryJournal") then
				oldJournal = recipe:get(i)
			end
		end
	end

	---@type InventoryItem | Literature
	local journal = oldJournal
	if not journal then
		return
	end
	local journalModData = journal:getModData()
	journalModData["SRJ"] = journalModData["SRJ"] or {}
	local JMD = journalModData["SRJ"]

	JMD["learnedRecipes"] = JMD["learnedRecipes"] or {}
	local learnedRecipes = JMD["learnedRecipes"]
	---@type ArrayList
	local knownRecipes = player:getKnownRecipes()
	local gainedRecipes = {}
	for i=0, knownRecipes:size()-1 do
		local recipeID = knownRecipes:get(i)
		gainedRecipes[recipeID] = true
	end

	---@type SurvivorDesc
	local playerDesc = player:getDescriptor()
	local playerProfessionID = playerDesc:getProfession()
	local playerProfession = ProfessionFactory.getProfession(playerProfessionID)

	---@type TraitCollection
	local playerTraits = player:getTraits()
	for i=0, playerTraits:size()-1 do
		local trait = playerTraits:get(i)
		---@type TraitFactory.Trait
		local traitTrait = TraitFactory.getTrait(trait)
		local traitRecipes = traitTrait:getFreeRecipes()
		for ii=0, traitRecipes:size()-1 do
			local traitRecipe = traitRecipes:get(ii)
			gainedRecipes[traitRecipe] = nil
		end
	end

	local profFreeRecipes = playerProfession:getFreeRecipes()
	for i=0, profFreeRecipes:size()-1 do
		local profRecipe = profFreeRecipes:get(i)
		gainedRecipes[profRecipe] = nil
	end

	for recipeID,v in pairs(gainedRecipes) do
		--print("-storing recipe: "..recipeID)
		if learnedRecipes[recipeID]~= true then
			learnedRecipes[recipeID] = true
		end
	end
	--ISTimedActionQueue.clear(player)
end


---@param player IsoGameCharacter
function SRJ.calculateGainedSkills(player)

	local bonusLevels = {}

	---@type SurvivorDesc
	local playerDesc = player:getDescriptor()
	local descXpMap = transformIntoKahluaTable(playerDesc:getXPBoostMap())

	for perk,level in pairs(descXpMap) do
		local perky = tostring(perk)
		local levely = tonumber(tostring(level))
		bonusLevels[perky] = levely
	end

	local gainedXP = {}
	local storingSkills = false

	--print("INFO: SkillRecoveryJournal: calculating gained skills:  total skills: "..Perks.getMaxIndex())
	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perks
		local perks = Perks.fromIndex(i)

		if perks then
			---@type PerkFactory.Perk
			local perk = PerkFactory.getPerk(perks)

			if perk then
				---@type IsoGameCharacter.PerkInfo
				local perkInfo = player:getPerkInfo(perks)
				if perkInfo then

					local perkLevel = perkInfo:getLevel()
					local perkType = tostring(perk:getType())
					local bonusLevelsFromTrait = bonusLevels[perkType] or 0
					local recoverableXPFactor = (SandboxVars.SkillRecoveryJournal.RecoveryPercentage/100) or 1
					local recoverableXP = perk:getTotalXpForLevel(perkLevel)

					recoverableXP = (recoverableXP-perk:getTotalXpForLevel(bonusLevelsFromTrait))*recoverableXPFactor

					if perkType == "Strength" or perkType == "Fitness" or recoverableXP==1 then
						recoverableXP = 0
					end

					--print("  "..i.." "..perkType.." = ("..perkLevel.."-"..bonusLevelsFromTrait..") = "..tostring(recoverableXP))

					if recoverableXP > 0 then
						gainedXP[perkType] = recoverableXP
						storingSkills = true
					end
				end
			end
		end
	end

	if not storingSkills then
		return
	end

	return gainedXP
end
