-----------------------------------------------------------------------------------------------
--- XPS
-- 
-- Copyright (c) NCsoft. All rights reserved
-- Author: draftomatic
-----------------------------------------------------------------------------------------------

local VERSION = "1.3.6"

require "Window"

local XPS = {} 

local LuaUtils
local Queue
local PixiePlot
local glog

local ePlotType = {
	ALL_XPS = 1,
	OUTGOING = 2,
	INCOMING = 3,
	DPS_OUT = 4,
	DPS_IN = 5,
	HPS_OUT = 6,
	HPS_IN = 7,
	SPS_OUT = 8,
	SPS_IN = 9,
	
	PLAYER_DAMAGE_OUT = 10,
	PLAYER_DAMAGE_IN = 11,
	PLAYER_HEALING_OUT = 12,
	PLAYER_HEALING_IN = 13,
	PLAYER_SHIELD_OUT = 14,
	PLAYER_SHIELD_IN = 15,
	
	ABILITY_DAMAGE_OUT = 16,
	ABILITY_DAMAGE_IN = 17,
	ABILITY_HEALING_OUT = 18,
	ABILITY_HEALING_IN = 19,
	ABILITY_SHIELD_OUT = 20,
	ABILITY_SHIELD_IN = 21,
	
	THREAT_METER = 22,
	
	GROUP_DAMAGE = 23,
}

local tReadoutLabels = {
	ElapsedCombatTime = "Elapsed Combat Time:",
	
	HPRegen = "Health Regen:",
	ShieldRegen = "Shield Regen:",
	
	DPSOut = "Outgoing DPS:",
	AvgDPSOut = "Avg Outgoing DPS:",
	MaxDPSOut = "Max Outgoing DPS:",
	TotalDamageOut = "Total Damage Dealt:",
	
	DPSIn = "Incoming DPS:",
	AvgDPSIn = "Avg Incoming DPS:",
	MaxDPSIn = "Max Incoming DPS:",
	TotalDamageIn = "Total Damage Taken:",
	
	HPSOut = "Outgoing HPS:",
	AvgHPSOut = "Avg Outgoing HPS:",
	MaxHPSOut = "Max Outgoing HPS:",
	TotalHealingOut = "Total Healing Done:",
	
	HPSIn = "Incoming HPS",
	AvgHPSIn = "Avg Incoming HPS:",
	MaxHPSIn = "Max Incoming HPS:",
	TotalHealingIn = "Total Healing Received:",
	
	SPSOut = "Outgoing SPS:",
	AvgSPSOut = "Avg Outgoing SPS:",
	MaxSPSOut = "Max Outgoing SPS:",
	TotalShieldOut = "Total Shield Given: ",
	
	SPSIn = "Incoming SPS:",
	AvgSPSIn = "Avg Incoming SPS:",
	MaxSPSIn = "Max Incoming SPS:",
	TotalShieldIn = "Total Shield Received: ",
	
	ExpPer30Min = "Experience per 30min:",
	ExpGained = "Experience Gained:",
	ETL = "Time to Level:"
}

-- Map for sorting readouts
local tReadoutPositions = {
	bElapsedCombatTime = 1,
	
	bHPRegen = 2,
	bShieldRegen = 3,
	
	bDPSOut = 4,
	bAvgDPSOut = 5,
	bMaxDPSOut = 6,
	bTotalDamageOut = 7,
	
	bDPSIn = 8,
	bAvgDPSIn = 9,
	bMaxDPSIn = 10,
	bTotalDamageIn = 11,
	
	bHPSOut = 12,
	bAvgHPSOut = 13,
	bMaxHPSOut = 14,
	bTotalHealingOut = 15,
	
	bHPSIn = 16,
	bAvgHPSIn = 17,
	bMaxHPSIn = 18,
	bTotalHealingIn = 19,
	
	bSPSOut = 20,
	bAvgSPSOut = 21,
	bMaxSPSOut = 22,
	bTotalShieldOut = 23,
	
	bSPSIn = 24,
	bAvgSPSIn = 25,
	bMaxSPSIn = 26,
	bTotalShieldIn = 27,
	
	bExpGained = 28,
	bExpPer30Min = 29,
	bETL = 30
}

-- Map for readout colors
--[[local tReadoutColors = {
	bElapsedCombatTime = "xkcdEggshellBlue,
	bHPRegen = "xkcdAcidGreen,
	bShieldRegen = 3,
	bDPSOut = 4,
	bAvgDPSOut = 5,
	bMaxDPSOut = 6,
	bTotalDamageOut = 7,
	bTotalDamageIn = 8,
	bHPSOut = 9,
	bAvgHPSOut = 10,
	bMaxHPSOut = 11,
	bTotalHealingOut = 12,
	bTotalHealingIn = 13,
	bExpGained = 14,
	bExpPer30Min = 15,
	bETL = 16
}--]]

function XPS:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end
function XPS:Init()
	Apollo.RegisterAddon(self, true, "XPS", {
		"Drafto:XPS:Config",
		"Gemini:Logging-1.2", 
		"Drafto:Lib:LuaUtils-1.2", 
		"Drafto:Lib:Queue-1.2", 
		"Drafto:Lib:PixiePlot-1.4"
	})
