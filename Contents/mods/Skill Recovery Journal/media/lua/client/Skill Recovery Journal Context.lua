require "ISUI/ISInventoryPaneContextMenu"
require "Skill Recovery Journal Reading"

local contextSRJ = {}


function contextSRJ.readItems(items, player)
	items = ISInventoryPane.getActualItems(items)
	for i,item in ipairs(items) do
		if item:getContainer() ~= nil then
			ISInventoryPaneContextMenu.transferIfNeeded(player, item)
			ISTimedActionQueue.add(ReadSkillRecoveryJournal:new(player, item))
			break
		end
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

			if emptyBook==false and mismatchID==false then
				context:addOptionOnTop(getText("IGUI_Rename"), item, contextSRJ.onRenameJournal, player)
			end

			local asleep = player:isAsleep()
			local illiterate = player:getTraits():isIlliterate()

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

			break
		end
	end
end


---@param player IsoGameCharacter|IsoPlayer
---@param journal InventoryItem|Literature
function contextSRJ.onRenameJournal(journal, player)
	local modal = ISTextBox:new(0, 0, 280, 100, journal:getDisplayName()..":", journal:getName(), nil, contextSRJ.onRenameJournalClick, player:getPlayerNum(), player, journal)
	modal:initialise()
	modal:addToUIManager()
end


---@param item InventoryItem
function contextSRJ:onRenameJournalClick(button, player, item)
	if button.internal == "OK" and button.parent.entry:getText() and button.parent.entry:getText() ~= "" then
		local journalModData = item:getModData()
		local JMD = journalModData["SRJ"]
		if JMD then
			JMD.usedRenameOption = nil
			JMD.renamedJournal = true
		end
		
		item:setName(button.parent.entry:getText())
		local pdata = getPlayerData(player:getPlayerNum())
		if pdata then
			pdata.playerInventory:refreshBackpacks()
			pdata.lootInventory:refreshBackpacks()
		end
	end
end

return contextSRJ