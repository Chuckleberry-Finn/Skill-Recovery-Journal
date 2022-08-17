require "Skill Recovery Journal Main"
require "ISUI/ISInventoryPaneContextMenu"


function SRJ.addRenameContext(player, context, items)
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

			if addOption then
				context:addOption(getText("IGUI_Rename"), item, SRJ.onRenameJournal, player)
				break
			end
		end
	end
end


---@param journal InventoryItem|Literature
function SRJ.onRenameJournal(journal, player)
	local modal = ISTextBox:new(0, 0, 280, 100, journal:getDisplayName()..":", journal:getName(), nil, SRJ.onRenameJournalClick, player, getSpecificPlayer(player), journal)
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