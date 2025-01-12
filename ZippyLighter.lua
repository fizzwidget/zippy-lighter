------------------------------------------------------
-- ZippyLighter.lua
------------------------------------------------------
local addonName, addonTable = ...

local BASIC_FIRE_SPELL_ID = 818
local COOKING_SKILL_ID = 185

FZL_PetSpecies = {
    -- 474, -- Cheetah Cub, testing
    297,    -- Lil' Ragnaros
    1204,    -- Pierre
}

FZL_Toys = {
    -- 34686,    -- Brazier of Dancing Flames, testing
    70722,    -- Little Wickerman
    67097,    -- Grim Campfire
    104309, -- Eternal Kiln
    116757, -- Steamworks Sausage Grill
}

function FZL_OnEvent(self, event, ...)

    if (event == "TRADE_SKILL_SHOW" or event == "PLAYER_REGEN_ENABLED") then

        if (InCombatLockdown()) then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")

        local skillID = C_TradeSkillUI.GetTradeSkillLine()
        if (skillID == COOKING_SKILL_ID) then
            if (not FZL_FireButton) then
                FZL_CreateFireButton()
            end
            local method = FZL_CookingMethod
            if (method == nil) then
                method = FZL_DetectMethod()
            end
            FZL_SetupFireButton(method)
            FZL_FireButton:Show()
        elseif (FZL_FireButton) then
            FZL_FireButton:Hide()
        end

    elseif (event == "MODIFIER_STATE_CHANGED") then

        if (FZL_FireButton and IsAltKeyDown() and FZL_HasOtherCookingMethods()) then
            if (FZL_FireButton and FZL_FireButton:IsMouseOver()) then
                FZL_ShowFlyout()
            end
        elseif (FZL_FlyoutFrame) then
            FZL_FlyoutFrame:Hide()
        end

    elseif (event == "SPELL_UPDATE_COOLDOWN" and FZL_FireButton) then

        local kind, id = strsplit(":", FZL_FireButton.info)
        local start, duration, enable
        if (kind == "spell") then
            start, duration, enable = GetSpellCooldown(id)
            CooldownFrame_Set(FZL_FireButtonCooldown, start, duration, enable)
        elseif (kind == "item") then
            start, duration, enable = GetItemCooldown(id)
            CooldownFrame_Set(FZL_FireButtonCooldown, start, duration, enable)
        end

    elseif (event == "SPELL_UPDATE_USABLE" and FZL_FireButton) then

        local kind, id = strsplit(":", FZL_FireButton.info)
        if (kind == "item") then
            -- assume usable because there's not a container item info that says otherwise
            FZL_FireButtonIcon:SetVertexColor(1, 1, 1)
        elseif (kind == "spell") then
            local isUsable, notEnoughMana = IsUsableSpell(id)
            if (not isUsable) then
                FZL_FireButtonIcon:SetVertexColor(0.4, 0.4, 0.4)
            elseif (notEnoughMana) then
                -- not sure this ever happens for fire, but we'll keep the pattern just in case
                FZL_FireButtonIcon:SetVertexColor(0.5, 0.5, 0.1)
            else
                FZL_FireButtonIcon:SetVertexColor(1, 1, 1)
            end
        end
    end

end

------------------------------------------------------
-- Cooking Fire button
------------------------------------------------------

function FZL_FireButton_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local kind, id, name = strsplit(":", FZL_FireButton.info)
    if (kind == "macro") then
        GameTooltip:SetText(name, 1,1,1)
        GameTooltip:AddLine(format(BATTLE_PET_TOOLTIP_SUMMON, name), nil,nil,nil, true)
    else
        GameTooltip:SetHyperlink(self.info)
    end
    GameTooltip:AddLine(" ")

    local c = GRAY_FONT_COLOR
    local title = GetAddOnMetadata(addonName, "Title")
    local version = GetAddOnMetadata(addonName, "Version")

    GameTooltip:AddDoubleLine(title, string.format("v%s", version), c.r, c.g, c.b, c.r, c.g, c.b)

    if (FZL_HasOtherCookingMethods()) then
        local keyText = _G[GetModifiedClick("SHOWITEMFLYOUT").."_KEY"]
        GameTooltip:AddLine(string.format(FZL_CONFIG_INFO, keyText), c.r, c.g, c.b)
    end
    GameTooltip:Show()

    if (IsModifiedClick("SHOWITEMFLYOUT")) then
        FZL_ShowFlyout()
    end
