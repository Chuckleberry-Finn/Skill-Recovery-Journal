require "TimedActions/ISReadABook"

local crossRefMods = {
	["CatsWalkWhileReadMod"]="ReadFasterWhenSitting",
	["CatsReadMod"]="ReadFasterWhenSitting",
	["CatsReadMod(slower)"]="ReadFasterWhenSitting",
	["SnakeUtilsPack"]="tooltip",
	["nicocokoSpeedReading"]="TimedActions/NSRReadABook",
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

local SRJOVERWRITE_ISReadABook_update = ISReadABook.update
function ISReadABook:update()

	---@type Literature
	local journal = self.item

	if journal:getType() ~= "SkillRecoveryJournal" then
		SRJOVERWRITE_ISReadABook_update(self)
	else
		self:setCurrentTime(1)
		self.readTimer = self.readTimer + getGameTime():getMultiplier() or getGameTime():getMultiplier() or 0
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

			elseif pSteamID ~= 0 then
				JMD["ID"] = JMD["ID"] or {}
				local journalID = JMD["ID"]
				if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
					delayedStop = true
					sayText = getText("IGUI_PlayerText_DoesntFeelRightToRead")
				end
			end

			if not delayedStop then

				if (#self.listenedToMedia > 0) then
					self.changesMade = true
					local mediaChunk = math.min(#self.listenedToMedia, math.floor(1.09^math.sqrt(#self.listenedToMedia)))
					table.insert(changesBeingMade, "media")
					for i=0, mediaChunk do
						local line = self.listenedToMedia[#self.listenedToMedia]
						player:addKnownMediaLine(line)
						table.remove(self.listenedToMedia,#self.listenedToMedia)
					end
				end

				if (#self.learnedRecipes > 0) then
					self.recipeIntervals = self.recipeIntervals+1
					self.changesMade = true
					if self.recipeIntervals > 5 then
						local recipeChunk = math.min(#self.learnedRecipes, math.floor(1.09^math.sqrt(#self.learnedRecipes)))
						
						local properPlural = getText("IGUI_Tooltip_Recipe")
						if recipeChunk>1 then
							properPlural = getText("IGUI_Tooltip_Recipes")
						end
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
					if skill and skill~="NONE" or skill~="MAX" then
						if xp > greatestXp then
							greatestXp = xp
						end
					else
						XpStoredInJournal[skill] = nil
					end
				end

				local xpRate = math.sqrt(greatestXp)/25

				local pMD = player:getModData()
				pMD.recoveryJournalXpLog = pMD.recoveryJournalXpLog or {}
				local readXp = pMD.recoveryJournalXpLog

				journalModData.recoveryJournalXpLog = journalModData.recoveryJournalXpLog or {}
				local jmdUsedXP = journalModData.recoveryJournalXpLog
				local bJournalUsedUp = false

				for skill,xp in pairs(XpStoredInJournal) do

					if Perks[skill] then

						readXp[skill] = readXp[skill] or 0
						local currentXP = readXp[skill]
						local journalXP = xp

						if SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true and jmdUsedXP[skill] then
							if jmdUsedXP[skill] >= currentXP then
								bJournalUsedUp = true
							end
							currentXP = math.max(currentXP, jmdUsedXP[skill])
						end

						if currentXP < journalXP then
							local readTimeMulti = SandboxVars.SkillRecoveryJournal.ReadTimeSpeed or 1
							local perkLevelPlusOne = player:getPerkLevel(Perks[skill])+1
							local perPerkXpRate = ((xpRate*math.sqrt(perkLevelPlusOne))*1000)/1000 * readTimeMulti
							if perkLevelPlusOne == 11 then
								perPerkXpRate=false
							end
							--print ("TESTING:  perPerkXpRate:"..perPerkXpRate.."  perkLevel:"..perkLevel.."  xpStored:"..xp.."  currentXP:"..currentXP)

							if perPerkXpRate~=false then

								if currentXP+perPerkXpRate > journalXP then
									perPerkXpRate = math.max(journalXP-currentXP, 0.001)
								end

								readXp[skill] = readXp[skill]+perPerkXpRate
								jmdUsedXP[skill] = jmdUsedXP[skill] or 0
								jmdUsedXP[skill] = jmdUsedXP[skill]+perPerkXpRate

								player:getXp():AddXP(Perks[skill], perPerkXpRate, false, false, true)

								changesMade = true

								local skill_name = getText("IGUI_perks_"..skill)
								if skill_name == ("IGUI_perks_"..skill) then
									skill_name = skill
								end
								table.insert(changesBeingMade, skill_name)

								self:resetJobDelta()
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
			end
		end
	end
end


local SRJOVERWRITE_ISReadABook_new = ISReadABook.new
function ISReadABook:new(player, item, time)
	local o = SRJOVERWRITE_ISReadABook_new(self, player, item, time)

	if o and item:getType() == "SkillRecoveryJournal" then
		o.loopedAction = false
		o.useProgressBar = false
		o.maxTime = 55
		o.readTimer = 0

		o.stopOnWalk = false
		--o.gainedRecipes = SRJ.getGainedRecipes(player)
		o.learnedRecipes = {}
		o.listenedToMedia = {}
		o.recipeIntervals = 0
		
		local journalModData = item:getModData()
		local JMD = journalModData["SRJ"]
		if JMD then


			local listenedToMedia = JMD["listenedToMedia"]
			if listenedToMedia then
				for line,_ in pairs(listenedToMedia) do
					if not player:isKnownMediaLine(line) then
						table.insert(o.listenedToMedia, line)
					end
				end
			end


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
