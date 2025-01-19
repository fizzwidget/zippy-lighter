------------------------------------------------------
-- Addon loading & shared infrastructure
------------------------------------------------------
local addonName, T = ...
_G[addonName] = T

T.Title = C_AddOns.GetAddOnMetadata(addonName, "Title")
T.Version = C_AddOns.GetAddOnMetadata(addonName, "Version")

-- event handling
T.EventFrame = CreateFrame("Frame")
T.EventFrame:SetScript("OnEvent", function(self, event, ...)
    local handler = T.EventHandlers[event]
    assert(handler, "Missing event handler for registered event "..event)
    handler(T.EventHandlers, ...)
end)
T.EventHandlers = setmetatable({}, {__newindex = function(table, key, value)
    assert(type(value) == 'function', "Members of this table must be functions")
    rawset(table, key, value)
    T.EventFrame:RegisterEvent(key)
end })
local Events = T.EventHandlers

------------------------------------------------------
-- Constants
------------------------------------------------------

local COOKING_SKILL_ID = 185
local BASIC_FIRE_SPELL_ID = 818
local BASIC_FIRE_SPELL = "spell:"..BASIC_FIRE_SPELL_ID

FZL_PetSpecies = {
    -- 474,   -- Cheetah Cub (for testing)
    297,      -- Lil' Ragnaros
    1204,     -- Pierre
}

FZL_Toys = {
    -- 34686, -- Brazier of Dancing Flames (for testing)
    70722,    -- Little Wickerman
    67097,    -- Grim Campfire
    104309,   -- Eternal Kiln
    116757,   -- Steamworks Sausage Grill
}

------------------------------------------------------
-- Events
------------------------------------------------------

function Events:TRADE_SKILL_LIST_UPDATE(...)
    -- defer update if in combat
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    T:UpdateFireButton()
end

function Events:PLAYER_REGEN_ENABLED(...)
    -- update may be deferred to after combat ends
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    T:UpdateFireButton()
end
T.EventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") -- register on InCombatLockdown

function Events:MODIFIER_STATE_CHANGED(...)
    
    if not FZL_FireButton then return; end

    -- show/hide flyout frame with alt key    
    if IsModifiedClick("SHOWITEMFLYOUT") and T:DefaultCookingMethod() ~= nil then
        if FZL_FireButton:IsMouseOver() then
            T:ShowFlyout()
        end
    elseif FZL_FlyoutFrame then
        FZL_FlyoutFrame:Hide()
    end
end

function Events:SPELL_UPDATE_COOLDOWN(...)
    
    if not FZL_FireButton then return; end

    -- update cooldown indicator on fire button
    local kind, id = strsplit(":", FZL_FireButton.info)
    local start, duration, enable
    if kind == "spell" then
        start, duration, enable = C_Spell.GetSpellCooldown(id)
        CooldownFrame_Set(FZL_FireButtonCooldown, start, duration, enable)
    elseif kind == "item" then
        start, duration, enable = C_Item.GetItemCooldown(id)
        CooldownFrame_Set(FZL_FireButtonCooldown, start, duration, enable)
    end
end

function Events:SPELL_UPDATE_USABLE(...)
    
    if not FZL_FireButton then return; end

    -- update fire button for spell ready or not
    local kind, id = strsplit(":", FZL_FireButton.info)
    if kind == "item" then
        -- assume usable because there's not a container item info that says otherwise
        FZL_FireButtonIcon:SetVertexColor(1, 1, 1)
    elseif kind == "spell" then
        local isUsable, notEnoughMana = C_Spell.IsSpellUsable(id)
        if not isUsable then
            FZL_FireButtonIcon:SetVertexColor(0.4, 0.4, 0.4)
        elseif notEnoughMana then
            -- not sure this ever happens for fire, but we'll keep the pattern just in case
            FZL_FireButtonIcon:SetVertexColor(0.5, 0.5, 0.1)
        else
            FZL_FireButtonIcon:SetVertexColor(1, 1, 1)
        end
    end
end

------------------------------------------------------
-- Cooking Fire button
------------------------------------------------------

local FireButtonMixin = {} -- not a real Mixin, just copying some functions

function FireButtonMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local kind, id, name = strsplit(":", FZL_FireButton.info)
    if kind == "macro" then
        GameTooltip:SetText(name, 1,1,1)
        GameTooltip:AddLine(format(BATTLE_PET_TOOLTIP_SUMMON, name), nil,nil,nil, true)
    else
        GameTooltip:SetHyperlink(self.info)
    end
    GameTooltip:AddLine(" ")

    local c = GRAY_FONT_COLOR
    GameTooltip:AddDoubleLine(T.Title, string.format("v%s", T.Version), c.r, c.g, c.b, c.r, c.g, c.b)

    if T:DefaultCookingMethod() ~= nil then
        local keyText = _G[GetModifiedClick("SHOWITEMFLYOUT").."_KEY"]
        GameTooltip:AddLine(string.format(FZL_CONFIG_INFO, keyText), c.r, c.g, c.b)
    end
    GameTooltip:Show()

    if IsModifiedClick("SHOWITEMFLYOUT") then
        T:ShowFlyout()
    end
end

