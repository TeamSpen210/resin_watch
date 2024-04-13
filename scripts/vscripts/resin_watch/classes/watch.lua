if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

local RESIN_NOTIFY_HAPTIC_SEQ = HapticSequence(0.12, 0.9, 0.08)

local RESIN_COUNTER_INDEX_0 = 32
local RESIN_COUNTER_INDEX_9 = 41
local RESIN_COUNTER_INDEX_BLANK = 43
local AMMO_COUNTER_INDEX_0 = 16
local AMMO_COUNTER_INDEX_9 = 25
local AMMO_COUNTER_INDEX_BLANK = 27

local SKIN_LEVEL_RESIN_BLANK = 0
local SKIN_LEVEL_RESIN_UP = 1
local SKIN_LEVEL_RESIN_DOWN = 2
local SKIN_LEVEL_AMMO_BLANK = 3
local SKIN_LEVEL_AMMO_UP = 4
local SKIN_LEVEL_AMMO_DOWN = 5

local SKIN_COMPASS_RESIN = 0
local SKIN_COMPASS_RESIN_BLANK = 1
local SKIN_COMPASS_AMMO = 2
local SKIN_COMPASS_AMMO_BLANK = 3

local CLASS_LIST_RESIN = {
    "item_hlvr_crafting_currency_small",
    "item_hlvr_crafting_currency_large"
}

local CLASS_LIST_AMMO = {
    "item_hlvr_clip_energygun",
    "item_hlvr_clip_energygun_multiple",
    "item_hlvr_clip_rapidfire",
    "item_hlvr_clip_shotgun_single",
    "item_hlvr_clip_shotgun_multiple",
    "item_hlvr_clip_generic_pistol",
    "item_hlvr_clip_generic_pistol_multiple",
}

local CLASS_LIST_ITEMS = {
    "item_hlvr_grenade_frag",
    "item_hlvr_grenade_xen",
    "item_healthvial",
    "item_hlvr_health_station_vial",
    "item_item_crate",
}


---@class ResinWatch : EntityClass
local base = entity("ResinWatch")

---Rotating indicator parented to the watch.
---@type EntityHandle
base.compassEnt = nil

---Text panel parented to the watch.
---@type EntityHandle
base.panelEnt = nil

---The type of entity to track.
---@type "resin"|"ammo"
base.trackingMode = "resin"

---Level indicator parented to the watch.
---@type EntityHandle
base.levelIndicatorEnt = nil

---Amount of resin that was found in the map since last check.
---@type number
base.__lastResinCount = -1

---The resin current being tracked by the watch.
---@type EntityHandle
base.__lastResinTracked = nil

---The type of indicator the last level indicator used.
---@type 0|1|2 # 0 = Same floor, 1 = above floor, 2 = below floor
base.__lastLevelType = 0

---List of classnames that are currently tracked.
---@type string[]
base.__currentTrackedClasses = CLASS_LIST_RESIN



local CLASS_LIST_AMMO_ITEMS = ArrayAppend(CLASS_LIST_AMMO, CLASS_LIST_ITEMS)

function base:Precache(context)
    PrecacheModel("models/resin_watch/resin_watch_compass.vmdl", context)
    PrecacheModel("models/resin_watch/resin_watch_base.vmdl", context)
    PrecacheModel("models/resin_watch/resin_watch_level_indicator.vmdl", context)
    PrecacheModel("models/hands/counter_panels.vmdl", context)
    PrecacheResource("sound", "ResinWatch.ResinTrackedBeep", context)
end


---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
    -- Counter
    local panel = SpawnEntityFromTableSynchronous("prop_dynamic", {
        targetname = self:GetName().."_panel",
        model = "models/hands/counter_panels.vmdl",
        disableshadows = "1",
        bodygroups = "{\n\tcounter = 1\n}",
        solid = "0",
    })
    panel:SetAbsScale(0.867)
    panel:SetParent(self, "")
    panel:SetLocalOrigin(Vector(-0.00900647, 1.00959, -0.160784))
    panel:SetLocalAngles(0, 359.293, -37.9338)
    panel:SetAbsOrigin(panel:GetAbsOrigin() + panel:GetUpVector() * 0.03)

    -- Compass
    local compass = SpawnEntityFromTableSynchronous("prop_dynamic", {
        targetname = self:GetName().."_compass",
        model = "models/resin_watch/resin_watch_compass.vmdl",
        origin = self:GetAbsOrigin(),
        disableshadows = "1",
    })
    compass:SetParent(self, "")
    compass:ResetLocal()

    -- Level indicator
    local level = SpawnEntityFromTableSynchronous("prop_dynamic", {
        targetname = self:GetName().."_level_indicator",
        model = "models/resin_watch/resin_watch_level_indicator.vmdl",
        origin = self:GetAbsOrigin(),
        disableshadows = "1",
    })
    level:SetParent(self, "")
    level:ResetLocal()

    self.panelEnt = panel
    self.compassEnt = compass
    self.levelIndicatorEnt = level
