local SRJ = {}

SRJ.xpPatched = false

SRJ.xpHandler = require "Skill Recovery Journal XP"
SRJ.modDataHandler = require "Skill Recovery Journal ModData"

Events.OnGameTimeLoaded.Add(function()
    SRJ.gameTime = GameTime.getInstance()
end)


---@param player IsoGameCharacter|IsoPlayer
function SRJ.checkFitnessCanAddXp(player)
	if player:getNutrition():canAddFitnessXp() then return end

	local fitness = player:getPerkLevel(Perks.Fitness)

	local under, extremeUnder = player:hasTrait(CharacterTrait.UNDERWEIGHT), (player:hasTrait(CharacterTrait.EMACIATED) or player:hasTrait(CharacterTrait.VERY_UNDERWEIGHT))
	local over, extremeOver = player:hasTrait(CharacterTrait.OVERWEIGHT), player:hasTrait(CharacterTrait.OBESE)

	local mildIssue = under or over
	local extremeIssue = extremeUnder or extremeOver

	local blockAddXp = false

	if ( fitness >= 9 and (extremeIssue or mildIssue) ) then
		blockAddXp = true

	elseif ( fitness < 6 ) then
		--blockAddXp = false

	elseif extremeIssue then
		blockAddXp = true
	end

	local message = ((under or extremeUnder) and "IGUI_PlayerText_NeedGainWeight") or ((over or extremeOver) and "IGUI_PlayerText_NeedLoseWeight")

	return blockAddXp, message
end


--TODO: Implement this
function SRJ.checkProteinLevelMulti(player)
	local multi = 1
	if player:getNutrition():getProteins() > 50 and player:getNutrition():getProteins() < 300 then multi = 1.5
	elseif player:getNutrition():getProteins() < -300 then multi = 0.7
	end
	return multi
end


function SRJ.bSkillValid(perk)
	local ID = perk and perk:isPassiv() and "Passive" or perk:getParent():getId()
	local specific = SandboxVars.SkillRecoveryJournal["Recover"..ID.."Skills"]
	--if getDebug() then print("bSkillValid check sandbox option 'SkillRecoveryJournal.Recover"..ID.."Skills' -> ".. tostring(specific)) end

	local default = SandboxVars.SkillRecoveryJournal.RecoveryPercentage or 100
	local recoverPercentage = ((specific==nil) or (specific==-1)) and default or specific

	return (not (recoverPercentage <= 0)), (recoverPercentage/100)
end


-- returns all gained skills as per config or false if no valid skill xp gained
function SRJ.calculateGainedSkill(player, perk, passiveSkillsInit, startingLevels, deductibleXP)

	if not passiveSkillsInit then
		passiveSkillsInit = SRJ.modDataHandler.getPassiveLevels(player)
	end

	if not startingLevels then
		startingLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	end

	if not deductibleXP then
		deductibleXP = SRJ.modDataHandler.getDeductedXP(player)
	end

	if perk and perk:getParent():getId()~="None" then
		local perkXP = player:getXp():getXP(perk)
		if perkXP > 0 then
			local perkID = perk:getId()
			--if getDebug() then print("perkXP: ",perkID," = ",perkXP) end

			---figure out how much XP was present at player start
			local passivePerkFixLevel = passiveSkillsInit and passiveSkillsInit[perkID]
			local passiveFixXP = passivePerkFixLevel and perk:getTotalXpForLevel(passivePerkFixLevel)
			--if getDebug() then print(" -passiveFixXP:",passiveFixXP,"  (",passivePerkFixLevel,")") end

			local startingPerkLevel = startingLevels[perkID]
			local startingPerkXP = startingPerkLevel and perk:getTotalXpForLevel(startingPerkLevel) or 0
			--if getDebug() then print(" -startingPerkXP:",startingPerkXP,  "(",startingPerkLevel,")") end

			local deductedXP = (SandboxVars.SkillRecoveryJournal.TranscribeTVXP==false) and deductibleXP[perkID] or 0
			--if getDebug() then print(" -deductedXP:",deductedXP) end

			local sandboxOptionRecover, recoveryPercentage = SRJ.bSkillValid(perk)

			local recoverableXP = sandboxOptionRecover and perkXP-(passiveFixXP or startingPerkXP)-deductedXP or 0
			--if getDebug() then print(" -recoverableXP-deductions: ",recoverableXP) end

			if recoverableXP > 0 then

				--local deductBonusXP = SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses ~= true
				--if deductBonusXP then
				recoverableXP = SRJ.xpHandler.unBoostXP(player,perk,recoverableXP)
				--if getDebug() then print(" recoverableXP-unboosted: ",recoverableXP) end
				--end
				local gainedXP = recoverableXP * recoveryPercentage
				--if getDebug() then print(" FINAL: ", gainedXP) end
				return gainedXP
			end
		end
	end

	return false
