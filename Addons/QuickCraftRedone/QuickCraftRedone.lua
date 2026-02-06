local addonName, ns = ...

local Util = ns.Util
local Schematic = ns.Schematic

local QuickCraft = {}

-- use to only save when in-game create/craft button is clicked, not when called from /qc craft cmd
QuickCraft.skipNextSave = false

function QuickCraft:CreateSaveButton()
    if self.saveButton then return end

    local craftingPage = ProfessionsFrame and ProfessionsFrame:IsVisible() and ProfessionsFrame.CraftingPage
	if not craftingPage then return end

    local createButton = craftingPage.CreateButton

    -- Secure button (macro-based)
    local btn = CreateFrame("Button", nil, craftingPage, "SecureActionButtonTemplate, UIPanelButtonTemplate")

    btn:SetSize(createButton:GetSize())
    btn:SetPoint("BOTTOM", createButton, "TOP", 0, 12)
    btn:SetText("Save Recipe")
    btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 11)
    btn:SetAlpha(1)
    btn:Hide()

    ----------------------------------------------------------------
    -- Initial state
    ----------------------------------------------------------------
    btn.isCancelState = false
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "/run ProfessionsFrame.CraftingPage.CreateButton:Click()")

    ----------------------------------------------------------------
    -- State switch: Save - Cancel
    ----------------------------------------------------------------
    btn:HookScript("PostClick", function(self)
        if self.isCancelState then return end

        self.isCancelState = true
        self:SetText("Cancel Craft")
        self:SetAlpha(0.75) -- visual feedback
        self:SetAttribute("macrotext", "/stopcasting")
    end)

    ----------------------------------------------------------------
    -- Reset logic: Cancel - Save (on cast end)
    ----------------------------------------------------------------
    local resetter = CreateFrame("Frame")
    resetter:RegisterEvent("UNIT_SPELLCAST_STOP")
    resetter:RegisterEvent("UNIT_SPELLCAST_FAILED")
    resetter:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    resetter:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

    resetter:SetScript("OnEvent", function(_, _, unit)
        if unit ~= "player" then return end
        if not btn.isCancelState then return end

        btn.isCancelState = false
        btn:SetText("Save Recipe")
        btn:SetAlpha(1)
        btn:SetAttribute("macrotext", "/run ProfessionsFrame.CraftingPage.CreateButton:Click()")

        -- brief disable to prevent spam / double execution
        btn:Disable()
        C_Timer.After(1, function()
            if btn:IsShown() then
                btn:Enable()
            end
        end)
    end)

    ----------------------------------------------------------------
    -- Tooltip
    ----------------------------------------------------------------
    btn:SetScript("OnEnter", function(self)
        local schematicForm = craftingPage.SchematicForm
        local transaction = schematicForm and schematicForm:GetTransaction()
        local recipeID = transaction and transaction:GetRecipeID()
        local createBtn = craftingPage.CreateButton

        if not self:IsEnabled() and createBtn:IsEnabled() == false then
            createBtn:GetScript("OnEnter")(createBtn)
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("QuickCraft")
            if recipeID then
                GameTooltip:AddLine("/qc craft " .. recipeID, 1, 1, 0)
            end
            GameTooltip:AddLine("Save selected reagents for use with QuickCraft",0.7, 0.7, 1)
			GameTooltip:AddLine("Click this 2x in a row", 1, 1, 0)
			GameTooltip:AddLine("Once to start/save craft and then right after to cancel cast", 1, 1, 0)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    ----------------------------------------------------------------
    -- Visibility + enable state sync
    ----------------------------------------------------------------
    craftingPage:HookScript("OnShow", function()
        btn:Show()
    end)

    craftingPage:HookScript("OnHide", function()
        btn:Hide()
    end)

    btn:SetEnabled(createButton:IsEnabled())
    hooksecurefunc(createButton, "SetEnabled", function(_, enabled)
        btn:SetEnabled(enabled)
    end)

    self.saveButton = btn
end

function QuickCraft:Init()
	local professionSpells = Util:GetLearnedProfessionSpells()

	self.buttons = {}
	for spell, skillLine in pairs(professionSpells) do
		local buttons = Util:FindSpellButtons(spell)

		for _, button in ipairs(buttons) do
			self:CreateOverlayButton(button, skillLine)
		end
	end

	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
		local spellID = tooltip:GetPrimaryTooltipData().id

		if not professionSpells[spellID] then
			return
		end

		if tooltip:GetOwner() == nil then
			return
		end

		local button = tooltip:GetOwner().QuickCraftOverlay
		if button == nil then
			return
		end

		button:UpdateTooltip(tooltip)
	end)

	hooksecurefunc(C_TradeSkillUI, "CraftEnchant", function(recipeSpellID, numCasts, craftingReagents, itemTarget, applyConcentration)
		if QuickCraft.skipNextSave then return end
		QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, itemTarget, nil, applyConcentration)
	end)

	hooksecurefunc(C_TradeSkillUI, "CraftSalvage", function(recipeSpellID, numCasts, itemTarget, craftingReagents, applyConcentration)
		if QuickCraft.skipNextSave then return end
		QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, nil, itemTarget, applyConcentration)
	end)

	hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(recipeSpellID, numCasts, craftingReagents, recipeLevel, orderID, applyConcentration)
		if QuickCraft.skipNextSave then return end
		QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, nil, nil, applyConcentration)
	end)
