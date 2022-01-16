require "Skill Recovery Journal Main"
require "ISUI/ISInventoryPaneContextMenu"


function SRJ.addRenameContext(player, context, items)
	for _, v in ipairs(items) do

		local item = v
		if not instanceof(v, "InventoryItem") then
			item = v.items[1]
		end

		if item:getType() == "SkillRecoveryJournal" then
			context:addOption(getText("Rename"), item, SRJ.onRenameJournal, player)
			break
		end
	end
end


function SRJ.onRenameJournal(journal, player)
	local modal = ISTextBox:new(0, 0, 280, 100, "Bound Journal:", journal:getName(), nil, SRJ.onRenameJournalClick, player, getSpecificPlayer(player), journal)
	modal:initialise()
	modal:addToUIManager()
end


function SRJ:onRenameJournalClick(button, player, item)
	if button.internal == "OK" and button.parent.entry:getText() and button.parent.entry:getText() ~= "" then
		item:setName(button.parent.entry:getText())
		local pdata = getPlayerData(player:getPlayerNum())
		pdata.playerInventory:refreshBackpacks()
		pdata.lootInventory:refreshBackpacks()
	end
end

Events.OnPreFillInventoryObjectContextMenu.Add(SRJ.addRenameContext)