end
function XPS:OnLoad()
	--
	-- Libraries
	--
	self.config = Apollo.GetPackage("Drafto:XPS:Config").tPackage
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	LuaUtils = Apollo.GetPackage("Drafto:Lib:LuaUtils-1.2").tPackage
	Queue = Apollo.GetPackage("Drafto:Lib:Queue-1.2").tPackage		-- All time-based queues are push left, pop right. Right side is older.
	PixiePlot = Apollo.GetPackage("Drafto:Lib:PixiePlot-1.4").tPackage
	
	-- Get a logger
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.FATAL,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	})
	
	glog:info("XPS OnLoad")
	glog:info(self.config)
	
	--
	-- Variables and Data Structures
	--
	
	-- Readout value form elements
	self.tWndReadouts = nil
	
	-- Real-Time Averaging queue variables. Allows playing with sampling rate and averaging interval.
	self.maxQueueSize = 12			-- Number of intervals to average for instantaneous DPS. Multiply this by self.updateInterval to get averaging interval.
	self.updateInterval = 1/3		-- In seconds
	
	--  In combat flag
	self.bInCombat = false
	
	-- HP and Shield regen are simply computed from the change from previous update
	self.nHealthPrev = 0
	self.nShieldPrev = 0
	
	-- Counters for current fight
	self.nTotalDamageOut = 0				-- Total damage since addon started running
	self.nTotalDamageIn = 0					-- Total damage since addon started running
	self.nTotalHealingOut = 0				-- Total healing since addon started running
	self.nTotalHealingIn = 0				-- Total healing since addon started running
	self.nTotalShieldOut = 0				-- Total shield since addon started running
	self.nTotalShieldIn = 0					-- Total shield since addon started running
	
	self.nDamageOutCombatStart = 0			-- Total damage when combat started
	self.nDamageInCombatStart = 0			-- Total damage when combat started
	self.nHealingOutCombatStart = 0			-- Total healing when combat started
	self.nHealingInCombatStart = 0			-- Total healing when combat started
	self.nShieldOutCombatStart = 0			-- Total shield when combat started
	self.nShieldInCombatStart = 0			-- Total shield when combat started
	
	self.nExpCombatStart = 0				-- Total exp when combat started
	self.nExpCounter = 0					-- Counts experience gained and can be reset
	self.nTimeExpCounterStart = os.time()	-- Time that exp counter was reset
	
	-- Combat data queues
	self.nItemsInQueue = 0
	
	self.qCurCombatDamageOut = nil			-- Queue used for real-time DPS averaging
	self.qCombatDPSOut = Queue.new()		-- Holds nStoredFights of DPS time series
	self.qCurCombatDamageIn = nil			-- Queue used for real-time DPS averaging
	self.qCombatDPSIn = Queue.new()			-- Holds nStoredFights of DPS time series
	
	self.qCurCombatHealingOut = nil			-- Queue used for real-time HPS averaging
	self.qCombatHPSOut = Queue.new()		-- Holds nStoredFights of HPS time series
	self.qCurCombatHealingIn = nil			-- Queue used for real-time HPS averaging
	self.qCombatHPSIn = Queue.new()			-- Holds nStoredFights of HPS time series
	
	self.qCurCombatShieldOut = nil			-- Queue used for real-time SPS averaging
	self.qCombatSPSOut = Queue.new()		-- Holds nStoredFights of SPS time series
	self.qCurCombatShieldIn = nil			-- Queue used for real-time SPS averaging
	self.qCombatSPSIn = Queue.new()			-- Holds nStoredFights of SPS time series
	
	-- Standard combat stats. Always recorded.
	self.qCombatStats = Queue.new()			-- Holds nStoredFights of combat stats
	self.tCurCombatStats = nil
	
	-- Damage by player maps
	-- {name = damage}
	self.qCombatPlayerDamageOut = Queue.new()		-- Holds nStoredFights of player damage totals
	self.tCurPlayerDamageOut = nil
	self.qCombatPlayerDamageIn = Queue.new()		-- Holds nStoredFights of player damage totals
	self.tCurPlayerDamageIn = nil
	
	-- Healing by player maps
	-- {name = healing}
	self.qCombatPlayerHealingOut = Queue.new()		-- Holds nStoredFights of player Healing totals
	self.tCurPlayerHealingOut = nil
	self.qCombatPlayerHealingIn = Queue.new()		-- Holds nStoredFights of player Healing totals
	self.tCurPlayerHealingIn = nil
	
	-- Shield by player maps
	-- {name = shield}
	self.qCombatPlayerShieldOut = Queue.new()		-- Holds nStoredFights of player Shield totals
	self.tCurPlayerShieldOut = nil
	self.qCombatPlayerShieldIn = Queue.new()		-- Holds nStoredFights of player Shield totals
	self.tCurPlayerShieldIn = nil
	
	-- Damage by Ability maps
	-- {spellName = damage}
	self.qCombatAbilityDamageOut = Queue.new()		-- Holds nStoredFights of player damage totals
	self.tCurAbilityDamageOut = nil
	self.qCombatAbilityDamageIn = Queue.new()		-- Holds nStoredFights of player damage totals
	self.tCurAbilityDamageIn = nil
	
	-- Healing by Ability maps
	-- {spellName = healing}
	self.qCombatAbilityHealingOut = Queue.new()		-- Holds nStoredFights of player healing totals
	self.tCurAbilityHealingOut = nil
	self.qCombatAbilityHealingIn = Queue.new()		-- Holds nStoredFights of player healing totals
	self.tCurAbilityHealingIn = nil
	
	-- Shield by Ability maps
	-- {spellName = shield}
	self.qCombatAbilityShieldOut = Queue.new()		-- Holds nStoredFights of player shield totals
	self.tCurAbilityShieldOut = nil
	self.qCombatAbilityShieldIn = Queue.new()		-- Holds nStoredFights of player shield totals
	self.tCurAbilityShieldIn = nil
	
	-- Not used yet...
	self.tGroupDamage = {}
	self.tGroupHealing = {}
	
	--
	-- Forms
	--
	
	-- Readouts
	self.wndReadouts = Apollo.LoadForm("XPS.xml", "ReadoutsForm", nil, self)
	self.wndReadouts:Show(false)
	
	-- DPS HPS SPS Real-time Plots
	self.wndOutgoingPlot = Apollo.LoadForm("XPS.xml", "OutgoingPlotForm", nil, self)
	self.wndOutgoingPlot:Show(false)
	
	self.wndIncomingPlot = Apollo.LoadForm("XPS.xml", "IncomingPlotForm", nil, self)
	self.wndIncomingPlot:Show(false)
	
	-- Threat Meter
	self.wndThreatMeter = Apollo.LoadForm("XPS.xml", "ThreatMeterForm", nil, self)
	self.wndThreatMeter:Show(false)
	
	-- Combat History
	self.wndCombatHistory = Apollo.LoadForm("XPS.xml", "CombatHistoryForm", nil, self)
	self.wndCombatHistory:Show(false)
	
	-- Combat History Selectors
	self.wndFightSelector = self.wndCombatHistory:FindChild("FightSelector")
	self.wndPlotTypeSelector = self.wndCombatHistory:FindChild("PlotTypeSelector")
	self.wndPlotTypeSelector:AddItem("All Time Series", "", ePlotType.ALL_XPS)
	self.wndPlotTypeSelector:AddItem("All Outgoing", "", ePlotType.OUTGOING)
	self.wndPlotTypeSelector:AddItem("Outgoing DPS", "", ePlotType.DPS_OUT)
	self.wndPlotTypeSelector:AddItem("Outgoing HPS", "", ePlotType.HPS_OUT)
	self.wndPlotTypeSelector:AddItem("Outgoing SPS", "", ePlotType.SPS_OUT)
	self.wndPlotTypeSelector:AddItem("All Incoming", "", ePlotType.INCOMING)
	self.wndPlotTypeSelector:AddItem("Incoming DPS", "", ePlotType.DPS_IN)
	self.wndPlotTypeSelector:AddItem("Incoming HPS", "", ePlotType.HPS_IN)
	self.wndPlotTypeSelector:AddItem("Incoming SPS", "", ePlotType.SPS_IN)
	
	self.wndPlotTypeSelector:AddItem("Damage Dealt to Enemies", "", ePlotType.PLAYER_DAMAGE_OUT)
	self.wndPlotTypeSelector:AddItem("Damage Taken from Enemies", "", ePlotType.PLAYER_DAMAGE_IN)
	self.wndPlotTypeSelector:AddItem("Healing Done to Allies", "", ePlotType.PLAYER_HEALING_OUT)
	self.wndPlotTypeSelector:AddItem("Healing Received from Allies", "", ePlotType.PLAYER_HEALING_IN)
	self.wndPlotTypeSelector:AddItem("Shield Given to Allies", "", ePlotType.PLAYER_SHIELD_OUT)
	self.wndPlotTypeSelector:AddItem("Shield Received from Allies", "", ePlotType.PLAYER_SHIELD_IN)
	
	self.wndPlotTypeSelector:AddItem("Damage Dealt by Abilities", "", ePlotType.ABILITY_DAMAGE_OUT)
	self.wndPlotTypeSelector:AddItem("Damage Taken from Abilities", "", ePlotType.ABILITY_DAMAGE_IN)
	self.wndPlotTypeSelector:AddItem("Healing Done by Abilities", "", ePlotType.ABILITY_HEALING_OUT)
	self.wndPlotTypeSelector:AddItem("Healing Received from Abilities", "", ePlotType.ABILITY_HEALING_IN)
	self.wndPlotTypeSelector:AddItem("Shield Given by Abilities", "", ePlotType.ABILITY_SHIELD_OUT)
	self.wndPlotTypeSelector:AddItem("Shield Received from Abilities", "", ePlotType.ABILITY_SHIELD_IN)

	--self.wndPlotTypeSelector:AddItem("Group Damage", "", ePlotType.GROUP_DAMAGE)
	
	self.wndPlotTypeSelector:SelectItemByIndex(0)
	
	-- Combat History Stats
	self.wndTimeCombatStart = self.wndCombatHistory:FindChild("TimeCombatStart")
	self.wndElapsedTime = self.wndCombatHistory:FindChild("ElapsedTime")
	
	self.wndTotalHits = self.wndCombatHistory:FindChild("TotalHits")
	self.wndTotalEnemyHits = self.wndCombatHistory:FindChild("TotalEnemyHits")
	self.wndCriticalHits = self.wndCombatHistory:FindChild("CriticalHits")
	self.wndCriticalRatio = self.wndCombatHistory:FindChild("CriticalRatio")
	self.wndEnemyCriticalHits = self.wndCombatHistory:FindChild("EnemyCriticalHits")
	self.wndEnemyCriticalRatio = self.wndCombatHistory:FindChild("EnemyCriticalRatio")
	self.wndDeflects = self.wndCombatHistory:FindChild("Deflects")
	self.wndDeflectRatio = self.wndCombatHistory:FindChild("DeflectRatio")
	self.wndEnemyDeflects = self.wndCombatHistory:FindChild("EnemyDeflects")
	self.wndEnemyDeflectRatio = self.wndCombatHistory:FindChild("EnemyDeflectRatio")
	
	self.wndTotalDamageOut = self.wndCombatHistory:FindChild("TotalDamageOut")
	self.wndAvgDPSOut = self.wndCombatHistory:FindChild("AvgDPSOut")
	self.wndMaxDPSOut = self.wndCombatHistory:FindChild("MaxDPSOut")
	self.wndTotalDamageIn = self.wndCombatHistory:FindChild("TotalDamageIn")
	self.wndAvgDPSIn = self.wndCombatHistory:FindChild("AvgDPSIn")
	self.wndMaxDPSIn = self.wndCombatHistory:FindChild("MaxDPSIn")
	
	self.wndTotalHealingOut = self.wndCombatHistory:FindChild("TotalHealingOut")
	self.wndAvgHPSOut = self.wndCombatHistory:FindChild("AvgHPSOut")
	self.wndMaxHPSOut = self.wndCombatHistory:FindChild("MaxHPSOut")
	self.wndTotalHealingIn = self.wndCombatHistory:FindChild("TotalHealingIn")
	self.wndAvgHPSIn = self.wndCombatHistory:FindChild("AvgHPSIn")
	self.wndMaxHPSIn = self.wndCombatHistory:FindChild("MaxHPSIn")
	
	self.wndTotalShieldOut = self.wndCombatHistory:FindChild("TotalShieldOut")
	self.wndAvgSPSOut = self.wndCombatHistory:FindChild("AvgSPSOut")
	self.wndMaxSPSOut = self.wndCombatHistory:FindChild("MaxSPSOut")
	self.wndTotalShieldIn = self.wndCombatHistory:FindChild("TotalShieldIn")
	self.wndAvgSPSIn = self.wndCombatHistory:FindChild("AvgSPSIn")
	self.wndMaxSPSIn = self.wndCombatHistory:FindChild("MaxSPSIn")
	
	self.wndExpGained = self.wndCombatHistory:FindChild("ExpGained")
	self.wndExpToLevel = self.wndCombatHistory:FindChild("ExpToLevel")
	
	-- Plots
	self.plotOutgoing = nil
	self.plotIncoming = nil
	self.plotThreatMeter = nil
	self.plotNPCDamage = nil
	self.plotGroupDamage = nil
	
	-- Combat History Plot		
	local wndCombatHistoryPlot = self.wndCombatHistory:FindChild("Plot")
	self.plotCombatHistory = PixiePlot:New(wndCombatHistoryPlot)
	
	--[[
	-- Group Plot		
	self.wndGroupPlot = Apollo.LoadForm("XPS.xml", "GroupPlotForm", nil, self)
	self.wndGroupPlot:Show(false)
	local plotGroupContainer = self.wndGroupPlot:FindChild("PlotGroup")
	self.plotGroup = PixiePlot(plotGroupContainer)
	self.plotGroup:SetOption("ePlotStyle", PixiePlot.BAR)
	self.plotGroup:SetOption("eBarOrientation", PixiePlot.HORIZONTAL)
	self.plotGroup:SetOption("fBarMargin", 1)
	self.plotGroup:SetOption("fBarSpacing", 1)
	--self.plotGroup:SetOption("xAxisLabel", "Time")
	--self.plotGroup:SetOption("yAxisLabel", "Damage")
	self.plotGroup:SetOption("fLabelMargin", "0")
	self.plotGroup:SetOption("fPlotMargin", "0")
	self.plotGroup:SetOption("aPlotColors", {
		{a=1,r=0.29,g=0.90,b=0.39},
		{a=1,r=0.90,g=0.39,b=0.29}
	})
	--]]

	self:SetPlotOptionsByType(self.plotCombatHistory)
	
	-- Initialize Config
	Apollo.RegisterEventHandler("XPSConfigOnSave", "OnConfigSave", self)
	self.config:Init()
	
	-- Timers
	Apollo.CreateTimer("XPSTimer", self.updateInterval, true)
	Apollo.RegisterTimerHandler("XPSTimer", "Update", self)
	
	-- Event Handlers
	Apollo.RegisterEventHandler("DamageOrHealingDone", "OnDamageOrHealingDone", self)
	Apollo.RegisterEventHandler("UnitEnteredCombat", "OnUnitEnteredCombat", self)
	Apollo.RegisterEventHandler("TargetThreatListUpdated", "OnTargetThreatListUpdated", self)
	Apollo.RegisterEventHandler("ExperienceGained", "OnExperienceGained", self)
	Apollo.RegisterEventHandler("CombatLogDamage", "OnCombatLogDamage", self)
	Apollo.RegisterEventHandler("CombatLogHeal", "OnCombatLogHealing", self)
	Apollo.RegisterEventHandler("CombatLogDeflect", "OnCombatLogDeflect", self)
	
	-- Register slash command
	Apollo.RegisterSlashCommand("xps", "OnXPSOn", self)
	
	Apollo.SetConsoleVariable("cmbtlog.disableOtherPlayers", false)
	---[[
	Apollo.SetConsoleVariable("cmbtlog.disableAbsorption", false)
	Apollo.SetConsoleVariable("cmbtlog.disableCCState", false)
	Apollo.SetConsoleVariable("cmbtlog.disableDamage", false)
	Apollo.SetConsoleVariable("cmbtlog.disableDeflect", false)
	Apollo.SetConsoleVariable("cmbtlog.disableDelayDeath", false)
	Apollo.SetConsoleVariable("cmbtlog.disableDispel", false)
	Apollo.SetConsoleVariable("cmbtlog.disableFallingDamage", false)
	Apollo.SetConsoleVariable("cmbtlog.disableHeal", false)
	Apollo.SetConsoleVariable("cmbtlog.disableImmunity", false)
	Apollo.SetConsoleVariable("cmbtlog.disableInterrupted", false)
	Apollo.SetConsoleVariable("cmbtlog.disableModifyInterruptArmor", false)
	Apollo.SetConsoleVariable("cmbtlog.disableTransference", false)
	Apollo.SetConsoleVariable("cmbtlog.disableVitalModifier", false)
	Apollo.SetConsoleVariable("cmbtlog.disableDeath", false)--]]
	
	glog:info("XPS OnLoad finished")
end

function XPS:OnDependencyError(strDep, strError)
	return false
end

function XPS:CreateNewCombatStats()
	return {
		nTimeCombatStart = os.time(),
		nElapsedTime = 0,
		
		nHitCount = 0,
		nEnemyHitCount = 0,
		nCritCount = 0,
		nEnemyCritCount = 0,
		nDeflectCount = 0,
		nEnemyDeflectCount = 0,
	
		nTotalDamageOut = 0,
		nAvgDPSOut = 0,
		nMaxDPSOut = 0,
		nTotalDamageIn = 0,
		nAvgDPSIn = 0,
		nMaxDPSIn = 0,
		
		nTotalHealingOut = 0,
		nAvgHPSOut = 0,
		nMaxHPSOut = 0,
		nTotalHealingIn = 0,
		nAvgHPSIn = 0,
		nMaxHPSIn = 0,
		
		nTotalShieldOut = 0,
		nAvgSPSOut = 0,
		nMaxSPSOut = 0,
		nTotalShieldIn = 0,
		nAvgSPSIn = 0,
		nMaxSPSIn = 0,
		
		nExpGained = 0,
		nExpPerSecond = 0,
		nExpPer30Min = 0,
		nExpToLevel = 0
	}
end

function XPS.OnConfigSave(self, tOptions)
	glog:info("OnConfigSave callback")
	self.wndReadouts:Show(tOptions["bReadouts"])
	if tOptions["bReadouts"] then
		self:RebuildReadoutsForm()
	end
	self.wndThreatMeter:Show(tOptions["bThreatMeter"])
	self.wndOutgoingPlot:Show(false)
	self.wndIncomingPlot:Show(false)
end

function XPS:RebuildReadoutsForm()
	glog:info("RebuildReadoutsForm")
	
	local tTempReadouts = self.config:GetReadouts()
	
	-- Empty readout items
	self.wndReadouts:DestroyChildren()
	
	-- Clear old readout windows
	self.tWndReadouts = {}
	
	-- Sort readouts
	local tReadouts = {}
	for k,bReadout in pairs(tTempReadouts) do
		if bReadout == true then
			glog:debug(k .. " : " .. tostring(bReadout))
			tReadouts[tReadoutPositions[k]] = k
		end
	end
	glog:debug(tReadouts)
	
	-- Add a ReadoutLine for each readout option
	for i=1,LuaUtils:GetTableSize(tReadoutPositions) do
		local strReadout = tReadouts[i]
		if strReadout then
			glog:debug("Sorted readout: " .. strReadout)
			-- Load form
			local wndLine = Apollo.LoadForm("XPS.xml", "ReadoutLine", self.wndReadouts, self)
			
			-- Get value name
			local strName = string.sub(strReadout, 2)	-- Trick to convert option name to window name by removing the "b"
			wndLine:SetName(strName)
			glog:debug("Adding readout with name: " .. strName)
			
			-- Set readout label
			local strLabel = tReadoutLabels[strName]
			wndLine:FindChild("ReadoutLabel"):SetText(strLabel)
			
			-- Get readout value
			local wndValue = wndLine:FindChild("ReadoutValue")
			wndValue:SetText("0")
			
			-- Store readout value window
			self.tWndReadouts[strName] = wndValue
		end
	end
	glog:debug(self.tWndReadouts)
	
	-- Tidy readouts window
	self.wndReadouts:ArrangeChildrenVert()
	
	-- Doesn't work for content inside children
	--self.wndReadouts:SetHeightToContentHeight()
	
	-- Manually compute height
	local nHeight = 0
	for i,wndChild in ipairs(self.wndReadouts:GetChildren()) do
		nHeight = nHeight + wndChild:GetHeight()
	end
	local left, top, right, bottom = self.wndReadouts:GetAnchorOffsets()
	self.wndReadouts:SetAnchorOffsets(left, top, right, top + nHeight + 6)
end

function XPS:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.General then return nil end
	return {
		nVersion = VERSION,
		tAnchorOffsets = {
			wndReadouts = LuaUtils:Pack(self.wndReadouts:GetAnchorOffsets()),
			wndOutgoingPlot = LuaUtils:Pack(self.wndOutgoingPlot:GetAnchorOffsets()),
			wndIncomingPlot = LuaUtils:Pack(self.wndIncomingPlot:GetAnchorOffsets()),
			wndThreatMeter = LuaUtils:Pack(self.wndThreatMeter:GetAnchorOffsets()),
			wndCombatHistory = LuaUtils:Pack(self.wndCombatHistory:GetAnchorOffsets())
		},
		tOptions = self.config:GetOptions()
	}
