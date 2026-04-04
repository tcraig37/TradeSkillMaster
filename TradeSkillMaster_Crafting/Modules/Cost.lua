-- ------------------------------------------------------------------------------ --
--                            TradeSkillMaster_Crafting                           --
--            http://www.curse.com/addons/wow/tradeskillmaster_crafting           --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- load the parent file (TSM) into a local variable and register this file as a module
local TSM = select(2, ...)
local Cost = TSM:NewModule("Cost", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_Crafting") -- loads the localization table


local currentVisited = {}
local cache = { time = 0 }

-- Known daily-cooldown spell IDs. GetTradeSkillCooldown() only reports a CD
-- while it is active, so scans that run when the CD is available miss it.
local KNOWN_CD_SPELLS = {
	-- Classic transmutes
	[11479] = true,  -- Transmute: Iron to Gold
	[11480] = true,  -- Transmute: Mithril to Truesilver
	[17187] = true,  -- Transmute: Arcanite
	[25146] = true,  -- Transmute: Elemental Fire
	-- Classic elemental transmutes
	[17559] = true,  -- Transmute: Air to Fire
	[17560] = true,  -- Transmute: Fire to Earth
	[17561] = true,  -- Transmute: Earth to Water
	[17562] = true,  -- Transmute: Water to Air
	[17563] = true,  -- Transmute: Undeath to Water
	[17564] = true,  -- Transmute: Water to Undeath
	[17565] = true,  -- Transmute: Life to Earth
	[17566] = true,  -- Transmute: Earth to Life
	-- TBC primal transmutes
	[28566] = true,  -- Transmute: Primal Air to Fire
	[28567] = true,  -- Transmute: Primal Earth to Water
	[28568] = true,  -- Transmute: Primal Fire to Earth
	[28569] = true,  -- Transmute: Primal Water to Air
	[28580] = true,  -- Transmute: Primal Shadow to Water
	[28581] = true,  -- Transmute: Primal Water to Shadow
	[28582] = true,  -- Transmute: Primal Mana to Fire
	[28583] = true,  -- Transmute: Primal Fire to Mana
	[28584] = true,  -- Transmute: Primal Life to Earth
	[28585] = true,  -- Transmute: Primal Earth to Life
	[29688] = true,  -- Transmute: Primal Might
	-- TBC meta gem transmutes
	[32765] = true,  -- Transmute: Earthstorm Diamond
	[32766] = true,  -- Transmute: Skyfire Diamond
	-- WotLK eternal transmutes
	[53771] = true,  -- Transmute: Eternal Life to Shadow
	[53773] = true,  -- Transmute: Eternal Life to Fire
	[53774] = true,  -- Transmute: Eternal Fire to Water
	[53775] = true,  -- Transmute: Eternal Fire to Life
	[53776] = true,  -- Transmute: Eternal Air to Water
	[53777] = true,  -- Transmute: Eternal Air to Earth
	[53779] = true,  -- Transmute: Eternal Shadow to Earth
	[53780] = true,  -- Transmute: Eternal Shadow to Life
	[53781] = true,  -- Transmute: Eternal Earth to Air
	[53782] = true,  -- Transmute: Eternal Earth to Shadow
	[53783] = true,  -- Transmute: Eternal Water to Air
	[53784] = true,  -- Transmute: Eternal Water to Fire
	[54020] = true,  -- Transmute: Eternal Might
	-- WotLK meta gem transmutes
	[57425] = true,  -- Transmute: Skyflare Diamond
	[57427] = true,  -- Transmute: Earthsiege Diamond
	-- WotLK misc transmutes
	[60350] = true,  -- Transmute: Titanium
	-- WotLK epic gem transmutes
	[66658] = true,  -- Transmute: Ametrine
	[66659] = true,  -- Transmute: Cardinal Ruby
	[66660] = true,  -- Transmute: King's Amber
	[66662] = true,  -- Transmute: Dreadstone
	[66663] = true,  -- Transmute: Majestic Zircon
	[66664] = true,  -- Transmute: Eye of Zul
}

local function HasCooldown(spellID)
	local craft = TSM.db.realm.crafts[spellID]
	return (craft and craft.hasCD) or KNOWN_CD_SPELLS[spellID]
end
function Cost:GetMatCost(itemString)
	local mat = TSM.db.realm.mats[itemString]
	if not mat then return end

	if cache.time < (time() - 1) then
		cache = {}
		cache.time = time()
	end
	if cache[itemString] then return cache[itemString] end

	if currentVisited[itemString] then return end
	currentVisited[itemString] = true
	local cost = TSM:GetCustomPrice(mat.customValue or TSM.db.global.defaultMatCostMethod, itemString)
	currentVisited[itemString] = nil

	cache[itemString] = cost
	return cost
end

-- gets the value of a crafted item
function Cost:GetCraftValue(itemString)
	if type(itemString) == "number" then
		-- we got passed a spell
		if not TSM.db.realm.crafts[itemString] then return end
		itemString = TSM.db.realm.crafts[itemString].itemID
	end
	if type(itemString) ~= "string" then return end
	local operation = TSMAPI:GetItemOperation(itemString, "Crafting")
	TSMAPI:UpdateOperation("Crafting", operation and operation[1])
	operation = operation and TSM.operations[operation[1]]
	local priceMethod = operation and operation.craftPriceMethod or TSM.db.global.defaultCraftPriceMethod
	return TSM:GetCustomPrice(priceMethod, itemString)
end

-- gets the cost to create this craft
function Cost:GetCraftCost(itemID)
	local spellIDs
	if type(itemID) == "string" then
		-- we got passed an item
		spellIDs = TSM.craftReverseLookup[TSMAPI:GetBaseItemstring(itemID)]
	elseif type(itemID) == "number" then
		-- we got passed a spell
		if TSM.db.realm.crafts[itemID] then
			spellIDs = { itemID }
		end
	end
	if not spellIDs or #spellIDs == 0 then return end

	local lowestCost
	for _, spellID in ipairs(spellIDs) do
		local craft = TSM.db.realm.crafts[spellID]
		local cost, costIsValid = 0, true
		if #spellIDs >= 2 and TSM.db.global.ignoreCDCraftCost and HasCooldown(spellID) then
			costIsValid = false
		end
		for matID, matQuantity in pairs(craft.mats) do
		
			local MatName = GetItemInfo(matID)
			if MatName ~= nil and strfind(MatName, "Vellum") then			
				local NewItemString = CheapestVellum(matID)
				if matID ~= NewItemString then
					matID = NewItemString
				end
			end
			local matCost = Cost:GetMatCost(matID)
			if not matCost or matCost == 0 then
				costIsValid = false
				break
			end
			cost = cost + matQuantity * matCost
		end
		cost = floor(cost / (craft.numResult) + 0.5) --rounds to nearest gold

		if costIsValid then
			if not lowestCost or cost < lowestCost then
				lowestCost = cost
			end
		end
	end

	return lowestCost
end

-- calulates the cost, buyout, and profit for a crafted item
function Cost:GetCraftPrices(itemID)
	if not itemID then return end

	local cost, buyout, profit
	cost = Cost:GetCraftCost(itemID)
	buyout = Cost:GetCraftValue(itemID)

	if cost and buyout then
		profit = floor(buyout - buyout * TSM.db.global.profitPercent - cost + 0.5)
	end

	return cost, buyout, profit
end

-- gets the spellID, cost, buyout, and profit for the cheapest way to craft the given item
function Cost:GetLowestCraftPrices(itemString, intermediate)
	local spellIDs = TSM.craftReverseLookup[itemString]
	if not spellIDs then return end
	local lowestCost, cheapestSpellID
	local soh = "item:76061:0:0:0:0:0:0" -- Spirit of Harmony
	local hasValidSpell
	for _, spellID in ipairs(spellIDs) do
		if TSM.db.realm.crafts[spellID] then
			if not (intermediate and (TSM.db.realm.crafts[spellID].mats[soh] or HasCooldown(spellID))) then
				hasValidSpell = true
				local cost = Cost:GetCraftCost(spellID)
				if cost and (not lowestCost or cost < lowestCost) then
					-- exclude spells with cooldown if option to ignore is enabled or more than one way to craft and not soulbound e.g. BoE
					if not TSM.db.global.ignoreCDCraftCost then
						if HasCooldown(spellID) then
							if TSMAPI.SOULBOUND_MATS[itemString] or #spellIDs == 1 then
								lowestCost = cost
								cheapestSpellID = spellID
							end
						else
							lowestCost = cost
							cheapestSpellID = spellID
						end
					elseif not HasCooldown(spellID) then
						lowestCost = cost
						cheapestSpellID = spellID
					end
				end
			end --exclude spells using SOH or with cooldown from intermediate crafts
		end
	end

	if intermediate and not hasValidSpell then return end

	if not lowestCost or not cheapestSpellID then return end
	local profit, buyout
	buyout = Cost:GetCraftValue(itemString)
	if buyout then
		profit = floor(buyout - buyout * TSM.db.global.profitPercent - lowestCost + 0.5)
	end

	return cheapestSpellID, lowestCost, buyout, profit
end
