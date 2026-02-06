-- Initialize saved variables
if not TLDRAutoDB then
    TLDRAutoDB = { enabled = true }
end

-- Slash command
SLASH_TLDRAUTO1 = "/tldrauto"
SlashCmdList["TLDRAUTO"] = function(msg)
    msg = msg:lower():trim()

    if msg == "on" then
        TLDRAutoDB.enabled = true
        print("TLDRAuto: ENABLED")

    elseif msg == "off" then
        TLDRAutoDB.enabled = false
        print("TLDRAuto: DISABLED")

    else
        print("TLDRAuto usage: /tldrauto on | off")
        print("TLDRAuto is currently " .. (TLDRAutoDB.enabled and "ON" or "OFF"))
    end
end

------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADVENTURE_MAP_OPEN")

frame:SetScript("OnEvent", function()
    if not TLDRAutoDB.enabled then
        return
    end

    C_Timer.After(1, function()
        if not TLDRAutoDB.enabled then
            return
        end

        --[[
        if TLDRMissionsFrameCalculateButton
            and TLDRMissionsFrameCalculateButton:IsShown()
            and TLDRMissionsFrameCalculateButton:IsEnabled() then

            TLDRMissionsFrameCalculateButton:Click()
        end
        --]]

        if TLDRMissionsShortcutButton
            and TLDRMissionsShortcutButton:IsShown()
            and TLDRMissionsShortcutButton:IsEnabled() then

            TLDRMissionsShortcutButton:Click()
        end
    end)
end)
