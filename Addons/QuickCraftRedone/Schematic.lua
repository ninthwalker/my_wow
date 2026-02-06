local _, ns = ...

local Util = ns.Util

local Schematic = {}
Schematic.__index = Schematic

function Schematic.__eq(a, b)
    if a == nil or b == nil then
        return false
    end

    return a.recipeID == b.recipeID
       and a.applyConcentration == b.applyConcentration
       and a.salvage == b.salvage
       and a.enchant == b.enchant
end

-- helper functions
local function dumpTable(t, indent)
    indent = indent or ""
    if type(t) ~= "table" then
        print(indent, tostring(t))
        return
    end
    for k, v in pairs(t) do
        if type(v) == "table" then
            print(indent .. tostring(k) .. " = table:")
            dumpTable(v, indent .. "  ")
        else
            print(indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

function Schematic:CanApplyConcentration(craftingReagents)
    -- Only relevant if this saved craft wants to apply concentration
    if not self.applyConcentration then
        return true, 0, 0
    end
    
    -- Get current conc
    local skillLineID = C_TradeSkillUI.GetProfessionChildSkillLineID()
    local currencyID = C_TradeSkillUI.GetConcentrationCurrencyID(skillLineID)
    local currentConcInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
	if not currencyID then
        -- try crafting anyways. Fail true
        Util:Debug("Cannot determine current concentration, will try and craft anyways", self.recipe)
        return true, 0, 0
    end

    local currentConcentration = currentConcInfo.quantity or 0

    -- Ask Blizzard how much concentration THIS craft would consume
    local operationInfo = C_TradeSkillUI.GetCraftingOperationInfo(
        self.recipe,
        craftingReagents or {},
        nil,    -- allocationItemGUID
        false   -- applyConcentration (must be boolean) and always set to fale, true makes it fail and makes sense since applying conc doesn't change the required amount.
    )

    -- or 0 to have things fail true and try and craft anyways if concentration info can't be found
    local requiredConcentration = operationInfo and operationInfo.concentrationCost or 0

    Util:Debug(
        "recipeID =", self.recipe,
        "current conc=", currentConcentration,
        "required conc=", requiredConcentration
    )
    if currentConcentration < requiredConcentration then
        return false, currentConcentration, requiredConcentration
    end

    return true, currentConcentration, requiredConcentration
end

function Schematic:ConvertQuickCraftReagents()
    local craftingReagentInfoTbl = {}

    -- Get Blizzard’s official recipe schematic
    local schematic = C_TradeSkillUI.GetRecipeSchematic(self.spell, false)
    if not schematic or not schematic.reagentSlotSchematics then
        return craftingReagentInfoTbl
    end

    -- Get saved DB reagents for this spell
    local savedReagents = {}
    local dbEntry = QuickCraftPerCharacterDB.schematics[self.spell]
    if dbEntry and dbEntry.reagents then
        savedReagents = dbEntry.reagents
    end

    -- Build valid crafting table (making sure not to include reagents which only have one available option)
    for _, r in ipairs(savedReagents) do
        local slotSchematicFull = schematic.reagentSlotSchematics[r.s]

        -- Skip if slot has only one possible reagent
        local numReagents = 0
        if slotSchematicFull and slotSchematicFull.reagents then
            for _ in pairs(slotSchematicFull.reagents) do
                numReagents = numReagents + 1
            end
        end

        if slotSchematicFull and slotSchematicFull.required and numReagents == 1 then
            Util:Debug("Skipping single-option required reagent for crafting table:", r.item)
        else
            table.insert(craftingReagentInfoTbl, {
                quantity = r.q,
                dataSlotIndex = r.i,
                reagent = {
                    itemID = r.item,
                    currencyID = r.currencyID or nil
                }
            })
        end
    end

    return craftingReagentInfoTbl
end

-- main functions
function Schematic:Create(recipeSpellID, savedReagents, enchantItem, salvageItem, applyConcentration)
    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, false)
    local o = {}
    o.reagents = {}

    for _, r in ipairs(savedReagents or {}) do
        if r.item and r.q then
            table.insert(o.reagents, {
                i = r.i,
				s = r.s,
                item = r.item,
                q = r.q
            })
        else
            Util:Debug("Skipping invalid saved reagent", recipeSchematic.name, recipeSpellID, r)
        end
    end

    if enchantItem then
        o.enchant = C_Item.GetItemGUID(enchantItem)
    end
    if salvageItem then
        o.salvage = C_Item.GetItemGUID(salvageItem)
    end

    o.applyConcentration = applyConcentration and true or false
    o.recipe = recipeSchematic.recipeID
    o.spell = recipeSpellID
    o.recipeName = recipeSchematic.name
    o.updatedAt = GetServerTime()
    setmetatable(o, self)
    return o
