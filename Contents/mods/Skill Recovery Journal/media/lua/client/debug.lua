if getDebug() then
	Events.OnCustomUIKey.Add(function(key)
		---@type IsoPlayer | IsoGameCharacter | IsoGameCharacter | IsoLivingCharacter | IsoMovingObject player
		local player = getSpecificPlayer(0)

		if key == Keyboard.KEY_1 then
			SRJ.calculateGainedSkills(player)
		end

	end)
end
