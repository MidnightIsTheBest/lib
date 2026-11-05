--[[
    ██╗  ██╗██████╗  █████╗ ██╗  ██╗██╗  ██╗
    ██║ ██╔╝██╔══██╗██╔══██╗╚██╗██╔╝╚██╗██╔╝
    █████╔╝ ██████╔╝███████║ ╚███╔╝  ╚███╔╝
    ██╔═██╗ ██╔══██╗██╔══██║ ██╔██╗  ██╔██╗
    ██║  ██╗██║  ██║██║  ██║██╔╝ ██╗██╔╝ ██╗
    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   UI  v2.0

    Clean, animated Roblox UI library with a Linoria-style API.
      • Sidebar layout, Code (monospace) font
      • Tweened hover/state transitions, switch toggles, ripple buttons
      • Fade + scale open/close, fading tab switches, sliding tab highlight
      • Smooth (lerped) window dragging
      • Toggles, sliders, buttons, dropdowns (single/multi), inputs,
        keybinds, colour pickers, labels, dividers, tabboxes,
        notifications and a watermark

    Works as a ModuleScript (require) or via loadstring (returns Library).
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TextService      = game:GetService("TextService")
local GuiService       = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local FONT = Enum.Font.Code
local FONT_BOLD = Font.new(Font.fromEnum(FONT).Family, Enum.FontWeight.Bold)

local Library = {
    Theme = {
        Background = Color3.fromRGB(11, 11, 14),
        Sidebar    = Color3.fromRGB(15, 15, 19),
        Section    = Color3.fromRGB(17, 17, 22),
        Element    = Color3.fromRGB(25, 25, 31),
        Hover      = Color3.fromRGB(32, 32, 40),
        Outline    = Color3.fromRGB(33, 33, 41),
        Highlight  = Color3.fromRGB(58, 58, 72),
        Accent     = Color3.fromRGB(139, 99, 255),
        Text       = Color3.fromRGB(236, 236, 242),
        SubText    = Color3.fromRGB(124, 124, 140),
    },

    Flags = {},      -- flag -> current value
    Options = {},    -- flag -> element object
    Toggles = {},    -- flag -> toggle object

    ToggleKey = "RightShift",
    DragSmoothness = 18,   -- higher = snappier dragging
    TweenSpeed = 0.2,

    Registry = {},
    Connections = {},
    Windows = {},
    UnloadCallbacks = {},
    ActivePopup = nil,
    ActiveDrag = nil,
    Picking = false,
    Unloaded = false,
    NotifyOrder = 0,
}
local Theme = Library.Theme

---------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------
local function New(class, props)
    local obj = Instance.new(class)
    if obj:IsA("GuiObject") then
        obj.BorderSizePixel = 0
    end
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else obj[k] = v end
    end
    if parent then obj.Parent = parent end
    return obj
end

local function Tween(obj, props, time, style, dir)
    local tween = TweenService:Create(
        obj,
        TweenInfo.new(time or Library.TweenSpeed, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props
    )
    tween:Play()
    return tween
end

local function Corner(parent, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius or 4), Parent = parent })
end

local function Round(parent)
    return New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

local function Stroke(parent, color, thickness, transparency)
    return New("UIStroke", {
        Color = color or Theme.Outline,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function Padding(parent, t, b, l, r)
    return New("UIPadding", {
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
        Parent = parent,
    })
end

local function List(parent, padding, direction, hAlign, vAlign)
    return New("UIListLayout", {
        Padding = UDim.new(0, padding or 0),
        FillDirection = direction or Enum.FillDirection.Vertical,
        HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
        VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = parent,
    })
end

local function MakeText(class, props)
    local bold = props.Bold
    props.Bold = nil
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.TextSize = props.TextSize or 13
    props.TextColor3 = props.TextColor3 or Theme.Text
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    if class == "TextButton" and props.AutoButtonColor == nil then
        props.AutoButtonColor = false
    end
    if bold then props.FontFace = FONT_BOLD else props.Font = props.Font or FONT end
    return New(class, props)
end

local function TextWidth(text, size)
    return TextService:GetTextSize(text, size or 13, FONT, Vector2.new(10000, 10000)).X
end

-- Theme registry: objects that follow a theme colour live
local function Reg(obj, prop, key)
    obj[prop] = Theme[key]
    table.insert(Library.Registry, { Object = obj, Property = prop, Key = key })
    return obj
end

local function AccentGradient(parent, rotation)
    return New("UIGradient", {
        Rotation = rotation or 0,
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 190)),
        Parent = parent,
    })
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then warn("[Kraxx] callback error: " .. tostring(err)) end
end

local function Fire(obj, ...)
    SafeCall(obj.Callback, ...)
    for _, fn in ipairs(obj.Changed) do SafeCall(fn, ...) end
end

local function MousePos()
    local inset = GuiService:GetGuiInset()
    return UserInputService:GetMouseLocation() - inset
end

local function IsOver(gui, pos)
    local p, s = gui.AbsolutePosition, gui.AbsoluteSize
    return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function IsClick(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function InputName(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Unknown then return nil end
        return input.KeyCode.Name
    elseif t == Enum.UserInputType.MouseButton1 then return "MB1"
    elseif t == Enum.UserInputType.MouseButton2 then return "MB2"
    elseif t == Enum.UserInputType.MouseButton3 then return "MB3"
    end
    return nil
end

local function NormalizeKey(key)
    if typeof(key) == "EnumItem" then return key.Name end
    if type(key) == "string" and key ~= "" then return key end
    return "None"
end

local function InputMatches(input, key)
    return key ~= nil and key ~= "None" and InputName(input) == key
end

local function NormArgs(flag, cfg)
    if type(flag) == "table" then return flag.Flag, flag end
    return flag, cfg or {}
end

local function Viewport()
    local cam = workspace.CurrentCamera
    local inset = GuiService:GetGuiInset()
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    return vp - Vector2.new(0, inset.Y)
end

function Library:Connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(self.Connections, c)
    return c
end

---------------------------------------------------------------------
-- Root GUI
---------------------------------------------------------------------
local ScreenGui = New("ScreenGui", {
    Name = "Kraxx",
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})

do
    local parented = false
    local hui = (typeof(gethui) == "function") and gethui or nil
    if hui then
        parented = pcall(function() ScreenGui.Parent = hui() end) and ScreenGui.Parent ~= nil
    end
    if not parented then
        parented = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) and ScreenGui.Parent ~= nil
    end
    if not parented then
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

Library.ScreenGui = ScreenGui

Library.Overlay = New("Frame", {
    Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = ScreenGui,
})

Library.NotifyHolder = New("Frame", {
    Name = "Notifications", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 300, 1, -32), ZIndex = 60, Parent = ScreenGui,
})
List(Library.NotifyHolder, 8, nil, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)

---------------------------------------------------------------------
-- Popups (dropdown lists, colour pickers)
---------------------------------------------------------------------
function Library:OpenPopup(data)
    if self.ActivePopup then self:ClosePopup() end
    self.ActivePopup = data
    if data.Follow then data.Follow() end
end

function Library:ClosePopup()
    local p = self.ActivePopup
    if not p then return end
    self.ActivePopup = nil
    SafeCall(p.Close)
end

local function PopupShell(width, height)
    local popup = New("CanvasGroup", {
        BackgroundColor3 = Theme.Section, Size = UDim2.fromOffset(width or 100, height or 0),
        GroupTransparency = 1, Visible = false, Parent = Library.Overlay,
    })
    Corner(popup, 6)
    local border = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 20, Parent = popup,
    })
    Corner(border, 5)
    Stroke(border, Theme.Highlight, 1, 0.4)
    return popup
