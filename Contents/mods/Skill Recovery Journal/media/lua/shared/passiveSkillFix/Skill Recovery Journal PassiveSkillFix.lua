--TODO: REMOVE IN A MONTH OR TWO
--[[
---@param id number
---@param player IsoPlayer|IsoGameCharacter
function SRJ_setRecoverableLevels(id, player)
	local pMD = player:getModData()
	if not pMD.recoveryJournalPassiveSkillsInit then
		pMD.recoveryJournalPassiveSkillsInit = {}
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
						pMD.recoveryJournalPassiveSkillsInit[perkType] = currentLevel
					end
				end
			end
		end
	end
	--DEBUG for k,v in pairs(pMD.recoveryJournalPassiveSkillsInit) do print(" -- PASSIVE-INIT: "..k.." = "..v) end
end
Events.OnCreatePlayer.Add(SRJ_setRecoverableLevels)
--]]