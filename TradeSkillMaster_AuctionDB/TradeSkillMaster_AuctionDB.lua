-- ------------------------------------------------------------------------------ --
--                           TradeSkillMaster_AuctionDB                           --
--           http://www.curse.com/addons/wow/tradeskillmaster_auctiondb           --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- register this file with Ace Libraries
local TSM = select(2, ...)
TSM = LibStub("AceAddon-3.0"):NewAddon(TSM, "TSM_AuctionDB", "AceEvent-3.0", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0") -- load the AceGUI libraries

local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table

TSM.MAX_AVG_DAY = 1
local SECONDS_PER_DAY = 60 * 60 * 24

local savedDBDefaults = {
	realm = {
		appData = {},
		scanData = "",
		time = 0,
		lastCompleteScan = 0,
		lastScanSecondsPerPage = -1,
		appDataUpdate = 0,
	},
	profile = {
		tooltip = true,
		resultsPerPage = 50,
		resultsSortOrder = "ascending",
		resultsSortMethod = "name",
		hidePoorQualityItems = true,
		marketValueTooltip = true,
		minBuyoutTooltip = true,
		predictedPriceTooltip = false,
		trendTooltip = false,
		volatilityTooltip = false,
		confidenceTooltip = false,
		weekdayTooltip = false,
		smartPriceTooltip = false,
		showAHTab = true,
		disableGetAll = false,
	},
}

-- Called once the player has loaded WOW.
function TSM:OnInitialize()
	-- load the savedDB into TSM.db
	TSM.db = LibStub:GetLibrary("AceDB-3.0"):New("TradeSkillMaster_AuctionDBDB", savedDBDefaults, true)

	-- make easier references to all the modules
	for moduleName, module in pairs(TSM.modules) do
		TSM[moduleName] = module
	end

	-- register this module with TSM
	TSM:RegisterModule()
	TSM.db.realm.time = 10 -- because AceDB won't save if we don't do this...
	
	TSM.data = {}
	TSM:Deserialize(TSM.db.realm.scanData, TSM.data)
end

-- registers this module with TSM by first setting all fields and then calling TSMAPI:NewModule().
function TSM:RegisterModule()
	TSM.priceSources = {
		{ key = "DBMarket", label = L["AuctionDB - Market Value"], callback = "GetMarketValue" },
		{ key = "DBMinBuyout", label = L["AuctionDB - Minimum Buyout"], callback = "GetMinBuyout" },
		{ key = "DBPredicted", label = L["AuctionDB - Predicted Price"], callback = "GetPredictedPrice" },
		{ key = "DBTrend", label = L["AuctionDB - Trend (per day)"], callback = "GetTrendValue" },
		{ key = "DBVolatility", label = L["AuctionDB - Volatility"], callback = "GetVolatilityValue" },
		{ key = "DBConfidence", label = L["AuctionDB - Confidence"], callback = "GetConfidenceValue" },
		{ key = "DBWeekday", label = L["AuctionDB - Weekday Price"], callback = "GetWeekdayValue" },
		{ key = "DBSmartPrice", label = L["AuctionDB - Smart Price"], callback = "GetSmartPriceValue" },
	}
	TSM.icons = {
		{ side = "module", desc = "AuctionDB", slashCommand = "auctiondb", callback = "Config:Load", icon = "Interface\\Icons\\Inv_Misc_Platnumdisks" },
	}
	if TSM.db.profile.showAHTab then
		TSM.auctionTab = { callbackShow = "GUI:Show", callbackHide = "GUI:Hide" }
	end
	TSM.slashCommands = {
		{ key = "adbreset", label = L["Resets AuctionDB's scan data"], callback = "Reset" },
	}
	TSM.moduleAPIs = {
		{ key = "lastCompleteScan", callback = TSM.GetLastCompleteScan },
		{ key = "lastCompleteScanTime", callback = TSM.GetLastCompleteScanTime },
		{ key = "adbScans", callback = TSM.GetScans },
		{ key = "adbOppositeFaction", callback = TSM.GetOppositeFactionData },
	}
	TSM.tooltipOptions = {callback = "Config:LoadTooltipOptions"}
	TSMAPI:NewModule(TSM)
end

function TSM:LoadAuctionData()
	local function LoadDataThread(self, itemIDs)
		-- process new items first
		for itemID in pairs(TSM.db.realm.appData) do
			if not TSM.data[itemID] then
				TSM:DecodeItemData(itemID)
				TSM:ProcessAppData(itemID)
				TSM:EncodeItemData(itemID)
			end
			self:Yield()
		end
		
		local currentDay = TSM.Data:GetDay()
		for _, itemID in ipairs(itemIDs) do
			TSM:DecodeItemData(itemID)
			TSM:ProcessAppData(itemID)
			if type(TSM.data[itemID].scans) == "table" then
				local temp = {}
				for i=0, 14 do
					if i <= TSM.MAX_AVG_DAY then
						temp[currentDay-i] = TSM.Data:ConvertScansToAvg(TSM.data[itemID].scans[currentDay-i])
					else
						local dayScans = TSM.data[itemID].scans[currentDay-i]
						if type(dayScans) == "table" then
							if dayScans.avg then
								temp[currentDay-i] = dayScans.avg
							else
								-- old method
								temp[currentDay-i] = TSM.Data:GetAverage(dayScans)
							end
						elseif type(dayScans) == "number" then
							temp[currentDay-i] = dayScans
						end
					end
				end
				TSM.data[itemID].scans = temp
			end
			TSM:EncodeItemData(itemID)
			self:Yield()
		end
	end
	
	local itemIDs = {}
	for itemID in pairs(TSM.data) do
		tinsert(itemIDs, itemID)
	end
	TSMAPI.Threading:Start(LoadDataThread, 0.1, nil, itemIDs)
end

function TSM:ProcessAppData(itemID)
	if not TSM.db.realm.appData[itemID] then return end
	
	TSM.data[itemID] = TSM.data[itemID] or {scans = {}, lastScan = 0}
	local dbData = TSM.data[itemID]
	local day = TSM.Data:GetDay()
	for _, appData in ipairs(TSM.db.realm.appData[itemID]) do
		local marketValue, minBuyout, scanTime = appData.m, appData.b, appData.t
		if abs(day - TSM.Data:GetDay(scanTime)) <= TSM.MAX_AVG_DAY then
			local dayScans = dbData.scans
			dayScans[day] = dayScans[day] or {avg=0, count=0}
			if type(dayScans[day]) == "number" then
				-- this should never happen...
				dayScans[day] = {dayScans[day]}
			end
			dayScans[day].avg = dayScans[day].avg or 0
			dayScans[day].count = dayScans[day].count or 0
			if #dayScans[day] > 0 then
				dayScans[day] = TSM.Data:ConvertScansToAvg(dayScans[day])
			end
			dayScans[day].avg = floor((dayScans[day].avg * dayScans[day].count + marketValue) / (dayScans[day].count + 1) + 0.5)
			dayScans[day].count = dayScans[day].count + 1
			dayScans[day].weekday = dayScans[day].weekday or tonumber(date("%w", scanTime))
			if not dbData.lastScan or dbData.lastScan < scanTime then
				dbData.lastScan = scanTime
				dbData.minBuyout = minBuyout > 0 and minBuyout or nil
			end
		end
	end
	TSM.Data:UpdateMarketValue(dbData)
	TSM.db.realm.appData[itemID] = nil
end

function TSM:OnEnable()
	local function DecodeJSON(data)
		data = gsub(data, ":", "=")
		data = gsub(data, "\"horde\"", "horde")
		data = gsub(data, "\"alliance\"", "alliance")
		data = gsub(data, "\"m\"", "m")
		data = gsub(data, "\"n\"", "n")
		data = gsub(data, "\"b\"", "b")
		data = gsub(data, "\"([0-9]+)\"", "[%1]")
		loadstring("TSM_APP_DATA_TMP = " .. data .. "")()
		local val = TSM_APP_DATA_TMP
		TSM_APP_DATA_TMP = nil
		return val
	end

	if TSM.AppData then
		local realm = strlower(GetRealmName() or "")
		local faction = strlower(UnitFactionGroup("player") or "")
		if faction == "" or faction == "Neutral" then return end
		local numNewScans = 0
		local maxScanTime = 0
		for realmInfo, appScanData in pairs(TSM.AppData) do
			local r, f, t, extra = ("-"):split(realmInfo)
			if extra then
				r = r .. "-" .. f
				f = t
				t = extra
			end
			r = strlower(r)
			f = strlower(f)
			local scanTime = tonumber(t)
			if realm == r and (faction == f or f == "both") and scanTime > TSM.db.realm.appDataUpdate and abs(TSM.Data:GetDay() - TSM.Data:GetDay(scanTime)) <= TSM.MAX_AVG_DAY then
				local importData = DecodeJSON(appScanData)[faction]
				if importData then
					for itemID, data in pairs(importData) do
						itemID = tonumber(itemID)
						data.m = tonumber(data.m)
						data.b = tonumber(data.b)
						data.t = scanTime
						if itemID and data.m and data.b then
							TSM.db.realm.appData[itemID] = TSM.db.realm.appData[itemID] or {}
							tinsert(TSM.db.realm.appData[itemID], data)
						end
					end
					maxScanTime = max(maxScanTime, scanTime)
					numNewScans = numNewScans + 1
				end
			end
		end

		if numNewScans > 0 then
			TSM.db.realm.appDataUpdate = maxScanTime
			TSM.db.realm.lastCompleteScan = TSM.db.realm.appDataUpdate
			TSM:Printf(L["Imported %s scans worth of new auction data!"], numNewScans)
		end

		TSM.AppData = nil
	end

	TSM:LoadAuctionData()
end

function TSM:OnTSMDBShutdown()
	TSM.db.realm.time = 0
	TSM:Serialize(TSM.data)
end

function TSM:GetTooltip(itemString, quantity)
	if not TSM.db.profile.tooltip then return end
	if not strfind(itemString, "item:") then return end
	local itemID = TSMAPI:GetItemID(itemString)
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	local text = {}
	local moneyCoinsTooltip = TSMAPI:GetMoneyCoinsTooltip()
	quantity = quantity or 1

	-- add market value info
	if TSM.db.profile.marketValueTooltip then
		local marketValue = TSM:GetMarketValue(itemID)
		if marketValue then
				if moneyCoinsTooltip then
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Market Value x%s:"], quantity), right = TSMAPI:FormatTextMoneyIcon(marketValue * quantity, "|cffffffff", true) })
					else
						tinsert(text, { left = "  " .. L["Market Value:"], right = TSMAPI:FormatTextMoneyIcon(marketValue, "|cffffffff", true) })
					end
				else
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Market Value x%s:"], quantity), right = TSMAPI:FormatTextMoney(marketValue * quantity, "|cffffffff", true) })
					else
						tinsert(text, { left = "  " .. L["Market Value:"], right = TSMAPI:FormatTextMoney(marketValue, "|cffffffff", true) })
					end
				end
			end
	end

	-- add min buyout info
	if TSM.db.profile.minBuyoutTooltip then
		local minBuyout = TSM:GetMinBuyout(itemID)
		if minBuyout then
			if quantity then
				if moneyCoinsTooltip then
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Min Buyout x%s:"], quantity), right = TSMAPI:FormatTextMoneyIcon(minBuyout * quantity, "|cffffffff", true) })
					else
						tinsert(text, { left = "  " .. L["Min Buyout:"], right = TSMAPI:FormatTextMoneyIcon(minBuyout, "|cffffffff", true) })
					end
				else
					if IsShiftKeyDown() then
						tinsert(text, { left = "  " .. format(L["Min Buyout x%s:"], quantity), right = TSMAPI:FormatTextMoney(minBuyout * quantity, "|cffffffff", true) })
					else
						tinsert(text, { left = "  " .. L["Min Buyout:"], right = TSMAPI:FormatTextMoney(minBuyout, "|cffffffff", true) })
					end
				end
			end
		end
	end

	-- add predicted price info
	if TSM.db.profile.predictedPriceTooltip then
		local scans = TSM.data[itemID].scans
		if scans then
			local slope, predicted, numPoints = TSM.Data:CalculateTrend(scans)
			if predicted and predicted > 0 and numPoints >= 2 then
				local arrow = ""
				if slope and slope > 0 then
					arrow = " |cff00ff00^|r"  -- green up
				elseif slope and slope < 0 then
					arrow = " |cffff0000v|r"  -- red down
				end
				if moneyCoinsTooltip then
					tinsert(text, { left = "  " .. L["Predicted Price:"], right = TSMAPI:FormatTextMoneyIcon(predicted, "|cffffffff", true) .. arrow })
				else
					tinsert(text, { left = "  " .. L["Predicted Price:"], right = TSMAPI:FormatTextMoney(predicted, "|cffffffff", true) .. arrow })
				end
			end
		end
	end

	-- add trend info
	if TSM.db.profile.trendTooltip then
		local scans = TSM.data[itemID].scans
		if scans then
			local slope, _, numPoints = TSM.Data:CalculateTrend(scans)
			if slope and numPoints >= 2 then
				local marketValue = TSM.data[itemID].marketValue
				if marketValue and marketValue > 0 then
					local pctPerDay = (slope / marketValue) * 100
					local trendColor
					if pctPerDay > 1 then
						trendColor = "|cff00ff00" -- green: rising
					elseif pctPerDay < -1 then
						trendColor = "|cffff0000" -- red: falling
					else
						trendColor = "|cffffff00" -- yellow: stable
					end
					tinsert(text, { left = "  " .. L["Trend:"], right = format("%s%+.1f%%/day|r", trendColor, pctPerDay) })
				end
			end
		end
	end

	-- add volatility info
	if TSM.db.profile.volatilityTooltip then
		local scans = TSM.data[itemID].scans
		if scans then
			local volatility, numPoints = TSM.Data:CalculateVolatility(scans)
			if volatility and numPoints >= 2 then
				local volLabel, volColor
				if volatility <= 10 then
					volLabel = L["Low"]
					volColor = "|cff00ff00"
				elseif volatility <= 30 then
					volLabel = L["Medium"]
					volColor = "|cffffff00"
				else
					volLabel = L["High"]
					volColor = "|cffff0000"
				end
				tinsert(text, { left = "  " .. L["Volatility:"], right = format("%s%s (CV: %d)|r", volColor, volLabel, volatility) })
			end
		end
	end

	-- add confidence info
	if TSM.db.profile.confidenceTooltip then
		local scans = TSM.data[itemID].scans
		if scans then
			local confidence = TSM.Data:CalculateConfidence(scans, TSM.data[itemID].lastScan)
			if confidence then
				local confLabel, confColor
				if confidence >= 70 then
					confLabel = L["High"]
					confColor = "|cff00ff00"
				elseif confidence >= 40 then
					confLabel = L["Medium"]
					confColor = "|cffffff00"
				else
					confLabel = L["Low"]
					confColor = "|cffff0000"
				end
				tinsert(text, { left = "  " .. L["Confidence:"], right = format("%s%s (%d%%)|r", confColor, confLabel, confidence) })
			end
		end
	end

	-- add weekday price info
	if TSM.db.profile.weekdayTooltip then
		local scans = TSM.data[itemID].scans
		if scans then
			local today = TSM.Data:GetDay()
			local todayWeekday = TSM.Data:GetWeekday(today)
			local weekdayAvg, samples, overallAvg, deviationPct = TSM.Data:GetWeekdayPrice(scans, todayWeekday)
			if weekdayAvg and samples > 0 then
				local dayName = TSM.Data:GetWeekdayName(todayWeekday)
				local devColor
				if deviationPct > 5 then
					devColor = "|cff00ff00"  -- green: above average
				elseif deviationPct < -5 then
					devColor = "|cffff0000"  -- red: below average
				else
					devColor = "|cffffff00"  -- yellow: near average
				end
				local rightText
				if moneyCoinsTooltip then
					rightText = TSMAPI:FormatTextMoneyIcon(weekdayAvg, "|cffffffff", true) .. format(" %s(%s %+.0f%%)|r", devColor, dayName, deviationPct)
				else
					rightText = TSMAPI:FormatTextMoney(weekdayAvg, "|cffffffff", true) .. format(" %s(%s %+.0f%%)|r", devColor, dayName, deviationPct)
				end
				tinsert(text, { left = "  " .. L["Weekday Price:"], right = rightText })
			end
		end
	end

	-- add smart price
	if TSM.db.profile.smartPriceTooltip then
		local scans = TSM.data[itemID].scans
		local mv = TSM.data[itemID].marketValue
		if scans and mv and mv > 0 then
			local smartPrice, parts = TSM.Data:CalculateSmartPrice(scans, TSM.data[itemID].lastScan, mv)
			if smartPrice then
				local diff = smartPrice - mv
				local diffPct = (diff / mv) * 100
				local arrow, color
				if diffPct > 2 then
					arrow = "^"; color = "|cff00ff00"
				elseif diffPct < -2 then
					arrow = "v"; color = "|cffff0000"
				else
					arrow = "~"; color = "|cffffff00"
				end
				local rightText
				if moneyCoinsTooltip then
					rightText = TSMAPI:FormatTextMoneyIcon(smartPrice, "|cffffffff", true) .. format(" %s%s %+.0f%%|r", color, arrow, diffPct)
				else
					rightText = TSMAPI:FormatTextMoney(smartPrice, "|cffffffff", true) .. format(" %s%s %+.0f%%|r", color, arrow, diffPct)
				end
				tinsert(text, { left = "  " .. L["Smart Price:"], right = rightText })
			end
		end
	end

	-- add heading and last scan time info
	if #text > 0 then
		local lastScan = TSM:GetLastScanTime(itemID)
		if lastScan then
			local timeColor = "|cffff0000"
			if (time() - lastScan) < 60 * 60 * 3 then
				timeColor = "|cff00ff00"
			elseif (time() - lastScan) < 60 * 60 * 12 then
				timeColor = "|cffffff00"
			end
			local timeDiff = SecondsToTime(time() - lastScan)		
			--tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = "|cffffffff" .. format(L["%s ago"], timeDiff) })
			tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = format("%s (%s)", format("|cffffffff".."%d auctions".."|r", TSM.data[itemID].quantity), format(timeColor..L["%s ago"].."|r", timeDiff)) })
		else
			tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = "|cffffffff" .. L["Not Scanned"] })
		end
		return text
	end