end

---------------------------------------------------------------------
-- Global input
---------------------------------------------------------------------
Library:Connect(UserInputService.InputBegan, function(input)
    if IsClick(input) and Library.ActivePopup then
        local p = Library.ActivePopup
        local pos = MousePos()
        if not IsOver(p.Frame, pos) and not (p.Owner and IsOver(p.Owner, pos)) then
            Library:ClosePopup()
        end
    end

    if not Library.Picking and not UserInputService:GetFocusedTextBox() and InputMatches(input, Library.ToggleKey) then
        for _, w in ipairs(Library.Windows) do w:Toggle() end
    end
end)

Library:Connect(UserInputService.InputChanged, function(input)
    local drag = Library.ActiveDrag
    if drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        SafeCall(drag.Move, MousePos())
    end
end)

Library:Connect(UserInputService.InputEnded, function(input)
    if IsClick(input) and Library.ActiveDrag then
        local drag = Library.ActiveDrag
        Library.ActiveDrag = nil
        SafeCall(drag.End)
    end
end)

Library:Connect(RunService.RenderStepped, function(dt)
    for _, w in ipairs(Library.Windows) do w:_Step(dt) end
    local p = Library.ActivePopup
    if p and p.Follow then p.Follow() end
end)

local function BeginDrag(move, finish)
    Library.ActiveDrag = { Move = move, End = finish }
    move(MousePos())
end

---------------------------------------------------------------------
-- Shared object methods (OnChanged + inline addons)
---------------------------------------------------------------------
local ObjectMethods = {}
local ObjectMeta = { __index = ObjectMethods }

function ObjectMethods:OnChanged(fn)
    table.insert(self.Changed, fn)
    return self
end

local function AddonHolder(parent)
    local holder = New("Frame", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = parent,
    })
    List(holder, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
    return holder
end

local function BindLabelWidth(label, holder, left)
    local function update()
        local w = holder.AbsoluteSize.X
        label.Size = UDim2.new(1, -(left + w + (w > 0 and 10 or 0)), label.Size.Y.Scale, label.Size.Y.Offset)
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
    update()
end

local function Register(flag, obj)
    if flag then
        Library.Options[flag] = obj
        if obj.Type == "Toggle" then Library.Toggles[flag] = obj end
    end
end

local function NextAddonOrder(obj)
    obj.AddonOrder = (obj.AddonOrder or 0) + 1
    return obj.AddonOrder
end

---------------------------------------------------------------------
-- Keybind (addon)
---------------------------------------------------------------------
local Modes = { "Toggle", "Hold", "Always" }

local function CreateKeybind(parentObj, flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    assert(parentObj.AddonHolder, "AddKeybind: this element cannot hold addons")

    local KB = setmetatable({
        Type = "Keybind", Value = NormalizeKey(cfg.Default), Mode = cfg.Mode or "Toggle",
        State = false, Changed = {}, Callback = cfg.Callback, Text = cfg.Text,
    }, ObjectMeta)
    local picking = false

    local Btn = MakeText("TextButton", {
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Element, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 18), TextSize = 12, TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Center, Text = "", LayoutOrder = NextAddonOrder(parentObj),
        Parent = parentObj.AddonHolder,
    })
    Corner(Btn, 4)
    local BtnStroke = Stroke(Btn)
    Padding(Btn, 0, 0, 7, 7)

    local function Render()
        Btn.Text = picking and "..." or KB.Value
        local active = KB:GetState() and KB.Value ~= "None"
        Tween(Btn, { TextColor3 = (picking or active) and Theme.Accent or Theme.SubText }, 0.15)
        Tween(BtnStroke, { Color = picking and Theme.Accent or Theme.Outline }, 0.15)
    end

    function KB:GetState()
        if self.Mode == "Always" then return true end
        return self.State
    end

    function KB:SetState(state)
        state = state and true or false
        if self.State == state then return end
        self.State = state
        Render()
        if cfg.SyncToggleState and parentObj.Type == "Toggle" then parentObj:SetValue(state) end
        SafeCall(self.Callback, self:GetState())
    end

    function KB:SetValue(key, mode)
        self.Value = NormalizeKey(key)
        if mode then self.Mode = mode end
        if flag then Library.Flags[flag] = self.Value end
        Render()
        SafeCall(cfg.ChangedCallback, self.Value)
        for _, fn in ipairs(self.Changed) do SafeCall(fn, self.Value) end
    end

    Btn.MouseEnter:Connect(function() if not picking then Tween(BtnStroke, { Color = Theme.Highlight }, 0.15) end end)
    Btn.MouseLeave:Connect(function() if not picking then Tween(BtnStroke, { Color = Theme.Outline }, 0.15) end end)

    Btn.MouseButton1Click:Connect(function()
        picking = true
        Library.Picking = true
        Render()
    end)

    Btn.MouseButton2Click:Connect(function()
        local idx = table.find(Modes, KB.Mode) or 1
        KB.Mode = Modes[idx % #Modes + 1]
        KB.State = false
        Render()
        Library:Notify({ Title = "Keybind", Text = ("%s → %s mode"):format(KB.Text or parentObj.Text or "Keybind", KB.Mode), Duration = 2 })
    end)

    Library:Connect(UserInputService.InputBegan, function(input)
        if picking then
            local name = InputName(input)
            if not name then return end
            if name == "Escape" or name == "Backspace" then name = "None" end
            picking = false
            task.defer(function() Library.Picking = false end)
            KB:SetValue(name)
            return
        end
        if UserInputService:GetFocusedTextBox() then return end
        if InputMatches(input, KB.Value) then
            if KB.Mode == "Toggle" then KB:SetState(not KB.State)
            elseif KB.Mode == "Hold" then KB:SetState(true) end
        end
    end)

    Library:Connect(UserInputService.InputEnded, function(input)
        if KB.Mode == "Hold" and InputMatches(input, KB.Value) then KB:SetState(false) end
    end)

    if cfg.SyncToggleState and parentObj.Type == "Toggle" then
        KB.State = parentObj.Value
        parentObj:OnChanged(function(v) KB.State = v; Render() end)
    end

    if flag then Library.Flags[flag] = KB.Value end
    Register(flag, KB)
    Render()
    return KB
end

---------------------------------------------------------------------
-- Colour picker (addon)
---------------------------------------------------------------------
local function CreateColorPicker(parentObj, flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    assert(parentObj.AddonHolder, "AddColorPicker: this element cannot hold addons")

    local CP = setmetatable({
        Type = "ColorPicker", Value = cfg.Default or Color3.new(1, 1, 1), Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local h, s, v = CP.Value:ToHSV()
    local opened = false

    local Swatch = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = CP.Value, Size = UDim2.fromOffset(28, 16),
        LayoutOrder = NextAddonOrder(parentObj), Parent = parentObj.AddonHolder,
    })
    Corner(Swatch, 4)
    local SwatchStroke = Stroke(Swatch, Theme.Highlight, 1, 0.3)

    local W, H = 232, 250
    local Popup = PopupShell(W, H)
    local PopScale = New("UIScale", { Scale = 1, Parent = Popup })

    MakeText("TextLabel", {
        Text = cfg.Title or parentObj.Text or "Colour", TextSize = 13, Bold = true,
        Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), Parent = Popup,
    })

    local SV = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromHSV(h, 1, 1),
        Position = UDim2.fromOffset(12, 34), Size = UDim2.fromOffset(176, 170), Parent = Popup,
    })
    Corner(SV, 5)
    local Sat = New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = SV })
    Corner(Sat, 5)
    New("UIGradient", {
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
        Parent = Sat,
    })
    local Val = New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), Parent = SV })
    Corner(Val, 5)
    New("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
        Parent = Val,
    })
    local SVCursor = New("Frame", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12),
        ZIndex = 3, Parent = SV,
    })
    Round(SVCursor)
    Stroke(SVCursor, Color3.new(1, 1, 1), 2)

    local Hue = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1),
        Position = UDim2.fromOffset(198, 34), Size = UDim2.fromOffset(22, 170), Parent = Popup,
    })
    Corner(Hue, 5)
    local hueKeys = {}
    for i = 0, 6 do
        table.insert(hueKeys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
    end
    New("UIGradient", { Rotation = 90, Color = ColorSequence.new(hueKeys), Parent = Hue })
    local HueCursor = New("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4),
        ZIndex = 3, Parent = Hue,
    })
    Corner(HueCursor, 2)
    Stroke(HueCursor, Color3.new(0, 0, 0), 1, 0.6)

    local Preview = New("Frame", {
        BackgroundColor3 = CP.Value, Position = UDim2.fromOffset(12, 214), Size = UDim2.fromOffset(24, 24), Parent = Popup,
    })
    Corner(Preview, 5)
    Stroke(Preview, Theme.Highlight, 1, 0.3)

    local HexFrame = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.fromOffset(44, 214), Size = UDim2.fromOffset(W - 56, 24), Parent = Popup,
    })
    Corner(HexFrame, 5)
    local HexStroke = Stroke(HexFrame)
    local HexBox = New("TextBox", {
        BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "", PlaceholderText = "#FFFFFF",
        PlaceholderColor3 = Theme.SubText, Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -18, 1, 0),
        Parent = HexFrame,
    })

    local function Render()
        local col = Color3.fromHSV(h, s, v)
        SV.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        SVCursor.Position = UDim2.fromScale(s, 1 - v)
        HueCursor.Position = UDim2.new(0.5, 0, h, 0)
        Swatch.BackgroundColor3 = col
        Preview.BackgroundColor3 = col
        if not HexBox:IsFocused() then HexBox.Text = "#" .. col:ToHex():upper() end
    end

    local function Commit(silent)
        CP.Value = Color3.fromHSV(h, s, v)
        if flag then Library.Flags[flag] = CP.Value end
        Render()
        if not silent then Fire(CP, CP.Value) end
    end

    function CP:SetValueRGB(color, silent)
        h, s, v = color:ToHSV()
        Commit(silent)
    end
    CP.SetValue = CP.SetValueRGB

    SV.InputBegan:Connect(function(input)
        if not IsClick(input) then return end
        BeginDrag(function(m)
            local p, sz = SV.AbsolutePosition, SV.AbsoluteSize
            s = math.clamp((m.X - p.X) / sz.X, 0, 1)
            v = 1 - math.clamp((m.Y - p.Y) / sz.Y, 0, 1)
            Commit()
        end)
    end)

    Hue.InputBegan:Connect(function(input)
        if not IsClick(input) then return end
        BeginDrag(function(m)
            h = math.clamp((m.Y - Hue.AbsolutePosition.Y) / Hue.AbsoluteSize.Y, 0, 0.999)
            Commit()
        end)
    end)

    HexBox.Focused:Connect(function() Tween(HexStroke, { Color = Theme.Accent }, 0.15) end)
    HexBox.FocusLost:Connect(function()
        Tween(HexStroke, { Color = Theme.Outline }, 0.15)
        local ok, col = pcall(Color3.fromHex, (HexBox.Text:gsub("#", "")))
        if ok and col then CP:SetValueRGB(col) else Render() end
    end)

    local function Close()
        opened = false
        Tween(SwatchStroke, { Color = Theme.Highlight, Transparency = 0.3 }, 0.15)
        Tween(PopScale, { Scale = 0.95 }, 0.15)
        local t = Tween(Popup, { GroupTransparency = 1 }, 0.15)
        t.Completed:Connect(function() if not opened then Popup.Visible = false end end)
    end

    local function Open()
        opened = true
        Popup.Visible = true
        PopScale.Scale = 0.95
        Tween(PopScale, { Scale = 1 }, 0.25)
        Tween(Popup, { GroupTransparency = 0 }, 0.22)
        Tween(SwatchStroke, { Color = Theme.Accent, Transparency = 0 }, 0.15)
        Library:OpenPopup({
            Frame = Popup, Owner = Swatch, Close = Close,
            Follow = function()
                local sp, ss = Swatch.AbsolutePosition, Swatch.AbsoluteSize
                local vp = Viewport()
                local x = math.clamp(sp.X + ss.X - W, 4, vp.X - W - 4)
                local y = sp.Y + ss.Y + 6
                if y + H > vp.Y - 4 then y = sp.Y - H - 6 end
                Popup.Position = UDim2.fromOffset(x, y)
            end,
        })
    end

    Swatch.MouseButton1Click:Connect(function()
        if opened then Library:ClosePopup() else Open() end
    end)
    Swatch.MouseEnter:Connect(function() if not opened then Tween(SwatchStroke, { Transparency = 0 }, 0.15) end end)
    Swatch.MouseLeave:Connect(function() if not opened then Tween(SwatchStroke, { Transparency = 0.3 }, 0.15) end end)

    Commit(true)
    Register(flag, CP)
    return CP
