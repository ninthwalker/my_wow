local ADDON_NAME = ...
local frame = CreateFrame("Frame")

local DB = ConcentrationCrafterDB

--------------------------------------------------
-- Init
--------------------------------------------------
local function InitDB()
    ConcentrationCrafterDB = ConcentrationCrafterDB or {}
    DB = ConcentrationCrafterDB
    DB.items_to_deposit = DB.items_to_deposit or {}

    if DB.enabled == nil then
        DB.enabled = true
    end
end

--------------------------------------------------
-- Utility: Find bag slots containing target items
--------------------------------------------------
local function GetBagSlotsForItems()
    local slots = {}

    -- normal bags: backpack + 4 bag slots
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.Bag_4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and DB.items_to_deposit[info.itemID] and not info.isLocked then
                table.insert(slots, {
                    bag = bag,
                    slot = slot,
                    itemID = info.itemID,
                    itemName = DB.items_to_deposit[info.itemID] or GetItemInfo(info.itemID)
                })
            end
        end
    end

    -- reagent bank
    local reagentBag = Enum.BagIndex.ReagentBag
    local numSlots = C_Container.GetContainerNumSlots(reagentBag)
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(reagentBag, slot)
        if info and info.itemID and DB.items_to_deposit[info.itemID] and not info.isLocked then
            table.insert(slots, {
                bag = reagentBag,
                slot = slot,
                itemID = info.itemID,
                itemName = DB.items_to_deposit[info.itemID] or GetItemInfo(info.itemID)
            })
        end
    end

    return slots
end

--------------------------------------------------
-- Deposit logic
--------------------------------------------------
local function DepositToWarbandBank(event)
    if not DB.enabled then return end
    if not C_Bank.CanViewBank(2) then return end -- 2 = warband bank

    local itemXfer = GetBagSlotsForItems()
    if #itemXfer == 0 then
        if event ~= "BAG_UPDATE_DELAYED" then
            print("|cffffff00CC: No items to transfer|r")
        end
        return
    end

    -- find next empty warband bank slot
    local emptySlot = nil
    for warbandBag = Enum.BagIndex.AccountBankTab_1, Enum.BagIndex.AccountBankTab_5 do
        local numSlots = C_Container.GetContainerNumSlots(warbandBag)
        for slot = 1, numSlots do
            local item = C_Container.GetContainerItemID(warbandBag, slot)
            if not item then
                emptySlot = {bag = warbandBag, slot = slot}
                break
            end
        end
        if emptySlot then break end
    end

    if not emptySlot then
        print("|cffff5555CC: Transfer Failed! No empty Warband Bank slots left!|r")
        return
    end

    -- transfer the first item in the list
    local firstItem = itemXfer[1]
    C_Container.PickupContainerItem(firstItem.bag, firstItem.slot)
    C_Container.PickupContainerItem(emptySlot.bag, emptySlot.slot)

    -- print transfer result
    local name = firstItem.itemName or ("ItemID " .. firstItem.itemID)
    print("|cff00ff00CC: Transferred |cffffff00" .. name .. "|cff00ff00 to Warband Bank Tab " .. emptySlot.bag .. " slot " .. emptySlot.slot .. "|r")
end

--------------------------------------------------
-- Crafting
--------------------------------------------------

local function CraftIt(event)
    if not DB.enabled then
        return
    end

    if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
        -- prof frame didn't open
        print("CC: Profession Window not found!")
        return
    end

    if not (CraftSimAPI and CraftSimAPI.GetCraftSim) then
        -- craftsim not found
        print("CC: Craftsim not found!")
        return
    end

    -- root craftsim path
    local rootPath = CraftSimAPI:GetCraftSim().CRAFTQ.frame.content.queueTab.content

    -- clear all
    C_Timer.After(2, function()
         rootPath.clearAllButton.clickCallback()
    end)

    -- wait 2 sec and Queue favorites button
    C_Timer.After(2, function()
         rootPath.queueFavoritesButton.clickCallback()
    end)

    -- wait 15 sec and check if favorite scan is done. if not, wait another 15 sec and check again.
    -- CraftEnchant/CraftRecime are protected and can't be directly called from an addon/script. needs a hardware event
    -- Also cant call another adddons button from my addon
    -- so need to make a macro and do it like this:
    -- if enabled then click:
    -- /run local b=CraftSimAPI:GetCraftSim().CRAFTQ.frame.content.queueTab.content.craftNextButton if b.frame:IsEnabled() then b.clickCallback() else print("Craftsim 'Next Craft' not ready!") end

end

--------------------------------------------------
-- Events
--------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_CLOSE")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
    elseif event == "BANKFRAME_OPENED" then
        C_Timer.After(0.5, function()
            DepositToWarbandBank(event)
        end)
    elseif event == "BAG_UPDATE_DELAYED" then
        C_Timer.After(0.25, function()
            DepositToWarbandBank(event)
        end)
    elseif event == "TRADE_SKILL_SHOW" then
        C_Timer.After(2, function()
            CraftIt(event)
        end)
    end
end)

--------------------------------------------------
-- Slash Command
--------------------------------------------------
SLASH_CONCENTRATIONCRAFTER1 = "/cc"

SLASH_CONCENTRATIONCRAFTER1 = "/cc"

SlashCmdList["CONCENTRATIONCRAFTER"] = function(msg)
    local cmd, param = msg:match("^(%S*)%s*(%S*)$")
    cmd = cmd and cmd:lower()

    if cmd == "on" then
        DB.enabled = true
        print("|cff00ff00Concentration Crafter Enabled|r")

    elseif cmd == "off" then
        DB.enabled = false
        print("|cffff5555Concentration Crafter Disabled|r")

    elseif cmd == "add" and param then
        local itemID = tonumber(param)
        if itemID then
            local itemName = GetItemInfo(itemID)
            if itemName then
                DB.items_to_deposit[itemID] = itemName
                print("|cff00ff00Added |cffffff00" .. itemID .. " - " .. itemName .. "|cff00ff00 to deposit list|r")
            else
                print("|cffff5555ItemID |cffffff00" .. itemID .. " |cffff5555not found!|r")
                print("|cffffff00Please specify a correct itemID|r")
            end
        else
            print("|cffff5555Invalid itemID: " .. param .. "|r")
        end

    elseif cmd == "remove" and param then
        local itemID = tonumber(param)
        if itemID and DB.items_to_deposit[itemID] then
            local itemName = DB.items_to_deposit[itemID]
            DB.items_to_deposit[itemID] = nil
            print("|cff00ff00Removed |cffffff00" .. itemID .. " - " .. itemName .. "|cff00ff00 from deposit list|r")
        else
            print("|cffff5555ItemID |cffffff00" .. (param or "") .. " |cffff5555not found in deposit list!|r")
        end

    elseif cmd == "list" then
        print("|cffffff00Items currently in deposit list:|r")
        local count = 0
        for itemID, itemName in pairs(DB.items_to_deposit) do
            print(" - |cffffff00" .. itemID .. "|r - |cff00ff00" .. itemName .. "|r")
            count = count + 1
        end
        if count == 0 then
            print(" <none>")
        end

    elseif cmd == "" then
        print("Concentration Crafter Status: " .. (DB.enabled and "|cff00ff00Enabled|r" or "|cffff5555Disabled|r"))
        print("Commands: /cc on | off | add <itemID> | remove <itemID> | list")

    else
        print("Usage: /cc on | off | add <itemID> | remove <itemID> | list")
    end
end