end

function Schematic:GetTargetItemLocation()
	local target = self.salvage or self.enchant
	if target == nil then
		return
	end

	local item = Item:CreateFromItemGUID(target)
	if item:HasItemLocation() then
		return item:GetItemLocation()
	end

	for _, target in ipairs(C_TradeSkillUI.GetCraftingTargetItems({ C_Item.GetItemIDByGUID(target) })) do
		local location = C_Item.GetItemLocation(target.itemGUID)

		if location and location:IsBagAndSlot() then
			return location
		end
	end

	Util:Debug("Cannot find any valid target", self.recipe)
end

function Schematic:Craft(numCasts)
    local recipeLink = C_TradeSkillUI.GetRecipeLink(self.spell)

    -- Convert your QuickCraft style reagents to Blizzard-valid table
    local craftingReagentInfoTbl = self:ConvertQuickCraftReagents()
    local location = self:GetTargetItemLocation()
    
    -- concentrationtion check
    local applyConcentration = self.applyConcentration and true or false
    local hasEnoughConc, currentConc, requiredConc = self:CanApplyConcentration(craftingReagentInfoTbl)

    if not hasEnoughConc then
        print("|cffff0000Can't craft:", recipeLink, "- Insufficient concentration!|r")
        print("|cffffff00Current Concentration:", currentConc .. "|r")
        print("|cffffff00Required Concentration:", requiredConc .. "|r")
        return
    end

    -- notify
    if numCasts == 1 then
        print("|cffffff00Beginning", numCasts, "craft:", recipeLink, "(" .. self.spell .. ")|r")
    else
        print("|cffffff00Beginning", numCasts, "crafts:", recipeLink, "(" .. self.spell .. ")|r")
    end

    -- craft
    if self.enchant and location then
        C_TradeSkillUI.CraftEnchant(self.spell, numCasts, craftingReagentInfoTbl, location, applyConcentration)
    elseif self.salvage and location then
        C_TradeSkillUI.CraftSalvage(self.spell, numCasts, location)
    else
        -- enable for very verbose debugging
		-- print("dumping table:")
		-- dumpTable(craftingReagentInfoTbl)
        C_TradeSkillUI.CraftRecipe(self.spell, numCasts, craftingReagentInfoTbl, nil, nil, applyConcentration)
    end
end

