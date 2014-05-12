-----------------------------------------------------------------------------------------------------------------------
-- Handles XPS config panel
-- Copyright (c) NCsoft. All rights reserved
-- @author draftomatic
-----------------------------------------------------------------------------------------------------------------------

local glog
local LuaUtils

local XPSConfig = {}

local tDefaultOptions = {

	-- Readouts
	bReadouts = true,
	
	bElapsedCombatTime = true,
	
	bHPRegen = false,
	bShieldRegen = false,
	
	bDPSOut = false,
	 bAvgDPSOut = true,
	bMaxDPSOut = false,
	 bTotalDamageOut = true,
	
	bDPSIn = false,
	bAvgDPSIn = false,
	bMaxDPSIn = false,
	bTotalDamageIn = false,
	
	bHPSOut = false,
	 bAvgHPSOut = true,
	bMaxHPSOut = false,
	 bTotalHealingOut = true,
	
	bHPSIn = false,
	bAvgHPSIn = false,
	bMaxHPSIn = false,
	bTotalHealingIn = false,
	
	bSPSOut = false,
	bAvgSPSOut = false,
	bMaxSPSOut = false,
	bTotalShieldOut = false,
	
	bSPSIn = false,
	bAvgSPSIn = false,
	bMaxSPSIn = false,
	bTotalShieldIn = false,
	
	bETL = false,
	bExpPer30Min = false,
	bExpGained = false,
	
	-- Record
	bRecordData = true,
	
	nStoredFights = 5,
	
	bRecordDPSOut = true,
	bRecordDPSIn = true,
	bRecordHPSOut = true,
	bRecordHPSIn = true,
	bRecordSPSOut = true,
	bRecordSPSIn = true,
	
	bRecordPlayerDamageOut = true,
	bRecordPlayerDamageIn = true,
	bRecordPlayerHealingOut = true,
	bRecordPlayerHealingIn = true,
	bRecordPlayerShieldOut = true,
	bRecordPlayerShieldIn = true,
	
	bRecordAbilityDamageOut = true,
	bRecordAbilityDamageIn = true,
	bRecordAbilityHealingOut = true,
	bRecordAbilityHealingIn = true,
	bRecordAbilityShieldOut = true,
	bRecordAbilityShieldIn = true,
	
	bShowOutgoingPlotInCombat = true,
	bShowIncomingPlotInCombat = true,
	bShowAfterCombat = true,
	
	-- Thread Meter
	bThreatMeter = true
}

