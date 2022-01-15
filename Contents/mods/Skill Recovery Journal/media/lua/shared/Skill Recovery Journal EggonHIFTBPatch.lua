require "--EHIFTB_Init"
function EHITFB_PATCH()
	if EHIFTB and EHIFTB.Const and EHIFTB.Const.invalidItemTypes then
		EHIFTB.Const.invalidItemTypes["Base.SkillRecoveryJournal"] = true
	end
end
Events.OnGameBoot.Add(EHITFB_PATCH)