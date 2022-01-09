require "ISUI/ISUIWriteJournal"
require "ISUI/ISInventoryPaneContextMenu"

function ISUIWriteJournal:initialise()
	ISCollapsableWindow.initialise(self)

	--    self.winwo = self:wrapInCollapsableWindow()
	--    self.winwo:addToUIManager()
	--    self.winwo.closeButton:setVisible(false)
	--    self.winwo:setX(self.x)
	--    self.winwo:setY(self.y)

	local btnWid = 100
	local btnHgt = 25
	local padBottom = 10

	self.yes = ISButton:new((self:getWidth() / 2) - btnWid - 5, self:getHeight() - padBottom - btnHgt, btnWid, btnHgt, getText("UI_Ok"), self, ISUIWriteJournal.onClick)
	self.yes.internal = "OK"
	self.yes:initialise()
	self.yes:instantiate()
	self.yes.borderColor = {r=1, g=1, b=1, a=0.1}
	self:addChild(self.yes)

	self.no = ISButton:new((self:getWidth() / 2) + 5, self:getHeight() - padBottom - btnHgt, btnWid, btnHgt, getText("UI_Cancel"), self, ISUIWriteJournal.onClick)
	self.no.internal = "CANCEL"
	self.no:initialise()
	self.no:instantiate()
	self.no.borderColor = {r=1, g=1, b=1, a=0.1}
	self:addChild(self.no)

	self.title = ISTextEntryBox:new(self.title, self:getWidth() / 2 - ((self:getWidth() - 20) / 2), 20, self:getWidth() - 20, 2 + self.fontHgt + 2)
	self.title:initialise()
	self.title:instantiate()
	self:addChild(self.title)
	if self.locked then
		self.title:setEditable(false)
	end

	local inset = 2
	local height = inset --+ self.lineNumber * self.fontHgt + inset

	if self.numberOfPages > 0 then
		height = inset + self.lineNumber * self.fontHgt + inset
	end

	self.entry = ISTextEntryBox:new(self.defaultEntryText, self:getWidth() / 2 - ((self:getWidth() - 20) / 2), 45, self:getWidth() - 20, height)
	self.entry:initialise()
	self.entry:instantiate()
	self.entry:setMultipleLine(true)
	self.entry.javaObject:setMaxLines(self.lineNumber)
	self:addChild(self.entry)
	if self.locked then
		self.entry:setEditable(false)
	end

	if self.numberOfPages <= 0 then
		self.entry:setVisible(false)
	end

	if not self.locked then
		self.deleteButton = ISButton:new(self.entry.x, 50 + height, 15, 13, "", self, ISUIWriteJournal.onClick)
		self.deleteButton.internal = "DELETEPAGE"
		self.deleteButton:initialise()
		self.deleteButton:instantiate()
		self.deleteButton.borderColor = {r=1, g=1, b=1, a=0.1}
		self.deleteButton:setImage(getTexture("media/ui/trashIcon.png"))
		self.deleteButton:setTooltip(getText("Tooltip_Journal_Erase"))
		if self.numberOfPages <= 0 then
			self.deleteButton:setVisible(false)
		end
		self:addChild(self.deleteButton)

		self.lockButton = ISButton:new(self.deleteButton.x + self.deleteButton.width + 3, self.deleteButton.y, 15, 13, "", self, ISUIWriteJournal.onClick)
		self.lockButton.internal = "LOCKBOOK"
		self.lockButton:initialise()
		self.lockButton:instantiate()
		self.lockButton.borderColor = {r=1, g=1, b=1, a=0.1}
		self.lockButton:setImage(getTexture("media/ui/lockOpen.png"))
		self.lockButton:setTooltip(getText("Tooltip_Journal_Lock"))
		self:addChild(self.lockButton)

		if self.notebook:getLockedBy() then
			self.lockButton.internal = "UNLOCKBOOK"
			self.lockButton:setImage(getTexture("media/ui/lock.png"))
			self.lockButton:setTooltip(getText("Tooltip_Journal_UnLock"))
			self.entry:setEditable(false)
			self.title:setEditable(false)
		end
	end

	if self.numberOfPages > 1 then
		self.pageLabel = ISLabel:new (self.entry.x + self.entry.width, 45 + height, 18, getText("IGUI_Pages") .. self.currentPage .. "/" .. self.numberOfPages, 1, 1, 1, 1, UIFont.Small, false)
		self.pageLabel:initialise()
		self.pageLabel:instantiate()
		self:addChild(self.pageLabel)

		self.nextPage = ISButton:new(self.width / 2 + 3, self.pageLabel.y + 3, 15, 15, ">", self, ISUIWriteJournal.onClick)
		self.nextPage.internal = "NEXTPAGE"
		self.nextPage:initialise()
		self.nextPage:instantiate()
		self.nextPage.borderColor = {r=1, g=1, b=1, a=0.1}
		self:addChild(self.nextPage)

		self.previousPage = ISButton:new(self.nextPage.x - 20, self.nextPage.y, 15, 15, "<", self, ISUIWriteJournal.onClick)
		self.previousPage.internal = "PREVIOUSPAGE"
		self.previousPage:initialise()
		self.previousPage:instantiate()
		self.previousPage.borderColor = {r=1, g=1, b=1, a=0.1}
		self.previousPage:setEnable(false)
		self:addChild(self.previousPage)
	end

end


ISInventoryPaneContextMenu.onWriteSomething = function(notebook, editable, player)
	local fontHgt = getTextManager():getFontFromEnum(UIFont.Small):getLineHeight()
	local height = 110

	if notebook:getNumberOfPages()>0 then
		height = height + (15 * fontHgt)
	end

	local modal = ISUIWriteJournal:new(0, 0, 280, height, nil, ISInventoryPaneContextMenu.onWriteSomethingClick, getSpecificPlayer(player), notebook, notebook:seePage(1), notebook:getName(), 15, editable, notebook:getPageToWrite())
	modal:initialise()
	modal:addToUIManager()
	if JoypadState.players[player+1] then
		setJoypadFocus(player, modal)
	end
end