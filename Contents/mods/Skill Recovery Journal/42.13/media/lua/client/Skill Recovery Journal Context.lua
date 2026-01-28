require "ISUI/ISInventoryPaneContextMenu"

local contextSRJ = {}


---@param context ISContextMenu
function contextSRJ.postContextMenu(playerID, context, items)
	local recipeName = getRecipeDisplayName("Transcribe Journal")
	local option = context:getOptionFromName(recipeName)
	if not option then return end
	local subOption = option.subOption and context:getSubMenu(option.subOption)
	if not subOption then return end
	local actualOption = subOption:getOptionFromName(getText("ContextMenu_One"))
	if not actualOption then return end
	option.onSelect = actualOption.onSelect
	option.target = actualOption.target
	option.param1 = actualOption.param1
	option.param2 = actualOption.param2
	option.param3 = actualOption.param3
	option.param4 = actualOption.param4
	option.param5 = actualOption.param5
	option.param6 = actualOption.param6
	option.param7 = actualOption.param7
	option.param8 = actualOption.param8
	option.param9 = actualOption.param9
	option.param10 = actualOption.param10
	option.subOption = nil
end


function contextSRJ.readItems(items, player)
	items = ISInventoryPane.getActualItems(items)
	for i,item in ipairs(items) do
		if item:getContainer() ~= nil then
			ISInventoryPaneContextMenu.transferIfNeeded(player, item)
		end
		ISTimedActionQueue.add(SkillRecoveryJournalAction:new(player, item, true))
		break
	end
end


function contextSRJ.writeItems(items, player, writingTool)
	items = ISInventoryPane.getActualItems(items)

	if writingTool:getContainer() ~= nil then ISInventoryPaneContextMenu.transferIfNeeded(player, writingTool) end

	for i,item in ipairs(items) do
		if item:getContainer() ~= nil then
			ISInventoryPaneContextMenu.transferIfNeeded(player, item)
		end
		ISTimedActionQueue.add(SkillRecoveryJournalAction:new(player, item, false, writingTool))
		break
	end
end


---@param context ISContextMenu
function contextSRJ.doContextMenu(playerID, context, items)

	local actualItems = ISInventoryPane.getActualItems(items)
	local player = getSpecificPlayer(playerID)

	for i,item in ipairs(actualItems) do

		if item:getType() == "SkillRecoveryBoundJournal" then

			local emptyBook, mismatchID = false, false
			if player and player.getSteamID then
				local journalModData = item:getModData()["SRJ"]
				local pSteamID = player:getSteamID()
				if (not journalModData) then
					emptyBook = true
				elseif pSteamID ~= 0 then
					journalModData["ID"] = journalModData["ID"] or {}
					local journalID = journalModData["ID"]
					if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then mismatchID = true end
				end
			end

			if emptyBook==false and mismatchID==false and player:getInventory():containsRecursive(item) then
				context:addOptionOnTop(getText("IGUI_Rename"), item, contextSRJ.onRenameJournal, player)
			end

			local asleep = player:isAsleep()
			local illiterate = player:hasTrait(CharacterTrait.ILLITERATE)
			local readOption = context:addOptionOnTop(getText("ContextMenu_Read"), actualItems, contextSRJ.readItems, player)

			if asleep or illiterate or emptyBook or mismatchID then
				readOption.notAvailable = true
				local tooltip = ISInventoryPaneContextMenu.addToolTip()
				tooltip.description = (asleep and getText("ContextMenu_NoOptionSleeping"))
						or (illiterate and getText("ContextMenu_Illiterate"))
						or (emptyBook and getText("IGUI_PlayerText_NothingWritten"))
						or (mismatchID and getText("IGUI_PlayerText_DoesntFeelRightToRead"))
				readOption.toolTip = tooltip
			end

			local inv = player:getInventory()
			local hasWritingTool = inv:getFirstTagRecurse(ItemTag.WRITE)

			local writeOption = context:addOptionOnTop(getText("IGUI_TranscribeIntoJournal"), actualItems, contextSRJ.writeItems, player, hasWritingTool)

			if asleep or illiterate or mismatchID or (not hasWritingTool) then
				writeOption.notAvailable = true
				local tooltip = ISInventoryPaneContextMenu.addToolTip()
				tooltip.description = (asleep and getText("ContextMenu_NoOptionSleeping"))
						or (illiterate and getText("IGUI_PlayerText_Illiterate2"))
						or (mismatchID and getText("IGUI_PlayerText_DoesntFeelRightToWrite"))
						or ((not hasWritingTool) and getText("Tooltip_Map_CantWrite"))
				writeOption.toolTip = tooltip
			end

			break
		end
	end
end


---@param player IsoGameCharacter|IsoPlayer
---@param journal InventoryItem|Literature
function contextSRJ.onRenameJournal(journal, player)
	-- once vanilla fixed it, this could maybe be used:
	--local modal = ISTextBox:new(0, 0, 280, 180, journal:getDisplayName()..":", journal:getName(), nil, ISInventoryPaneContextMenu.onRenameBagClick, player, getSpecificPlayer(player), journal);
	local modal = ISTextBox:new(0, 0, 280, 100, journal:getDisplayName()..":", journal:getName(), nil, contextSRJ.onRenameJournalClick, player:getPlayerNum(), player, journal)
	modal:initialise()
	modal:addToUIManager()
end


---@param item InventoryItem
function contextSRJ:onRenameJournalClick(button, player, item)
	if button.internal == "OK" and button.parent.entry:getText() and button.parent.entry:getText() ~= "" then
		local newName = button.parent.entry:getText()
		item:setName(newName)

		-- send changes to server
		sendClientCommand(player, "SkillRecoveryJournal", "rename", {itemID = item:getID(), name = newName})
	end
end

return contextSRJ