function XPSConfig:OnLoad()
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	LuaUtils = Apollo.GetPackage("Drafto:Lib:LuaUtils-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.FATAL,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	})
	glog:info("XPSConfig:OnLoad finished")
	glog:info(LuaUtils)
end

function XPSConfig:Init()
	glog:info("XPSConfig:Init")
	
	-- Set callback
	self.cbOnSave = cbOnSave
	self.tCBSelf = tCBSelf
	
	-- Containers
	self.xmlConfig = XmlDoc.CreateFromFile("XPSConfig.xml")
	glog:info("xmlConfig:")
	glog:info(self.xmlConfig)
	self.wndConfig = Apollo.LoadForm(self.xmlConfig, "XPSConfig", nil, self)
	self.wndConfig:Show(false)
	self.wndReadouts = self.wndConfig:FindChild("ReadoutsContainer")
	self.wndRecord = self.wndConfig:FindChild("RecordContainer")
	
	-- Global checkboxes
	self.wndShowReadouts = self.wndConfig:FindChild("XPSGlobalOpt_bReadouts")
	self.wndShowReadouts:SetCheck(true)
	self.wndRecordData = self.wndConfig:FindChild("XPSGlobalOpt_bRecordData")
	self.wndRecordData:SetCheck(true)
	self.wndThreatMeter = self.wndConfig:FindChild("XPSGlobalOpt_bThreatMeter")
	self.wndThreatMeter:SetCheck(true)
	
	-- Initialize options
	self.tOptions = {}
	self.tReadoutOptions = {}
	self:SetOptions(tDefaultOptions)
	--self:ParseOptions()
end

function XPSConfig:OnDependencyError(strDep, strError)
	glog:error(strDep .. " : " .. strError)
	return false
end

-- Get an option
function XPSConfig:GetOpt(strName)
	return self.tOptions[strName]
end

-- Get all options
function XPSConfig:GetOptions()
	return self.tOptions
end

-- Get readout options only
function XPSConfig:GetReadout(strName)
	return self.tReadoutOptions[strName]
end

-- Get readout options only
function XPSConfig:GetReadouts()
	return self.tReadoutOptions
end

-- Set an option manually
function XPSConfig:SetOpt(strName, value)
	self.tOptions[strName] = value
end

--- Show/Hide
function XPSConfig:Show(bShow)
	self.wndConfig:Show(bShow)
end

function XPSConfig:SetOptions(tOptions)
	self.tOptions = tOptions
	self.tReadoutOptions = {}
	
	-- Set globals
	self.wndShowReadouts:SetCheck(tOptions.bReadouts == true)
	self.wndRecordData:SetCheck(tOptions.bRecordData == true)
	self.wndThreatMeter:SetCheck(tOptions.bThreatMeter == true)
	
	-- Set readouts
	for i,wnd in ipairs(self.wndReadouts:GetChildren()) do 
		local strName = wnd:GetName()
		if string.find(strName, "XPSOpt_") then
			local key = strName:sub((strName:find("_")+1))				-- split on "_" returning second half
			wnd:SetCheck(tOptions[key] == true)
			self.tReadoutOptions[key] = tOptions[key] == true
		end
	end
	-- Set record data
	for i,wnd in ipairs(self.wndRecord:GetChildren()) do 
		local strName = wnd:GetName()
		if string.find(strName, "XPSOpt_") then
			local key = strName:sub((strName:find("_")+1))				-- split on "_" returning second half
			if LuaUtils:StartsWith(key, "b") then
				wnd:SetCheck(tOptions[key] == true)
			elseif LuaUtils:StartsWith(key, "n") then
				if tOptions[key] ~= nil then
					wnd:SetText(tostring(tOptions[key]))
				end
			end
		end
	end
	
	self:FireOnSaveCallback()
end

--- Reads all the options from the form
function XPSConfig:ParseOptions()
	glog:info("XPSConfig:ParseOptions")
	self.tOptions = {}
	self.tReadoutOptions = {}
	
	-- Globals
	self.tOptions.bReadouts = self.wndShowReadouts:IsChecked()
	self.tOptions.bRecordData = self.wndRecordData:IsChecked()
	self.tOptions.bThreatMeter = self.wndThreatMeter:IsChecked()
	
	-- Readouts
	for i,wnd in ipairs(self.wndReadouts:GetChildren()) do 
		local strName = wnd:GetName()
		if string.find(strName, "XPSOpt_") then
			local key = strName:sub((strName:find("_")+1))				-- split on "_" returning second half
			self.tOptions[key] = wnd:IsChecked()
			self.tReadoutOptions[key] = wnd:IsChecked()
		end
	end
	
	-- Record Data options
	for i,wnd in ipairs(self.wndRecord:GetChildren()) do 
		local strName = wnd:GetName()
		if string.find(strName, "XPSOpt_") then
			local key = strName:sub((strName:find("_")+1))				-- split on "_" returning second half
			if LuaUtils:StartsWith(key, "b") then
				self.tOptions[key] = wnd:IsChecked()
			elseif LuaUtils:StartsWith(key, "n") then
				self.tOptions[key] = tonumber(wnd:GetText())		-- Needs input validation, or change to combobox
			end
		end
	end
	
end	



-- 
-- Event Handlers
--
function XPSConfig:OnReadoutsUncheck(wndHandler, wndControl, eMouseButton)
	if wndHandler ~= wndControl then return end
	for i,wnd in ipairs(self.wndReadouts:GetChildren()) do 
		wnd:Enable(false)
	end
end

function XPSConfig:OnReadoutsCheck(wndHandler, wndControl, eMouseButton)
	if wndHandler ~= wndControl then return end
	for i,wnd in ipairs(self.wndReadouts:GetChildren()) do 
		wnd:Enable(true)
	end
end

function XPSConfig:OnRecordUncheck(wndHandler, wndControl, eMouseButton)
	if wndHandler ~= wndControl then return end
	for i,wnd in ipairs(self.wndRecord:GetChildren()) do 
		wnd:Enable(false)
	end
end

function XPSConfig:OnRecordCheck(wndHandler, wndControl, eMouseButton)
	if wndHandler ~= wndControl then return end
	for i,wnd in ipairs(self.wndRecord:GetChildren()) do 
		wnd:Enable(true)
	end
end

--- When a config option is clicked
function XPSConfig:OptionClick(wndHandler, wndControl, eMouseButton)
	-- Nothing for now
end

--- When the Save button is clicked
function XPSConfig:OnSave()
	glog:info("XPSConfig:OnSave")
	--glog:debug("tOptions:")
	--glog:debug(self.tOptions)
	--glog:debug("tReadoutOptions:")
	--glog:debug(self.tReadoutOptions)
	self:ParseOptions()
	self.wndConfig:Show(false) -- hide the window
	self:FireOnSaveCallback()
end

function XPSConfig:FireOnSaveCallback()
	--if self.cbOnSave ~= nil then
		Event_FireGenericEvent("XPSConfigOnSave", self.tOptions)
		--self.tCBSelf[self.cbOnSave](self.tCBSelf, self.tOptions)
	--end
end

--- When the Close button is clicked
function XPSConfig:OnClose()
	self.wndConfig:Show(false) -- hide the window
end

-- Register Library
Apollo.RegisterPackage(XPSConfig, "Drafto:XPS:Config", 1, {"Gemini:Logging-1.2", "Drafto:Lib:LuaUtils-1.2"})