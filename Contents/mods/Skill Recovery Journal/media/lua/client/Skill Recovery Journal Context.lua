require "ISUI/ISInventoryPaneContextMenu"

local contextSRJ = {}

function contextSRJ.addRenameContext(player, context, items)
	for _, v in ipairs(items) do

		local item = v
		if not instanceof(v, "InventoryItem") then
			item = v.items[1]
		end

		if item:getType() == "SkillRecoveryJournal" then

			local addOption = true
			if player and player.getSteamID then
				local journalModData = item:getModData()
				local JMD = journalModData["SRJ"]
				local pSteamID = player:getSteamID()
				if (not JMD) then
					addOption = false
				elseif player:HasTrait("Illiterate") then
					addOption = false
				elseif pSteamID ~= 0 then
					JMD["ID"] = JMD["ID"] or {}
					local journalID = JMD["ID"]
					if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
						addOption = false
					end
				end
			end

			if addOption==true then
				context:addOption(getText("IGUI_Rename"), item, contextSRJ.onRenameJournal, player)
				break
			end
		end
	end
end


---@param journal InventoryItem|Literature
function contextSRJ.onRenameJournal(journal, player)
	local modal = ISTextBox:new(0, 0, 280, 100, journal:getDisplayName()..":", journal:getName(), nil, contextSRJ.onRenameJournalClick, player, getSpecificPlayer(player), journal)
	modal:initialise()
	modal:addToUIManager()
end


---@param item InventoryItem
function contextSRJ:onRenameJournalClick(button, player, item)
	if button.internal == "OK" and button.parent.entry:getText() and button.parent.entry:getText() ~= "" then
		local journalModData = item:getModData()
		local JMD = journalModData["SRJ"]
		if JMD then JMD.usedRenameOption = true end
		
		item:setName(button.parent.entry:getText())
		local pdata = getPlayerData(player:getPlayerNum())
		if pdata then
			pdata.playerInventory:refreshBackpacks()
			pdata.lootInventory:refreshBackpacks()
		end
	end
end

Events.OnPreFillInventoryObjectContextMenu.Add(contextSRJ.addRenameContext)