end

function ObjectMethods:AddKeybind(flag, cfg) return CreateKeybind(self, flag, cfg) end
function ObjectMethods:AddColorPicker(flag, cfg) return CreateColorPicker(self, flag, cfg) end

---------------------------------------------------------------------
-- Elements (shared by groupboxes and tabbox tabs)
---------------------------------------------------------------------
local Elements = {}
Elements.__index = Elements

function Elements:_Next()
    self.Order += 1
    return self.Order
end

-- Label ----------------------------------------------------------------
function Elements:AddLabel(text, wrap)
    if type(text) == "table" then text, wrap = text.Text, text.DoesWrap end
    local Label = setmetatable({ Type = "Label", Text = text, Changed = {} }, ObjectMeta)

    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, wrap and 0 or 20),
        AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    local TL = MakeText("TextLabel", {
        Text = text or "", TextColor3 = wrap and Theme.SubText or Theme.Text, TextWrapped = wrap or false,
        Size = wrap and UDim2.new(1, 0, 0, 0) or UDim2.new(1, 0, 1, 0),
        AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        TextTruncate = wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
        Parent = Row,
    })
    Label.AddonHolder = AddonHolder(Row)
    BindLabelWidth(TL, Label.AddonHolder, 0)

    function Label:SetText(t)
        self.Text = t
        TL.Text = t
    end
    return Label
end

-- Divider --------------------------------------------------------------
function Elements:AddDivider()
    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = self:_Next(), Parent = self.Container,
    })
    New("Frame", {
        BackgroundColor3 = Theme.Outline, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.new(1, 0, 0, 1), Parent = Row,
    })
end

-- Button ---------------------------------------------------------------
local function Ripple(button)
    local rel = MousePos() - button.AbsolutePosition
    local r = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rel.X, rel.Y), Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.6, ZIndex = 2, Parent = button,
    })
    Round(r)
    local size = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.2
    local t = Tween(r, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, 0.6)
    t.Completed:Connect(function() r:Destroy() end)
end