end

function XPS:OnRestore(eLevel, tData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.General then return nil end
	if not tData then return end
	--glog:info(tData)
	---[[
	if tData.nVersion == VERSION then 
		if tData.tAnchorOffsets then
			for k,v in pairs(tData.tAnchorOffsets) do
				self[k]:SetAnchorOffsets(unpack(v)) 
			end
		end
		if tData.tOptions then
			self.config:SetOptions(tData.tOptions)
		end
	end
	--]]
end

--- Updates datasets and visible UI's
function XPS:Update(bFlushQueues)
	
	local unitPlayer = GameLib.GetPlayerUnit()
	if unitPlayer == nil then return end

	-- Experience
	if self.config:GetReadout("bExpGained") then
		self.tWndReadouts["ExpGained"]:SetText(LuaUtils:MarkupText(self.nExpCounter, "xkcdAmethyst", "CRB_InterfaceMedium"))
	end
	
	-- Elapsed time
	local nCurElapsedTime = os.time() - self.nTimeExpCounterStart

	-- Exp to level
	local nExpToLevel = GetXpToNextLevel() - (GetXp() - GetXpToCurrentLevel())
	
	-- Exp per 30min
	local nElapsedMinutes = nCurElapsedTime / 60
	local nElapsed30MinPeriods = nElapsedMinutes / 30
	if self.config:GetReadout("bExpPer30Min") then
		local nETL = self.nExpCounter / nElapsed30MinPeriods
		self.tWndReadouts["ExpPer30Min"]:SetText(LuaUtils:MarkupText(math.ceil(nETL), "xkcdAmethyst", "CRB_InterfaceMedium"))
	end
	
	-- Time to Level
	if self.config:GetReadout("bETL") then
		--self.tCurCombatStats.nExpPerSecond = self.nExpCounter / elapsedSeconds
		--self.tCurCombatStats.nExpPer30Min = self.nExpCounter / elapsed30MinPeriods
		local strText = "Never"
		if nCurElapsedTime > 0 and self.nExpCounter > 0 then
			local nExpPerSecond = self.nExpCounter / nCurElapsedTime
			local nSecondsToLevel = nExpToLevel / nExpPerSecond
			strText = LuaUtils:FormatTime(nSecondsToLevel)
		end
		self.tWndReadouts["ETL"]:SetText(LuaUtils:MarkupText(strText, "xkcdAmethyst", "CRB_InterfaceMedium"))
	end
	
	-- Basic stats for hp/shield regen
	local tBasicStats = unitPlayer:GetBasicStats()
	if tBasicStats == nil then return end
	
	-- Health Regen
	local nHealthCur = tBasicStats.health
	local nHealthMax = tBasicStats.maxHealth
	
	if self.config:GetOpt("bHPRegen") then
		local nHealthRegen = (nHealthCur - self.nHealthPrev) / self.updateInterval		-- Normalize to per second
		local wndHPRegen = self.tWndReadouts["HPRegen"]
		if nHealthRegen > 0 then
			local sHealthRegen = "+" .. math.ceil(nHealthRegen)
			wndHPRegen:SetText(LuaUtils:MarkupText(sHealthRegen, "xkcdAcidGreen", "CRB_InterfaceMedium"))
		elseif nHealthRegen < 0 then
			wndHPRegen:SetText(LuaUtils:MarkupText(math.ceil(nHealthRegen), "red", "CRB_InterfaceMedium"))
		else
			wndHPRegen:SetText(LuaUtils:MarkupText("0", "xkcdAcidGreen", "CRB_InterfaceMedium"))
		end
	end
	self.nHealthPrev = nHealthCur
	
	
	-- Shield Regen
	local nShieldCur = unitPlayer:GetShieldCapacity()
	local nShieldMax = unitPlayer:GetShieldCapacityMax()
	
	if self.config:GetOpt("bShieldRegen") then
		local nShieldRegen = (nShieldCur - self.nShieldPrev) / self.updateInterval		-- Normalize to per second
		local wndShieldRegen = self.tWndReadouts["ShieldRegen"]
		if nShieldRegen > 0 then
			local sShieldRegen = "+" .. math.ceil(nShieldRegen)
			wndShieldRegen:SetText(LuaUtils:MarkupText(sShieldRegen, "cyan", "CRB_InterfaceMedium"))
		elseif nShieldRegen < 0 then
			wndShieldRegen:SetText(LuaUtils:MarkupText(math.ceil(nShieldRegen), "red", "CRB_InterfaceMedium"))
		else
			wndShieldRegen:SetText(LuaUtils:MarkupText("0", "cyan", "CRB_InterfaceMedium"))
		end
	end
	self.nShieldPrev = nShieldCur

	
	-- Combat-Only stats
	if self.bInCombat then
	
		--
		-- Elapsed combat time
		--
		if self.config:GetReadout("bElapsedCombatTime") then
			local strTime = LuaUtils:FormatTime(os.time() - self.tCurCombatStats.nTimeCombatStart)
			self.tWndReadouts["ElapsedCombatTime"]:SetText(LuaUtils:MarkupText(strTime, "xkcdEggshellBlue", "CRB_InterfaceMedium"))
		end
		
		
		--
		-- Exp to Level
		--
		self.tCurCombatStats.nExpToLevel = nExpToLevel
		
		
		--
		-- Outgoing Damage
		--
		
		-- Real-time
		local nDPSOut = self:ComputeXPS(self.qCurCombatDamageOut)
		
		-- Real-time
		if self.config:GetReadout("bDPSOut") then
			self.tWndReadouts["DPSOut"]:SetText(LuaUtils:MarkupText(math.ceil(nDPSOut), "xkcdAmber", "CRB_InterfaceMedium"))
		end
		
		-- Average
		self.tCurCombatStats.nAvgDPSOut = math.ceil(self:ComputeCombatAverage(self.nTotalDamageOut - self.nDamageOutCombatStart))
		if self.config:GetReadout("bAvgDPSOut") then
			self.tWndReadouts["AvgDPSOut"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nAvgDPSOut, "xkcdAmber", "CRB_InterfaceMedium"))
		end
		
		-- Max
		if nDPSOut > self.tCurCombatStats.nMaxDPSOut then
			self.tCurCombatStats.nMaxDPSOut = nDPSOut
		end
		if self.config:GetReadout("bMaxDPSOut") then
			self.tWndReadouts["MaxDPSOut"]:SetText(LuaUtils:MarkupText(math.ceil(self.tCurCombatStats.nMaxDPSOut), "xkcdAmber", "CRB_InterfaceMedium"))
		end
		
		-- Total
		if self.config:GetReadout("bTotalDamageOut") then
			self.tWndReadouts["TotalDamageOut"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nTotalDamageOut, "xkcdAmber", "CRB_InterfaceMedium"))
		end
		
		-- Combat time series
		if self.config:GetOpt("bRecordDPSOut") then
			table.insert(self.qCombatDPSOut[self.qCombatDPSOut.first], nDPSOut)
		end
		
		
		--
		-- Incoming Damage
		--
		
		-- Real-time
		local nDPSIn = self:ComputeXPS(self.qCurCombatDamageIn)
		
		-- Real-time
		if self.config:GetReadout("bDPSIn") then
			self.tWndReadouts["DPSIn"]:SetText(LuaUtils:MarkupText(math.ceil(nDPSIn), "xkcdLipstick", "CRB_InterfaceMedium"))
		end
		
		-- Average
		self.tCurCombatStats.nAvgDPSIn = math.ceil(self:ComputeCombatAverage(self.nTotalDamageIn - self.nDamageInCombatStart))
		if self.config:GetReadout("bAvgDPSIn") then
			self.tWndReadouts["AvgDPSIn"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nAvgDPSIn, "xkcdLipstick", "CRB_InterfaceMedium"))
		end
		
		-- Max
		if nDPSIn > self.tCurCombatStats.nMaxDPSIn then
			self.tCurCombatStats.nMaxDPSIn = nDPSIn
		end
		if self.config:GetReadout("bMaxDPSIn") then
			self.tWndReadouts["MaxDPSIn"]:SetText(LuaUtils:MarkupText(math.ceil(self.tCurCombatStats.nMaxDPSIn), "xkcdLipstick", "CRB_InterfaceMedium"))
		end
		
		-- Total
		if self.config:GetReadout("bTotalDamageIn") then
			self.tWndReadouts["TotalDamageIn"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nTotalDamageIn, "xkcdLipstick", "CRB_InterfaceMedium"))
		end
		
		-- Combat time series
		if self.config:GetOpt("bRecordDPSIn") then
			table.insert(self.qCombatDPSIn[self.qCombatDPSIn.first], nDPSIn)
		end
		
		
		--
		-- Outgoing Healing
		--
		
		-- Compute from queue
		local nHPSOut = self:ComputeXPS(self.qCurCombatHealingOut)
		
		-- Real-time
		if self.config:GetReadout("bHPSOut") then
			self.tWndReadouts["HPSOut"]:SetText(LuaUtils:MarkupText(math.ceil(nHPSOut), "xkcdAcidGreen", "CRB_InterfaceMedium"))
		end
		
		-- Average
		self.tCurCombatStats.nAvgHPSOut = math.ceil(self:ComputeCombatAverage(self.nTotalHealingOut - self.nHealingOutCombatStart))
		if self.config:GetReadout("bAvgHPSOut") then
			self.tWndReadouts["AvgHPSOut"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nAvgHPSOut, "xkcdAcidGreen", "CRB_InterfaceMedium"))
		end
		
		-- Max
		if nHPSOut > self.tCurCombatStats.nMaxHPSOut then
			self.tCurCombatStats.nMaxHPSOut = nHPSOut
		end
		if self.config:GetReadout("bMaxHPSOut") then
			self.tWndReadouts["MaxHPSOut"]:SetText(LuaUtils:MarkupText(math.ceil(self.tCurCombatStats.nMaxHPSOut), "xkcdAcidGreen", "CRB_InterfaceMedium"))
		end
		
		-- Done
		if self.config:GetReadout("bTotalHealingOut") then
			self.tWndReadouts["TotalHealingOut"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nTotalHealingOut, "xkcdAcidGreen", "CRB_InterfaceMedium"))
		end
		
		-- Combat time series
		if self.config:GetOpt("bRecordHPSOut") then
			table.insert(self.qCombatHPSOut[self.qCombatHPSOut.first], nHPSOut)
		end
		
		
		--
		-- Incoming Healing
		--
		
		-- Compute from queue
		local nHPSIn = self:ComputeXPS(self.qCurCombatHealingIn)
		
		-- Real-time
		if self.config:GetReadout("bHPSIn") then
			self.tWndReadouts["HPSIn"]:SetText(LuaUtils:MarkupText(math.ceil(nHPSIn), "xkcdBrightYellow", "CRB_InterfaceMedium"))
		end
		
		-- Average
		self.tCurCombatStats.nAvgHPSIn = math.ceil(self:ComputeCombatAverage(self.nTotalHealingIn - self.nHealingInCombatStart))
		if self.config:GetReadout("bAvgHPSIn") then
			self.tWndReadouts["AvgHPSIn"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nAvgHPSIn, "xkcdBrightYellow", "CRB_InterfaceMedium"))
		end
		
		-- Max
		if nHPSIn > self.tCurCombatStats.nMaxHPSIn then
			self.tCurCombatStats.nMaxHPSIn = nHPSIn
		end
		if self.config:GetReadout("bMaxHPSIn") then
			self.tWndReadouts["MaxHPSIn"]:SetText(LuaUtils:MarkupText(math.ceil(self.tCurCombatStats.nMaxHPSIn), "xkcdBrightYellow", "CRB_InterfaceMedium"))
		end
		
		-- Done
		if self.config:GetReadout("bTotalHealingIn") then
			self.tWndReadouts["TotalHealingIn"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nTotalHealingIn, "xkcdBrightYellow", "CRB_InterfaceMedium"))
		end
		
		-- Combat time series
		if self.config:GetOpt("bRecordHPSIn") then
			table.insert(self.qCombatHPSIn[self.qCombatHPSIn.first], nHPSIn)
		end
		
		
		--
		-- Outgoing Shield
		--
		
		-- Compute from queue
		local nSPSOut = self:ComputeXPS(self.qCurCombatShieldOut)
		
		-- Real-time
		if self.config:GetReadout("bSPSOut") then
			self.tWndReadouts["SPSOut"]:SetText(LuaUtils:MarkupText(math.ceil(nSPSOut), "cyan", "CRB_InterfaceMedium"))
		end
		
		-- Average
		self.tCurCombatStats.nAvgSPSOut = math.ceil(self:ComputeCombatAverage(self.nTotalShieldOut - self.nShieldOutCombatStart))
		if self.config:GetReadout("bAvgSPSOut") then
			self.tWndReadouts["AvgSPSOut"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nAvgSPSOut, "cyan", "CRB_InterfaceMedium"))
		end
		
		-- Max
		if nSPSOut > self.tCurCombatStats.nMaxSPSOut then
			self.tCurCombatStats.nMaxSPSOut = nSPSOut
		end
		if self.config:GetReadout("bMaxSPSOut") then
			self.tWndReadouts["MaxSPSOut"]:SetText(LuaUtils:MarkupText(math.ceil(self.tCurCombatStats.nMaxSPSOut), "cyan", "CRB_InterfaceMedium"))
		end
		
		-- Done
		if self.config:GetReadout("bTotalShieldOut") then
			self.tWndReadouts["TotalShieldOut"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nTotalShieldOut, "cyan", "CRB_InterfaceMedium"))
		end
		
		-- Combat time series
		if self.config:GetOpt("bRecordSPSOut") then
			table.insert(self.qCombatSPSOut[self.qCombatSPSOut.first], nSPSOut)
		end
		
		
		--
		-- Incoming Shield
		--
		
		-- Compute from queue
		local nSPSIn = self:ComputeXPS(self.qCurCombatShieldIn)
		
		-- Real-time
		if self.config:GetReadout("bSPSIn") then
			self.tWndReadouts["SPSIn"]:SetText(LuaUtils:MarkupText(math.ceil(nSPSIn), "xkcdBrightBlue", "CRB_InterfaceMedium"))
		end
		
		-- Average
		self.tCurCombatStats.nAvgSPSIn = math.ceil(self:ComputeCombatAverage(self.nTotalShieldIn - self.nShieldInCombatStart))
		if self.config:GetReadout("bAvgSPSIn") then
			self.tWndReadouts["AvgSPSIn"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nAvgSPSIn, "xkcdBrightBlue", "CRB_InterfaceMedium"))
		end
		
		-- Max
		if nSPSIn > self.tCurCombatStats.nMaxSPSIn then
			self.tCurCombatStats.nMaxSPSIn = nSPSIn
		end
		if self.config:GetReadout("bMaxSPSIn") then
			self.tWndReadouts["MaxSPSIn"]:SetText(LuaUtils:MarkupText(math.ceil(self.tCurCombatStats.nMaxSPSIn), "xkcdBrightBlue", "CRB_InterfaceMedium"))
		end
		
		-- Done
		if self.config:GetReadout("bTotalShieldIn") then
			self.tWndReadouts["TotalShieldIn"]:SetText(LuaUtils:MarkupText(self.tCurCombatStats.nTotalShieldIn, "xkcdBrightBlue", "CRB_InterfaceMedium"))
		end
		
		-- Combat time series
		if self.config:GetOpt("bRecordSPSIn") then
			table.insert(self.qCombatSPSIn[self.qCombatSPSIn.first], nSPSIn)
		end
		
		
		--
		-- Real-Time Plots
		--
		
		-- Outgoing plot
		if 	self.config:GetOpt("bShowOutgoingPlotInCombat") and 
			(self.config:GetOpt("bRecordDPSOut") or self.config:GetOpt("bRecordHPSOut") or self.config:GetOpt("bRecordSPSOut")) then
			self:UpdateOutgoingPlot()
		end
		
		-- Incoming plot
		if 	self.config:GetOpt("bShowIncomingPlotInCombat") and 
			(self.config:GetOpt("bRecordDPSIn") or self.config:GetOpt("bRecordHPSIn") or self.config:GetOpt("bRecordSPSIn")) then
			self:UpdateIncomingPlot()
		end
		
		
		-- Update queues
		if bFlushQueues then
			-- Remove queue entries
			Queue.PopRight(self.qCurCombatDamageOut)
			Queue.PopRight(self.qCurCombatDamageIn)
			
			Queue.PopRight(self.qCurCombatHealingOut)
			Queue.PopRight(self.qCurCombatHealingIn)
			
			Queue.PopRight(self.qCurCombatShieldOut)
			Queue.PopRight(self.qCurCombatShieldIn)
			
			self.nItemsInQueue = self.nItemsInQueue - 1
		else
			-- Add queue entries for this interval
			Queue.PushLeft(self.qCurCombatDamageOut, 0)
			Queue.PushLeft(self.qCurCombatDamageIn, 0)
			
			Queue.PushLeft(self.qCurCombatHealingOut, 0)
			Queue.PushLeft(self.qCurCombatHealingIn, 0)
			
			Queue.PushLeft(self.qCurCombatShieldOut, 0)
			Queue.PushLeft(self.qCurCombatShieldIn, 0)
			
			-- Limit queue sizes
			if Queue.Size(self.qCurCombatDamageOut) >= self.maxQueueSize then
				Queue.PopRight(self.qCurCombatDamageOut)
			end
			if Queue.Size(self.qCurCombatDamageIn) >= self.maxQueueSize then
				Queue.PopRight(self.qCurCombatDamageIn)
			end
			
			if Queue.Size(self.qCurCombatHealingOut) >= self.maxQueueSize then
				Queue.PopRight(self.qCurCombatHealingOut)
			end
			if Queue.Size(self.qCurCombatHealingIn) >= self.maxQueueSize then
				Queue.PopRight(self.qCurCombatHealingIn)
			end
			
			if Queue.Size(self.qCurCombatShieldOut) >= self.maxQueueSize then
				Queue.PopRight(self.qCurCombatShieldOut)
			end
			if Queue.Size(self.qCurCombatShieldIn) >= self.maxQueueSize then
				Queue.PopRight(self.qCurCombatShieldIn)
			end
		end
	
	-- not in combat
	else	
	
		-- Clear real-time readouts
		if self.config:GetReadout("bDPSOut") then
			self.tWndReadouts["DPSOut"]:SetText(LuaUtils:MarkupText(0, "xkcdAmber", "CRB_InterfaceMedium"))
		end
		if self.config:GetReadout("bDPSIn") then
			self.tWndReadouts["DPSIn"]:SetText(LuaUtils:MarkupText(0, "xkcdLipstick", "CRB_InterfaceMedium"))
		end
		
		if self.config:GetReadout("bHPSOut") then
			self.tWndReadouts["HPSOut"]:SetText(LuaUtils:MarkupText(0, "xkcdAcidGreen", "CRB_InterfaceMedium"))
		end
		if self.config:GetReadout("bHPSIn") then
			self.tWndReadouts["HPSIn"]:SetText(LuaUtils:MarkupText(0, "xkcdBrightYellow", "CRB_InterfaceMedium"))
		end
		
		if self.config:GetReadout("bSPSOut") then
			self.tWndReadouts["SPSOut"]:SetText(LuaUtils:MarkupText(0, "cyan", "CRB_InterfaceMedium"))
		end
		if self.config:GetReadout("bSPSIn") then
			self.tWndReadouts["SPSIn"]:SetText(LuaUtils:MarkupText(0, "xkcdBrightBlue", "CRB_InterfaceMedium"))
		end
		
	end		-- bInCombat