end

function QuickCraft:CreateOverlayButton(button, skillLine)
	if button.QuickCraftOverlay then
		Util:Debug("Error: Button has been initialized", button:GetName())
		return
	end

	local overlay = CreateFrame("Button", nil, button, "UIPanelButtonTemplate")

	overlay.skillLine = skillLine
	overlay.lastCraft = self:GetLastSchematic(skillLine, false)
	overlay.lastSalvage = self:GetLastSchematic(skillLine, true)
	Mixin(overlay, ns.QuickCraftButtonMixin)

	overlay:OnLoad()

	button.QuickCraftOverlay = overlay
	table.insert(self.buttons, overlay)
end

function QuickCraft:SaveSchematic(recipeSpellID, craftingReagents, enchantItem, salvageItem, applyConcentration)
    if ProfessionsFrame == nil or not ProfessionsFrame:IsVisible() then
        Util:Debug("Skip saving schematic: QuickCraft")
        return
    end

    -- Get Blizzard recipe schematic
    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, false)
    if not ProfessionsFrame.CraftingPage.SchematicForm:IsCurrentRecipe(recipeSchematic.recipeID) then
        Util:Debug("Skip saving schematic: no transaction", recipeSpellID)
        return
    end

    local transaction = ProfessionsFrame.CraftingPage.SchematicForm:GetTransaction()
    if not transaction or not transaction.reagentTbls then
        Util:Debug("No transaction reagents found for recipe", recipeSpellID)
        return
    end

    -- Map full schematic slots by slotIndex for easy lookup
    local slotSchematicsBySlotIndex = {}
    for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
        slotSchematicsBySlotIndex[slot.slotIndex] = slot
    end

    local savedReagents = {}

    for _, slotTbl in ipairs(transaction.reagentTbls) do
        local slotIndex = slotTbl.reagentSlotSchematic and slotTbl.reagentSlotSchematic.slotIndex
        local dataSlotIndex = slotTbl.reagentSlotSchematic and slotTbl.reagentSlotSchematic.dataSlotIndex
        local slotSchematicFull = slotSchematicsBySlotIndex[slotIndex]

        if slotTbl.allocations and slotTbl.allocations.allocs then
            for _, alloc in ipairs(slotTbl.allocations.allocs) do
                if alloc.reagent and alloc.reagent.itemID and alloc.quantity then

					table.insert(savedReagents, {
						i = dataSlotIndex,
						s = slotIndex,
						item = alloc.reagent.itemID,
						q = alloc.quantity,
					})

					Util:Debug(
						"Saved reagent:",
						"slotIndex(s) =", slotIndex,
						"dataSlotIndex(i) =", dataSlotIndex,
						"recipeName() =", recipeSchematic.name,
						"itemID(item) =", alloc.reagent.itemID,
						"quantity(q) =", alloc.quantity
					)
                end
            end
        end
    end

    -- Include enchant and salvage items as GUIDs
    local enchantGUID = enchantItem and C_Item.GetItemGUID(enchantItem) or nil
    local salvageGUID = salvageItem and C_Item.GetItemGUID(salvageItem) or nil

    -- Create and save schematic
    local schematic = Schematic:Create(
        recipeSpellID,
        savedReagents,
        enchantItem,
        salvageItem,
        applyConcentration
    )

    self.db.char.schematics[schematic.recipe] = schematic
	self.db.global.schematics[schematic.recipe] = schematic
	local recipeLink = C_TradeSkillUI.GetRecipeLink(schematic.recipe)
    print("|cff00ff00Saved schematic:", recipeLink .." [" .. schematic.recipe .. "] Total reagents:", #savedReagents, "|r")

    self:UpdateLastCraft(schematic.recipe, salvageItem ~= nil)
end

function QuickCraft:UpdateLastCraft(recipeID, isSalvage)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	local lastCraft = isSalvage and self.db.char.lastSalvage or self.db.char.lastCraft
	local skillLine = info.parentProfessionID or info.professionID

	lastCraft[skillLine] = { recipe = recipeID, skillLine = skillLine }
	lastCraft.updatedAt = GetServerTime()

	Util:Debug("Updated last craft:", recipeID, isSalvage, skillLine)
end

function QuickCraft:RestoreSchematic()
	local recipeID = ProfessionsFrame.CraftingPage.SchematicForm:GetTransaction():GetRecipeID()
	local recipeName = C_TradeSkillUI.GetRecipeInfo(recipeID).name
	local schematic = self:GetSchematic(recipeID)

	if schematic == nil then
		Util:Debug("|cffff0000NO Saved schematic:", recipeName, "[" .. recipeID .. "]|r")
		return
	end

	Schematic.Allocate(schematic)
end

function QuickCraft:GetSchematic(recipeID)
	local schematic = self.db.char.schematics[recipeID] or self.db.global.schematics[recipeID]

	if schematic then
		setmetatable(schematic, Schematic)
	end

	return schematic
end

function QuickCraft:GetLastSchematic(skillLine, isSalvage)
	local lastCraft = isSalvage and self.db.char.lastSalvage or self.db.char.lastCraft

	if lastCraft == nil or lastCraft[skillLine] == nil then
		return
	end

	return self:GetSchematic(lastCraft[skillLine].recipe)
end

function QuickCraft:Craft(recipeID, numCasts)
	local schematic = self:GetSchematic(recipeID)
	if not ProfessionsFrame or not ProfessionsFrame:IsShown() then
		print("|cffffff00Open the crafting window first!|r")
		return
	end

	if schematic then
		schematic:Craft(numCasts)
	else
		print("|cffff0000No Saved Craft found for:", recipeID, "|r")
	end
end

function QuickCraft:WipeSavedSchematics()
    QuickCraftRedonePerCharacterDB.schematics = {}
    QuickCraftRedonePerCharacterDB.lastCraft = {}
    QuickCraftRedonePerCharacterDB.lastSalvage = {}

    self.db.char = QuickCraftRedonePerCharacterDB

    print("All saved recipes wiped for this character!")
end

function QuickCraft:ExecuteChatCommands(command)
	if command == "debug" then
		-- Toggle Debug Mode
		self.db.global.debug = not self.db.global.debug
		Util.debug = self.db.global.debug
		print("Debug Mode:", self.db.global.debug)
		return
	end

	if command == "wipe" then
		QuickCraft:WipeSavedSchematics()
		return
	end

	local action, recipe, numCasts =
    	command:match("^(%a+)%s+(%d+)%s*(%d*)$")

	if action == "craft" then
		local recipeID = tonumber(recipe)
		local num = tonumber(numCasts) or 1

		-- makes ure not to save any schematic data when being called from the slash cmd
		QuickCraft.skipNextSave = true

		-- pcall so we caan always return here and reset the skipNextSave back to False
		local success, err = pcall(function()
			QuickCraft:Craft(recipeID, num)
		end)

		QuickCraft.skipNextSave = false

		if not success then
			print("|cffff0000QuickCraft failed for recipe", recipeID, ":", err, "|r")
		end

		return
	end
	
	print("Usage:")
	print("  /qc debug - Turn on/off debugging mode")
	print("  /qc craft <recipeID> <opt: numCrafts> - Craft the recipe with last-used reagents")
	print("  /qc wipe - Clears all saved recipes for this character")
end

if _G["QuickCraft"] == nil then
	_G["QuickCraft"] = QuickCraft

	SLASH_QUICK_CRAFT1 = "/QuickCraft"
	SLASH_QUICK_CRAFT2 = "/qc"
	function SlashCmdList.QUICK_CRAFT(msg, editBox)
		QuickCraft:ExecuteChatCommands(msg)
	end

	local DefaultQuickCraftRedoneDB = { schematics = {}, lastCraft = {}, lastSalvage = {} }

	QuickCraft.frame = CreateFrame("Frame")

	QuickCraft.frame:SetScript("OnEvent", function(self, event, ...)
		QuickCraft.eventsHandler[event](event, ...)
	end)

	function QuickCraft:RegisterEvent(name, handler)
		if self.eventsHandler == nil then
			self.eventsHandler = {}
		end
		self.eventsHandler[name] = handler
		self.frame:RegisterEvent(name)
	end

	function QuickCraft:UnregisterEvent(name)
		self.eventsHandler[name] = nil
		self.frame:UnregisterEvent(name)
	end

	QuickCraft:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, isInitialLogin, isReloadingUi)
		if isInitialLogin == false and isReloadingUi == false then
			return
		end

		QuickCraft:Init()
	end)

	QuickCraft:RegisterEvent("TRADE_SKILL_SHOW", function()
		hooksecurefunc(ProfessionsFrame.CraftingPage.SchematicForm, "Init", function()
			QuickCraft:RestoreSchematic()
		end)

		QuickCraft:CreateSaveButton()

		QuickCraft:UnregisterEvent("TRADE_SKILL_SHOW")
	end)

	QuickCraft:RegisterEvent("ADDON_LOADED", function(event, name)
		if name ~= addonName then
			return
		end

		QuickCraftRedoneDB = QuickCraftRedoneDB or DefaultQuickCraftRedoneDB
		QuickCraftRedonePerCharacterDB = QuickCraftRedonePerCharacterDB or DefaultQuickCraftRedoneDB

		Util.debug = QuickCraftRedoneDB.debug
		QuickCraft.db = { char = QuickCraftRedonePerCharacterDB, global = QuickCraftRedoneDB }
	end)
end