function Elements:AddButton(cfg, callback)
    if type(cfg) == "string" then cfg = { Text = cfg, Func = callback } end
    cfg = cfg or {}
    local func = cfg.Func or cfg.Callback or callback
    local Button = setmetatable({ Type = "Button", Text = cfg.Text or "Button", Changed = {} }, ObjectMeta)
    local armed = false

    local B = MakeText("TextButton", {
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Element, Text = Button.Text,
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), ClipsDescendants = true,
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    Corner(B, 6)
    local BStroke = Stroke(B)

    B.MouseEnter:Connect(function()
        Tween(B, { BackgroundColor3 = Theme.Hover }, 0.15)
        Tween(BStroke, { Color = Theme.Highlight }, 0.15)
    end)
    B.MouseLeave:Connect(function()
        Tween(B, { BackgroundColor3 = Theme.Element }, 0.15)
        Tween(BStroke, { Color = Theme.Outline }, 0.15)
    end)

    local function Disarm()
        armed = false
        B.Text = Button.Text
        Tween(B, { TextColor3 = Theme.Text }, 0.15)
    end

    B.MouseButton1Click:Connect(function()
        Ripple(B)
        if cfg.DoubleClick then
            if armed then
                Disarm()
                SafeCall(func)
            else
                armed = true
                B.Text = "Click again to confirm"
                Tween(B, { TextColor3 = Theme.Accent }, 0.15)
                task.delay(2, function() if armed then Disarm() end end)
            end
        else
            SafeCall(func)
        end
    end)

    function Button:SetText(t)
        self.Text = t
        if not armed then B.Text = t end
    end
    return Button
end

-- Toggle (switch) --------------------------------------------------------
function Elements:AddToggle(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local Toggle = setmetatable({
        Type = "Toggle", Value = cfg.Default == true, Text = cfg.Text or flag, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local hovering = false

    local Row = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    local Lbl = MakeText("TextLabel", {
        Text = Toggle.Text, TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.new(1, 0, 1, 0), Parent = Row,
    })
    Toggle.AddonHolder = AddonHolder(Row)
    BindLabelWidth(Lbl, Toggle.AddonHolder, 0)

    local Track = New("Frame", {
        BackgroundColor3 = Theme.Element, Size = UDim2.fromOffset(32, 18), LayoutOrder = 1000,
        Parent = Toggle.AddonHolder,
    })
    Round(Track)
    local TrackStroke = Stroke(Track)
    local TrackFill = Reg(New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = Track,
    }), "BackgroundColor3", "Accent")
    Round(TrackFill)
    AccentGradient(TrackFill)
    local Knob = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.SubText, ZIndex = 2, Parent = Track,
    })
    Round(Knob)

    local function Render(time)
        local on = Toggle.Value
        Tween(TrackFill, { BackgroundTransparency = on and 0 or 1 }, time)
        Tween(TrackStroke, { Color = on and Theme.Accent or (hovering and Theme.Highlight or Theme.Outline), Transparency = on and 1 or 0 }, time)
        Tween(Knob, {
            Position = on and UDim2.new(0, 17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = on and Color3.new(1, 1, 1) or (hovering and Theme.Text or Theme.SubText),
        }, time, Enum.EasingStyle.Back)
        Tween(Lbl, { TextColor3 = (on or hovering) and Theme.Text or Theme.SubText }, time)
    end

    function Toggle:SetValue(value, silent)
        value = value and true or false
        if value == self.Value then return end
        self.Value = value
        if flag then Library.Flags[flag] = value end
        Render(0.25)
        if not silent then Fire(self, value) end
    end

    function Toggle:SetText(t) self.Text = t; Lbl.Text = t end

    Row.MouseButton1Click:Connect(function() Toggle:SetValue(not Toggle.Value) end)
    Row.MouseEnter:Connect(function() hovering = true; Render(0.15) end)
    Row.MouseLeave:Connect(function() hovering = false; Render(0.15) end)

    if flag then Library.Flags[flag] = Toggle.Value end
    Render(0)
    Register(flag, Toggle)
    return Toggle
end

-- Slider ---------------------------------------------------------------
function Elements:AddSlider(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local min, max = cfg.Min or 0, cfg.Max or 100
    local rounding = cfg.Rounding or 0
    local suffix = cfg.Suffix or ""
    local Slider = setmetatable({
        Type = "Slider", Min = min, Max = max, Value = nil, Text = cfg.Text or flag, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local dragging, hovering = false, false

    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = self:_Next(), Parent = self.Container,
    })
    local Lbl = MakeText("TextLabel", {
        Text = Slider.Text, TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.new(1, -90, 0, 18), Parent = Row,
    })
    local Pill = New("Frame", {
        BackgroundColor3 = Theme.Element, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = Row,
    })
    Corner(Pill, 4)
    Padding(Pill, 0, 0, 6, 6)
    local ValLbl = MakeText("TextLabel", {
        Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = Pill,
    })

    local Bar = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.fromOffset(0, 27), Size = UDim2.new(1, 0, 0, 4), Parent = Row,
    })
    Round(Bar)
    local Fill = Reg(New("Frame", { Size = UDim2.fromScale(0, 1), Parent = Bar }), "BackgroundColor3", "Accent")
    Round(Fill)
    AccentGradient(Fill)
    local Knob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(10, 10),
        BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2, Parent = Bar,
    })
    Round(Knob)
    Reg(Stroke(Knob, nil, 2), "Color", "Accent")

    local Hit = New("TextButton", {
        Text = "", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 20), Parent = Row,
    })

    local function RoundTo(n)
        local m = 10 ^ rounding
        return math.floor(n * m + 0.5) / m
    end
    local function Format(n)
        if rounding <= 0 then return tostring(math.floor(n + 0.5)) end
        return string.format("%." .. rounding .. "f", n)
    end
    local function RenderKnob()
        local active = dragging or hovering
        Tween(Knob, { Size = active and UDim2.fromOffset(14, 14) or UDim2.fromOffset(10, 10) }, 0.18, Enum.EasingStyle.Back)
        Tween(Lbl, { TextColor3 = active and Theme.Text or Theme.SubText }, 0.15)
        Tween(ValLbl, { TextColor3 = dragging and Theme.Accent or Theme.Text }, 0.15)
    end

    function Slider:SetValue(value, silent)
        value = RoundTo(math.clamp(tonumber(value) or min, min, max))
        local changed = value ~= self.Value
        self.Value = value
        if flag then Library.Flags[flag] = value end
        local pct = (max == min) and 0 or (value - min) / (max - min)
        Tween(Fill, { Size = UDim2.fromScale(pct, 1) }, 0.12)
        Tween(Knob, { Position = UDim2.fromScale(pct, 0.5) }, 0.12)
        ValLbl.Text = Format(value) .. suffix .. (cfg.ShowMax and (" / " .. Format(max) .. suffix) or "")
        if changed and not silent then Fire(self, value) end
    end

    function Slider:SetMin(n) min = n; self.Min = n; self:SetValue(self.Value) end
    function Slider:SetMax(n) max = n; self.Max = n; self:SetValue(self.Value) end

    Hit.MouseEnter:Connect(function() hovering = true; RenderKnob() end)
    Hit.MouseLeave:Connect(function() hovering = false; RenderKnob() end)
    Hit.InputBegan:Connect(function(input)
        if not IsClick(input) then return end
        dragging = true
        RenderKnob()
        BeginDrag(function(m)
            local pct = math.clamp((m.X - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
            Slider:SetValue(min + (max - min) * pct)
        end, function()
            dragging = false
            RenderKnob()
        end)
    end)

    Slider:SetValue(cfg.Default or min, true)
    RenderKnob()
    Register(flag, Slider)
    return Slider
end

-- Dropdown -------------------------------------------------------------
function Elements:AddDropdown(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local Dropdown = setmetatable({
        Type = "Dropdown", Values = cfg.Values or {}, Multi = cfg.Multi == true, Text = cfg.Text,
        Value = nil, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local opened = false
    local optionButtons = {}
    local ROW_H = 26

    local hasText = cfg.Text ~= nil
    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, hasText and 52 or 30),
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    if hasText then
        MakeText("TextLabel", { Text = cfg.Text, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 16), Parent = Row })
    end
    local Box = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Element,
        Position = UDim2.fromOffset(0, hasText and 22 or 0), Size = UDim2.new(1, 0, 0, 30), Parent = Row,
    })
    Corner(Box, 6)
    local BoxStroke = Stroke(Box)
    local Display = MakeText("TextLabel", {
        Text = "None", TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -40, 1, 0), Parent = Box,
    })
    local Sign = MakeText("TextLabel", {
        Text = "+", TextSize = 14, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(16, 16), Parent = Box,
    })

    local Popup = PopupShell(100, 0)
    local Scroll = New("ScrollingFrame", {
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Highlight,
        ScrollingDirection = Enum.ScrollingDirection.Y, Parent = Popup,
    })
    Padding(Scroll, 4, 4, 4, 4)
    List(Scroll, 2)

    local function IsSelected(val)
        if Dropdown.Multi then return Dropdown.Value[val] == true end
        return Dropdown.Value == val
    end

    local function RefreshDisplay()
        local text
        if Dropdown.Multi then
            local parts = {}
            for _, val in ipairs(Dropdown.Values) do
                if Dropdown.Value[val] then table.insert(parts, tostring(val)) end
            end
            text = #parts > 0 and table.concat(parts, ", ") or nil
        else
            text = Dropdown.Value ~= nil and tostring(Dropdown.Value) or nil
        end
        Display.Text = text or "None"
        Display.TextColor3 = text and Theme.Text or Theme.SubText
        if flag then Library.Flags[flag] = Dropdown.Value end
    end

    local function RefreshOptions(time)
        for btn, val in pairs(optionButtons) do
            local sel = IsSelected(val)
            local dot = btn:FindFirstChild("Dot")
            Tween(btn, { TextColor3 = sel and Theme.Text or Theme.SubText }, time or 0.15)
            if dot then
                Tween(dot, { BackgroundTransparency = sel and 0 or 1, Size = sel and UDim2.fromOffset(6, 6) or UDim2.fromOffset(0, 0) }, time or 0.15)
            end
        end
    end

    local function Select(val)
        if Dropdown.Multi then
            Dropdown.Value[val] = (not Dropdown.Value[val]) or nil
        else
            if Dropdown.Value == val and cfg.AllowNull then
                Dropdown.Value = nil
            else
                Dropdown.Value = val
            end
            Library:ClosePopup()
        end
        RefreshDisplay()
        RefreshOptions()
        Fire(Dropdown, Dropdown.Value)
    end

    local function BuildOptions()
        for btn in pairs(optionButtons) do btn:Destroy() end
        table.clear(optionButtons)
        for i, val in ipairs(Dropdown.Values) do
            local btn = MakeText("TextButton", {
                BackgroundTransparency = 1, BackgroundColor3 = Theme.Hover, Text = tostring(val),
                TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd,
                Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = i, Parent = Scroll,
            })
            Corner(btn, 4)
            Padding(btn, 0, 0, 10, 24)
            local dot = Reg(New("Frame", {
                Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 12, 0.5, 0),
                Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Parent = btn,
            }), "BackgroundColor3", "Accent")
            Round(dot)
            optionButtons[btn] = val
            btn.MouseEnter:Connect(function() Tween(btn, { BackgroundTransparency = 0 }, 0.12) end)
            btn.MouseLeave:Connect(function() Tween(btn, { BackgroundTransparency = 1 }, 0.12) end)
            btn.MouseButton1Click:Connect(function() Select(val) end)
        end
    end

    local function Close()
        opened = false
        Sign.Text = "+"
        Tween(Sign, { TextColor3 = Theme.SubText }, 0.2)
        Tween(BoxStroke, { Color = Theme.Outline }, 0.2)
        local w = Popup.AbsoluteSize.X
        local t = Tween(Popup, { GroupTransparency = 1, Size = UDim2.fromOffset(w, math.max(Popup.AbsoluteSize.Y - 10, 0)) }, 0.15)
        t.Completed:Connect(function() if not opened then Popup.Visible = false end end)
    end

    local function Open()
        opened = true
        BuildOptions()
        RefreshOptions(0)
        local count = math.clamp(#Dropdown.Values, 1, cfg.MaxVisible or 7)
        local height = count * (ROW_H + 2) + 6
        local width = Box.AbsoluteSize.X
        Popup.Visible = true
        Popup.GroupTransparency = 1
        Popup.Size = UDim2.fromOffset(width, math.max(height - 16, 0))
        Tween(Popup, { Size = UDim2.fromOffset(width, height), GroupTransparency = 0 }, 0.25)
        Sign.Text = "-"
        Tween(Sign, { TextColor3 = Theme.Accent }, 0.2)
        Tween(BoxStroke, { Color = Theme.Accent }, 0.2)
        Library:OpenPopup({
            Frame = Popup, Owner = Box, Close = Close,
            Follow = function()
                local bp, bs = Box.AbsolutePosition, Box.AbsoluteSize
                local vp = Viewport()
                local y = bp.Y + bs.Y + 5
                if y + height > vp.Y - 4 then y = bp.Y - height - 5 end
                Popup.Position = UDim2.fromOffset(bp.X, y)
            end,
        })
    end

    Box.MouseButton1Click:Connect(function()
        if opened then Library:ClosePopup() else Open() end
    end)
    Box.MouseEnter:Connect(function()
        if not opened then Tween(BoxStroke, { Color = Theme.Highlight }, 0.15) end
        Tween(Box, { BackgroundColor3 = Theme.Hover }, 0.15)
    end)
    Box.MouseLeave:Connect(function()
        if not opened then Tween(BoxStroke, { Color = Theme.Outline }, 0.15) end
        Tween(Box, { BackgroundColor3 = Theme.Element }, 0.15)
    end)

    function Dropdown:SetValue(value, silent)
        if self.Multi then
            local dict = {}
            if type(value) == "table" then
                if #value > 0 then
                    for _, val in ipairs(value) do dict[val] = true end
                else
                    for k, on in pairs(value) do if on then dict[k] = true end end
                end
            end
            self.Value = dict
        else
            self.Value = value
        end
        RefreshDisplay()
        if opened then RefreshOptions() end
        if not silent then Fire(self, self.Value) end
    end

    function Dropdown:SetValues(values)
        self.Values = values or {}
        if self.Multi then
            for k in pairs(self.Value) do
                if not table.find(self.Values, k) then self.Value[k] = nil end
            end
        elseif self.Value ~= nil and not table.find(self.Values, self.Value) then
            self.Value = nil
        end
        if opened then Library:ClosePopup() end
        RefreshDisplay()
    end

    local default = cfg.Default
    if Dropdown.Multi then
        Dropdown:SetValue(type(default) == "table" and default or {}, true)
    else
        if type(default) == "number" and Dropdown.Values[default] ~= nil and not table.find(Dropdown.Values, default) then
            default = Dropdown.Values[default]
        end
        Dropdown:SetValue(default, true)
    end

    Register(flag, Dropdown)
    return Dropdown
end

-- Input ----------------------------------------------------------------
function Elements:AddInput(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local Input = setmetatable({
        Type = "Input", Value = tostring(cfg.Default or ""), Text = cfg.Text, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)

    local hasText = cfg.Text ~= nil
    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, hasText and 52 or 30),
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    if hasText then
        MakeText("TextLabel", { Text = cfg.Text, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 16), Parent = Row })
    end
    local Box = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.fromOffset(0, hasText and 22 or 0),
        Size = UDim2.new(1, 0, 0, 30), ClipsDescendants = true, Parent = Row,
    })
    Corner(Box, 6)
    local BoxStroke = Stroke(Box)
    local TB = New("TextBox", {
        BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = Theme.Text,
        PlaceholderText = cfg.Placeholder or "", PlaceholderColor3 = Theme.SubText, Text = Input.Value,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true,
        Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Parent = Box,
    })

    function Input:SetValue(text, silent)
        text = tostring(text or "")
        if cfg.MaxLength then text = text:sub(1, cfg.MaxLength) end
        if TB.Text ~= text then TB.Text = text end
        if text == self.Value then return end
        self.Value = text
        if flag then Library.Flags[flag] = text end
        if not silent then Fire(self, text) end
    end

    local function Commit()
        local text = TB.Text
        if cfg.Numeric and text ~= "" and text ~= "-" and text ~= "." and not tonumber(text) then
            TB.Text = Input.Value
            return
        end
        Input:SetValue(text)
    end

    TB.Focused:Connect(function() Tween(BoxStroke, { Color = Theme.Accent }, 0.15) end)
    TB.FocusLost:Connect(function()
        Tween(BoxStroke, { Color = Theme.Outline }, 0.15)
        if cfg.Finished then Commit() end
    end)
    if not cfg.Finished then
        TB:GetPropertyChangedSignal("Text"):Connect(Commit)
    end
    Box.MouseEnter:Connect(function() if not TB:IsFocused() then Tween(BoxStroke, { Color = Theme.Highlight }, 0.15) end end)
    Box.MouseLeave:Connect(function() if not TB:IsFocused() then Tween(BoxStroke, { Color = Theme.Outline }, 0.15) end end)

    if flag then Library.Flags[flag] = Input.Value end
    Register(flag, Input)
    return Input