end

function TSM:Reset()
	-- Popup Confirmation Window used in this module
	StaticPopupDialogs["TSMAuctionDBClearDataConfirm"] = StaticPopupDialogs["TSMAuctionDBClearDataConfirm"] or {
		text = L["Are you sure you want to clear your AuctionDB data?"],
		button1 = YES,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnAccept = function()
			TSM.db.realm.lastCompleteScan = 0
			TSM.db.realm.appDataUpdate = 0
			for i in pairs(TSM.data) do
				TSM.data[i] = nil
			end
			TSM:Print(L["Reset Data"])
		end,
		OnCancel = false,
	}

	StaticPopup_Show("TSMAuctionDBClearDataConfirm")
	for i = 1, 10 do
		local popup = _G["StaticPopup" .. i]
		if popup and popup.which == "TSMAuctionDBClearDataConfirm" then
			popup:SetFrameStrata("TOOLTIP")
			break
		end
	end
end

local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_="
local base = #alpha
local alphaTable = {}
local alphaTableLookup = {}
for i = 1, base do
	local char = strsub(alpha, i, i)
	tinsert(alphaTable, char)
	alphaTableLookup[char] = i
end

local function decode(h)
	if not h then return end
	if strfind(h, "~") then return end
	local result = 0

	local len = #h
	for j=len-1, 0, -1 do
		if not alphaTableLookup[strsub(h, len-j, len-j)] then error(h.." at index "..len-j) end
		result = result + (alphaTableLookup[strsub(h, len-j, len-j)] - 1) * (base ^ j)
		j = j - 1
	end

	return result
