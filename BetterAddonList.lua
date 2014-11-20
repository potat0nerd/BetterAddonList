local ADDON_NAME = ...
BetterAddonListDB = BetterAddonListDB or {}

-- GLOBALS: BetterAddonListDB SLASH_BETTERADDONLIST1 SLASH_BETTERADDONLIST2 SlashCmdList SLASH_RELOADUI1 SLASH_RELOADUI2 UIDROPDOWNMENU_MENU_VALUE
-- GLOBALS: AddonList AddonList_Enable AddonList_SetSecurityIcon AddonList_SetStatus AddonCharacterDropDown AddonListScrollFrame AddonTooltip_BuildDeps GetAddOnEnableState
-- GLOBALS: StaticPopup_Show UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton UIDropDownMenu_GetSelectedValue UIDropDownMenu_SetSelectedValue UIDropDownMenu_SetText
-- GLOBALS: ADDON_BUTTON_HEIGHT ADDON_DEPENDENCIES MAX_ADDONS_DISPLAYED SearchBoxTemplate_OnTextChanged GameTooltip C_Timer FauxScrollFrame_Update

local AddonList_Update = AddonList_Update

local L = setmetatable({}, {
	__index = function(t, k)
		t[k] = k
		return k
	end,
})

local sets = nil
local nested = nil
local character = nil
local DEFAULT_SET = "__default__"

local function IsAddonProtected(index)
	if not index then return end
	local name, _, _, _, _, security = GetAddOnInfo(index)
	return name == ADDON_NAME or security == "SECURE" or BetterAddonListDB.protected[name]
end

local function SetAddonProtected(index, state)
	if not index then return end
	local name, _, _, _, _, security = GetAddOnInfo(index)
	if name ~= ADDON_NAME and security == "INSECURE" then
		BetterAddonListDB.protected[name] = state and true or nil
	end
end


local addon = CreateFrame("Frame")
addon:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_LOGOUT")

function addon:ADDON_LOADED(name)
	if name ~= ADDON_NAME then return end
	self:UnregisterEvent("ADDON_LOADED")

	if not BetterAddonListDB.sets then
		BetterAddonListDB.sets = {}
	end
	sets = BetterAddonListDB.sets

	if not BetterAddonListDB.nested then
		BetterAddonListDB.nested = {}
	end
	nested = BetterAddonListDB.nested

	if not BetterAddonListDB.protected then
		BetterAddonListDB.protected = {}
	end

	character = UnitName("player")

	hooksecurefunc("DisableAllAddOns", function()
		self:EnableProtected()
	end)
end