end

--- Updates damage/healing values
function XPS:OnDamageOrHealingDone(unitCaster, unitTarget, eDamageType, nDamage, nShieldDamage, nAbsorptionAmount, bCritical, strSpellName)
	
	-- Fall damage doesn't have a caster; ignore those cases
	if unitCaster == nil then return end
	
	-- Force combat start (when will it end??)
	--if not self.bInCombat then
	--	self:ProcessEnteredCombat()
	--	self:ProcessEnteredCombat()
	--end
	
	---[[
	if unitCaster then
		glog:info("damage/healing given by: " .. unitCaster:GetName())
	end
	if unitTarget then
		glog:info("damage/healing received by: " .. unitTarget:GetName())
	end
	--]]
	
	-- Individual stats
	if self.bInCombat then
	
		-- Healing
		if eDamageType == GameLib.CodeEnumDamageType.Heal then
		
			-- Get healing value
			local nHealing = nDamage-- + nShieldDamage
			glog:debug("Healing: " .. nHealing)
			
			-- Outgoing 
			if unitCaster == GameLib.GetPlayerUnit() then
				
				if not unitTarget then return end
				
				-- Update totals
				self.nTotalHealingOut = self.nTotalHealingOut + nHealing
				self.tCurCombatStats.nTotalHealingOut = self.tCurCombatStats.nTotalHealingOut + nHealing
				
				-- Add value to current interval total
				self.qCurCombatHealingOut[self.qCurCombatHealingOut.first] = self.qCurCombatHealingOut[self.qCurCombatHealingOut.first] + nHealing
				
				-- Outgoing Ability Healing
				if strSpellName and self.config:GetOpt("bRecordAbilityHealingOut") then
					local nAbilityHealing = self.tCurAbilityHealingOut[strSpellName]
					if nAbilityHealing == nil then
						self.tCurAbilityHealingOut[strSpellName] = nHealing
					else
						self.tCurAbilityHealingOut[strSpellName] = nAbilityHealing + nHealing
					end
				end
				
				-- Outgoing Player Healing
				if self.config:GetOpt("bRecordPlayerHealingOut") then
					local strTargetName = unitTarget:GetName()
					local nTargetHealing = self.tCurPlayerHealingOut[strTargetName]
					if nTargetHealing == nil then
						self.tCurPlayerHealingOut[strTargetName] = nHealing
					else
						self.tCurPlayerHealingOut[strTargetName] = nTargetHealing + nHealing
					end
				end
				
			-- Incoming
			elseif unitTarget == GameLib.GetPlayerUnit() then
			
				if not unitCaster then return end
				
				-- Update totals
				self.nTotalHealingIn = self.nTotalHealingIn + nHealing
				self.tCurCombatStats.nTotalHealingIn = self.tCurCombatStats.nTotalHealingIn + nHealing
				
				-- Add value to current interval total
				self.qCurCombatHealingIn[self.qCurCombatHealingIn.first] = self.qCurCombatHealingIn[self.qCurCombatHealingIn.first] + nHealing
				
				-- Incoming Ability Healing
				if strSpellName and self.config:GetOpt("bRecordAbilityHealingIn") then
					local nAbilityHealing = self.tCurAbilityHealingIn[strSpellName]
					if nAbilityHealing == nil then
						self.tCurAbilityHealingIn[strSpellName] = nHealing
					else
						self.tCurAbilityHealingIn[strSpellName] = nAbilityHealing + nHealing
					end
				end
				
				-- Incoming Player Healing
				if self.config:GetOpt("bRecordPlayerHealingIn") then
					local strCasterName = unitCaster:GetName()
					local nCasterHealing = self.tCurPlayerHealingIn[strCasterName]
					if nCasterHealing == nil then
						self.tCurPlayerHealingIn[strCasterName] = nHealing
					else
						self.tCurPlayerHealingIn[strCasterName] = nCasterHealing + nHealing
					end
				end
				
			end
		
		
		-- Shield
		elseif eDamageType == GameLib.CodeEnumDamageType.HealShields then
		
			-- Get shield value
			local nShield = nDamage
			glog:debug("Shield: " .. nShield)
			
			-- Outgoing 
			if unitCaster == GameLib.GetPlayerUnit() then
				
				if not unitTarget then return end
				
				-- Update totals
				self.nTotalShieldOut = self.nTotalShieldOut + nShield
				self.tCurCombatStats.nTotalShieldOut = self.tCurCombatStats.nTotalShieldOut + nShield
				
				-- Add value to current interval total
				self.qCurCombatShieldOut[self.qCurCombatShieldOut.first] = self.qCurCombatShieldOut[self.qCurCombatShieldOut.first] + nShield
				
				-- Outgoing Ability Shield
				if strSpellName and self.config:GetOpt("bRecordAbilityShieldOut") then
					local nAbilityShield = self.tCurAbilityShieldOut[strSpellName]
					if nAbilityShield == nil then
						self.tCurAbilityShieldOut[strSpellName] = nShield
					else
						self.tCurAbilityShieldOut[strSpellName] = nAbilityShield + nShield
					end
				end
				
				-- Outgoing Player Shield
				if self.config:GetOpt("bRecordPlayerShieldOut") then
					local strTargetName = unitTarget:GetName()
					local nTargetShield = self.tCurPlayerShieldOut[strTargetName]
					if nTargetShield == nil then
						self.tCurPlayerShieldOut[strTargetName] = nShield
					else
						self.tCurPlayerShieldOut[strTargetName] = nTargetShield + nShield
					end
				end
				
			-- Incoming
			elseif unitTarget == GameLib.GetPlayerUnit() then
			
				if not unitCaster then return end
				
				-- Update totals
				self.nTotalShieldIn = self.nTotalShieldIn + nShield
				self.tCurCombatStats.nTotalShieldIn = self.tCurCombatStats.nTotalShieldIn + nShield
				
				-- Add value to current interval total
				self.qCurCombatShieldIn[self.qCurCombatShieldIn.first] = self.qCurCombatShieldIn[self.qCurCombatShieldIn.first] + nShield
				
				-- Incoming Ability Shield
				if strSpellName and self.config:GetOpt("bRecordAbilityShieldIn") then
					local nAbilityShield = self.tCurAbilityShieldIn[strSpellName]
					if nAbilityShield == nil then
						self.tCurAbilityShieldIn[strSpellName] = nShield
					else
						self.tCurAbilityShieldIn[strSpellName] = nAbilityShield + nShield
					end
				end
				
				-- Incoming Player Shield
				if self.config:GetOpt("bRecordPlayerShieldIn") then
					local strCasterName = unitCaster:GetName()
					local nCasterShield = self.tCurPlayerShieldIn[strCasterName]
					if nCasterShield == nil then
						self.tCurPlayerShieldIn[strCasterName] = nShield
					else
						self.tCurPlayerShieldIn[strCasterName] = nCasterShield + nShield
					end
				end
				
			end		-- outgoing/incoming
			
		-- Damage
		else
		
			-- Get value. Include shield and absorb in damage.
			local nActualDamage = nDamage + nShieldDamage + nAbsorptionAmount
			glog:debug("Damage: " .. nActualDamage)
			
			-- Outgoing
			if unitCaster == GameLib.GetPlayerUnit() then
			
				if not unitTarget then return end
				
				-- Update totals
				self.tCurCombatStats.nHitCount = self.tCurCombatStats.nHitCount + 1
				self.nTotalDamageOut = self.nTotalDamageOut + nActualDamage
				self.tCurCombatStats.nTotalDamageOut = self.tCurCombatStats.nTotalDamageOut + nActualDamage
				
				-- Add value to current interval total
				self.qCurCombatDamageOut[self.qCurCombatDamageOut.first] = self.qCurCombatDamageOut[self.qCurCombatDamageOut.first] + nActualDamage
				
				-- Count crits
				if bCritical then
					self.tCurCombatStats.nCritCount = self.tCurCombatStats.nCritCount + 1
				end
				
				-- Deflects are counted using combat log events
				
				glog:info("crits: " .. self.tCurCombatStats.nCritCount)
				glog:info("hits: " .. self.tCurCombatStats.nHitCount)
				
				-- Outgoing Ability Damage
				if strSpellName and self.config:GetOpt("bRecordAbilityDamageOut") then
					local nAbilityDamage = self.tCurAbilityDamageOut[strSpellName]
					if nAbilityDamage == nil then
						self.tCurAbilityDamageOut[strSpellName] = nActualDamage
					else
						self.tCurAbilityDamageOut[strSpellName] = nAbilityDamage + nActualDamage
					end
				end
				
				-- Outgoing Player Damage
				if self.config:GetOpt("bRecordPlayerDamageOut") then
					local strTargetName = unitTarget:GetName()
					local nTargetDamage = self.tCurPlayerDamageOut[strTargetName]
					if nTargetDamage == nil then
						self.tCurPlayerDamageOut[strTargetName] = nActualDamage
					else
						self.tCurPlayerDamageOut[strTargetName] = nTargetDamage + nActualDamage
					end
				end
				
			-- Incoming
			elseif unitTarget == GameLib.GetPlayerUnit() then
			
				if not unitCaster then return end
				
				-- Update totals
				self.tCurCombatStats.nEnemyHitCount = self.tCurCombatStats.nEnemyHitCount + 1
				self.nTotalDamageIn = self.nTotalDamageIn + nActualDamage
				self.tCurCombatStats.nTotalDamageIn = self.tCurCombatStats.nTotalDamageIn + nActualDamage
				
				-- Add value to current interval total
				self.qCurCombatDamageIn[self.qCurCombatDamageIn.first] = self.qCurCombatDamageIn[self.qCurCombatDamageIn.first] + nActualDamage
				
				-- Count crits
				if bCritical then
					self.tCurCombatStats.nEnemyCritCount = self.tCurCombatStats.nEnemyCritCount + 1
				end
				
				-- Deflects are counted using combat log events
				
				-- Incoming Ability Damage
				if strSpellName and self.config:GetOpt("bRecordAbilityDamageIn") then
					local nAbilityDamage = self.tCurAbilityDamageIn[strSpellName]
					if nAbilityDamage == nil then
						self.tCurAbilityDamageIn[strSpellName] = nActualDamage
					else
						self.tCurAbilityDamageIn[strSpellName] = nAbilityDamage + nActualDamage
					end
				end
				
				-- Incoming Player Damage
				if self.config:GetOpt("bRecordPlayerDamageIn") then
					local strCasterName = unitCaster:GetName()
					local nCasterDamage = self.tCurPlayerDamageIn[strCasterName]
					if nCasterDamage == nil then
						self.tCurPlayerDamageIn[strCasterName] = nActualDamage
					else
						self.tCurPlayerDamageIn[strCasterName] = nCasterDamage + nActualDamage
					end
				end
				
			end		-- outgoing/incoming
		end
		
	end		-- bInCombat
	
	-- Group stats
	--[[
	if GroupLib.InGroup() then 
		self.bInCombat = true
		if LuaUtils:GetTableSize(self.tGroupDamage) == 0 then
			self:InitGroupData()
		end
		local name = unitCaster:GetName()
		if eDamageType == GameLib.CodeEnumDamageType.Heal or eDamageType == GameLib.CodeEnumDamageType.HealShields then
			glog:info((nDamage + nShieldDamage) .. " healing by: " .. name)
			if self.tGroupHealing[name] ~= nil then
				self.tGroupHealing[name] = self.tGroupHealing[name] + nDamage + nShieldDamage
			end
		else
			glog:info((nDamage + nShieldDamage + nAbsorptionAmount) .. " damage by: " .. name)
			if self.tGroupDamage[name] ~= nil then
				self.tGroupDamage[name] = self.tGroupDamage[name] + nDamage + nShieldDamage + nAbsorptionAmount
			end
		end
		return 
	end
	--]]
	
