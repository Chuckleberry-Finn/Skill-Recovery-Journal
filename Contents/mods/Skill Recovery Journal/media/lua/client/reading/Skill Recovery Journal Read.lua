require "TimedActions/ISReadABook"

local crossRefMods = {
	["CatsWalkWhileReadMod"]="ReadFasterWhenSitting",
	["CatsReadMod"]="ReadFasterWhenSitting",
	["CatsReadMod(slower)"]="ReadFasterWhenSitting",
	["SnakeUtilsPack"]="tooltip",
	["nicocokoSpeedReading"]="TimedActions/NSRReadABook",
	["CDDAReading"]="TimedActions/ISReadABook",
}
local loadedModIDs = {}
local activeModIDs = getActivatedMods()
for i=1, activeModIDs:size() do
	local modID = activeModIDs:get(i-1)
	if crossRefMods[modID] and not loadedModIDs[modID] then
		require (crossRefMods[modID])
		loadedModIDs[modID] = true
	end
end


local SRJ = require "Skill Recovery Journal Main"


local SRJOVERWRITE_ISReadABook_update = ISReadABook.update
function ISReadABook:update()

	---@type Literature
	local journal = self.item

	if journal:getType() ~= "SkillRecoveryJournal" then
		SRJOVERWRITE_ISReadABook_update(self)
	else
		self.readTimer = (self.readTimer or 0) + (getGameTime():getMultiplier() or 0)
		-- normalize update time via in game time. Adjust updateInterval as needed
		local updateInterval = 10
		if self.readTimer >= updateInterval then
			self.readTimer = 0
			
			---@type IsoGameCharacter | IsoPlayer | IsoMovingObject | IsoObject
			local player = self.character

			local journalModData = journal:getModData()
			local JMD = journalModData["SRJ"]
			local changesMade = false
			local changesBeingMade = {}
			local delayedStop = false
			local sayText
			local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}

			local pSteamID = player:getSteamID()

			if (not JMD) then
				delayedStop = true
				sayText = getText("IGUI_PlayerText_NothingWritten")

			elseif self.character:HasTrait("Illiterate") then
				delayedStop = true
				sayText = getText("IGUI_PlayerText_IGUI_PlayerText_Illiterate"..ZombRand(2)+1)-- 0,1 + 1

			elseif pSteamID ~= 0 then
				JMD["ID"] = JMD["ID"] or {}
				local journalID = JMD["ID"]
				if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
					delayedStop = true
					sayText = getText("IGUI_PlayerText_DoesntFeelRightToRead")
				end
			end

			if not delayedStop then

				if (#self.learnedRecipes > 0) then
					self.recipeIntervals = self.recipeIntervals+1
					self.changesMade = true
					if self.recipeIntervals > 5 then
						local recipeChunk = math.min(#self.learnedRecipes, math.floor(1.09^math.sqrt(#self.learnedRecipes)))
						
						local properPlural = getText("IGUI_Tooltip_Recipe")
						if recipeChunk>1 then properPlural = getText("IGUI_Tooltip_Recipes") end
						table.insert(changesBeingMade, recipeChunk.." "..properPlural)

						for i=0, recipeChunk do
							local recipeID = self.learnedRecipes[#self.learnedRecipes]
							if recipeID then player:learnRecipe(recipeID) end
							table.remove(self.learnedRecipes,#self.learnedRecipes)
						end
						self.recipeIntervals = 0
					end
				end

				local XpStoredInJournal = JMD["gainedXP"]
				local greatestXp = 0

				for skill,xp in pairs(XpStoredInJournal) do
					if skill=="NONE" or skill=="MAX" then
						XpStoredInJournal[skill] = nil
					else
						if xp > greatestXp then greatestXp = xp end
					end
				end

				local xpRate = math.sqrt(greatestXp)/25
				local readXP = SRJ.getReadXP(player)

				journalModData.recoveryJournalXpLog = journalModData.recoveryJournalXpLog or {}
				local jmdUsedXP = journalModData.recoveryJournalXpLog
				local bJournalUsedUp = false

				local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)

				for skill,xp in pairs(XpStoredInJournal) do
					if Perks[skill] then

						readXP[skill] = readXP[skill] or 0
						local currentlyReadXP = readXP[skill]
						local journalXP = xp

						if oneTimeUse and jmdUsedXP[skill] and jmdUsedXP[skill] then
							if jmdUsedXP[skill] >= currentlyReadXP then bJournalUsedUp = true end
							currentlyReadXP = math.max(currentlyReadXP, jmdUsedXP[skill])
						end

						if currentlyReadXP < journalXP then
							local readTimeMulti = SandboxVars.SkillRecoveryJournal.ReadTimeSpeed or 1
							local perkLevelPlusOne = player:getPerkLevel(Perks[skill])+1
							local perPerkXpRate = ((xpRate*math.sqrt(perkLevelPlusOne))*1000)/1000 * readTimeMulti
							if perkLevelPlusOne == 11 then
								perPerkXpRate=false
							end
							--print("TESTING:  perPerkXpRate:"..perPerkXpRate.."  perkLevel:"..perkLevel.."  xpStored:"..xp.."  currentXP:"..currentXP)

							if perPerkXpRate~=false then

								if currentlyReadXP+perPerkXpRate > journalXP then perPerkXpRate = math.max(journalXP-currentlyReadXP, 0.001) end

								readXP[skill] = readXP[skill]+perPerkXpRate
								jmdUsedXP[skill] = (jmdUsedXP[skill] or 0)+perPerkXpRate

								---- perksType, XP, passHook, applyXPBoosts, transmitMP)
								player:getXp():AddXP(Perks[skill], perPerkXpRate, false, false, true)
								--SRJ.recordXPGain(player, skill, perPerkXpRate, {})

								changesMade = true
								self:resetJobDelta()

								local skill_name = getText("IGUI_perks_"..skill)
								if skill_name == ("IGUI_perks_"..skill) then skill_name = skill end
								table.insert(changesBeingMade, skill_name)
							end
						end
					end
				end

				if JMD and (not changesMade) then
					delayedStop = true

					if bJournalUsedUp then
						sayText = getText("IGUI_JournalXPUsedUp")
					else
						sayTextChoices = {"IGUI_PlayerText_KnowSkill","IGUI_PlayerText_BookObsolete"}
						sayText = getText(sayTextChoices[ZombRand(#sayTextChoices)+1])
					end

				elseif changesMade then
					local changesBeingMadeText = ""
					for k,v in pairs(changesBeingMade) do
						changesBeingMadeText = changesBeingMadeText.." "..v
						if k~=#changesBeingMade then
							changesBeingMadeText = changesBeingMadeText..", "
						end
					end
					if #changesBeingMade>0 then
						changesBeingMadeText = getText("IGUI_Tooltip_Learning")..": "..changesBeingMadeText
					end

					HaloTextHelper:update()
					HaloTextHelper.addText(self.character, changesBeingMadeText, HaloTextHelper.getColorWhite())
				end
			end

			if delayedStop then
				if sayText and not self.spoke then
					self.spoke = true
					player:Say(sayText, 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
				end
				updateInterval = self.maxTime
				self:forceStop()
			end
		end
	end
end


local SRJOVERWRITE_ISReadABook_new = ISReadABook.new
function ISReadABook:new(player, item, time)
	local o = SRJOVERWRITE_ISReadABook_new(self, player, item, time)

	if o and player and item:getType() == "SkillRecoveryJournal" then
		o.loopedAction = true
		o.useProgressBar = false
		o.maxTime = 55
		o.readTimer = 0

		o.stopOnWalk = false
		o.learnedRecipes = {}
		o.recipeIntervals = 0

		local journalModData = item:getModData()
		local JMD = journalModData["SRJ"]
		if JMD then

			if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
				local learnedRecipes = JMD["learnedRecipes"]
				if learnedRecipes then
					for recipeID,_ in pairs(learnedRecipes) do
						if not player:isRecipeKnown(recipeID) then
							table.insert(o.learnedRecipes, recipeID)
						end
					end
				end
			end
		end
	end

	return o
end