function addon:PLAYER_LOGIN()
	-- make the panel movable
	local mover = CreateFrame("Frame", "AddonListMover", AddonList)
	mover:EnableMouse(true)
	mover:SetPoint("TOP", AddonList, "TOP", 0, 0)
	mover:SetWidth(500)
	mover:SetHeight(25)
	mover:SetScript("OnMouseDown", function(self) AddonList:StartMoving() end)
	mover:SetScript("OnMouseUp", function(self) AddonList:StopMovingOrSizing() end)
	AddonList:SetMovable(true)
	AddonList:ClearAllPoints()
	AddonList:SetPoint("CENTER")

	--UIPanelWindows["AddonList"].area = nil -- let the frame overlap over ui frames

	-- default to showing the player profile
	UIDropDownMenu_SetSelectedValue(AddonCharacterDropDown, character)
	UIDropDownMenu_SetText(AddonCharacterDropDown, character) -- don't show "Custom" ... this dropdown is weird.

	-- save a list of enabled addons so that you can reset to it
	-- could use AddonList.startStatus, but this is easier.
	self:SaveSet(DEFAULT_SET)

	SLASH_BETTERADDONLIST1 = "/addons"
	SLASH_BETTERADDONLIST2 = "/acp" -- muscle memory ;[
	SlashCmdList["BETTERADDONLIST"] = function(input)
		if not input or input:trim() == "" then
			ShowUIPanel(AddonList)
			return
		end

		local command, rest = input:match("^(%S*)%s*(.-)$")
		command = command and command:lower()
		rest = (rest and rest ~= "") and rest:trim() or nil

		if command == "load" then
			if sets[rest] then
				self:LoadSet(rest)
				self:Print(L["Enabled only addons in set %q."]:format(rest))
			else
				self:Print(L["No set named %q."]:format(rest))
			end
		elseif command == "unload" then
			if sets[rest] then
				self:DisableSet(rest)
				self:Print(L["Disabled addons in set %q."]:format(rest))
			else
				self:Print(L["No set named %q."]:format(rest))
			end
		elseif command == "disableall" then
			DisableAllAddOns()
			_G.AddonList_Update()
			self:Print(L["Disabled all addons."])
		elseif command == "reset" then
			self:LoadSet(DEFAULT_SET)
			self:Print(L["Reset addons to what was enabled at login."])
		end
	end

	-- add some reload slashes, too
	SLASH_RELOADUI1 = "/reloadui"
	SLASH_RELOADUI2 = "/rl"
	SlashCmdList["RELOADUI"] = function()
		ReloadUI()
	end
end

function addon:PLAYER_LOGOUT()
	-- clean up
	sets[DEFAULT_SET] = nil
	if nested then
		for k,v in next, nested do
			if not next(v) then
				nested[k] = nil
			end
		end
	end
end

function addon:Print(...)
	print("|cff33ff99BetterAddonList|r:", tostringall(...))
end

StaticPopupDialogs["BETTER_ADDONLIST_SAVESET"] = {
	text = L["Save the currently selected addons to %s?"],
	button1 = YES,
	button2 = CANCEL,
	OnAccept = function(self) addon:SaveSet(self.data) end,
	OnShow = function(self) CloseDropDownMenus(1) end,
	OnHide = function(self) self.data = nil end,
	timeout = 0,
	hideOnEscape = 1,
	whileDead = 1,
	exclusive = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_DELETESET"] = {
	text = L["Delete set %s?"],
	button1 = YES,
	button2 = CANCEL,
	OnAccept = function(self) addon:DeleteSet(self.data) end,
	OnShow = function(self) CloseDropDownMenus(1) end,
	OnHide = function(self) self.data = nil end,
	timeout = 0,
	hideOnEscape = 1,
	whileDead = 1,
	exclusive = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_NEWSET"] = {
	text = L["Enter the name for the new set"],
	button1 = OKAY,
	button2 = CANCEL,
	OnAccept = function(self)
		local name = self.editBox:GetText()
		addon:NewSet(name)
	end,
	EditBoxOnEnterPressed = function(self)
		local name = self:GetParent().editBox:GetText()
		addon:NewSet(name)
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	OnShow = function(self)
		CloseDropDownMenus(1)
		self.editBox:SetFocus()
	end,
	OnHide = function(self)
		self.editBox:SetText("")
	end,
	timeout = 0,
	hideOnEscape = 1,
	exclusive = 1,
	whileDead = 1,
	hasEditBox = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_RENAMESET"] = {
	text = L["Enter the new name for %s"],
	button1 = OKAY,
	button2 = CANCEL,
	OnAccept = function(self)
		local text = self.editBox:GetText()
		addon:RenameSet(self.data, text)
	end,
	EditBoxOnEnterPressed = function(self)
		local dialog = self:GetParent()
		local text = dialog.editBox:GetText()
		addon:RenameSet(dialog.data, text)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	OnShow = function(self)
		CloseDropDownMenus(1)
		self.editBox:SetFocus()
	end,
	OnHide = function(self)
		self.editBox:SetText("")
		self.data = nil
	end,
	timeout = 0,
	hideOnEscape = 1,
	exclusive = 1,
	whileDead = 1,
	hasEditBox = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_ERROR_NAME"] = {
	text = L["There is already a set named \"%s\".\nPlease choose another name."],
	button1 = OKAY,
	button2 = CANCEL,
	OnAccept = function(self)
		local name, text = unpack(self.data)
		StaticPopup_Show(name, text)
	end,
	OnHide = function(self)
		self.data = nil
	end,
	timeout = 0,
	hideOnEscape = 1,
	whileDead = 1,
	exclusive = 1,
	showAlert = 1,
	preferredIndex = 3,
}

-- sets menu
do
	local CURRENT_SET = nil
	local list = {}

	local separator = {
		isTitle = true,
		notCheckable = 1,
		icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
		iconInfo = {
			tCoordLeft = 0,
			tCoordRight = 1,
			tCoordTop = 0,
			tCoordBottom = 1,
			tSizeX = 0,
			tFitDropDownSizeX = true,
			tSizeY = 8,
		},
		iconOnly = true,
	}

	-- pseudo natural sorting
	local function pad(s)
		return ("%04d"):format(tonumber(s))
	end
	local function cmp(a, b)
		return a:gsub("(%d+)", pad):lower() < b:gsub("(%d+)", pad):lower()
	end

	local function menu(self, level)
		if not level then return end

		local info = UIDropDownMenu_CreateInfo()
		info.notCheckable = 1

		if level == 1 then
			if next(sets) then
				wipe(list)
				for name in next, sets do
					if name ~= DEFAULT_SET then
						list[#list+1] = name
					end
				end
				sort(list, cmp)

				info.hasArrow = 1
				for _, name in ipairs(list) do
					info.text = name
					info.value = name
					UIDropDownMenu_AddButton(info, level)
				end

				UIDropDownMenu_AddButton(separator, level)
			end

			info = UIDropDownMenu_CreateInfo()
			info.notCheckable = 1

			info.text = L["Create new set"]
			info.func = function() StaticPopup_Show("BETTER_ADDONLIST_NEWSET") end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Reset"]
			info.func = function() addon:LoadSet(DEFAULT_SET) end
			UIDropDownMenu_AddButton(info, level)

		elseif level == 2 then
			CURRENT_SET = UIDROPDOWNMENU_MENU_VALUE

			info.text = CURRENT_SET
			info.isTitle = 1
			UIDropDownMenu_AddButton(info, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = L["View (%d)"]:format(#sets[CURRENT_SET])
			info.value = "view_set"
			info.func = nil
			info.hasArrow = 1
			info.notCheckable = 1
			info.disabled = #sets[CURRENT_SET] == 0 and 1 or nil
			UIDropDownMenu_AddButton(info, level)

			UIDropDownMenu_AddButton(separator, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = L["Load"]
			info.func = function()
				addon:LoadSet(CURRENT_SET)
				CloseDropDownMenus(1)
			end
			info.notCheckable = 1
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Save"]
			info.func = function() StaticPopup_Show("BETTER_ADDONLIST_SAVESET", CURRENT_SET, nil, CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Rename"]
			info.func = function() StaticPopup_Show("BETTER_ADDONLIST_RENAMESET", CURRENT_SET, nil, CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Delete"]
			info.func = function() StaticPopup_Show("BETTER_ADDONLIST_DELETESET", CURRENT_SET, nil, CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			--[[
			UIDropDownMenu_AddButton(separator, level)

			info.text = L["Include with another set"]
			info.value = "include_set"
			info.func = nil
			info.hasArrow = 1
			info.disabled = (#list < 3) and 1 or nil -- have more than the current set and default
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Remove an included set"]
			info.value = "remove_set"
			info.func = nil
			info.hasArrow = 1
			info.disabled = (not nested[CURRENT_SET] or not next(nested[CURRENT_SET])) and 1 or nil
			UIDropDownMenu_AddButton(info, level)
			--]]

			UIDropDownMenu_AddButton(separator, level)

			info = UIDropDownMenu_CreateInfo()
			info.notCheckable = 1
			info.disabled = #sets[CURRENT_SET] == 0 and 1 or nil

			info.text = L["Enable addons from this set"]
			info.func = function() addon:EnableSet(CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Disable addons from this set"]
			info.func = function() addon:DisableSet(CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)
		elseif level == 3 then
			if UIDROPDOWNMENU_MENU_VALUE == "view_set" then
				info.text = L["Addon List"]
				info.isTitle = 1
				UIDropDownMenu_AddButton(info, level)
				info.isTitle = nil

				for i, name in ipairs(sets[CURRENT_SET]) do
					if i > 30 then
						info.text = L["... and %d more"]:format(#sets[CURRENT_SET] - i)
						UIDropDownMenu_AddButton(info, level)
						break
					end
					info.text = name
					UIDropDownMenu_AddButton(info, level)
				end
			--[[
			elseif UIDROPDOWNMENU_MENU_VALUE == "include_set" then
				info.text = L["Include with another set"]
				info.isTitle = 1
				UIDropDownMenu_AddButton(info, level)
				info.isTitle = nil

				for i, name in ipairs(list) do
					if name ~= CURRENT_SET and name ~= DEFAULT_SET then
						info.text = name
						info.func = function() StaticPopup_Show("BETTER_ADDONLIST_INCLUDESET", CURRENT_SET, nil, {CURRENT_SET, name}) end
						info.disabled = (nested[CURRENT_SET] and nested[CURRENT_SET][name]) and 1 or nil
						UIDropDownMenu_AddButton(info, level)
					end
				end
			elseif UIDROPDOWNMENU_MENU_VALUE == "remove_set" then
				info.text = L["Remove an included set"]
				info.isTitle = 1
				UIDropDownMenu_AddButton(info, level)
				info.isTitle = nil

				if nested[CURRENT_SET] then
					for name in next, nested[CURRENT_SET] do
						info.text = name
						info.func = function() StaticPopup_Show("BETTER_ADDONLIST_REMOVESET", CURRENT_SET, nil, {CURRENT_SET, name}) end
						UIDropDownMenu_AddButton(info, level)
					end
				end
			--]]
			end
		end
	end

	local dropdown = CreateFrame("Frame", "BetterAddonListSetsDropDown", AddonList, "UIDropDownMenuTemplate")
	dropdown.initialize = menu
	dropdown.displayMode = "MENU"

	local button = CreateFrame("Button", "BetterAddonListSetsButton", AddonList, "UIPanelButtonTemplate")
	button:SetPoint("LEFT", AddonCharacterDropDownButton, "RIGHT", 3, 0)
	button:SetSize(80, 22)
	button:SetText(L["Sets"])
	button:SetScript("OnClick", function(self)
		ToggleDropDownMenu(1, nil, dropdown, self:GetName(), 0, 0)
	end)
end

-- lock icon toggle / memory usage
do
	local function OnClick(lock, button, down)
		if IsShiftKeyDown() and button == "LeftButton" then
			local index = lock:GetParent():GetID()
			SetAddonProtected(index, not IsAddonProtected(index))
			AddonList_Enable(index, true)
		end
	end

	local lockIcons = {}
	local memIcons = {}
	for i=1, MAX_ADDONS_DISPLAYED do
		local checkbox = _G["AddonListEntry"..i.."Enabled"]

		local lock = CreateFrame("Button", nil, _G["AddonListEntry"..i], nil, i)
		lock:SetSize(16, 16)
		lock:SetPoint("CENTER", checkbox, "CENTER")
		lock:SetNormalTexture([[Interface\Glues\CharacterSelect\Glues-AddOn-Icons]])
		lock:GetNormalTexture():SetTexCoord(0, 16/64, 0, 1) -- AddonList_SetSecurityIcon
		lock:SetScript("OnClick", OnClick)
		lock:Hide()
		lockIcons[i] = lock

		checkbox:HookScript("OnClick", function(self, ...) OnClick(lock, ...) end)

		local mem = CreateFrame("Button", nil, _G["AddonListEntry"..i], nil, i)
		mem:SetSize(6, 32)
		mem:SetPoint("RIGHT", checkbox, "LEFT", 1, 0)
		mem:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem0]])
		memIcons[i] = mem
	end

	local updater = CreateFrame("Frame", nil, AddonList)
	updater:SetScript("OnShow", function(self)
		UpdateAddOnMemoryUsage()
		if not self.timer then
			self.timer = C_Timer.NewTicker(10, UpdateAddOnMemoryUsage)
		end
	end)
	updater:SetScript("OnHide", function(self)
		self.timer:Cancel()
		self.timer = nil
	end)

	hooksecurefunc("AddonList_LoadAddOn", function(self)
		UpdateAddOnMemoryUsage()
		AddonList_Update()
	end)

	hooksecurefunc("AddonTooltip_Update", function(self)
		local memory = self.memory
		if memory then
			local text = ""
			if memory > 1000 then
				memory = memory / 1000
				text = ("Memory: %.02f MB"):format(memory)
			else
				text = ("Memory: %.0f KB"):format(memory)
			end
			GameTooltip:AddLine(text)
		end
	end)

	AddonTooltip_BuildDeps = function(...) -- replaced!
		if select("#", ...) == 0 then
			return ""
		end

		local deps = {...}
		for i, dep in ipairs(deps) do
			if GetAddOnEnableState(character, dep) == 0 then
				deps[i] = ("|cffff2020%s|r"):format(dep)
			end
		end
		return ADDON_DEPENDENCIES .. table.concat(deps, ", ")
	end

	local function checkDeps(...)
		for i = 1, select("#", ...) do
			local dep = select(i, ...)
			if GetAddOnEnableState(character, dep) == 0 then
				return false
			end
		end
		return true
	end

	-- Update the panel my way
	AddonList_Update = function()
		if AddonList.searchList then
			local numEntrys = #AddonList.searchList
			for i=1, MAX_ADDONS_DISPLAYED do
				local offset = AddonList.offset + i
				local addonIndex = AddonList.searchList[offset]
				local entry = _G["AddonListEntry"..i]
				if offset > numEntrys then
					entry:Hide()
				else
					-- aaaaand copy from AddonList_Update
					local name, title, notes, loadable, reason, security = GetAddOnInfo(addonIndex)
					local enabled = GetAddOnEnableState(character, addonIndex) > 0

					local checkbox = _G["AddonListEntry"..i.."Enabled"]
					checkbox:SetChecked(enabled)

					local titleString = _G["AddonListEntry"..i.."Title"]
					if loadable or ( enabled and (reason == "DEP_DEMAND_LOADED" or reason == "DEMAND_LOADED") ) then
						titleString:SetTextColor(1.0, 0.78, 0.0)
					elseif enabled and reason ~= "DEP_DISABLED" then
						titleString:SetTextColor(1.0, 0.1, 0.1)
					else
						titleString:SetTextColor(0.5, 0.5, 0.5)
					end
					titleString:SetText(title or name)

					local securityIcon = _G["AddonListEntry"..i.."SecurityIcon"]
					if security == "SECURE" then
						AddonList_SetSecurityIcon(securityIcon, 1)
					elseif security == "INSECURE" then
						AddonList_SetSecurityIcon(securityIcon, 2)
					elseif security == "BANNED" then
						AddonList_SetSecurityIcon(securityIcon, 3)
					end
					_G["AddonListEntry"..i.."Security"].tooltip = _G["ADDON_"..security]

					local statusString = _G["AddonListEntry"..i.."Status"]
					statusString:SetText((not enabled and reason) and _G["ADDON_"..reason] or "")

					if enabled ~= AddonList.startStatus[addonIndex] and reason ~= "DEP_DISABLED" then
						if enabled then
							local lod = IsAddOnLoadOnDemand(addonIndex) and not IsAddOnLoaded(addonIndex)
							AddonList_SetStatus(entry, lod, false, not lod)
						else
							AddonList_SetStatus(entry, false, false, true)
						end
					else
						AddonList_SetStatus(entry, false, true, false)
					end

					entry:SetID(addonIndex)
					entry:Show()
				end
			end

			FauxScrollFrame_Update(AddonListScrollFrame, numEntrys, MAX_ADDONS_DISPLAYED, ADDON_BUTTON_HEIGHT)
		end

		local numAddons = GetNumAddOns()
		for i=1, MAX_ADDONS_DISPLAYED do
			local entry = _G["AddonListEntry"..i]
			local checkbox = _G["AddonListEntry"..i.."Enabled"]
			local title = _G["AddonListEntry"..i.."Title"]
			local status = _G["AddonListEntry"..i.."Status"]

			local lockIcon = lockIcons[i]
			local memIcon = memIcons[i]

			local addonIndex = entry:GetID()
			if addonIndex > numAddons then
				entry.memory = nil
				memIcon:Hide()
				lockIcon:Hide()
				checkbox:Show()
			else
				local enabled = GetAddOnEnableState(character, addonIndex) > 0
				if enabled then
					local depsEnabled = checkDeps(GetAddOnDependencies(addonIndex))
					if not depsEnabled then
						title:SetTextColor(1.0, 0.1, 0.1)
						status:SetText(_G["ADDON_DEP_DISABLED"])
					end
					if IsAddOnLoadOnDemand(addonIndex) and not IsAddOnLoaded(addonIndex) and depsEnabled then
						AddonList_SetStatus(entry, true, false, false)
					end

					local memory = GetAddOnMemoryUsage(addonIndex)
					entry.memory = memory
					local usage = memory/8000 -- just needed some baseline!
					if usage > 0.8 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem5]])
					elseif usage > 0.6 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem4]])
					elseif usage > 0.4 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem3]])
					elseif usage > 0.2 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem2]])
					elseif usage > 0.1 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem1]])
					else
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem0]])
					end
					memIcon:Show()
				else
					entry.memory = nil
					memIcon:Hide()
				end

				local protected = IsAddonProtected(addonIndex)
				lockIcon:SetShown(protected)
				checkbox:SetShown(not protected)
			end
		end
	end
	hooksecurefunc("AddonList_Update", AddonList_Update)