end


-- returns all gained skills as per config or nil if no valid skill xp gained
function SRJ.calculateAllGainedSkills(player)
	local gainedXP

	local passiveSkillsInit = SRJ.modDataHandler.getPassiveLevels(player)
	local startingLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(player)
	local deductibleXP = SRJ.modDataHandler.getDeductedXP(player)

	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perk
		local perk = Perks.fromIndex(i)
		local gained = SRJ.calculateGainedSkill(player, perk, passiveSkillsInit, startingLevels, deductibleXP)
		if gained then
			--if getDebug() then print("calculateAllGainedSkills gained " .. gained) end
			gainedXP = gainedXP or {}
			gainedXP[perk:getId()] = gained
		end
	end

	return gainedXP
end


function SRJ.getGainedRecipes(player, exclude)
	local gainedRecipes = {}

	-- get all recipes known by player
	---@type ArrayList
	local knownRecipes = player:getKnownRecipes()
	for i=0, knownRecipes:size()-1 do
		local recipeID = knownRecipes:get(i)
		gainedRecipes[recipeID] = true
		
		--if getDebug() then print("Adding known recipe " .. tostring(recipeID)) end
	end

	---@type SurvivorDesc
	local playerDesc = player:getDescriptor()

	-- remove freebies granted by profession
	local playerProfessionID = playerDesc:getCharacterProfession()
	local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(playerProfessionID)
	local profFreeRecipes = profDef:getGrantedRecipes() 
	for i=0, profFreeRecipes:size()-1 do
		local profRecipe = profFreeRecipes:get(i)
		gainedRecipes[profRecipe] = nil
		--if getDebug() then print("Removing gained prof recipe " .. tostring(profRecipe)) end
	end

	-- remove freebies granted by trait
	local playerTraits = player:getCharacterTraits()
	for i=0, playerTraits:getKnownTraits():size()-1 do
		local traitTrait = playerTraits:getKnownTraits():get(i)
		local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitTrait)
		local traitRecipes = traitDef:getGrantedRecipes()
		for ii=0, traitRecipes:size()-1 do
			local traitRecipe = traitRecipes:get(ii)
			gainedRecipes[traitRecipe] = nil
			--if getDebug() then print("Removing gained trait recipe " .. tostring(traitRecipe)) end
		end
	end

	--- return iterable list
	local returnedGainedRecipes = {}
	for recipeID,_ in pairs(gainedRecipes) do
		if not exclude or exclude[recipeID] ~= true then
			-- TODO: remove auto learned recipes from skills (maybe we had higher level/xpBoost last life)
			table.insert(returnedGainedRecipes, recipeID)
			--if getDebug() then print("Resulting gained recipe " .. tostring(recipeID) .. " -> " .. tostring(_)) end
		end
	end

	return returnedGainedRecipes
end


function SRJ.showHaloProgressText(character, changesBeingMade, totalStoredXP, totalRecoverableXP, oldJournalTotalXP, title)
	if isServer() then
		local args = {}
		args.changesBeingMade = changesBeingMade
		args.totalStoredXP = totalStoredXP
		args.totalRecoverableXP = totalRecoverableXP
		args.oldJournalTotalXP = oldJournalTotalXP
		args.title = title
		sendServerCommand(character, "SkillRecoveryJournal", "write_changes", args)
	else
		local progressText = math.floor(((totalStoredXP - oldJournalTotalXP) / (totalRecoverableXP - oldJournalTotalXP)) * 100 + 0.5) .. "%"
		--if getDebug() then print("In Book " .. totalStoredXP - oldJournalTotalXP, " - in char " .. totalRecoverableXP - oldJournalTotalXP .. " = " .. progressText) end

		local changesBeingMadeText = getText(title) .. " (" .. progressText ..") :"
		for k,v in pairs(changesBeingMade) do changesBeingMadeText = changesBeingMadeText.." "..v..((k~=#changesBeingMade and ", ") or "") end
		HaloTextHelper.addText(character, changesBeingMadeText, "", HaloTextHelper.getColorWhite())
	end
end


function SRJ.showCharacterFeedback(character, text)
	-- only visible when called on client
	if isServer() then
		local args = {}
		args.text = text
		sendServerCommand(character, "SkillRecoveryJournal", "character_say", args)
	else
		character:Say(getText(text), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
	end
end

return SRJ