end

function FZL_CreateFireButton()
    FZL_FireButton = CreateFrame("Button", "FZL_FireButton", TradeSkillFrame, "SpellBookSkillLineTabTemplate,SecureActionButtonTemplate")

    FZL_FireButton:SetPoint("TOPLEFT", TradeSkillFrame, "TOPRIGHT", 0, -65)

    FZL_FireButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    FZL_FireButton:CreateTexture("FZL_FireButtonIcon", "ARTWORK")
    FZL_FireButtonIcon:SetAllPoints(FZL_FireButton:GetNormalTexture())
    FZL_FireButtonCooldown = CreateFrame("Cooldown", "FZL_FireButtonCooldown", FZL_FireButton, "CooldownFrameTemplate")
    FZL_FireButtonCooldown:SetAllPoints(FZL_FireButton:GetNormalTexture())

    FZL_FireButton:SetScript("OnEnter", FZL_FireButton_OnEnter)
end

function FZL_SetupFireButton(method)
    local kind, id, name, icon = strsplit(":", method)
    if (kind == "spell") then
        name, _, icon = GetSpellInfo(id)
        FZL_FireButton:SetAttribute("type", "spell")
        FZL_FireButton:SetAttribute("spell", name)
        FZL_FireButtonCooldown:Show()
    elseif (kind == "item") then    -- item
        FZL_FireButton:SetAttribute("type", "macro")
        FZL_FireButton:SetAttribute("macrotext", "/usetoy "..name)
        FZL_FireButtonCooldown:Show()
    else
        FZL_FireButton:SetAttribute("type", "macro")
        FZL_FireButton:SetAttribute("macrotext", "/summonpet "..name)
        FZL_FireButtonCooldown:Hide()
    end
    FZL_FireButtonIcon:SetTexture(icon)
    FZL_FireButton.info = method
end

------------------------------------------------------
-- choose cooking fire flyout
------------------------------------------------------

function FZL_FlyoutButton_OnClick(self)
    FZL_FlyoutFrame:Hide()
    FZL_CookingMethod = self.info
    local method = FZL_CookingMethod
    if (method == nil) then
        method = FZL_DetectMethod()
    end
    FZL_SetupFireButton(method)
end

function FZL_FlyoutButton_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if (self.info) then
        local kind, id, name = strsplit(":", self.info)
        if (kind == "macro") then
            GameTooltip:SetText(name, 1,1,1)
            GameTooltip:AddLine(format(BATTLE_PET_TOOLTIP_SUMMON, name), nil,nil,nil, true)
        else
            GameTooltip:SetHyperlink(self.info)
        end
    else
        GameTooltip:SetText(FZL_AUTO_DETECT)
    end
    GameTooltip:Show()
end

function FZL_SetupFlyoutButton(index, method)
    local button = _G["FZL_FlyoutButton"..index]
    if (button == nil) then
        button = CreateFrame("Button", "FZL_FlyoutButton"..index, FZL_FlyoutFrame, "ActionButtonTemplate")
        button:SetWidth(32)
        button:SetHeight(32)
        button:SetNormalTexture(nil)
        button:SetScript("OnClick", FZL_FlyoutButton_OnClick)
        button:SetScript("OnEnter", FZL_FlyoutButton_OnEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)

        local lastButton = _G["FZL_FlyoutButton"..(index - 1)]
        if (lastButton) then
            button:SetPoint("LEFT", lastButton, "RIGHT")
        else
            button:SetPoint("LEFT", FZL_FlyoutFrame, "LEFT")
        end
    end
    local kind, id, name, icon
    if (method) then
        kind, id, name, icon = strsplit(":", method)
    end
    if (kind == "spell") then
        _, _, icon = GetSpellInfo(id)
    elseif (kind ~= "macro" and kind ~= "item") then
        icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    local buttonIcon = _G["FZL_FlyoutButton"..index.."Icon"]
    buttonIcon:SetTexture(icon)
    button.info = method