end

-- Standalone keybind / colour picker rows -------------------------------
function Elements:AddKeybind(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local row = self:AddLabel(cfg.Text or flag or "Keybind")
    return CreateKeybind(row, flag, cfg)
end

function Elements:AddColorPicker(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local row = self:AddLabel(cfg.Text or flag or "Colour")
    return CreateColorPicker(row, flag, cfg)
end

---------------------------------------------------------------------
-- Groupbox / Tabbox builders
---------------------------------------------------------------------
local function SectionFrame(parent, order)
    local Box = New("Frame", {
        BackgroundColor3 = Theme.Section, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = order, Parent = parent,
    })
    Corner(Box, 8)
    Stroke(Box)
    List(Box, 0)
    return Box
end

local function ElementContainer(parent, order)
    local c = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = order, Parent = parent,
    })
    Padding(c, 10, 14, 14, 14)
    List(c, 10)
    return c
end

local function NewGroupbox(column, name, order)
    local Box = SectionFrame(column, order)
    local Header = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, Parent = Box,
    })
    local Bar = Reg(New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(3, 12), Parent = Header,
    }), "BackgroundColor3", "Accent")
    Corner(Bar, 2)
    MakeText("TextLabel", {
        Text = name, Bold = true, TextSize = 14, Position = UDim2.fromOffset(25, 0), Size = UDim2.new(1, -39, 1, 0), Parent = Header,
    })
    New("Frame", {
        BackgroundColor3 = Theme.Outline, Position = UDim2.new(0, 14, 1, -1), Size = UDim2.new(1, -28, 0, 1), Parent = Header,
    })
    local Container = ElementContainer(Box, 2)
    return setmetatable({ Frame = Box, Container = Container, Order = 0, Name = name }, Elements)