end

-- search
do
	-- bleh, less code than creating my own check button
	AddonListForceLoad:ClearAllPoints()
	AddonListForceLoad:SetPoint("LEFT", BetterAddonListSetsButton, "RIGHT", 2, 0)
	local regions = {AddonListForceLoad:GetRegions()}
	if regions[1]:GetWidth() > 88 then -- don't truncate if we don't have to to >.<
		regions[1]:SetText(L["Load out of date"])
	end
	regions = nil

	local strfind = string.find
	local searchList = {}
	local searchString = ""
	local function OnTextChanged(self)
		SearchBoxTemplate_OnTextChanged(self)
		local oldText = searchString
		searchString = self:GetText():lower()

		if searchString == "" then
			AddonList.searchList = nil
			_G.AddonList_Update()
		elseif oldText ~= searchString then
			wipe(searchList)
			for i=1, GetNumAddOns() do
				local name, title, notes = GetAddOnInfo(i)
				local enabled = GetAddOnEnableState(character, i) > 0
				if strfind(name:lower(), searchString, nil, true) or (title and strfind(title:lower(), searchString, nil, true)) then
					searchList[#searchList+1] = i
				end
			end
			AddonList.searchList = searchList
			AddonList_Update()
		end
	end

	local editBox = CreateFrame("EditBox", "BetterAddonListSearchBox", AddonList, "SearchBoxTemplate")
	editBox:SetPoint("TOPRIGHT", -11, -33) -- -107 w/filter
	--editBox:SetPoint("TOPLEFT", AddonList, "TOPRIGHT", -126, -33) -- -222 w/filter
	editBox:SetSize(115, 20)
	editBox:SetMaxLetters(40)
	editBox:SetScript("OnTextChanged", OnTextChanged)

	--[==[
	local filterButton = CreateFrame("Button", "BetterAddonListFilterButton", AddonList, "UIMenuButtonStretchTemplate")
	filterButton:SetPoint("LEFT", editBox, "RIGHT", 3, 0)
	filterButton:SetSize(93, 22)
	filterButton:SetText(FILTER)
	filterButton:SetScript("OnClick", function(self)
		PlaySound("igMainMenuOptionCheckBoxOn")
		ToggleDropDownMenu(1, nil, self, self:GetName(), 74, 15)
	end)

	local arrow = filterButton:CreateTexture(nil, "ARTWORK")
	arrow:SetPoint("RIGHT", -5, 0)
	arrow:SetSize(10, 12)
	arrow:SetTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
	arrow:Show()
	filterButton.Icon = arrow

	filterButton:Hide()

	local function menu(self, level)
		local info = UIDropDownMenu_CreateInfo()
		info.keepShownOnClick = true

		-- filters?
		-- - enabled, loadable, lod
		-- - Addon meta flags
		if level == 1 then
			info.isNotRadio = true
			info.text = "Enabled"
			info.func = function(_, _, _, checked)
				--setFilterEnabled(checked)
				--AddonList_Update()
			end
			--info.checked = getFilterEnabled()
			UIDropDownMenu_AddButton(info, level)

			info.text = "Disabled"
			info.func = function(_, _, _, checked)
				--setFilterDisabled(checked)
				--AddonList_Update()
			end
			--info.checked = getFilterDisabled()
			UIDropDownMenu_AddButton(info, level)

			--[[
			info.checked = 	nil
			info.isNotRadio = nil
			info.func =  nil

			info.text = "Categories"
			info.value = 1
			info.hasArrow = true
			info.notCheckable = true
			UIDropDownMenu_AddButton(info, level)
		else
			if UIDROPDOWNMENU_MENU_VALUE == 1 then
				info.hasArrow = false
				info.isNotRadio = true
				info.notCheckable = true

				info.text = CHECK_ALL
				UIDropDownMenu_AddButton(info, level)

				info.text = UNCHECK_ALL
				UIDropDownMenu_AddButton(info, level)
			end
			--]]
		end
	end

	local filterDropDown = CreateFrame("Frame", "BetterAddonListFilterDropDown", AddonList, "UIDropDownMenuTemplate")
	filterDropDown.initialize = menu
	filterDropDown.displayMode = "MENU"
	--]==]
end

function addon:EnableProtected()
	EnableAddOn(ADDON_NAME, true)
	for name in next, BetterAddonListDB.protected do
		EnableAddOn(name, character)
	end
end

function addon:LoadSet(name)
	DisableAllAddOns()
	self:EnableSet(name)
end

function addon:EnableSet(name)
	local set = sets[name]
	if set and #set > 0 then
		for i=1, GetNumAddOns() do
			local name = GetAddOnInfo(i)
			if tContains(set, name) then
				EnableAddOn(name, character)
			end
		end
	end
	_G.AddonList_Update()
end

function addon:DisableSet(name)
	local set = sets[name]
	if set and #set > 0 then
		for i=1, GetNumAddOns() do
			local name = GetAddOnInfo(i)
			if not IsAddonProtected(name) and tContains(set, name) then
				DisableAddOn(name, character)
			end
		end
	end
	_G.AddonList_Update()
end


function addon:NewSet(name, overwrite) -- EmptySet
	if not name or name == "" then return end

	if sets[name] and not overwrite then
		StaticPopup_Show("BETTER_ADDONLIST_ERROR_NAME", name, nil, {"BETTER_ADDONLIST_NEWSET"})
		return
	end

	local set = sets[name]
	if not set then
		sets[name] = {}
		set = sets[name]
	end
	wipe(set)
end

do
	local function cmp(a, b) -- ignore color
		return a:gsub("(%|c%x%x%x%x%x%x%x%x|%|r)", "") < b:gsub("(%|c%x%x%x%x%x%x%x%x|%|r)", "") -- =~ s/(\|c[a-fA-F0-9]{8}|\|r)//g
	end

	function addon:SaveSet(name)
		if not name or name == "" then return end

		local set = sets[name]
		if not set then
			sets[name] = {}
			set = sets[name]
		end
		wipe(set)

		for i=1, GetNumAddOns() do
			local enabled = GetAddOnEnableState(character, i) > 0
			if enabled and not IsAddonProtected(i) then
				set[#set+1] = GetAddOnInfo(i)
			end
		end
		sort(set, cmp)
	end
end

function addon:RenameSet(name, newName)
	if not sets[name] then return end
	if sets[newName] then
		StaticPopup_Show("BETTER_ADDONLIST_ERROR_NAME", newName, nil, {"BETTER_ADDONLIST_RENAMESET", name, nil, name})
		return
	end

	sets[newName] = CopyTable(sets[name])
	sets[name] = nil
end

function addon:DeleteSet(name)
	if not sets[name] then return end

	sets[name] = nil
end