end

function XPS:InitGroupData()
	local nSize = GroupLib.GetGroupMaxSize()
	for i=1,nSize do
		local member = GroupLib.GetGroupMember(i)
		if member == nil then break end
		glog:info("found member: " .. member.characterName)
		self.tGroupDamage[member.characterName] = 0
		self.tGroupHealing[member.characterName] = 0
	end
end

function XPS:ResetReadouts()
	if self.tWndReadouts ~= nil then
		for k,wnd in pairs(self.tWndReadouts) do
			wnd:SetText("0")
		end
	end
end

--- Event Handler for player entering/exiting combat
function XPS:OnUnitEnteredCombat(unit, bInCombat)
	if unit == GameLib.GetPlayerUnit() then
		if bInCombat then
			self:ProcessEnteredCombat()
		else
			self:ProcessExitedCombat()
		end
	end
end

function XPS:ProcessEnteredCombat()
	glog:info("Entered Combat")
	
	-- Hide history dialog
	self.wndCombatHistory:Show(false)
	
	-- Reset readouts
	self:ResetReadouts()
		
	-- Get combat start values
	self.bInCombat = true
	self.nItemsInQueue = 0
	
	self.nDamageOutCombatStart = self.nTotalDamageOut
	self.nDamageInCombatStart = self.nTotalDamageIn
	
	self.nHealingOutCombatStart = self.nTotalHealingOut
	self.nHealingInCombatStart = self.nTotalHealingIn
	
	self.nShieldOutCombatStart = self.nTotalShieldOut
	self.nShieldInCombatStart = self.nTotalShieldIn
	
	self.nExpCombatStart = GetXp()
	
	-- Initialize combat stats
	self.tCurCombatStats = self:CreateNewCombatStats()
	
	-- Initialize Player damage maps
	if self.config:GetOpt("bRecordPlayerDamageOut") then
		self.tCurPlayerDamageOut = {}
	else
		self.tCurPlayerDamageOut = nil						-- Placeholder
	end
	if self.config:GetOpt("bRecordPlayerDamageIn") then
		self.tCurPlayerDamageIn = {}
	else
		self.tCurPlayerDamageIn = nil						-- Placeholder
	end
	
	-- Initialize Player healing maps
	if self.config:GetOpt("bRecordPlayerHealingOut") then
		self.tCurPlayerHealingOut = {}
	else
		self.tCurPlayerHealingOut = nil						-- Placeholder
	end
	if self.config:GetOpt("bRecordPlayerHealingIn") then
		self.tCurPlayerHealingIn = {}
	else
		self.tCurPlayerHealingIn = nil						-- Placeholder
	end
	
	-- Initialize Player shield maps
	if self.config:GetOpt("bRecordPlayerShieldOut") then
		self.tCurPlayerShieldOut = {}
	else
		self.tCurPlayerShieldOut = nil						-- Placeholder
	end
	if self.config:GetOpt("bRecordPlayerShieldIn") then
		self.tCurPlayerShieldIn = {}
	else
		self.tCurPlayerShieldIn = nil						-- Placeholder
	end
	
	-- Initialize Ability damage maps
	if self.config:GetOpt("bRecordAbilityDamageOut") then
		self.tCurAbilityDamageOut = {}
	else
		self.tCurAbilityDamageOut = nil					-- Placeholder
	end
	if self.config:GetOpt("bRecordAbilityDamageIn") then
		self.tCurAbilityDamageIn = {}
	else
		self.tCurAbilityDamageIn = nil					-- Placeholder
	end
	
	-- Initialize Ability healing maps
	if self.config:GetOpt("bRecordAbilityHealingOut") then
		self.tCurAbilityHealingOut = {}
	else
		self.tCurAbilityHealingOut = nil					-- Placeholder
	end
	if self.config:GetOpt("bRecordAbilityHealingIn") then
		self.tCurAbilityHealingIn = {}
	else
		self.tCurAbilityHealingIn = nil					-- Placeholder
	end
	
	-- Initialize Ability shield maps
	if self.config:GetOpt("bRecordAbilityShieldOut") then
		self.tCurAbilityShieldOut = {}
	else
		self.tCurAbilityShieldOut = nil					-- Placeholder
	end
	if self.config:GetOpt("bRecordAbilityShieldIn") then
		self.tCurAbilityShieldIn = {}
	else
		self.tCurAbilityShieldIn = nil					-- Placeholder
	end
	
	-- Initialize Outgoing DPS queues
	self.qCurCombatDamageOut = Queue.new()				-- New averaging queue
	Queue.PushLeft(self.qCurCombatDamageOut, 0)			-- Bin for first interval
	if self.config:GetOpt("bRecordDPSOut") then
		Queue.PushLeft(self.qCombatDPSOut, {})			-- New combat time series
	else
		Queue.PushLeft(self.qCombatDPSOut, nil)			-- Placeholder
	end
	-- Limit Outgoing DPS history size
	if Queue.Size(self.qCombatDPSOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatDPSOut)
	end
	
	-- Initialize Incoming DPS queues
	self.qCurCombatDamageIn = Queue.new()				-- New averaging queue
	Queue.PushLeft(self.qCurCombatDamageIn, 0)			-- Bin for first interval
	if self.config:GetOpt("bRecordDPSIn") then
		Queue.PushLeft(self.qCombatDPSIn, {})			-- New combat time series
	else
		Queue.PushLeft(self.qCombatDPSIn, nil)			-- Placeholder
	end
	-- Limit Incoming DPS history size
	if Queue.Size(self.qCombatDPSIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatDPSIn)
	end
	
	-- Initialize Outgoing HPS queues
	self.qCurCombatHealingOut = Queue.new()				-- New averaging queue
	Queue.PushLeft(self.qCurCombatHealingOut, 0)		-- Bin for first interval
	if self.config:GetOpt("bRecordHPSOut") then
		Queue.PushLeft(self.qCombatHPSOut, {})			-- New combat time series
	else
		Queue.PushLeft(self.qCombatHPSOut, nil)			-- Placeholder
	end
	-- Limit Outgoing HPS history size
	if Queue.Size(self.qCombatHPSOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatHPSOut)
	end
	
	-- Initialize Incoming HPS queues
	self.qCurCombatHealingIn = Queue.new()				-- New averaging queue
	Queue.PushLeft(self.qCurCombatHealingIn, 0)			-- Bin for first interval
	if self.config:GetOpt("bRecordHPSIn") then
		Queue.PushLeft(self.qCombatHPSIn, {})			-- New combat time series
	else
		Queue.PushLeft(self.qCombatHPSIn, nil)			-- Placeholder
	end
	-- Limit Incoming HPS history size
	if Queue.Size(self.qCombatHPSIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatHPSIn)
	end
	
	-- Initialize Outgoing SPS queues
	self.qCurCombatShieldOut = Queue.new()				-- New averaging queue
	Queue.PushLeft(self.qCurCombatShieldOut, 0)			-- Bin for first interval
	if self.config:GetOpt("bRecordSPSOut") then
		Queue.PushLeft(self.qCombatSPSOut, {})			-- New combat time series
	else
		Queue.PushLeft(self.qCombatSPSOut, nil)			-- Placeholder
	end
	-- Limit Outgoing SPS history size
	if Queue.Size(self.qCombatSPSOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatSPSOut)
	end
	
	-- Initialize Incoming SPS queues
	self.qCurCombatShieldIn = Queue.new()		-- New averaging queue
	Queue.PushLeft(self.qCurCombatShieldIn, 0)	-- Bin for first interval
	if self.config:GetOpt("bRecordSPSIn") then
		Queue.PushLeft(self.qCombatSPSIn, {})			-- New combat time series
	else
		Queue.PushLeft(self.qCombatSPSIn, nil)		-- Placeholder
	end
	-- Limit Incoming SPS history size
	if Queue.Size(self.qCombatSPSIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatSPSIn)
	end
	
	-- Group
	--[[if GroupLib.InGroup() then
		glog:info("in group")
		self:InitGroupData()
	else
		glog:info("not in group")
	end--]]
	
	-- Show Readouts
	if self.config:GetOpt("bReadouts") then
		self:RebuildReadoutsForm()
		self.wndReadouts:Show(true)
	else
		self.wndReadouts:Show(false)
	end
	
	-- Show Outgoing plot
	if self.config:GetOpt("bShowOutgoingPlotInCombat") then
		self:UpdateOutgoingPlot()
		self.wndOutgoingPlot:Show(true)
	else
		self.wndOutgoingPlot:Show(false)
	end
	
	-- Show Incoming plot
	if self.config:GetOpt("bShowIncomingPlotInCombat") then
		self:UpdateIncomingPlot()
		self.wndIncomingPlot:Show(true)
	else
		self.wndIncomingPlot:Show(false)
	end
	
	-- Show Threat Meter
	if self.config:GetOpt("bThreatMeter") then
		self.wndThreatMeter:Show(true)
	else
		self.wndThreatMeter:Show(false)
	end