end

local function NewTabbox(column, order)
    local Box = SectionFrame(column, order)
    local BarHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, Parent = Box })
    local Bar = New("Frame", {
        BackgroundColor3 = Theme.Background, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 28), Parent = BarHolder,
    })
    Corner(Bar, 6)
    Stroke(Bar)
    local Highlight = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(0, 0, 1, -6), Parent = Bar,
    })
    Corner(Highlight, 4)
    Stroke(Highlight, Theme.Highlight, 1, 0.5)
    local Holder = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2, Parent = Box,
    })

    local Tabbox = { Tabs = {}, Active = nil, Frame = Box }

    local function Layout(instant)
        local n = #Tabbox.Tabs
        for i, t in ipairs(Tabbox.Tabs) do
            t.Button.Size = UDim2.new(1 / n, -6 / n, 1, -6)
            t.Button.Position = UDim2.new((i - 1) / n, 3 - (i - 1) * 6 / n, 0, 3)
            if t == Tabbox.Active then
                local props = { Position = t.Button.Position, Size = t.Button.Size }
                if instant then
                    Highlight.Position, Highlight.Size = props.Position, props.Size
                else
                    Tween(Highlight, props, 0.3)
                end
            end
        end
    end

    function Tabbox:Select(sub)
        if self.Active == sub then return end
        Library:ClosePopup()
        local first = self.Active == nil
        self.Active = sub
        for _, t in ipairs(self.Tabs) do
            t.Container.Visible = (t == sub)
            Tween(t.Button, { TextColor3 = (t == sub) and Theme.Text or Theme.SubText }, 0.2)
        end
        Layout(first)
    end

    function Tabbox:AddTab(name)
        local Container = ElementContainer(Holder, #self.Tabs + 1)
        Container.Visible = false
        local Btn = MakeText("TextButton", {
            Text = name, TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 2, Parent = Bar,
        })
        local sub = setmetatable({ Container = Container, Order = 0, Button = Btn, Name = name }, Elements)
        table.insert(self.Tabs, sub)
        Btn.MouseButton1Click:Connect(function() self:Select(sub) end)
        Btn.MouseEnter:Connect(function() if self.Active ~= sub then Tween(Btn, { TextColor3 = Theme.Text }, 0.15) end end)
        Btn.MouseLeave:Connect(function() if self.Active ~= sub then Tween(Btn, { TextColor3 = Theme.SubText }, 0.15) end end)
        if not self.Active then self:Select(sub) else Layout(true) end
        return sub
    end

    return Tabbox
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local SIDEBAR_W = 180
local HEADER_H = 58
local TAB_H, TAB_GAP = 34, 4

function Library:CreateWindow(cfg)
    cfg = cfg or {}
    if cfg.ToggleKey then self.ToggleKey = NormalizeKey(cfg.ToggleKey) end

    local size = cfg.Size or UDim2.fromOffset(720, 500)
    local vp = Viewport()
    local start = cfg.Position and Vector2.new(cfg.Position.X.Offset, cfg.Position.Y.Offset) or (vp / 2)

    local Window = { Tabs = {}, Open = false, ActiveTab = nil, Current = start, Target = start }

    local Holder = New("Frame", {
        Name = "Window", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(start.X, start.Y), Size = size, Visible = false, Parent = ScreenGui,
    })
    local Scale = New("UIScale", { Scale = 0.94, Parent = Holder })

    -- soft shadow built from layered frames (no image assets needed)
    local shadows = {}
    for i = 1, 6 do
        local layer = New("Frame", {
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
            Position = UDim2.fromOffset(-i * 3, -i * 3 + 4), Size = UDim2.new(1, i * 6, 1, i * 6),
            ZIndex = 0, Parent = Holder,
        })
        Corner(layer, 10 + i * 3)
        table.insert(shadows, layer)
    end

    -- Modal button frees the mouse in first-person/locked-mouse games while the UI is open
    New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Modal = true, Parent = Holder })

    local Canvas = New("CanvasGroup", {
        BackgroundColor3 = Theme.Background, Size = UDim2.fromScale(1, 1), GroupTransparency = 1,
        Active = true, ZIndex = 1, Parent = Holder,
    })
    Corner(Canvas, 10)
    local Border = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 50, Parent = Canvas,
    })
    Corner(Border, 9)
    Stroke(Border, Theme.Highlight, 1, 0.45)

    ------------------------------------------------------------ sidebar
    local Sidebar = New("Frame", {
        BackgroundColor3 = Theme.Sidebar, Size = UDim2.new(0, SIDEBAR_W, 1, 0), Active = true, Parent = Canvas,
    })
    New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0), Parent = Sidebar })

    local Brand = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, HEADER_H), Active = true, Parent = Sidebar })
    local Logo = Reg(New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(30, 30), Parent = Brand,
    }), "BackgroundColor3", "Accent")
    Corner(Logo, 8)
    AccentGradient(Logo, 45)
    MakeText("TextLabel", {
        Text = cfg.Logo or string.sub(cfg.Title or "K", 1, 1), Bold = true, TextSize = 17, TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = Logo,
    })
    MakeText("TextLabel", {
        Text = cfg.Title or "Kraxx", Bold = true, TextSize = 16, Position = UDim2.new(0, 56, 0.5, -15),
        Size = UDim2.new(1, -64, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, Parent = Brand,
    })
    MakeText("TextLabel", {
        Text = cfg.Subtitle or "v2.0", TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 56, 0.5, 2),
        Size = UDim2.new(1, -64, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, Parent = Brand,
    })
    New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.new(0, 14, 1, -1), Size = UDim2.new(1, -28, 0, 1), Parent = Brand })

    local TabList = New("ScrollingFrame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(0, HEADER_H + 10), Size = UDim2.new(1, 0, 1, -(HEADER_H + 10) - 62),
        CanvasSize = UDim2.new(), ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = Sidebar,
    })
    local TabHighlight = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, TAB_H),
        Visible = false, Parent = TabList,
    })
    Corner(TabHighlight, 6)
    Stroke(TabHighlight, Theme.Highlight, 1, 0.6)
    local TabBar = Reg(New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 16), Parent = TabHighlight,
    }), "BackgroundColor3", "Accent")
    Corner(TabBar, 2)

    -- footer: player info
    local Footer = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -62), Size = UDim2.new(1, 0, 0, 62), Parent = Sidebar,
    })
    New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 1), Parent = Footer })
    local Avatar = New("ImageLabel", {
        BackgroundColor3 = Theme.Element, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0),
        Size = UDim2.fromOffset(30, 30), Image = "", Parent = Footer,
    })
    Round(Avatar)
    Reg(Stroke(Avatar, nil, 1.5), "Color", "Accent")
    task.spawn(function()
        local ok, img = pcall(function()
            return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
        end)
        if ok and img then Avatar.Image = img end
    end)
    MakeText("TextLabel", {
        Text = LocalPlayer.DisplayName, TextSize = 13, Position = UDim2.new(0, 56, 0.5, -15),
        Size = UDim2.new(1, -64, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, Parent = Footer,
    })
    local KeyHint = MakeText("TextLabel", {
        Text = "", TextSize = 11, TextColor3 = Theme.SubText, Position = UDim2.new(0, 56, 0.5, 2),
        Size = UDim2.new(1, -64, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, Parent = Footer,
    })
    Window.KeyHint = KeyHint
    function Window:_UpdateHint() KeyHint.Text = "[" .. Library.ToggleKey .. "] toggle" end
    Window:_UpdateHint()

    ------------------------------------------------------------ main area
    local Main = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(SIDEBAR_W, 0), Size = UDim2.new(1, -SIDEBAR_W, 1, 0), Parent = Canvas,
    })
    local Header = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, HEADER_H), Active = true, Parent = Main })
    local PageTitle = MakeText("TextLabel", {
        Text = "", Bold = true, TextSize = 17, Position = UDim2.new(0, 20, 0.5, -16), Size = UDim2.new(1, -40, 0, 18), Parent = Header,
    })
    local PageDesc = MakeText("TextLabel", {
        Text = "", TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 20, 0.5, 3), Size = UDim2.new(1, -40, 0, 14), Parent = Header,
    })
    New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), Parent = Header })

    local Content = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(0, HEADER_H), Size = UDim2.new(1, 0, 1, -HEADER_H),
        ClipsDescendants = true, Parent = Main,
    })
    local Cover = New("Frame", {
        BackgroundColor3 = Theme.Background, Size = UDim2.fromScale(1, 1), ZIndex = 20, Visible = false, Parent = Content,
    })

    ------------------------------------------------------------ smooth dragging
    local function HookDrag(frame)
        frame.InputBegan:Connect(function(input)
            if not IsClick(input) then return end
            local startMouse, origin = MousePos(), Window.Target
            BeginDrag(function(m)
                local t = origin + (m - startMouse)
                local view = Viewport()
                local half = Holder.AbsoluteSize / 2
                Window.Target = Vector2.new(
                    math.clamp(t.X, -half.X + 100, view.X + half.X - 100),
                    math.clamp(t.Y, half.Y - 10, view.Y + half.Y - 60)
                )
            end)
        end)
    end
    HookDrag(Brand)
    HookDrag(Header)

    function Window:_Step(dt)
        local diff = self.Target - self.Current
        if diff.Magnitude < 0.1 then
            if self.Current ~= self.Target then
                self.Current = self.Target
                Holder.Position = UDim2.fromOffset(math.floor(self.Target.X + 0.5), math.floor(self.Target.Y + 0.5))
            end
            return
        end
        self.Current = self.Current:Lerp(self.Target, 1 - math.exp(-dt * Library.DragSmoothness))
        Holder.Position = UDim2.fromOffset(math.floor(self.Current.X + 0.5), math.floor(self.Current.Y + 0.5))
    end

    ------------------------------------------------------------ open / close
    function Window:SetOpen(state)
        state = state and true or false
        if self.Open == state then return end
        self.Open = state
        Library:ClosePopup()
        if state then
            Holder.Visible = true
            Tween(Canvas, { GroupTransparency = 0 }, 0.28)
            Tween(Scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            for _, layer in ipairs(shadows) do Tween(layer, { BackgroundTransparency = 0.91 }, 0.3) end
        else
            Tween(Canvas, { GroupTransparency = 1 }, 0.2)
            Tween(Scale, { Scale = 0.94 }, 0.2)
            local t
            for _, layer in ipairs(shadows) do t = Tween(layer, { BackgroundTransparency = 1 }, 0.2) end
            t.Completed:Connect(function()
                if not self.Open then Holder.Visible = false end
            end)
        end
    end

    function Window:Toggle() self:SetOpen(not self.Open) end

    ------------------------------------------------------------ tabs
    function Window:SelectTab(tab)
        if self.ActiveTab == tab then return end
        Library:ClosePopup()
        local old = self.ActiveTab
        if old then
            old.Page.Visible = false
            Tween(old.Button, { TextColor3 = Theme.SubText }, 0.2)
        end
        self.ActiveTab = tab

        tab.Page.Visible = true
        tab.Page.Position = UDim2.fromOffset(0, 14)
        Tween(tab.Page, { Position = UDim2.fromOffset(0, 0) }, 0.35)
        Cover.Visible = true
        Cover.BackgroundTransparency = 0
        local ct = Tween(Cover, { BackgroundTransparency = 1 }, 0.3)
        ct.Completed:Connect(function() if Cover.BackgroundTransparency >= 0.99 then Cover.Visible = false end end)

        PageTitle.Text = tab.Name
        PageDesc.Text = tab.Description or ""
        PageTitle.Position = UDim2.new(0, 20, 0.5, tab.Description and -16 or -9)
        PageTitle.TextTransparency, PageDesc.TextTransparency = 1, 1
        Tween(PageTitle, { TextTransparency = 0 }, 0.3)
        Tween(PageDesc, { TextTransparency = 0 }, 0.3)

        Tween(tab.Button, { TextColor3 = Theme.Text }, 0.2)
        local pos = UDim2.fromOffset(10, tab.Y)
        if old then
            Tween(TabHighlight, { Position = pos }, 0.32)
        else
            TabHighlight.Visible = true
            TabHighlight.Position = pos
        end
    end

    function Window:AddTab(name, description)
        local index = #self.Tabs + 1
        local Tab = { Name = name, Description = description, LeftOrder = 0, RightOrder = 0, Y = (index - 1) * (TAB_H + TAB_GAP) }

        local Btn = MakeText("TextButton", {
            Text = name, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(10, Tab.Y),
            Size = UDim2.new(1, -20, 0, TAB_H), ZIndex = 2, Parent = TabList,
        })
        Padding(Btn, 0, 0, 16, 8)
        Tab.Button = Btn
        TabList.CanvasSize = UDim2.fromOffset(0, index * (TAB_H + TAB_GAP))

        local Page = New("Frame", {
            BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = Content,
        })
        Tab.Page = Page

        local function Column(xScale, xOffset)
            local col = New("ScrollingFrame", {
                BackgroundTransparency = 1, Position = UDim2.new(xScale, xOffset, 0, 0), Size = UDim2.new(0.5, -21, 1, 0),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2,
                ScrollBarImageColor3 = Theme.Highlight, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = Page,
            })
            Padding(col, 14, 14, 1, 5)
            List(col, 12)
            col:GetPropertyChangedSignal("CanvasPosition"):Connect(function() Library:ClosePopup() end)
            return col
        end
        Tab.Left = Column(0, 14)
        Tab.Right = Column(0.5, 7)

        Btn.MouseButton1Click:Connect(function() Window:SelectTab(Tab) end)
        Btn.MouseEnter:Connect(function() if Window.ActiveTab ~= Tab then Tween(Btn, { TextColor3 = Theme.Text }, 0.15) end end)
        Btn.MouseLeave:Connect(function() if Window.ActiveTab ~= Tab then Tween(Btn, { TextColor3 = Theme.SubText }, 0.15) end end)

        function Tab:AddLeftGroupbox(n) self.LeftOrder += 1; return NewGroupbox(self.Left, n, self.LeftOrder) end
        function Tab:AddRightGroupbox(n) self.RightOrder += 1; return NewGroupbox(self.Right, n, self.RightOrder) end
        function Tab:AddLeftTabbox() self.LeftOrder += 1; return NewTabbox(self.Left, self.LeftOrder) end
        function Tab:AddRightTabbox() self.RightOrder += 1; return NewTabbox(self.Right, self.RightOrder) end

        table.insert(self.Tabs, Tab)
        if not self.ActiveTab then self:SelectTab(Tab) end
        return Tab
    end

    table.insert(Library.Windows, Window)
    task.defer(function() Window:SetOpen(cfg.AutoShow ~= false) end)
    return Window
end

---------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------
function Library:Notify(a, b)
    local title, text, duration
    if type(a) == "table" then
        title, text, duration = a.Title, a.Text or a.Content or "", a.Duration
    else
        text, duration = tostring(a), b
    end
    title = title or "Kraxx"
    duration = duration or 4

    local width = 300
    local textH = TextService:GetTextSize(text, 13, FONT, Vector2.new(width - 62, 1000)).Y
    local height = math.max(textH + 44, 58)

    self.NotifyOrder += 1
    local Slot = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), LayoutOrder = self.NotifyOrder, Parent = self.NotifyHolder,
    })
    local Card = New("CanvasGroup", {
        BackgroundColor3 = Theme.Section, Position = UDim2.fromOffset(50, 0), Size = UDim2.fromScale(1, 1),
        GroupTransparency = 1, Parent = Slot,
    })
    Corner(Card, 8)
    local border = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 5, Parent = Card,
    })
    Corner(border, 7)
    Stroke(border, Theme.Highlight, 1, 0.45)

    local Icon = New("Frame", { BackgroundColor3 = Theme.Accent, Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(24, 24), Parent = Card })
    Corner(Icon, 6)
    AccentGradient(Icon, 45)
    MakeText("TextLabel", {
        Text = "!", Bold = true, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1), Parent = Icon,
    })

    MakeText("TextLabel", {
        Text = title, Bold = true, TextSize = 14, Position = UDim2.fromOffset(48, 12), Size = UDim2.new(1, -62, 0, 16), Parent = Card,
    })
    MakeText("TextLabel", {
        Text = text, TextColor3 = Theme.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
        Position = UDim2.fromOffset(48, 31), Size = UDim2.new(1, -62, 0, textH), Parent = Card,
    })
    local Track = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), Parent = Card,
    })
    local Progress = New("Frame", { BackgroundColor3 = Theme.Accent, Size = UDim2.fromScale(1, 1), Parent = Track })
    AccentGradient(Progress)

    Tween(Card, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, 0.4)
    Tween(Progress, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)

    task.delay(duration, function()
        if not Slot.Parent then return end
        local t = Tween(Card, { Position = UDim2.fromOffset(50, 0), GroupTransparency = 1 }, 0.3)
        t.Completed:Wait()
        local t2 = Tween(Slot, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
        t2.Completed:Wait()
        Slot:Destroy()
    end)
end

---------------------------------------------------------------------
-- Watermark
---------------------------------------------------------------------
function Library:SetWatermark(text)
    if not self.Watermark then
        local wm = New("Frame", {
            BackgroundColor3 = Theme.Section, Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(0, 30),
            AutomaticSize = Enum.AutomaticSize.X, ZIndex = 40, Parent = ScreenGui,
        })
        Corner(wm, 7)
        Stroke(wm, Theme.Highlight, 1, 0.45)
        Padding(wm, 0, 0, 10, 12)
        List(wm, 8, Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center)
        local logo = Reg(New("Frame", { Size = UDim2.fromOffset(16, 16), LayoutOrder = 1, Parent = wm }), "BackgroundColor3", "Accent")
        Corner(logo, 4)
        AccentGradient(logo, 45)
        self.WatermarkLabel = MakeText("TextLabel", {
            Text = "", TextSize = 13, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 2, Parent = wm,
        })
        self.Watermark = wm
    end
    self.WatermarkLabel.Text = text
end

function Library:SetWatermarkVisibility(state)
    if self.Watermark then self.Watermark.Visible = state end
end

---------------------------------------------------------------------
-- Misc API
---------------------------------------------------------------------
function Library:SetToggleKey(key)
    self.ToggleKey = NormalizeKey(key)
    for _, w in ipairs(self.Windows) do w:_UpdateHint() end
end

function Library:SetThemeColor(key, color)
    Theme[key] = color
    for _, entry in ipairs(self.Registry) do
        if entry.Key == key then
            pcall(function() entry.Object[entry.Property] = color end)
        end
    end
end

function Library:SetAccent(color) self:SetThemeColor("Accent", color) end

function Library:OnUnload(fn) table.insert(self.UnloadCallbacks, fn) end

function Library:Unload()
    if self.Unloaded then return end
    self.Unloaded = true
    for _, fn in ipairs(self.UnloadCallbacks) do SafeCall(fn) end
    self:ClosePopup()
    for _, w in ipairs(self.Windows) do w:SetOpen(false) end
    for _, c in ipairs(self.Connections) do c:Disconnect() end
    task.delay(0.25, function() ScreenGui:Destroy() end)
end

return Library
