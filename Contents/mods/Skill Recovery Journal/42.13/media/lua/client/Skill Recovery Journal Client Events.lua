local SRJ = require "Skill Recovery Journal Main"
local contextSRJ = require "Skill Recovery Journal Context"
if contextSRJ then
    Events.OnPreFillInventoryObjectContextMenu.Add(contextSRJ.doContextMenu)
    Events.OnFillInventoryObjectContextMenu.Add(contextSRJ.postContextMenu)
end

function OnServerWriteCommand(module, command, args)
    -- server sends changes for client to show
    if module == "SkillRecoveryJournal" then
        if command == "write_changes" then 
            SRJ.showHaloProgressText(getPlayer(), args.changesBeingMade, args.totalStoredXP, args.totalRecoverableXP, args.oldJournalTotalXP, "IGUI_Tooltip_Transcribing")
        elseif command == "character_say" then
            SRJ.showCharacterFeedback(getPlayer(), args.text)
        end
    end
end

Events.OnServerCommand.Add(OnServerWriteCommand)