end

function XPS:ProcessExitedCombat()
	glog:info("Exited Combat")
	
	-- Don't process if we're not in combat (can happen if you Reload UI mid-combat)
	if not self.bInCombat then return end
	
	-- Empty the queues
	if self.config:GetOpt("bRecordData") then
		while self.nItemsInQueue > 0 do
			self:Update(true)
		end
	end
	
	-- End combat
	self.bInCombat = false
	--self:Update()		-- Uncomment to clear readouts on exiting combat
	
	-- Elapsed combat time
	self.tCurCombatStats.nElapsedTime = os.time() - self.tCurCombatStats.nTimeCombatStart
		
	-- Total experience gained
	self.tCurCombatStats.nExpGained = GetXp() - self.nExpCombatStart
	self.tCurCombatStats.nExpToLevel = GetXpToNextLevel() - (GetXp() - GetXpToCurrentLevel())
	
	-- Add combat stats
	Queue.PushLeft(self.qCombatStats, self.tCurCombatStats)
	
	-- Limit combat stats size
	if Queue.Size(self.qCombatStats) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatStats)
	end
	
	-- Add Player damage
	if self.config:GetOpt("bRecordPlayerDamageOut") then
		Queue.PushLeft(self.qCombatPlayerDamageOut, self.tCurPlayerDamageOut)
	else
		Queue.PushLeft(self.qCombatPlayerDamageOut, nil)
	end
	if self.config:GetOpt("bRecordPlayerDamageIn") then
		Queue.PushLeft(self.qCombatPlayerDamageIn, self.tCurPlayerDamageIn)
	else
		Queue.PushLeft(self.qCombatPlayerDamageIn, nil)
	end
	
	-- Add Player healing
	if self.config:GetOpt("bRecordPlayerHealingOut") then
		Queue.PushLeft(self.qCombatPlayerHealingOut, self.tCurPlayerHealingOut)
	else
		Queue.PushLeft(self.qCombatPlayerHealingOut, nil)
	end
	if self.config:GetOpt("bRecordPlayerHealingIn") then
		Queue.PushLeft(self.qCombatPlayerHealingIn, self.tCurPlayerHealingIn)
	else
		Queue.PushLeft(self.qCombatPlayerHealingIn, nil)
	end
	
	-- Add Player shield
	if self.config:GetOpt("bRecordPlayerShieldOut") then
		Queue.PushLeft(self.qCombatPlayerShieldOut, self.tCurPlayerShieldOut)
	else
		Queue.PushLeft(self.qCombatPlayerShieldOut, nil)
	end
	if self.config:GetOpt("bRecordPlayerShieldIn") then
		Queue.PushLeft(self.qCombatPlayerShieldIn, self.tCurPlayerShieldIn)
	else
		Queue.PushLeft(self.qCombatPlayerShieldIn, nil)
	end
	
	-- Add Ability damage
	if self.config:GetOpt("bRecordAbilityDamageOut") then
		Queue.PushLeft(self.qCombatAbilityDamageOut, self.tCurAbilityDamageOut)
	else
		Queue.PushLeft(self.qCombatAbilityDamageOut, nil)
	end
	if self.config:GetOpt("bRecordAbilityDamageIn") then
		Queue.PushLeft(self.qCombatAbilityDamageIn, self.tCurAbilityDamageIn)
	else
		Queue.PushLeft(self.qCombatAbilityDamageIn, nil)
	end
	
	-- Add Ability healing
	if self.config:GetOpt("bRecordAbilityHealingOut") then
		Queue.PushLeft(self.qCombatAbilityHealingOut, self.tCurAbilityHealingOut)
	else
		Queue.PushLeft(self.qCombatAbilityHealingOut, nil)
	end
	if self.config:GetOpt("bRecordAbilityHealingIn") then
		Queue.PushLeft(self.qCombatAbilityHealingIn, self.tCurAbilityHealingIn)
	else
		Queue.PushLeft(self.qCombatAbilityHealingIn, nil)
	end
	
	-- Add Ability shield
	if self.config:GetOpt("bRecordAbilityShieldOut") then
		Queue.PushLeft(self.qCombatAbilityShieldOut, self.tCurAbilityShieldOut)
	else
		Queue.PushLeft(self.qCombatAbilityShieldOut, nil)
	end
	if self.config:GetOpt("bRecordAbilityShieldIn") then
		Queue.PushLeft(self.qCombatAbilityShieldIn, self.tCurAbilityShieldIn)
	else
		Queue.PushLeft(self.qCombatAbilityShieldIn, nil)
	end
	
	-- Limit player queue history sizes
	if Queue.Size(self.qCombatPlayerDamageOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatPlayerDamageOut)
	end
	if Queue.Size(self.qCombatPlayerDamageIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatPlayerDamageIn)
	end
	if Queue.Size(self.qCombatPlayerHealingOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatPlayerHealingOut)
	end
	if Queue.Size(self.qCombatPlayerHealingIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatPlayerHealingIn)
	end
	if Queue.Size(self.qCombatPlayerShieldOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatPlayerShieldOut)
	end
	if Queue.Size(self.qCombatPlayerShieldIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatPlayerShieldIn)
	end
	-- Limit ability queue history sizes
	if Queue.Size(self.qCombatAbilityDamageOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatAbilityDamageOut)
	end
	if Queue.Size(self.qCombatAbilityDamageIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatAbilityDamageIn)
	end
	if Queue.Size(self.qCombatAbilityHealingOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatAbilityHealingOut)
	end
	if Queue.Size(self.qCombatAbilityHealingIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatAbilityHealingIn)
	end
	if Queue.Size(self.qCombatAbilityShieldOut) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatAbilityShieldOut)
	end
	if Queue.Size(self.qCombatAbilityShieldIn) > self.config:GetOpt("nStoredFights") then
		Queue.PopRight(self.qCombatAbilityShieldIn)
	end
	
	
	-- Show combat history window
	if self.config:GetOpt("bShowAfterCombat") then
		self:UpdateCombatHistoryWindow(self.qCombatStats.first)
		self.wndCombatHistory:Show(true)
	end
	self.wndOutgoingPlot:Show(false)
	self.wndIncomingPlot:Show(false)
end

-- nFightId is the queue index of the fight to make it easy on myself (can and will be negative)
function XPS:UpdateCombatHistoryWindow(nFightId)
	
	-- Update fights combobox
	self.wndFightSelector:DeleteAll()
	for i=self.qCombatStats.first, self.qCombatStats.last do
		local tStats = self.qCombatStats[i]
		glog:info("Adding fight item: " .. i)
		self.wndFightSelector:AddItem(os.date("%X", tStats.nTimeCombatStart), "", i)
	end
	self.wndFightSelector:SelectItemByData(nFightId)
	
	-- Update combat stats
	self:UpdateCombatHistoryStats(self.qCombatStats[nFightId])
	
	-- Update plot
	local eType = self.wndPlotTypeSelector:GetSelectedData()
	glog:debug("update history window, nFightId=" .. nFightId .. ", ePlotType=" .. eType)
	self:UpdateCombatHistoryPlot(nFightId, eType)
end

--local tPlotTypeLabels = {}
function XPS:UpdateCombatHistoryPlot(nFightId, eType)
	
	-- Flag if something was actually plotted. If not, don't redraw the plot.
	local bPlot = false
	
	-- Set options
	self:SetPlotOptionsByType(self.plotCombatHistory, eType)
	
	-- Set plot title
	--self.plotCombatHistory:FindChild("Title"):SetText(tPlotTypeLabels[ePlotType])
	
	-- Remove old datasets
	self.plotCombatHistory:RemoveAllDataSets()
	self.plotCombatHistory:Redraw()
	
	local tPlotColors = {}
	
	--
	-- Outgoing Time Series
	--
	
	-- Outgoing DPS dataset
	if eType == ePlotType.DPS_OUT or eType == ePlotType.OUTGOING or eType == ePlotType.ALL_XPS then
		if Queue.Size(self.qCombatDPSOut) > 0 then
			local tDPS = self.qCombatDPSOut[nFightId]
			if tDPS ~= nil and #tDPS > 2 then
				bPlot = true
				self.plotCombatHistory:AddDataSet({
					xStart = 0,
					values = tDPS
				})
				table.insert(tPlotColors, ApolloColor.new("xkcdAmber"):ToTable())
				self.plotCombatHistory:SetOption("aPlotColors", tPlotColors)
			end
		end
		-- Tweaks
		self.plotCombatHistory:SetXMin(-0.01)
		self.plotCombatHistory:SetYMin(-0.01)
	end
	
	-- Outgoing HPS dataset
	if eType == ePlotType.HPS_OUT or eType == ePlotType.OUTGOING or eType == ePlotType.ALL_XPS then
		if Queue.Size(self.qCombatHPSOut) > 0 then
			local tHPS = self.qCombatHPSOut[nFightId]
			if tHPS ~= nil and #tHPS > 2 then
				bPlot = true
				self.plotCombatHistory:AddDataSet({
					xStart = 0,
					values = tHPS
				})
				table.insert(tPlotColors, ApolloColor.new("xkcdAcidGreen"):ToTable())
				self.plotCombatHistory:SetOption("aPlotColors", tPlotColors)
			end
		end
		-- Tweaks
		self.plotCombatHistory:SetXMin(-0.01)
		self.plotCombatHistory:SetYMin(-0.01)
	end
	
	-- Outgoing SPS dataset
	if eType == ePlotType.SPS_OUT or eType == ePlotType.OUTGOING or eType == ePlotType.ALL_XPS then
		if Queue.Size(self.qCombatSPSOut) > 0 then
			local tSPS = self.qCombatSPSOut[nFightId]
			if tSPS ~= nil and #tSPS > 2 then
				bPlot = true
				self.plotCombatHistory:AddDataSet({
					xStart = 0,
					values = tSPS
				})
				table.insert(tPlotColors, ApolloColor.new("cyan"):ToTable())
				self.plotCombatHistory:SetOption("aPlotColors", tPlotColors)
			end
		end
		-- Tweaks
		self.plotCombatHistory:SetXMin(-0.01)
		self.plotCombatHistory:SetYMin(-0.01)
	end
	
	
	--
	-- Incoming Time Series
	--
	
	-- Incoming DPS dataset
	if eType == ePlotType.DPS_IN or eType == ePlotType.INCOMING or eType == ePlotType.ALL_XPS then
		if Queue.Size(self.qCombatDPSIn) > 0 then
			local tDPS = self.qCombatDPSIn[nFightId]
			if tDPS ~= nil and #tDPS > 2 then
				bPlot = true
				self.plotCombatHistory:AddDataSet({
					xStart = 0,
					values = tDPS
				})
				table.insert(tPlotColors, ApolloColor.new("xkcdLipstick"):ToTable())
				self.plotCombatHistory:SetOption("aPlotColors", tPlotColors)
			end
		end
		-- Tweaks
		self.plotCombatHistory:SetXMin(-0.01)
		self.plotCombatHistory:SetYMin(-0.01)
	end
	
	-- Incoming HPS dataset
	if eType == ePlotType.HPS_IN or eType == ePlotType.INCOMING or eType == ePlotType.ALL_XPS then
		if Queue.Size(self.qCombatHPSIn) > 0 then
			local tHPS = self.qCombatHPSIn[nFightId]
			if tHPS ~= nil and #tHPS > 2 then
				bPlot = true
				self.plotCombatHistory:AddDataSet({
					xStart = 0,
					values = tHPS
				})
				table.insert(tPlotColors, ApolloColor.new("xkcdBrightYellow"):ToTable())
				self.plotCombatHistory:SetOption("aPlotColors", tPlotColors)
			end
		end
		-- Tweaks
		self.plotCombatHistory:SetXMin(-0.01)
		self.plotCombatHistory:SetYMin(-0.01)
	end
	
	-- Incoming SPS dataset
	if eType == ePlotType.SPS_IN or eType == ePlotType.INCOMING or eType == ePlotType.ALL_XPS then
		if Queue.Size(self.qCombatSPSIn) > 0 then
			local tSPS = self.qCombatSPSIn[nFightId]
			if tSPS ~= nil and #tSPS > 2 then
				bPlot = true
				self.plotCombatHistory:AddDataSet({
					xStart = 0,
					values = tSPS
				})
				table.insert(tPlotColors, ApolloColor.new("xkcdBrightBlue"):ToTable())
				self.plotCombatHistory:SetOption("aPlotColors", tPlotColors)
			end
		end
		-- Tweaks
		self.plotCombatHistory:SetXMin(-0.01)
		self.plotCombatHistory:SetYMin(-0.01)
	end
	
	
	--
	-- Bar Graphs
	--
	
	-- Outgoing Player Damage
	if eType == ePlotType.PLAYER_DAMAGE_OUT then
		local tDamage = self.qCombatPlayerDamageOut[nFightId]
		if tDamage ~= nil and LuaUtils:GetTableSize(tDamage) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tDamage) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Incoming Player Damage
	if eType == ePlotType.PLAYER_DAMAGE_IN then
		local tDamage = self.qCombatPlayerDamageIn[nFightId]
		if tDamage ~= nil and LuaUtils:GetTableSize(tDamage) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tDamage) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Outgoing Player Healing
	if eType == ePlotType.PLAYER_HEALING_OUT then
		local tHealing = self.qCombatPlayerHealingOut[nFightId]
		if tHealing ~= nil and LuaUtils:GetTableSize(tHealing) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tHealing) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Incoming Player Healing
	if eType == ePlotType.PLAYER_HEALING_IN then
		local tHealing = self.qCombatPlayerHealingIn[nFightId]
		if tHealing ~= nil and LuaUtils:GetTableSize(tHealing) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tHealing) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Incoming Player Shield
	if eType == ePlotType.PLAYER_SHIELD_IN then
		local tShield = self.qCombatPlayerShieldIn[nFightId]
		if tShield ~= nil and LuaUtils:GetTableSize(tShield) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tShield) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Outgoing Player Shield
	if eType == ePlotType.PLAYER_SHIELD_OUT then
		local tShield = self.qCombatPlayerShieldOut[nFightId]
		if tShield ~= nil and LuaUtils:GetTableSize(tShield) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tShield) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Outgoing Ability Damage
	if eType == ePlotType.ABILITY_DAMAGE_OUT then
		local tDamage = self.qCombatAbilityDamageOut[nFightId]
		if tDamage ~= nil and LuaUtils:GetTableSize(tDamage) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tDamage) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Incoming Ability Damage
	if eType == ePlotType.ABILITY_DAMAGE_IN then
		local tDamage = self.qCombatAbilityDamageIn[nFightId]
		if tDamage ~= nil and LuaUtils:GetTableSize(tDamage) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tDamage) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Outgoing Ability Healing
	if eType == ePlotType.ABILITY_HEALING_OUT then
		local tHealing = self.qCombatAbilityHealingOut[nFightId]
		if tHealing ~= nil and LuaUtils:GetTableSize(tHealing) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tHealing) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Incoming Ability Healing
	if eType == ePlotType.ABILITY_HEALING_IN then
		local tHealing = self.qCombatAbilityHealingIn[nFightId]
		if tHealing ~= nil and LuaUtils:GetTableSize(tHealing) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tHealing) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Outgoing Ability Shield
	if eType == ePlotType.ABILITY_SHIELD_OUT then
		local tShield = self.qCombatAbilityShieldOut[nFightId]
		if tShield ~= nil and LuaUtils:GetTableSize(tShield) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tShield) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Incoming Ability Shield
	if eType == ePlotType.ABILITY_SHIELD_IN then
		local tShield = self.qCombatAbilityShieldIn[nFightId]
		if tShield ~= nil and LuaUtils:GetTableSize(tShield) > 0 then
			bPlot = true
			-- Transform to a bar graph DataSet
			local tLabels = {}
			local tValues = {}
			for k,v in pairs(tShield) do
				table.insert(tLabels, k .. " (" .. v .. ")")
				table.insert(tValues, v)
			end
			
			-- Add dataSet
			self.plotCombatHistory:AddDataSet({
				xStart = 0,
				values = tValues,
				labels = tLabels
			})
		end
	end
	
	-- Redraw
	if bPlot then
		self.plotCombatHistory:Redraw()
	end