end

---Called automatically on activate.
---Any self values set here are automatically saved
---@param readyType OnReadyType
function base:OnReady(readyType)
    self:SetTrackingMode(self.trackingMode)
    self:SetBlankVisuals()

    self:SetThink("ResinCountThink", "ResinWatchPanelThink", 0.1, self)
    self:ResumeThink()

    RegisterPlayerEventCallback("player_drop_resin_in_backpack", function (params)
        self:Delay(function()
            self:UpdateCounterPanel()
        end, 0)
    end, self)

    ---Moving watch to secondary hand.
    ---@param params PLAYER_EVENT_PRIMARY_HAND_CHANGED
    RegisterPlayerEventCallback("primary_hand_changed", function (params)
        self:AttachToHand(Player.SecondaryHand)
    end, self)
end

---Attach the watch to the desired hand.
---@param hand? CPropVRHand # Hand to attach to. If not given it will choose a hand based on convars.
---@param offset? Vector # Optional offset vector.
---@param angles? QAngle # Optional angles.
---@param attachment? string # Optional attachment name.
function base:AttachToHand(hand, offset, angles, attachment)
    if hand == nil then
        hand = EasyConvars:GetBool("resin_watch_primary_hand") and Player.PrimaryHand or Player.SecondaryHand
    end

    if hand == Player.LeftHand then
        attachment = attachment or "item_holder_l"
        offset = offset or Vector(0.6, 1.2, 0)
        angles = angles or QAngle(-7.07305, 0, -90)
    else
        attachment = attachment or "item_holder_r"
        offset = offset or Vector(0.6, 1.2, 0)
        angles = angles or QAngle(-7.07305-180, 0, -90)
    end
    -- if self.attachInverted then
    if EasyConvars:GetBool("resin_watch_inverted") then
        offset.y = -offset.y
        angles = RotateOrientation(angles, QAngle(180, 180, 0))
    end
    self:SetParent(hand:GetGlove(), attachment)
    self:SetLocalOrigin(offset)
    self:SetLocalQAngle(angles)
end

---Update the text panel on the watch with text.
---@param amount number
function base:UpdateCounterPanelNumber(amount)
    amount = Clamp(amount, 0, 99)
    local tens = math.floor(amount / 10)
    local ones = amount % 10

    local ind0,ind9 = RESIN_COUNTER_INDEX_0, RESIN_COUNTER_INDEX_9
    if self.trackingMode == "ammo" then
        ind0,ind9 = AMMO_COUNTER_INDEX_0, AMMO_COUNTER_INDEX_9
    end

    self.panelEnt:EntFire("SetRenderAttribute", "$CounterDigitTens="..RemapVal(tens, 0, 9, ind0, ind9))
    self.panelEnt:EntFire("SetRenderAttribute", "$CounterDigitOnes="..RemapVal(ones, 0, 9, ind0, ind9))
end

---Set the tracking mode.
---@param mode "resin"|"ammo"
function base:SetTrackingMode(mode)
    if not EasyConvars:GetBool("resin_watch_allow_ammo_tracking") and not EasyConvars:GetBool("resin_watch_allow_item_tracking") then
        mode = "resin"
    end
    -- Early exit if new mode isn't different
    if mode == self.trackingMode then return end

    self.trackingMode = mode
    self:SetBlankVisuals()

    self:UpdateTrackedClassList()
    self:UpdateCounterPanel(true)
end

---Toggle the tracking mode between resin and ammo/items.
function base:ToggleTrackingMode()
    if self.trackingMode == "resin" then
        self:SetTrackingMode("ammo")
    else
        self:SetTrackingMode("resin")
    end
end

---Set the indication visuals to blank, color based on tracking mode.
function base:SetBlankVisuals()
    local isResin = self.trackingMode == "resin"
    self.compassEnt:SetSkin(isResin and SKIN_COMPASS_RESIN_BLANK or SKIN_COMPASS_AMMO_BLANK)
    self.levelIndicatorEnt:SetSkin(isResin and SKIN_LEVEL_RESIN_BLANK or SKIN_LEVEL_AMMO_BLANK)
    self.panelEnt:EntFire("SetRenderAttribute", "$CounterIcon=" .. (isResin and RESIN_COUNTER_INDEX_BLANK or AMMO_COUNTER_INDEX_BLANK))
