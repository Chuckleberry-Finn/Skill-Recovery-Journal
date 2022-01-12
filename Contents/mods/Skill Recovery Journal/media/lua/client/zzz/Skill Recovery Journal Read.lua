require "Skill Recovery Journal Main"


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
					local readTimeMulti = SandboxVars.Character.ReadTimeMulti or 1
					local perkLevel = player:getPerkLevel(Perks[skill])+1
					local perPerkXpRate = (math.floor(((xpRate^perkLevel)*(2*perkLevel))*1000)/1000) * readTimeMulti
					if perkLevel == 11 then
						perPerkXpRate=0
					end
					--print ("TESTING:  perPerkXpRate:"..perPerkXpRate.."  perkLevel:"..perkLevel.."  xpStored:"..xp.."  currentXP:"..currentXP)
					if currentXP+perPerkXpRate > xp then
						perPerkXpRate = (xp-(currentXP-0.01))
						--print(" --xp overflowed, capped at:"..perPerkXpRate)
					end

					if perPerkXpRate>0 then
						player:getXp():AddXP(Perks[skill], perPerkXpRate)
						gainedXp = true
						self:resetJobDelta()
					end
				end
			end

			if JMD and (not gainedXp) then
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