end

function XPS:OnFightSelectorChanged(wndHandler, wndControl)
	local nFightId = wndHandler:GetSelectedData()
	--wndHandler:SelectItemByData(nFightId)
	glog:debug("Selected fight id: " .. nFightId)
	self:UpdateCombatHistoryWindow(nFightId)
end

function XPS:OnPlotTypeSelectorChanged(wndHandler, wndControl)
	local eType = wndHandler:GetSelectedData()
	--wndHandler:SelectItemByData(eType)
	glog:debug("Selected plot type: " .. eType)
	local nFightId = self.wndFightSelector:GetSelectedData()
	self:UpdateCombatHistoryPlot(nFightId, eType)
end

--- Updates the combat stats on the left side of combat history window
function XPS:UpdateCombatHistoryStats(tStats)
	glog:info(tStats)
	-- Combat time
	self.wndTimeCombatStart:SetText(os.date("%X", tStats.nTimeCombatStart))
	self.wndElapsedTime:SetText(LuaUtils:FormatTime(tStats.nElapsedTime))
	
	-- Total Hits
	self.wndTotalHits:SetText(tStats.nHitCount)
	self.wndTotalEnemyHits:SetText(tStats.nEnemyHitCount)
	
	-- Criticals
	self.wndCriticalHits:SetText(tStats.nCritCount)
	if tStats.nHitCount > 0 then
		self.wndCriticalRatio:SetText(math.ceil(tStats.nCritCount / tStats.nHitCount * 100) .. "%")
	else
		self.wndCriticalRatio:SetText("0%")
	end
		self.wndEnemyCriticalHits:SetText(tStats.nEnemyCritCount)
	if tStats.nEnemyHitCount > 0 then
		self.wndEnemyCriticalRatio:SetText(math.ceil(tStats.nEnemyCritCount / tStats.nEnemyHitCount * 100) .. "%")
	else
		self.wndEnemyCriticalRatio:SetText("0%")
	end
	
	-- Deflects
	self.wndDeflects:SetText(tStats.nDeflectCount)
	if tStats.nEnemyHitCount > 0 then
		self.wndDeflectRatio:SetText(math.ceil(tStats.nDeflectCount / tStats.nEnemyHitCount * 100) .. "%")
	else
		self.wndDeflectRatio:SetText("0%")
	end
		self.wndEnemyDeflects:SetText(tStats.nEnemyDeflectCount)
	if tStats.nHitCount > 0 then
		self.wndEnemyDeflectRatio:SetText(math.ceil(tStats.nEnemyDeflectCount / tStats.nHitCount * 100) .. "%")
	else
		self.wndEnemyDeflectRatio:SetText("0%")
	end
	
	-- Outgoing Damage/DPS
	self.wndTotalDamageOut:SetText(tStats.nTotalDamageOut)
	self.wndAvgDPSOut:SetText(math.ceil(tStats.nAvgDPSOut))
	self.wndMaxDPSOut:SetText(math.ceil(tStats.nMaxDPSOut))
	
	-- Incoming Damage/DPS
	self.wndTotalDamageIn:SetText(tStats.nTotalDamageIn)
	self.wndAvgDPSIn:SetText(math.ceil(tStats.nAvgDPSIn))
	self.wndMaxDPSIn:SetText(math.ceil(tStats.nMaxDPSIn))
	
	-- Outgoing Healing/HPS
	self.wndTotalHealingOut:SetText(tStats.nTotalHealingOut)
	self.wndAvgHPSOut:SetText(math.ceil(tStats.nAvgHPSOut))
	self.wndMaxHPSOut:SetText(math.ceil(tStats.nMaxHPSOut))
	
	-- Incoming Healing/HPS
	self.wndTotalHealingIn:SetText(tStats.nTotalHealingIn)
	self.wndAvgHPSIn:SetText(math.ceil(tStats.nAvgHPSIn))
	self.wndMaxHPSIn:SetText(math.ceil(tStats.nMaxHPSIn))
	
	-- Outgoing Shield/SPS
	self.wndTotalShieldOut:SetText(tStats.nTotalShieldOut)
	self.wndAvgSPSOut:SetText(math.ceil(tStats.nAvgSPSOut))
	self.wndMaxSPSOut:SetText(math.ceil(tStats.nMaxSPSOut))
	
	-- Incoming Shield/SPS
	self.wndTotalShieldIn:SetText(tStats.nTotalShieldIn)
	self.wndAvgSPSIn:SetText(math.ceil(tStats.nAvgSPSIn))
	self.wndMaxSPSIn:SetText(math.ceil(tStats.nMaxSPSIn))
	
	-- Experience
	local nExpTotalThisLevel = (GetXp() - GetXpToCurrentLevel()) + GetXpToNextLevel()
	local nPercentOfLevel = math.ceil(tStats.nExpGained / nExpTotalThisLevel * 100)
	self.wndExpGained:SetText(tStats.nExpGained)-- .. " (" .. nPercentOfLevel .. "%)")
	self.wndExpToLevel:SetText(GetXpToNextLevel() - (GetXp() - GetXpToCurrentLevel()))
	
end

function XPS:SetPlotOptionsByType(plot, eType)
	plot:SetXInterval(self.updateInterval)
	
	local tPlotColors
		
	if 	eType == ePlotType.ALL_XPS or
		eType == ePlotType.OUTGOING or
		eType == ePlotType.DPS_OUT or 
		eType == ePlotType.HPS_OUT or 
		eType == ePlotType.SPS_OUT or 
		eType == ePlotType.INCOMING or
		eType == ePlotType.DPS_IN or 
		eType == ePlotType.HPS_IN or
		eType == ePlotType.SPS_IN 
	then
		-- Base options for time series graphs
		plot:SetOption("ePlotStyle", PixiePlot.LINE)
		plot:SetOption("bDrawXValueLabels", true)
		plot:SetOption("bDrawYValueLabels", true)
		plot:SetOption("nYLabelDecimals", 0)
		plot:SetOption("bDrawXGridLines", true)
		plot:SetOption("bDrawYGridLines", true)
		plot:SetOption("fXLabelMargin", 45)
		plot:SetOption("fYLabelMargin", 45)
		plot:SetOption("fPlotMargin", 15)
		plot:SetOption("xValueFormatter", function(value) 
			return LuaUtils:FormatTime(value) 
		end)
		--plot:SetOption("bDrawXGridLines", true)
		plot:SetOption("bDrawYGridLines", true)
		plot:SetOption("bDrawSymbol", false)
		
		-- Colors
		if eType == ePlotType.ALL_XPS then
			tPlotColors = {
				ApolloColor.new("xkcdAmber"):ToTable(),
				ApolloColor.new("xkcdAcidGreen"):ToTable(),
				ApolloColor.new("cyan"):ToTable(),
				ApolloColor.new("xkcdLipstick"):ToTable(),
				ApolloColor.new("xkcdBrightYellow"):ToTable(),
				ApolloColor.new("xkcdBrightBlue"):ToTable()
			}
		elseif eType == ePlotType.OUTGOING then
			tPlotColors = {
				ApolloColor.new("xkcdAmber"):ToTable(),
				ApolloColor.new("xkcdAcidGreen"):ToTable(),
				ApolloColor.new("cyan"):ToTable()
			}
		elseif eType == ePlotType.DPS_OUT then
			tPlotColors = {ApolloColor.new("xkcdAmber"):ToTable()}
		elseif eType == ePlotType.HPS_OUT then
			tPlotColors = {ApolloColor.new("xkcdAcidGreen"):ToTable()}
		elseif eType == ePlotType.SPS_OUT then
			tPlotColors = {ApolloColor.new("cyan"):ToTable()}
		elseif eType == ePlotType.INCOMING then
			tPlotColors = {
				ApolloColor.new("xkcdLipstick"):ToTable(),
				ApolloColor.new("xkcdBrightYellow"):ToTable(),
				ApolloColor.new("xkcdBrightBlue"):ToTable()
			}
		elseif eType == ePlotType.DPS_IN then
			tPlotColors = {ApolloColor.new("xkcdLipstick"):ToTable()}
		elseif eType == ePlotType.HPS_IN then
			tPlotColors = {ApolloColor.new("xkcdBrightYellow"):ToTable()}
		elseif eType == ePlotType.SPS_IN then
			tPlotColors = {ApolloColor.new("xkcdBrightBlue"):ToTable()}
		end
		plot:SetOption("aPlotColors", tPlotColors)
		
	elseif 	eType == ePlotType.PLAYER_DAMAGE_OUT or
			eType == ePlotType.ABILITY_DAMAGE_OUT or
			eType == ePlotType.PLAYER_DAMAGE_IN or
			eType == ePlotType.ABILITY_DAMAGE_IN or
			eType == ePlotType.PLAYER_HEALING_OUT or
			eType == ePlotType.ABILITY_HEALING_OUT or
			eType == ePlotType.PLAYER_HEALING_IN or
			eType == ePlotType.ABILITY_HEALING_IN or
			eType == ePlotType.PLAYER_SHIELD_OUT or
			eType == ePlotType.ABILITY_SHIELD_OUT or
			eType == ePlotType.PLAYER_SHIELD_IN or
			eType == ePlotType.ABILITY_SHIELD_IN
	then
		-- Base options for bar graphs
		plot:SetOption("ePlotStyle", PixiePlot.BAR)
		plot:SetOption("eBarOrientation", PixiePlot.HORIZONTAL)
		plot:SetOption("bDrawXValueLabels", false)
		plot:SetOption("bDrawYValueLabels", true)
		plot:SetOption("bDrawXGridLines", true)
		plot:SetOption("bDrawYGridLines", false)
		plot:SetOption("fBarMargin", 3)
		plot:SetOption("fBarSpacing", 3)
		plot:SetOption("fXLabelMargin", 40)
		plot:SetOption("fYLabelMargin", 16)
		plot:SetOption("nYLabelDecimals", 0)
		plot:SetOption("nXLabelDecimals", 0)
		plot:SetOption("fPlotMargin", 8)
		plot:SetOption("strBarSprite", "WhiteFill")
		--plot:SetOption("strBarFont", "")
		plot:SetOption("aPlotColors", {
			{a=1,r=150/255,g=150/255,b=40/255}
		})
		plot:SetOption("xValueFormatter", nil)
		plot:SetOption("yValueFormatter", nil)
		
		-- Colors
		if eType == ePlotType.PLAYER_DAMAGE_OUT or eType == ePlotType.ABILITY_DAMAGE_OUT then
			tPlotColors = {ApolloColor.new("xkcdAmber"):ToTable()}
		elseif eType == ePlotType.PLAYER_DAMAGE_IN or eType == ePlotType.ABILITY_DAMAGE_IN then
			tPlotColors = {ApolloColor.new("xkcdLipstick"):ToTable()}
		elseif eType == ePlotType.PLAYER_HEALING_OUT or eType == ePlotType.ABILITY_HEALING_OUT then
			tPlotColors = {ApolloColor.new("xkcdAcidGreen"):ToTable()}
		elseif eType == ePlotType.PLAYER_HEALING_IN or eType == ePlotType.ABILITY_HEALING_IN then
			tPlotColors = {ApolloColor.new("xkcdBrightYellow"):ToTable()}
		elseif eType == ePlotType.PLAYER_SHIELD_OUT or eType == ePlotType.ABILITY_SHIELD_OUT then
			tPlotColors = {ApolloColor.new("cyan"):ToTable()}
		elseif eType == ePlotType.PLAYER_SHIELD_IN or eType == ePlotType.ABILITY_SHIELD_IN then
			tPlotColors = {ApolloColor.new("xkcdBrightBlue"):ToTable()}
		end
		plot:SetOption("aPlotColors", tPlotColors)
	elseif eType == ePlotType.THREAT_METER then		
		plot:SetOption("ePlotStyle", PixiePlot.BAR)
		plot:SetOption("eBarOrientation", PixiePlot.HORIZONTAL)
		plot:SetOption("bDrawXValueLabels", false)
		plot:SetOption("bDrawYValueLabels", false)
		plot:SetOption("bDrawXGridLines", false)
		plot:SetOption("bDrawYGridLines", false)
		plot:SetOption("fBarMargin", 6)
		plot:SetOption("fBarSpacing", 6)
		plot:SetOption("fXLabelMargin", 8)
		plot:SetOption("fYLabelMargin", 8)
		plot:SetOption("fPlotMargin", 4)
		plot:SetOption("strBarSprite", "sprRaid_HealthProgBar_Red")
		plot:SetOption("aPlotColors", {
			{a=1,r=1,g=1,b=1}
		})
	end
	
