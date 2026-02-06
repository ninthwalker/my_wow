local _, ns = ...

local Util = ns.Util

local QuickCraftButtonMixin = {}

function QuickCraftButtonMixin:OnLoad()
	local button = self:GetParent()

	Util:Debug("QuickCraftButtonMixin.OnLoad", button:GetName())

	self:SetAllPoints(button)
	self:SetAlpha(0)
	self:SetScript("OnMouseDown", function(f, key)
		if key == "LeftButton" and not IsAltKeyDown() then
			button:Click()
			return
		end

		if IsAltKeyDown() then
			self:Craft(key == "RightButton")
		end
	end)
	self:SetScript("OnEnter", function(f)
		button:OnEnter()
	end)
	self:SetScript("OnLeave", function(f)
		button:OnLeave()
	end)
	self:Show()
end

function QuickCraftButtonMixin:Craft(isSalvage)
	local schematic = isSalvage and self.lastSalvage or self.lastCraft
	if schematic == nil then
		Util:Message(RED_FONT_COLOR:WrapTextInColorCode("No recipe to QuickCraft - Craft something in Profession page first."))
		return
	end

	if not isSalvage and self.fulfilled ~= self.required then
		Util:Message(RED_FONT_COLOR:WrapTextInColorCode(PROFESSIONS_INSUFFICIENT_REAGENTS))
		return
	end

	local link = C_TradeSkillUI.GetRecipeLink(schematic.recipe)

	Util:Message(ACTION_SPELL_CAST_START .. ": " .. link)
	schematic:Craft()
end

function QuickCraftButtonMixin:AddInstructionsToTooltip(tooltip)
	GameTooltip_AddInstructionLine(tooltip, "<Press ALT to QuickCraft>")
end

function QuickCraftButtonMixin:AddReagentLineToToolTip(tooltip, indent, item, required)
	if not C_Item.IsItemDataCachedByID(item) then
		tooltip:AddLine(indent .. SEARCH_LOADING_TEXT)
		return
	end

	local fulfilled = C_Item.GetItemCount(item, true, true, true, true)
	local _, itemLink, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(item)
	local color = fulfilled >= required and "WHITE_FONT_COLOR" or "RED_FONT_COLOR"

	tooltip:AddDoubleLine(format("%s|T%d:15|t %s", indent, itemTexture, itemLink), format("|cn%s:%d/%d|r", color, fulfilled, required))

	self.required = self.required + 1
	self.fulfilled = self.fulfilled + (fulfilled >= required and 1 or 0)
end

function QuickCraftButtonMixin:AddConcentrationLineToToolTip(tooltip, indent)
	local skillLinesTWW = {
		[171] = 2871, -- Alchemy
		[164] = 2872, -- Blacksmithing
		[333] = 2874, -- Enchanting
		[202] = 2875, -- Engineering
		[773] = 2878, -- Inscription
		[755] = 2879, -- Jewelcrafting
		[165] = 2880, -- Leatherworking
		[197] = 2883, -- Tailoring
	}

	if self.concentrationCurrency == nil then
		local currencyID = C_TradeSkillUI.GetConcentrationCurrencyID(skillLinesTWW[self.skillLine])

		if not currencyID then
			tooltip:AddLine(indent .. SEARCH_LOADING_TEXT)
			return
		end

		self.concentrationCurrency = currencyID
	end

	local currency = C_CurrencyInfo.GetCurrencyInfo(self.concentrationCurrency)
	if not currency then
		tooltip:AddLine(indent .. SEARCH_LOADING_TEXT)
		return
	end

	local fulfilled = currency.quantity >= self.lastCraft.concentration

	tooltip:AddDoubleLine(
		format("%s|T%d:15|t %s", indent, currency.iconFileID, currency.name),
		format("|cn%s:%d/%d|r", fulfilled and "WHITE_FONT_COLOR" or "RED_FONT_COLOR", currency.quantity, self.lastCraft.concentration)
	)

	self.required = self.required + 1
	self.fulfilled = self.fulfilled + (fulfilled and 1 or 0)
end

function QuickCraftButtonMixin:AddCraftDetailsToTooltip(tooltip)
	if self.lastCraft == nil then
		tooltip:AddLine("|cnRED_FONT_COLOR:No recipe to QuickCraft|r")
		return
	end

	local indent = " "

	local schematic = C_TradeSkillUI.GetRecipeSchematic(self.lastCraft.spell, false)
	local recipeName = format("|cnWHITE_FONT_COLOR:%s|r", schematic.name)

	tooltip:AddLine(" ")
	tooltip:AddDoubleLine("Last recipe crafted:", recipeName)
	tooltip:AddLine(format("%s|cnLIGHTBLUE_FONT_COLOR:%s:|r", indent, PROFESSIONS_COLUMN_HEADER_REAGENTS))

	self.fulfilled = 0
	self.required = 0
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.dataSlotType == Enum.TradeskillSlotDataType.Reagent then
			self:AddReagentLineToToolTip(tooltip, indent, slot.reagents[1].itemID, slot.quantityRequired)
		elseif slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
			for _, reagent in ipairs(self.lastCraft.reagents) do
				if reagent.i == slot.dataSlotIndex then
					self:AddReagentLineToToolTip(tooltip, indent, reagent.item, reagent.v)
				end
			end
		end
	end
	self:AddConcentrationLineToToolTip(tooltip, indent)

	tooltip:AddLine(" ")
	if self.fulfilled == self.required then
		GameTooltip_AddInstructionLine(tooltip, "Press |A:NPE_LeftClick:16:16|a to craft last recipe " .. recipeName)
	else
		tooltip:AddLine(format("|cnRED_FONT_COLOR:%s|r", PROFESSIONS_INSUFFICIENT_REAGENTS))
	end
end

function QuickCraftButtonMixin:UpdateTooltip(tooltip)
	if IsAltKeyDown() then
		self:AddCraftDetailsToTooltip(tooltip)
	elseif not IsModifierKeyDown() then
		self:AddInstructionsToTooltip(tooltip)
	end
end

ns.QuickCraftButtonMixin = QuickCraftButtonMixin