end

function FZL_ShowFlyout()

    if (FZL_FlyoutFrame == nil) then
        FZL_FlyoutFrame = CreateFrame("Button", "FZL_FlyoutFrame", FZL_FireButton)
        FZL_FlyoutFrame:SetPoint("LEFT", FZL_FireButton, "RIGHT")
        FZL_FlyoutFrame:SetHeight(32)
    end
    local buttonIndex = 1

    for toyIndex = 1, #FZL_Toys do
        local toyItemID = FZL_Toys[toyIndex]
        if (PlayerHasToy(toyItemID)) then
            local _, toyName, icon = C_ToyBox.GetToyInfo(toyItemID)
            FZL_SetupFlyoutButton(buttonIndex, strjoin(":", "item", toyItemID, toyName, icon))
            buttonIndex = buttonIndex + 1
        end
    end

    for petIndex = 1, #FZL_PetSpecies do
        local petSpeciesID = FZL_PetSpecies[petIndex]
        local petID, name, icon = FZL_PetInfoForSpeciesID(petSpeciesID)
        if (petID) then
            FZL_SetupFlyoutButton(buttonIndex, strjoin(":", "macro", petID, name, icon))
            buttonIndex = buttonIndex + 1
        end
    end

    FZL_SetupFlyoutButton(buttonIndex, "spell:"..BASIC_FIRE_SPELL_ID)
    buttonIndex = buttonIndex + 1

    FZL_SetupFlyoutButton(buttonIndex, nil);    -- default (auto select)

    FZL_FlyoutFrame:SetWidth(32 * buttonIndex)
    FZL_FlyoutFrame:Show()

end

------------------------------------------------------
-- utility functions
------------------------------------------------------

function FZL_PetInfoForSpeciesID(queryID)
    local isWild = false
    for index = 1, C_PetJournal.GetNumPets(isWild) do
        local petID, speciesID, owned, customName, _, _, _, speciesName, icon = C_PetJournal.GetPetInfoByIndex(index, isWild)
        if (speciesID == queryID and owned) then
            return petID, customName or speciesName, icon
        end
    end
end

function FZL_HasOtherCookingMethods()
    return FZL_DetectMethod() ~= "spell:"..BASIC_FIRE_SPELL_ID
end

function FZL_DetectMethod()

    for toyIndex = 1, #FZL_Toys do
        local toyItemID = FZL_Toys[toyIndex]
        if (PlayerHasToy(toyItemID)) then
            local _, toyName, icon = C_ToyBox.GetToyInfo(toyItemID)
            return strjoin(":", "item", toyItemID, toyName, icon)
        end
    end

    for petIndex = 1, #FZL_PetSpecies do
        local petSpeciesID = FZL_PetSpecies[petIndex]
        local petID, name, icon = FZL_PetInfoForSpeciesID(petSpeciesID)
        if (petID) then
            return strjoin(":", "macro", petID, name, icon)
        end
    end

    return "spell:"..BASIC_FIRE_SPELL_ID;    -- default
end

------------------------------------------------------
-- Run-time loading
------------------------------------------------------

FZL_EventFrame = CreateFrame("Frame", nil, nil)
FZL_EventFrame:SetScript("OnEvent", FZL_OnEvent)
FZL_EventFrame:RegisterEvent("TRADE_SKILL_SHOW")
FZL_EventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
FZL_EventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
FZL_EventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