end

---Get the list of classnames related to the current tracking mode.
---@return string[]
function base:GetTrackedClassList()
    if self.trackingMode == "resin" then
        return CLASS_LIST_RESIN
    elseif self.trackingMode == "ammo" then
        local ammo, items = EasyConvars:GetBool("resin_watch_allow_ammo_tracking"), EasyConvars:GetBool("resin_watch_allow_item_tracking")
        if ammo and items then
            return CLASS_LIST_AMMO_ITEMS
        elseif ammo then
            return CLASS_LIST_AMMO
        elseif items then
            return CLASS_LIST_ITEMS
        end
    end
    return {}
end

---Set __currentTrackedClasses to the correct list based on mode and convars.
function base:UpdateTrackedClassList()
    self.__currentTrackedClasses = self:GetTrackedClassList()
end

---Get the total number of entities from a list of classes.
---@param classes string[]
---@return number
local function countClassList(classes)
    local count = 0
    for _, class in ipairs(classes) do
        count = count + #Entities:FindAllByClassname(class)
    end
    return count
end

---Updates the digit counter panel with the current number of tracked entities in the map.
---@param force? boolean # If true the number will be updated even if the number of entities hasn't changed.
function base:UpdateCounterPanel(force)
    -- local count = countClassList(self.trackingMode == "resin" and CLASS_LIST_RESIN or CLASS_LIST_AMMO_ITEMS)
    local count = countClassList(self.__currentTrackedClasses)

    if force then
        self.__lastResinCount = -1
    end

    if count ~= self.__lastResinCount then
        self:UpdateCounterPanelNumber(count)
        self.__lastResinCount = count
    end
end

---Check every 4 seconds for newly spawned resin.
---Updates immediately when resin is stored in backpack elsewhere in code.
function base:ResinCountThink()
    self:UpdateCounterPanel()
    return 4
end

---Main entity think function. Think state is saved between loads
function base:Think()
    local selfOrigin = self:GetAbsOrigin()

    ---@type EntityHandle
    local nearest = Entities:FindByClassnameListNearest(self.__currentTrackedClasses, selfOrigin, EasyConvars:GetInt("resin_watch_radius"))
    -- local nearest = Entities:FindByClassnameListNearest(self.trackingMode == "resin" and CLASS_LIST_RESIN or CLASS_LIST_AMMO_ITEMS, selfOrigin, EasyConvars:GetInt("resin_watch_radius"))

    if nearest then

        ---@type Vector
        local difference = nearest:GetCenter() - selfOrigin

        if self.__lastResinTracked ~= nearest then
            self.__lastResinTracked = nearest
            if EasyConvars:GetBool("resin_watch_notify") then
                self:EmitSound("ResinWatch.ResinTrackedBeep")
                if Player.SecondaryHand then
                    RESIN_NOTIFY_HAPTIC_SEQ:Fire(Player.SecondaryHand)
                end
            end
            local skin = SKIN_COMPASS_RESIN
            if self.trackingMode == "ammo" then skin = SKIN_COMPASS_AMMO end
            self.compassEnt:SetSkin(skin)
        end

        local dir = difference:Normalized()
        local global_yaw_angle = math.atan2(dir.y, dir.x)
        global_yaw_angle = math.deg(global_yaw_angle)

        local parent_yaw = self:GetAngles().y
        local local_yaw_angle_degrees = global_yaw_angle - parent_yaw
        if self:GetUpVector().z < -0.8 then
            local_yaw_angle_degrees = -local_yaw_angle_degrees
        end

        local final_yaw = LerpAngle(0.1, self.compassEnt:GetLocalAngles().y, local_yaw_angle_degrees)
        self.compassEnt:SetLocalAngles(0, final_yaw, 0)

        local zDiff = (nearest:GetCenter().z - selfOrigin.z)
        local levelType = 0

        if zDiff > EasyConvars:GetFloat("resin_watch_level_up") then
            levelType = 1
        elseif zDiff < EasyConvars:GetFloat("resin_watch_level_down") then
            levelType = 2
        end
        -- Adjust for ammo color
        if self.trackingMode == "ammo" then
            levelType = levelType + 3
        end

        if self.__lastLevelType ~= levelType then
            self.__lastLevelType = levelType
            self.levelIndicatorEnt:SetSkin(levelType)
        end

    else
        if self.__lastResinTracked ~= nil then
            self.__lastResinTracked = nil
            self.__lastLevelType = 0
            self:SetBlankVisuals()
        end
    end

    return 0
end

--Used for classes not attached directly to entities
return base