end

local function encode(d)
	d = tonumber(d)
	if not d or not (d < math.huge and d > 0) then -- this cannot be simplified since 0/0 is neither less than nor greater than any number
		return "~"
	end

	local r = d % base
	local diff = d - r
	if diff == 0 then
		return alphaTable[r + 1]
	else
		return encode(diff / base) .. alphaTable[r + 1]
	end
end

local function encodeScans(scans)
	local tbl, tbl2 = {}, {}
	for day, data in pairs(scans) do
		if type(data) == "table" and data.count and data.avg then
			-- New method of encoding scans (with optional weekday tag).
			local encoded = encode(data.avg).."@"..encode(data.count)
			if data.weekday then
				encoded = encoded .. "#" .. encode(data.weekday)
			end
			data = encoded
		elseif type(data) == "table" then
			-- Old method of encoding scans.
			for i = 1, #data do
				tbl2[i] = encode(data[i])
			end
			data = table.concat(tbl2, ";", 1, #data)
		else
			data = encode(data)
		end
		tinsert(tbl, encode(day) .. ":" .. data)
	end
	return table.concat(tbl, "!")
end

local function decodeScans(rope)
	if rope == "A" then return	end
	local scans = {}
	local days = {("!"):split(rope)}
	local currentDay = TSM.Data:GetDay()
	for _, data in ipairs(days) do
		local day, marketValueData = (":"):split(data)
		-- BUG FIXED: Guard against incorrectly encoded "day" or "marketValueData",
		-- which can happen extremely rarely due to some very rare, random bug
		-- somewhere else in TSM (or perhaps due to mixing different versions
		-- of TSM data). The cause of the rare corruption hasn't been found.
		-- NOTE: We simply skip any "days/market values" that cannot be decoded,
		-- which thereby ensures that we get a cleaned-up "decode" of the data,
		-- so that TSM will then write the fixed data when it next "re-encodes"
		-- the "decoded in-memory representation" of this item's data!
		if day ~= nil and day ~= "" and marketValueData ~= nil and marketValueData ~= "" then
			day = decode(day)
			-- BUG FIXED: Verify yet again that the day itself was properly decoded,
			-- but this time only check for "nil" which indicates "decode()" failure.
			if day ~= nil then
				-- Create a "scans" table entry for the decoded day.
				scans[day] = {}

				if strfind(marketValueData, "@") then
					-- New method of decoding scans (with optional weekday tag).
					local avg, countAndWeekday = ("@"):split(marketValueData)
					local count, weekday
					if strfind(countAndWeekday, "#") then
						local countStr, weekdayStr = ("#"):split(countAndWeekday)
						count = decode(countStr)
						weekday = decode(weekdayStr)
					else
						count = decode(countAndWeekday)
					end
					avg = decode(avg)
					if avg ~= "~" and count ~= "~" then
						if abs(currentDay - day) <= TSM.MAX_AVG_DAY then
							scans[day].avg = avg
							scans[day].count = count
							if weekday then
								scans[day].weekday = weekday
							end
						else
							scans[day] = avg
						end
					end
				else
					-- Old method of decoding scans.
					for _, value in ipairs({(";"):split(marketValueData)}) do
						local decodedValue = decode(value)
						if decodedValue ~= "~" then
							tinsert(scans[day], tonumber(decodedValue))
						end
					end
					if day ~= currentDay then
						scans[day] = TSM.Data:GetAverage(scans[day])
					end
				end
			end
		end
	end

	return scans
end

function TSM:Serialize()
	local results = {}
	for itemID, data in pairs(TSM.data) do
		if not data.encoded then
			-- should never get here, but just in-case
			TSM:EncodeItemData(itemID)
		end
		if data.encoded then
			tinsert(results, "?" .. encode(itemID) .. "," .. data.encoded)
		end
	end
	TSM.db.realm.scanData = table.concat(results)
end

function TSM:Deserialize(data, resultTbl, fullyDecode)
	if strsub(data, 1, 1) ~= "?" then return end

	for k, a, b, c, d, e, f in gmatch(data, "?([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^?]+)") do
		local itemID = decode(k)
		resultTbl[itemID] = {encoded=strjoin(",", a, b, c, d, e, f)}
		if fullyDecode then
			TSM:DecodeItemData(itemID, resultTbl)
		end
	end
end

function TSM:EncodeItemData(itemID, tbl)
	tbl = tbl or TSM.data
	local data = tbl[itemID]
	if data and data.marketValue then
		data.encoded = strjoin(",", encode(0), encode(data.marketValue), encode(data.lastScan), encode(0), encode(data.minBuyout), encodeScans(data.scans), encode(data.quantity))
	end
end

function TSM:DecodeItemData(itemID, tbl)
	tbl = tbl or TSM.data
	local data = tbl[itemID]
	if data and data.encoded and not data.marketValue then
		local a, b, c, d, e, f, g = (","):split(data.encoded)
		data.marketValue = decode(b)
		data.lastScan = decode(c)
		data.minBuyout = decode(e)
		data.scans = decodeScans(f)	
		data.quantity = decode(g)	
	end
end

function TSM:GetLastCompleteScan()
	local lastScan = {}
	for itemID, data in pairs(TSM.data) do
		TSM:DecodeItemData(itemID)
		if data.lastScan == TSM.db.realm.lastCompleteScan then
			lastScan[itemID] = { marketValue = data.marketValue, minBuyout = data.minBuyout }
		end
	end

	return lastScan
end

function TSM:GetLastCompleteScanTime()
	return TSM.db.realm.lastCompleteScan
end

function TSM:GetScans(link)
	if not link then return	end
	link = select(2, GetItemInfo(link))
	if not link then return	end
	local itemID = TSMAPI:GetItemID(link)
	if not TSM.data[itemID] then return	end
	TSM:DecodeItemData(itemID)

	return CopyTable(TSM.data[itemID].scans)
end

function TSM:GetOppositeFactionData()
	-- For cross-faction servers, data is shared, so return current data
	local result = {}
	TSM:Deserialize(TSM.db.realm.scanData, result, true)
	return result
end

function TSM:GetMarketValue(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	if not TSM.data[itemID].marketValue or TSM.data[itemID].marketValue == 0 then
		TSM.data[itemID].marketValue = TSM.Data:GetMarketValue(TSM.data[itemID].scans)
	end
	return TSM.data[itemID].marketValue ~= 0 and TSM.data[itemID].marketValue or nil
end

function TSM:GetLastScanTime(itemID)
	TSM:DecodeItemData(itemID)
	return itemID and TSM.data[itemID].lastScan
end

function TSM:GetMinBuyout(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	return TSM.data[itemID].minBuyout
end

function TSM:GetPredictedPrice(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	local scans = TSM.data[itemID].scans
	if not scans then return end
	local _, predicted = TSM.Data:CalculateTrend(scans)
	return predicted and predicted > 0 and predicted or nil
end

function TSM:GetTrendValue(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	local scans = TSM.data[itemID].scans
	if not scans then return end
	local slope = TSM.Data:CalculateTrend(scans)
	-- Return slope as absolute copper value (positive = rising, but price sources must be > 0)
	if not slope then return end
	-- Return the market value adjusted by the daily trend direction
	local marketValue = TSM.data[itemID].marketValue or 0
	if marketValue == 0 then return end
	-- Encode as: marketValue + slope (clamped to > 0)
	return max(1, floor(marketValue + slope + 0.5))
end

function TSM:GetVolatilityValue(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	local scans = TSM.data[itemID].scans
	if not scans then return end
	local volatility = TSM.Data:CalculateVolatility(scans)
	-- Return as copper value so it works in price source system (1 = 1% CV)
	return volatility and volatility > 0 and volatility or nil
end

function TSM:GetConfidenceValue(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	local scans = TSM.data[itemID].scans
	if not scans then return end
	local confidence = TSM.Data:CalculateConfidence(scans, TSM.data[itemID].lastScan)
	-- Return as copper value so it works in price source system (1 = 1%)
	return confidence and confidence > 0 and confidence or nil
end

function TSM:GetWeekdayValue(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	local scans = TSM.data[itemID].scans
	if not scans then return end
	local weekdayAvg = TSM.Data:GetWeekdayPrice(scans)
	return weekdayAvg and weekdayAvg > 0 and weekdayAvg or nil
end

function TSM:GetSmartPriceValue(itemID)
	if itemID and not tonumber(itemID) then
		itemID = TSMAPI:GetItemID(itemID)
	end
	if not itemID or not TSM.data[itemID] then return end
	TSM:DecodeItemData(itemID)
	local scans = TSM.data[itemID].scans
	local mv = TSM.data[itemID].marketValue
	if not scans or not mv or mv == 0 then return end
	local smartPrice = TSM.Data:CalculateSmartPrice(scans, TSM.data[itemID].lastScan, mv)
	return smartPrice and smartPrice > 0 and smartPrice or nil
end