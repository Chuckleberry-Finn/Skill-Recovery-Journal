local SRJ = {}

local errorMagActive = getActivatedMods():contains("\\errorMagnifier")
if not errorMagActive then print("ERROR: ","errorMagnifier missing!") return end

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


function SRJ.showHaloProgressText(character, changesBeingMade, updateCount, maxUpdates, title)
	if isServer() then
		local args = {}
		args.changesBeingMade = changesBeingMade
		args.updateCount = updateCount
		args.maxUpdates = maxUpdates
		args.title = title
		sendServerCommand(character, "SkillRecoveryJournal", "write_changes", args)
	else
		local percentFinished = math.floor(updateCount / maxUpdates * 100 + 0.5)
		local progressText = "?%"
		if percentFinished >= 0 then
			progressText = math.floor(percentFinished) .. "%"
		else 
		 	if getDebug() then print("Interval " .. updateCount, " / " .. maxUpdates) end
		end

		local changesBeingMadeText = getText(title) .. " (" .. progressText .. ") : "
		for k,v in pairs(changesBeingMade) do 
			local seperator
			local newText
			if type(v) ~= "number" then
				newText = getText(v)
				seperator = (k ~= #changesBeingMade and ", ") or ""
			else
				newText = "+" .. tostring(v)
				seperator = " "
			end
			changesBeingMadeText = changesBeingMadeText .. newText .. seperator
		end
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