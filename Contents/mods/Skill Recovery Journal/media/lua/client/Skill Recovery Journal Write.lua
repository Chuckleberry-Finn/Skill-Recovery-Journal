require "TimedActions/ISCraftAction"

local SRJ = require "Skill Recovery Journal Main"
local modDataCapture = require "Skill Recovery Journal ModData"

local SRJOVERWRITE_ISCraftAction_perform = ISCraftAction.perform
function ISCraftAction:perform()
	SRJOVERWRITE_ISCraftAction_perform(self)
	if self.recipe and self.recipe:getOriginalname() == "Transcribe Journal" and self.item and self.item:getType() == "SkillRecoveryBoundJournal" then
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


local SRJOVERWRITE_ISCraftAction_update = ISCraftAction.update
function ISCraftAction:update()
	SRJOVERWRITE_ISCraftAction_update(self)

	if self.recipe and self.recipe:getOriginalname() == "Transcribe Journal" and self.item:getType() == "SkillRecoveryBoundJournal" then
		self.craftTimer = self.craftTimer + getGameTime():getMultiplier()
		self.haloTextDelay = self.haloTextDelay - getGameTime():getMultiplier();
		self.item:setJobDelta(0.0)
		local updateInterval = 10
		if self.craftTimer >= updateInterval then
			self.craftTimer = 0
			self.changesMade = false

			local changesBeingMade, changesBeingMadeIndex = {}, {}

			local journalModData = self.item:getModData()
			journalModData["SRJ"] = journalModData["SRJ"] or {}
			local JMD = journalModData["SRJ"]
			local journalID = JMD["ID"]

			local bOwner = true

			local pSteamID = self.character:getSteamID()
			if pSteamID ~= 0 then
				if journalID and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then bOwner = false end

				local pUsername = self.character:getUsername()
				if pUsername and journalID["username"] and (journalID["username"] ~= pUsername) then bOwner = false end
			end

			local transcribeTimeMulti = SandboxVars.SkillRecoveryJournal.TranscribeSpeed or 1

			if bOwner and (#self.gainedRecipes > 0) then
				self.recipeIntervals = self.recipeIntervals+1
				self.changesMade = true

				if self.recipeIntervals > 5 then
					local recipeChunk = math.min(#self.gainedRecipes, math.floor(1.09^math.sqrt(#self.gainedRecipes))) * transcribeTimeMulti

					local properPlural = getText("IGUI_Tooltip_Recipe")
					if recipeChunk>1 then
						properPlural = getText("IGUI_Tooltip_Recipes")
					end
					table.insert(changesBeingMade, recipeChunk.." "..properPlural)

					for i=0, recipeChunk do
						local recipeID = self.gainedRecipes[#self.gainedRecipes]
						JMD["learnedRecipes"][recipeID] = true
						table.remove(self.gainedRecipes,#self.gainedRecipes)
					end
					self.recipeIntervals = 0
				end
			end

			local storedJournalXP = JMD["gainedXP"]
			local readXp = SRJ.getReadXP(self.character)
			local totalRecoverableXP = 1
			local totalStoredXP = 1

			---background fix for old XP------------( 1/3 )---------
			local oldXp = journalModData.oldXP
			--------------------------------------------------------

			if bOwner and storedJournalXP and self.gainedSkills then
				for perkID,xp in pairs(self.gainedSkills) do
					if xp > 0 then
						totalRecoverableXP = totalRecoverableXP + xp

						storedJournalXP[perkID] = storedJournalXP[perkID] or 0
						if xp > storedJournalXP[perkID] then

							local perkLevelPlusOne = self.character:getPerkLevel(Perks[perkID])+1

							local differential = SRJ.getMaxXPDifferential(perkID)

							local xpRate = math.sqrt(xp)/25
							xpRate = round(((xpRate*math.sqrt(perkLevelPlusOne))*1000)/1000 * transcribeTimeMulti / differential, 2)

							if xpRate>0 then
								self.changesMade = true

								local skill_name = getTextOrNull("IGUI_perks_"..perkID) or perkID

								if not changesBeingMadeIndex[skill_name] then
									changesBeingMadeIndex[skill_name] = true
									table.insert(changesBeingMade, skill_name)
								end

								---background fix for old XP---------------------( 2/3 )--------------------------------
								if oldXp and oldXp[perkID] then
									oldXp[perkID] = oldXp[perkID]-xpRate
									if oldXp[perkID] <= 0 then oldXp[perkID] = nil end
									---The work is done...
								end
								----------------------------------------------------------------------------------------

								local resultingXp = math.min(xp, storedJournalXP[perkID]+xpRate)
								--print("TESTING: "..skill.." recoverable:"..xp.." gained:"..storedJournalXP[skill].." +"..xpRate)
								storedJournalXP[perkID] = resultingXp
								readXp[perkID] = math.max(resultingXp,(readXp[perkID] or 0))
							end
						end
					end
					totalStoredXP = totalStoredXP + (storedJournalXP[perkID] or 0)
				end
			end

			---background fix for old XP---------------( 3/3 )--------------
			if oldXp then
				local perksFound = false
				for k,v in pairs(oldXp) do if k then perksFound = true end end
				if not perksFound then journalModData.oldXP = nil end
			end
			----------------------------------------------------------------

			SRJ.correctSandBoxOptions("KillsTrack")
			local killsRecoveryPercentage = SandboxVars.SkillRecoveryJournal.KillsTrack or 0
			if JMD and killsRecoveryPercentage > 0 then

				local zKills = math.floor(self.character:getZombieKills() * (killsRecoveryPercentage/100) )
				local sKills = math.floor(self.character:getSurvivorKills() * (killsRecoveryPercentage/100) )

				JMD.kills = JMD.kills or {}
				readXp.kills = readXp.kills or {}

				local zombieKills = (JMD.kills.Zombie or 0)
				local survivorKills = (JMD.kills.Survivor or 0)

				local unaccountedZKills = (zKills > zombieKills) and zKills-zombieKills
				local unaccountedSKills = (sKills > survivorKills) and sKills-survivorKills

				if unaccountedZKills or unaccountedSKills then
					if unaccountedZKills then
						table.insert(changesBeingMade, getText("IGUI_char_Zombies_Killed"))
						JMD.kills.Zombie = (JMD.kills.Zombie or 0) + unaccountedZKills
						readXp.kills.Zombie = (readXp.kills.Zombie or 0) + unaccountedZKills
					end
					if unaccountedSKills then
						table.insert(changesBeingMade, getText("IGUI_char_Survivor_Killed"))
						JMD.kills.Survivor = (JMD.kills.Survivor or 0) + unaccountedSKills
						readXp.kills.Survivor = (readXp.kills.Survivor or 0) + unaccountedSKills
					end
					self.changesMade = true
				end
			end

			if not self.modDataStoredComplete then
				self.modDataStoredComplete = true
				local modDataStored = modDataCapture.copyDataToJournal(self.character, self.item)
				if modDataStored then
					for _,dataID in pairs(modDataStored) do
						table.insert(changesBeingMade, dataID)
					end
					self.changesMade = true
				end
			end

			-- show transcript progress as halo text, prevent overlapping addTexts
			if self.haloTextDelay <= 0 and #changesBeingMade > 0 then
				self.haloTextDelay = 100
				--print("In Book: " .. totalStoredXP - self.oldJournalTotalXP .. " - in char: " .. totalRecoverableXP - self.oldJournalTotalXP)
				local progressText = math.floor(((totalStoredXP - self.oldJournalTotalXP) / (totalRecoverableXP - self.oldJournalTotalXP)) * 100 + 0.5) .. "%" 
				local changesBeingMadeText = getText("IGUI_Tooltip_Transcribing") .. " (" .. progressText ..") :"
				for k,v in pairs(changesBeingMade) do changesBeingMadeText = changesBeingMadeText.." "..v..((k~=#changesBeingMade and ", ") or "") end
				HaloTextHelper.addText(self.character, changesBeingMadeText, HaloTextHelper.getColorWhite())
			end

			-- handle sound
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


local SRJOVERWRITE_ISCraftAction_new = ISCraftAction.new
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
		if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
			for _,recipeID in pairs(gainedRecipes) do
				if learnedRecipes[recipeID] ~= true then
					table.insert(o.gainedRecipes,recipeID)
				end
			end
		end


		o.gainedSkills = SRJ.calculateGainedSkills(character) or false
		o.oldJournalTotalXP = 0
		for perkID, xp in pairs(JMD["gainedXP"]) do
			o.oldJournalTotalXP = o.oldJournalTotalXP + xp
		end
		o.willWrite = true
		local sayText

		--print("gainedSkills: "..tostring(gainedSkills))

		if not o.gainedSkills and (#o.gainedRecipes <= 0) then
			sayText=getText("IGUI_PlayerText_DontHaveAnyXP"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
			o.willWrite = false
		else
			JMD["ID"] = JMD["ID"] or {}
			local journalID = JMD["ID"]
			local pSteamID = character:getSteamID()
			local pUsername = character:getUsername()
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

			if isClient() and pUsername and journalID["username"] and (journalID["username"] ~= pUsername) then
				sayText=getText("IGUI_PlayerText_DoesntFeelRightToWrite"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
				o.willWrite = false
			end

			if o.willWrite and pUsername and (not journalID["username"]) then
				journalID["username"] = pUsername
			end
		end

		if character:HasTrait("Illiterate") then
			local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}
			sayText=getText(sayTextChoices[ZombRand(#sayTextChoices)+1]).." ("..getText("UI_trait_Illiterate")..")"
			o.willWrite = false
		end

		if sayText then character:Say(sayText) end
		if o.willWrite then JMD["author"] = character:getFullName() end

		o.craftTimer = 0
		o.recipeIntervals = 0
		o.useProgressBar = false
		o.loopedAction = false
		o.stopOnWalk = false
		o.maxTime = 50
		o.haloTextDelay = 0
	end

	return o
end


---@param player IsoGameCharacter | IsoPlayer
function SkillRecoveryJournalOnCanPerformWritingJournal(recipe, player, item)

	if item and (item:getType() == "SkillRecoveryBoundJournal") then
		return true
	end
	return false
end