function T:CreateFireButton()
    local parent = ProfessionsFrame.CraftingPage.SchematicForm
    FZL_FireButton = CreateFrame("Button", "FZL_FireButton", parent, "ActionButtonTemplate,SecureActionButtonTemplate")

    FZL_FireButton:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -5, 5)

    FZL_FireButton:SetScript("OnEnter", FireButtonMixin.OnEnter)
    FZL_FireButton:SetScript("OnLeave", GameTooltip_Hide)

end

function T:UpdateFireButton()    
    local info = C_TradeSkillUI.GetChildProfessionInfo()
    if info.parentProfessionID == COOKING_SKILL_ID then
        if not FZL_FireButton then
            T:CreateFireButton()
        end
        local method = FZL_CookingMethod
        if method == nil then
            method = T:DefaultCookingMethod() or BASIC_FIRE_SPELL
        end
        T:SetupFireButton(method)
        FZL_FireButton:Show()
    elseif FZL_FireButton then
        FZL_FireButton:Hide()
    end
end

function T:SetupFireButton(method)
    local kind, id, name, icon = strsplit(":", method)
    if kind == "spell" then
        local info = C_Spell.GetSpellInfo(id)
        icon = info.iconID
        FZL_FireButton:SetAttribute("type", "spell")
        FZL_FireButton:SetAttribute("spell", info.name)
        FZL_FireButtonCooldown:Show()
    elseif kind == "item" then    -- item
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

local FlyoutButtonMixin = {} -- not a real Mixin, just copying some functions

function FlyoutButtonMixin:OnClick()
    FZL_FlyoutFrame:Hide()
    FZL_CookingMethod = self.info
    local method = FZL_CookingMethod
    if method == nil then
        method = T:DefaultCookingMethod()
    end
    T:SetupFireButton(method)
end

function FlyoutButtonMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if self.info then
        local kind, id, name = strsplit(":", self.info)
        if kind == "macro" then
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

function T:SetupFlyoutButton(index, method)
    local button = _G["FZL_FlyoutButton"..index]
    if button == nil then
        button = CreateFrame("Button", "FZL_FlyoutButton"..index, FZL_FlyoutFrame, "ActionButtonTemplate")
        button:SetFrameStrata("DIALOG")
        button:SetScript("OnClick", FlyoutButtonMixin.OnClick)
        button:SetScript("OnEnter", FlyoutButtonMixin.OnEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)

        local lastButton = _G["FZL_FlyoutButton"..(index - 1)]
        if lastButton then
            button:SetPoint("LEFT", lastButton, "RIGHT")
        else
            button:SetPoint("LEFT", FZL_FlyoutFrame, "LEFT")
        end
    end
    local kind, id, name, icon
    if method then
        kind, id, name, icon = strsplit(":", method)
    end
    if kind == "spell" then
        local info = C_Spell.GetSpellInfo(id)
        icon = info.iconID
    elseif kind ~= "macro" and kind ~= "item" then
        icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    local buttonIcon = _G["FZL_FlyoutButton"..index.."Icon"]
    buttonIcon:SetTexture(icon)
    button.info = method
end

function T:ShowFlyout()

    if FZL_FlyoutFrame == nil then
        FZL_FlyoutFrame = CreateFrame("Button", "FZL_FlyoutFrame", FZL_FireButton)
        FZL_FlyoutFrame:SetPoint("LEFT", FZL_FireButton, "RIGHT")
        FZL_FlyoutFrame:SetHeight(32)
    end
    local buttonIndex = 1

    for _, toyItemID in pairs(FZL_Toys) do
        if PlayerHasToy(toyItemID) then
            local _, toyName, icon = C_ToyBox.GetToyInfo(toyItemID)
            T:SetupFlyoutButton(buttonIndex, strjoin(":", "item", toyItemID, toyName, icon))
            buttonIndex = buttonIndex + 1
        end
    end

    for _, petSpeciesID in pairs(FZL_PetSpecies) do
        local petID, name, icon = T:PetInfoForSpeciesID(petSpeciesID)
        if petID then
            T:SetupFlyoutButton(buttonIndex, strjoin(":", "macro", petID, name, icon))
            buttonIndex = buttonIndex + 1
        end
    end

    T:SetupFlyoutButton(buttonIndex, BASIC_FIRE_SPELL)
    buttonIndex = buttonIndex + 1

    T:SetupFlyoutButton(buttonIndex, nil);    -- default (auto select)

    FZL_FlyoutFrame:SetWidth(32 * buttonIndex)
    FZL_FlyoutFrame:Show()

end

------------------------------------------------------
-- utility functions
------------------------------------------------------

function T:PetInfoForSpeciesID(queryID)
    local isWild = false
    for index = 1, C_PetJournal.GetNumPets(isWild) do
        local petID, speciesID, owned, customName, _, _, _, speciesName, icon = C_PetJournal.GetPetInfoByIndex(index, isWild)
        if speciesID == queryID and owned then
            return petID, customName or speciesName, icon
        end
    end
end

function T:DefaultCookingMethod()

    for _, toyItemID in pairs(FZL_Toys) do
        if PlayerHasToy(toyItemID) then
            local _, toyName, icon = C_ToyBox.GetToyInfo(toyItemID)
            return strjoin(":", "item", toyItemID, toyName, icon)
        end
    end

    for _, petSpeciesID in pairs(FZL_PetSpecies) do
        local petID, name, icon = T:PetInfoForSpeciesID(petSpeciesID)
        if petID then
            return strjoin(":", "macro", petID, name, icon)
        end
    end

    return nil; -- fall back to Basic Fire
end
