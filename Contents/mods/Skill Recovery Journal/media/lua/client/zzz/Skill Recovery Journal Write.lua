require "Skill Recovery Journal Main"


ISToolTipInv_setItem = ISToolTipInv.setItem
function ISToolTipInv:setItem(item)
	if item:getType() == "SkillRecoveryJournal" then
		item:setTooltip(SRJ.generateTooltip(item, self.tooltip:getCharacter()))
	end
	ISToolTipInv_setItem(self, item)
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

		local transcribeSpeed = SandboxVars.Character.TranscribeSpeed or 0
		if writing and gainedXP then
			local transcribing = false
			for skill,xp in pairs(recoverableXP) do
				if xp > 0 then
					--debug_text = debug_text.." xp:"..xp
					gainedXP[skill] = gainedXP[skill] or 0
					if xp > gainedXP[skill] then
						if transcribeSpeed > 0 then
							local xpAdd = transcribeSpeed
							print("TESTING: XP:"..xp.." gainedXP["..skill.."]:"..gainedXP[skill].." xpAdd:"..xpAdd)
							self.changesMade = true
							transcribing = true
							gainedXP[skill] = math.min(xp, gainedXP[skill]+xpAdd)
							self:resetJobDelta()
						else
							local xpAdd = math.floor(xp/self.maxTime)+1
							--debug_text = debug_text.." adding:"..xpAdd
							self.changesMade = true
							gainedXP[skill] = math.min(xp, gainedXP[skill]+xpAdd)
						end
					end
				end
			end
			if transcribeSpeed > 0 and not transcribing then
				self:forceStop()
				self.character:Say(getText("IGUI_PlayerText_AllDoneWithJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
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
			local pSteamID = character:getSteamID()
			local pOnlineID = character:getOnlineID()
			print("-- SRJ INFO:".." pSteamID: "..pSteamID.." pOnlineID: "..pOnlineID.." --")

			if pSteamID ~= 0 then
				if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
					sayText=getText("IGUI_PlayerText_DoesntFeelRightToWrite"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
					willWrite = false
				end
				if willWrite and pSteamID then
					journalID["steamID"] = pSteamID
				end
			end
			if willWrite and pOnlineID then
				journalID["onlineID"] = pOnlineID
			end
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

			JMD["author"] = character:getFullName()

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

		local transcribeSpeed = SandboxVars.Character.TranscribeSpeed or 0
		if transcribeSpeed > 0 then
			o.loopedAction = false
			o.useProgressBar = false
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