end

--- Threat list for player target updated
function XPS:OnTargetThreatListUpdated(t1, v1, t2, v2, t3, v3, t4, v4, t5, v5)
	local tThreats = {t1, t2, t3, t4, t5}
	local tValues = {v1, v2, v3, v4, v5}
	if t1 ~= nil then
		if self.config:GetOpt("bThreatMeter") then
			glog:debug("Threat target: " .. GameLib.GetTargetUnit():GetName())
			self:UpdateThreatMeter(tThreats, tValues)
			self.wndThreatMeter:Show(true)
		end
	end
end

--- Updates threat bar graph
function XPS:UpdateThreatMeter(tThreats, tValues)
	if #tThreats == 0 then return end

	-- Transform dataset
	local tNames = {}
	local tActualValues = {}
	for i,t in ipairs(tThreats) do 
		local nValue = tValues[i]
		if t:GetName() and nValue and nValue > 1 then
			table.insert(tNames, t:GetName() .. " (" .. tValues[i] .. ")")
			table.insert(tActualValues, nValue)
		end
	end

	-- Sometimes the tValues can be 0, so exit out if we have no real threat
	if #tActualValues == 0 then return end

	-- Initialize plot if this is the first update
	if self.plotThreatMeter == nil then 
		self.plotThreatMeter = PixiePlot:New(self.wndThreatMeter:FindChild("Plot"))
		self:SetPlotOptionsByType(self.plotThreatMeter, ePlotType.THREAT_METER)
	end
	
	-- Set plot title
	self.wndThreatMeter:FindChild("ThreatTargetName"):SetText(GameLib.GetTargetUnit():GetName())
	
	-- Remove old datasets
	self.plotThreatMeter:RemoveAllDataSets()
	
	-- Add dataset
	self.plotThreatMeter:AddDataSet({
		xStart = 0,
		values = tActualValues,
		labels = tNames
	})
	
	-- Redraw
	self.plotThreatMeter:Redraw()
end

--- Updates Outgoing DPS/HPS/SPS line graph
function XPS:UpdateOutgoingPlot()
	
	-- Initialize plot if this is the first update
	if self.plotOutgoing == nil then 
		self.plotOutgoing = PixiePlot:New(self.wndOutgoingPlot:FindChild("Plot"))
		self:SetPlotOptionsByType(self.plotOutgoing, ePlotType.OUTGOING)
	end
	
	-- Remove old data
	self.plotOutgoing:RemoveAllDataSets()
	
	local tPlotColors = {}
	
	--
	-- Add recording datasets
	--
	
	-- Outgoing DPS
	if self.config:GetOpt("bRecordDPSOut") then
		local tDPS = self.qCombatDPSOut[self.qCombatDPSOut.first]
		if tDPS ~= nil and #tDPS > 2 then
			self.plotOutgoing:AddDataSet({
				xStart = 0,
				values = tDPS
			})
			table.insert(tPlotColors, ApolloColor.new("xkcdAmber"):ToTable())
		end
	end
	
	-- Outgoing HPS
	if self.config:GetOpt("bRecordHPSOut") then
		local tHPS = self.qCombatHPSOut[self.qCombatHPSOut.first]
		if tHPS ~= nil and #tHPS > 2 then
			self.plotOutgoing:AddDataSet({
				xStart = 0,
				values = tHPS
			})
		end
		table.insert(tPlotColors, ApolloColor.new("xkcdAcidGreen"):ToTable())
	end
	
	-- Outgoing SPS
	if self.config:GetOpt("bRecordSPSOut") then
		local tSPS = self.qCombatSPSOut[self.qCombatSPSOut.first]
		if tSPS ~= nil and #tSPS > 2 then
			self.plotOutgoing:AddDataSet({
				xStart = 0,
				values = tSPS
			})
		end
		table.insert(tPlotColors, ApolloColor.new("cyan"):ToTable())
	end
	
	-- Tweaks (needed??)
	self.plotOutgoing:SetXMin(-0.01)
	self.plotOutgoing:SetYMin(-0.01)
	
	-- Draw plot
	self.plotOutgoing:Redraw()
end

--- Updates Incoming DPS/HPS/SPS line graph
function XPS:UpdateIncomingPlot()
	
	-- Initialize plot if this is the first update
	if self.plotIncoming == nil then 
		self.plotIncoming = PixiePlot:New(self.wndIncomingPlot:FindChild("Plot"))
		self:SetPlotOptionsByType(self.plotIncoming, ePlotType.INCOMING)
	end
	
	-- Remove old data
	self.plotIncoming:RemoveAllDataSets()
	
	local tPlotColors = {}
	
	--
	-- Add recording datasets
	--
	
	-- Incoming DPS
	if self.config:GetOpt("bRecordDPSIn") then
		local tDPS = self.qCombatDPSIn[self.qCombatDPSIn.first]
		if tDPS ~= nil and #tDPS > 2 then
			self.plotIncoming:AddDataSet({
				xStart = 0,
				values = tDPS
			})
			table.insert(tPlotColors, ApolloColor.new("xkcdLipstick"):ToTable())
		end
	end
	
	-- Incoming HPS
	if self.config:GetOpt("bRecordHPSIn") then
		local tHPS = self.qCombatHPSIn[self.qCombatHPSIn.first]
		if tHPS ~= nil and #tHPS > 2 then
			self.plotIncoming:AddDataSet({
				xStart = 0,
				values = tHPS
			})
		end
		table.insert(tPlotColors, ApolloColor.new("xkcdBrightYellow"):ToTable())
	end
	
	-- Incoming SPS
	if self.config:GetOpt("bRecordSPSIn") then
		local tSPS = self.qCombatSPSIn[self.qCombatSPSIn.first]
		if tSPS ~= nil and #tSPS > 2 then
			self.plotIncoming:AddDataSet({
				xStart = 0,
				values = tSPS
			})
		end
		table.insert(tPlotColors, ApolloColor.new("xkcdBrightBlue"):ToTable())
	end
	
	-- Tweaks (needed??)
	self.plotIncoming:SetXMin(-0.01)
	self.plotIncoming:SetYMin(-0.01)
	
	-- Draw plot
	self.plotIncoming:Redraw()
end

--- Updates Total Damage/Healing bar graph
function XPS:UpdateGroupPlot()
	self.plotGroup:RemoveAllDataSets()
	--glog:info("num damage samples for plot:" .. #self.tCombatDamage)
	
	-- convert data structs
	local tDamageValues = {}
	local tDamageLabels = {}
	for k,v in pairs(self.tGroupDamage) do 
		table.insert(tDamageValues, v)
		table.insert(tDamageLabels, k)
	end
	self.plotGroup:AddDataSet({
		xStart= 0,
		values= tDamageValues,
		labels= tDamageLabels
	})
	
	local tHealingValues = {}
	local tHealingLabels = {}
	for k,v in pairs(self.tGroupHealing) do 
		table.insert(tHealingValues, v)
		table.insert(tHealingLabels, k)
	end
	self.plotGroup:AddDataSet({
		xStart= 0,
		values= tHealingValues,
		labels= tHealingLabels
	})
	self.plotGroup:SetXMin(-0.01)
	self.plotGroup:SetYMin(-0.01)
	self.plotGroup:Redraw()
end

--- Experience gained
function XPS:OnExperienceGained(eReason, unitTarget, strText, fDelay, nAmount)
	self.nExpCounter = self.nExpCounter + nAmount
end

--- Combat log damage for damage ability names
---[[
function XPS:OnCombatLogDamage(tData)
	glog:info(tData)
	return
	--[[if tData.unitCaster ~= GameLib.GetPlayerUnit() then return end
	local strSpellName = "Unknown Spell"
	if tData.splCallingSpell and tData.splCallingSpell:GetName() then
		strSpellName = tData.splCallingSpell:GetName()
	end
	glog:info(strSpellName)
	self.strLastCastedDamageSpellName = strSpellName--]]
end
--]]

--- Combat log healing for healing ability names
---[[
function XPS:OnCombatLogHealing(tData)
	glog:info(tData)
	return
	--[[if tData.unitCaster ~= GameLib.GetPlayerUnit() then return end
	local strSpellName = "Unknown Spell"
	if tData.splCallingSpell and tData.splCallingSpell:GetName() then
		strSpellName = tData.splCallingSpell:GetName()
	end
	glog:info(strSpellName)
	self.strLastCastedHealingSpellName = strSpellName--]]
end
--]]

function XPS:OnCombatLogDeflect(tEventArgs)
	if not self.bInCombat then return end
	local unitCaster = tEventArgs.unitCaster
	local unitTarget = tEventArgs.unitTarget
	if unitCaster == GameLib.GetPlayerUnit() then
		self.tCurCombatStats.nEnemyDeflectCount = self.tCurCombatStats.nEnemyDeflectCount + 1
	end
	if unitTarget == GameLib.GetPlayerUnit() then
		self.tCurCombatStats.nDeflectCount = self.tCurCombatStats.nDeflectCount + 1
	end
end

--- On SlashCommand "/xps"
function XPS:OnXPSOn(strCommand, strParam)
	if strParam == "config" then
		self.config:Show(true)
	elseif strParam == "resetexp" then
		self.nExpCounter = 0
		self.nTimeExpCounterStart = os.time()
	else
		if Queue.Size(self.qCombatStats) > 0 then
			self:UpdateCombatHistoryWindow(self.qCombatStats.first)
			--self:UpdateCombatHistoryStats(self.qCombatStats[self.qCombatStats.first])
			self.wndCombatHistory:Show(true)
		end
	end
end

--- When the Close button is clicked
function XPS:OnClose(wndHandler, wndControl)
	wndHandler:Show(false)
end

function XPS:OnConfigure(wndHandler, wndControl)
	self.config:Show(true)
end

function XPS:OnCombatHistoryClose(wndHandler, wndControl)
	self.wndCombatHistory:Show(false)
end





--- Computes average of the value for the current combat
function XPS:ComputeCombatAverage(nValue)
	local nTime = os.time() - self.tCurCombatStats.nTimeCombatStart
	if nTime == 0 then
		return nValue
	else
		return nValue / nTime
	end
end

--- Computes per second stats
function XPS:ComputeXPS(queue)
	local damage = 0
	for k,v in pairs(queue) do
		if k ~= "first" and k ~= "last" then
			damage = damage + v
		end
	end
	--glog:debug("Total queue damage: " .. damage)
	return damage / (Queue.Size(queue) * self.updateInterval)
end

local XPSInst = XPS:new()
XPSInst:Init()

