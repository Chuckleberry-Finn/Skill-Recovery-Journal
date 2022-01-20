require "TimedActions/ISCraftAction"

SRJOVERWRITE_ISCraftAction_perform = ISCraftAction.perform
function ISCraftAction:perform()
	SRJOVERWRITE_ISCraftAction_perform(self)
	if self.recipe and self.recipe:getOriginalname() == "Transcribe Journal" and self.item:getType() == "SkillRecoveryJournal" then
		if self.willWrite==true and (not self.character:HasTrait("Illiterate")) then
			if self.changesMade and self.changesMade==true then
				self.character:Say(getText("IGUI_PlayerText_AllDoneWithJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
			else
				self.character:Say(getText("IGUI_PlayerText_NothingToAddToJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
			end
		end
		self.character:playSound("CloseBook")
	end
end


SRJOVERWRITE_ISCraftAction_update = ISCraftAction.update
function ISCraftAction:update()
	SRJOVERWRITE_ISCraftAction_update(self)

	if self.recipe and self.recipe:getOriginalname() == "Transcribe Journal" and self.item:getType() == "SkillRecoveryJournal" then
		self.craftTimer = self.craftTimer + getGameTime():getMultiplier()
		self.item:setJobDelta(0.0)
		local updateInterval = 10
		if self.craftTimer >= updateInterval then
			self.craftTimer = 0
			self.changesMade = false

			local journalModData = self.item:getModData()
			journalModData["SRJ"] = journalModData["SRJ"] or {}
			local JMD = journalModData["SRJ"]
			local journalID = JMD["ID"]
			local pSteamID = self.character:getSteamID()

			local bOwner = true
			if pSteamID ~= 0 and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
				bOwner = false
			end

			if bOwner and (#self.gainedRecipes > 0) then
				self.recipeIntervals = self.recipeIntervals+1
				self.changesMade = true

				if self.recipeIntervals > 5 then
					local recipeChunk = math.floor(1.09^math.sqrt(#self.gainedRecipes))
					for i=0, recipeChunk do
						local recipeID = self.gainedRecipes[#self.gainedRecipes]
						JMD["learnedRecipes"][recipeID] = true
						table.remove(self.gainedRecipes,#self.gainedRecipes)
					end
					self.recipeIntervals = 0
				end
			end

			local storedJournalXP = JMD["gainedXP"]

			local pMD = self.character:getModData()
			pMD.recoveryJournalXpLog = pMD.recoveryJournalXpLog or {}
			local readXp = pMD.recoveryJournalXpLog
			local recoverableXP = SRJ.calculateGainedSkills(self.character)

			if bOwner and storedJournalXP and recoverableXP then
				for skill,xp in pairs(recoverableXP) do
					if xp > 0 then
						storedJournalXP[skill] = storedJournalXP[skill] or 0
						if xp > storedJournalXP[skill] then

							local transcribeTimeMulti = SandboxVars.SkillRecoveryJournal.TranscribeSpeed or 1
							local perkLevelPlusOne = self.character:getPerkLevel(Perks[skill])+1

							local xpRate = math.sqrt(xp)/25
							xpRate = ((xpRate*math.sqrt(perkLevelPlusOne))*1000)/1000 * transcribeTimeMulti

							if xpRate>0 then
								self.changesMade = true
								local resultingXp = math.min(xp, storedJournalXP[skill]+xpRate)
								--print("TESTING: "..skill.." recoverable:"..xp.." gained:"..storedJournalXP[skill].." +"..xpRate)
								JMD["gainedXP"][skill] = resultingXp
								readXp[skill] = resultingXp

							end
						end
					end
				end
			end

			if self.changesMade==true then

				self.playSoundLater = self.playSoundLater or 0
				if self.playSoundLater > 0 then
					self.playSoundLater = self.playSoundLater-1
				else
					self.playSoundLater = (ZombRand(2,6) + getGameTime():getMultiplier())
					self.character:playSound(self.writingToolSound)
				end
				
				self:resetJobDelta()
			end
		end
	end
end


SRJOVERWRITE_ISCraftAction_new = ISCraftAction.new
---@param character IsoGameCharacter
function ISCraftAction:new(character, item, time, recipe, container, containers)
	local o = SRJOVERWRITE_ISCraftAction_new(self, character, item, time, recipe, container, containers)

	if recipe and recipe:getOriginalname() == "Transcribe Journal" then

		local journal = item
		local journalModData = journal:getModData()
		journalModData["SRJ"] = journalModData["SRJ"] or {}
		local JMD = journalModData["SRJ"]

		o.writingToolSound = "PenWriteSounds"
		if character:getInventory():contains("Pencil") then
			o.writingToolSound = "PencilWriteSounds"
		end


		JMD["gainedXP"] = JMD["gainedXP"] or {}
		JMD["learnedRecipes"] = JMD["learnedRecipes"] or {}
		local learnedRecipes = JMD["learnedRecipes"]

		local gainedRecipes = SRJ.getGainedRecipes(character)
		o.gainedRecipes = {}
		for _,recipeID in pairs(gainedRecipes) do
			if learnedRecipes[recipeID] ~= true then
				table.insert(o.gainedRecipes,recipeID)
			end
		end

		local gainedSkills = SRJ.calculateGainedSkills(character) or false
		o.willWrite = true
		local sayText

		--print("gainedSkills: "..tostring(gainedSkills))

		if not gainedSkills and (#o.gainedRecipes <= 0) then
			sayText=getText("IGUI_PlayerText_DontHaveAnyXP"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
			o.willWrite = false
		else
			JMD["ID"] = JMD["ID"] or {}
			local journalID = JMD["ID"]
			local pSteamID = character:getSteamID()
			local pOnlineID = character:getOnlineID()
			--print("-- SRJ INFO:".." pSteamID: "..pSteamID.." pOnlineID: "..pOnlineID.." --")

			if pSteamID ~= 0 then
				if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
					sayText=getText("IGUI_PlayerText_DoesntFeelRightToWrite"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
					o.willWrite = false
				end
				if o.willWrite and pSteamID then
					journalID["steamID"] = pSteamID
				end
			end
			if o.willWrite and pOnlineID then
				journalID["onlineID"] = pOnlineID
			end
		end

		if character:HasTrait("Illiterate") then
			local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}
			sayText=getText(sayTextChoices[ZombRand(#sayTextChoices)+1]).." ("..getText("UI_trait_Illiterate")..")"
			o.willWrite = false
		end

		if sayText then
			character:Say(sayText)
		end

		if o.willWrite then
			JMD["author"] = character:getFullName()
		end

		o.craftTimer = 0
		o.recipeIntervals = 0
		o.useProgressBar = false
		o.loopedAction = false
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