local allocated = nil
function Schematic:Allocate()
    local schematicForm = ProfessionsFrame.CraftingPage.SchematicForm
    local transaction = schematicForm:GetTransaction()
    if not transaction then return end

    if allocated == transaction then return end
    local applyConcentration = self.applyConcentration and true or false
    local recipeLink = C_TradeSkillUI.GetRecipeLink(self.spell)

    -- set vars to use for output
    local allocateGood = true
    local allocateOccured = false
    local allocateReagent = false
    local allocateSalvage = false
    local allocateEnchant = false

    -- Allocate salvage
    if self.salvage then
        local item = Item:CreateFromItemGUID(self.salvage)
        if item:GetItemID() then
            transaction:SetSalvageAllocation(item)
            if schematicForm.salvageSlot and schematicForm.salvageSlot.SetItem then
                schematicForm.salvageSlot:SetItem(item)
                transaction:SetApplyConcentration(applyConcentration)
                allocateOccured = true
                allocateSalvage = true
            end
        end
    end

    -- Allocate enchant
    if self.enchant then
        local item = Item:CreateFromItemGUID(self.enchant)
        if item:GetItemID() then
            transaction:SetEnchantAllocation(item)
            if schematicForm.enchantSlot and schematicForm.enchantSlot.SetItem then
                schematicForm.enchantSlot:SetItem(item)
                transaction:SetApplyConcentration(applyConcentration)
                allocateOccured = true
                allocateEnchant = true
            end
        end
    end

    local indexToSlot = {}
    local finishingSlotMap = {}
    local finishingCounter = 0
    local schematicSlots = transaction:GetRecipeSchematic().reagentSlotSchematics

    -- Map dataSlotIndex to slotIndex and identify finishing slots
    for slotIndex, slotSchematic in ipairs(schematicSlots) do
        if slotSchematic.dataSlotIndex then
            indexToSlot[slotSchematic.dataSlotIndex] = indexToSlot[slotSchematic.dataSlotIndex] or {}
            table.insert(indexToSlot[slotSchematic.dataSlotIndex], slotIndex)
        end

        if slotSchematic.reagentType == Enum.CraftingReagentType.Finishing then
            finishingCounter = finishingCounter + 1
            finishingSlotMap[slotIndex] = finishingCounter
        end

        if slotSchematic.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
            transaction:ClearAllocations(slotIndex)
        end
    end

    for _, reagent in ipairs(self.reagents) do
        allocateReagent = true
        if not reagent.item then
            Util:Debug("Skipping reagent allocation: missing item", self.recipe, reagent.i)
            allocateGood = false
        else
            
            local candidateSlots = indexToSlot[reagent.i] or {}
            local allocatedThisReagent = false

            for _, slot in ipairs(candidateSlots) do
                local slotSchematic = schematicSlots[slot]
                if slotSchematic and slotSchematic.reagents then
                    local allowed = false
                    for _, r in ipairs(slotSchematic.reagents) do
                        if r.itemID == reagent.item then
                            allowed = true
                            break
                        end
                    end

                    if allowed then
                        local alloc = transaction:GetAllocations(slot)
                        if alloc then
                            alloc:Allocate({ itemID = reagent.item }, reagent.q)
                            allocateOccured = true
                            allocatedThisReagent = true
                        end

                        -- Safe UI SetItem for finishing slots
                        -- ui bug, it will allocate finishing reagents, but sometimes not show up in the UI box
                        -- ie: finishing reagent is a concentration reduing item (concentration concentrate).
                        -- but that box wont show it as being aplied, but the correct amount of concentration required will show as correct.
                        local finishingSlot = finishingSlotMap[slot]
                        if finishingSlot then
                            C_Timer.After(0.25, function()
                                local finSlotFrames = schematicForm.reagentSlots
                                if finSlotFrames
                                and finSlotFrames[Enum.CraftingReagentType.Finishing]
                                and finSlotFrames[Enum.CraftingReagentType.Finishing][finishingSlot]
                                and finSlotFrames[Enum.CraftingReagentType.Finishing][finishingSlot].SetItem then

                                    local finItem = Item:CreateFromItemID(reagent.item)
                                    finSlotFrames[Enum.CraftingReagentType.Finishing][finishingSlot]:SetItem(finItem)
                                    Util:Debug("Deferred UI SetItem complete for finishing slot", reagent.item, "finishingSlot", finishingSlot)
                                else
                                    Util:Debug("Finishing slot still not ready after delay", reagent.item, "finishingSlot", finishingSlot)
                                end
                            end)
                        end
                    else
                        Util:Debug("Skipping allocation: item not allowed in slot", reagent.item, "slotIndex", slot)
                    end
                end
            end

            if not allocatedThisReagent then
                Util:Debug("Failed to allocate reagent", reagent.item, "for recipe", self.recipe)
                allocateGood = false
            end
        end
    end

    -- apply concentration if needed, update slots.
    schematicForm:UpdateAllSlots()
    transaction:SetApplyConcentration(applyConcentration)
    transaction:SetManuallyAllocated(true)
    allocated = transaction

    if applyConcentration and not allocated:IsApplyingConcentration() then
        print("|cffff0000Issue applying concentration! You probably don't have enough|r")
    end

    if allocated and allocateGood and allocateOccured then
        if allocateReagent then
            print("|cff00ff00Restored schematic:", recipeLink, "[".. self.recipe .. "]|r")
        elseif allocateSalvage then
            print("|cff00ff00Restored salvage schematic:", recipeLink, "[".. (self.recipe or 0) .. "]|r")
        elseif allocateEnchant then
            print("|cff00ff00Restored enchant schematic:", recipeLink, "[".. (self.recipe or 0) .. "]|r")
        end   
    -- elseif allocateGood == false or allocateOccured == false then
    else
        print("|cffff0000Issue Restoring schematic:", recipeLink, "[".. (self.recipe or 0) .. "]|r")
    end

    -- debug
    local info = C_TradeSkillUI.GetCraftingOperationInfo(
        self.recipe,
        allocated:CreateRegularCurrencyReagentInfoTbl(),
        transaction:GetAllocationItemGUID(),
        false
    )
    --dumpTable(info)
end

ns.Schematic = Schematic
