--[[
    Kraxx UI  ·  v3
    Compact, sharp Roblox UI library with a Linoria-style API.

    • Square, pixel-crisp 1px borders, Code font, dense layout
    • Fades without CanvasGroups (text stays sharp), tweened states
    • Smooth lerped dragging, sliding tab marker, animated dropdowns
    • Toggles, sliders, buttons, dropdowns (single/multi), inputs,
      keybinds, colour pickers, labels, dividers, tabboxes,
      notifications, watermark

    Works with require() or loadstring(...)() — returns Library.
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TextService      = game:GetService("TextService")
local GuiService       = game:GetService("GuiService")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local FONT = Enum.Font.Code

local Library = {
    Theme = {
        Background = Color3.fromRGB(15, 15, 16),   -- panel behind groupboxes
        Main       = Color3.fromRGB(22, 22, 24),   -- window + groupboxes
        Element    = Color3.fromRGB(30, 30, 33),   -- boxes, bars, buttons
        Hover      = Color3.fromRGB(40, 40, 44),
        Outline    = Color3.fromRGB(44, 44, 48),   -- inner borders
        Border     = Color3.fromRGB(6, 6, 7),      -- outer / element borders
        Accent     = Color3.fromRGB(86, 156, 255),
        Text       = Color3.fromRGB(226, 226, 230),
        SubText    = Color3.fromRGB(136, 136, 144),
    },

    Flags = {}, Options = {}, Toggles = {},

    ToggleKey = "RightShift",
    DragSmoothness = 20,

    Registry = {}, Connections = {}, Windows = {}, UnloadCallbacks = {},
    Ordered = {},                 -- every element in creation order (used by configs)
    IgnoreFlags = {},             -- flags excluded from configs
    ConfigFolder = "Kraxx/configs",
    ConfigTitle = "Kraxx",
    ActivePopup = nil, ActiveDrag = nil, Picking = false, Unloaded = false, NotifyOrder = 0,
}
local Theme = Library.Theme

---------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------
local function New(class, props)
    local obj = Instance.new(class)
    if obj:IsA("GuiObject") then obj.BorderSizePixel = 0 end
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else obj[k] = v end
    end
    if parent then obj.Parent = parent end
    return obj
end

local function Tween(obj, props, time, style)
    local t = TweenService:Create(obj, TweenInfo.new(time or 0.15, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function Stroke(parent, color)
    return New("UIStroke", {
        Color = color or Theme.Border, Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter, Parent = parent,
    })
end

local function Padding(parent, t, b, l, r)
    return New("UIPadding", {
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0), Parent = parent,
    })
end

local function List(parent, padding, direction, hAlign, vAlign)
    return New("UIListLayout", {
        Padding = UDim.new(0, padding or 0), FillDirection = direction or Enum.FillDirection.Vertical,
        HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
        VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder, Parent = parent,
    })
end

-- subtle top-to-bottom shading, gives elements depth
local function Shade(parent)
    return New("UIGradient", {
        Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 205)), Parent = parent,
    })
end

local function MakeText(class, props)
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.Font = FONT
    props.TextSize = props.TextSize or 13
    props.TextColor3 = props.TextColor3 or Theme.Text
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    if class == "TextButton" and props.AutoButtonColor == nil then props.AutoButtonColor = false end
    return New(class, props)
end

local function TextSize(text, size, width)
    return TextService:GetTextSize(text, size or 13, FONT, Vector2.new(width or 10000, 10000))
end

local function Reg(obj, prop, key)
    obj[prop] = Theme[key]
    table.insert(Library.Registry, { Object = obj, Property = prop, Key = key })
    return obj
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
    return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
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
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    return vp - Vector2.new(0, GuiService:GetGuiInset().Y)
end

function Library:Connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(self.Connections, c)
    return c
end

---------------------------------------------------------------------
-- Crisp fading (tweens each object's transparency; no CanvasGroup blur)
---------------------------------------------------------------------
local TEXT_PROPS = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" }
local FadeProps = {
    Frame = { "BackgroundTransparency" },
    ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
    TextLabel = TEXT_PROPS, TextButton = TEXT_PROPS, TextBox = TEXT_PROPS,
    ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
    ImageButton = { "BackgroundTransparency", "ImageTransparency" },
    UIStroke = { "Transparency" },
}
local Base = setmetatable({}, { __mode = "k" })

local function Record(obj)
    local props = FadeProps[obj.ClassName]
    if not props then return nil end
    local b = Base[obj]
    if b then return b, false end
    b = {}
    for _, p in ipairs(props) do
        if obj[p] < 1 then b[p] = obj[p] end
    end
    Base[obj] = b
    return b, true
end

local function Walk(obj, fn)
    for _, child in ipairs(obj:GetChildren()) do
        if not (child:IsA("GuiObject") and not child.Visible) then
            fn(child)
            Walk(child, fn)
        end
    end
end

-- visible=true fades in, false fades out. fromZero forces a full fade-in.
local function Fade(root, visible, time, fromZero)
    local function apply(obj)
        local b, fresh = Record(obj)
        if not b then return end
        local goal = {}
        for p, val in pairs(b) do
            if visible then
                if fresh or fromZero then obj[p] = 1 end
                goal[p] = val
            else
                goal[p] = 1
            end
        end
        if next(goal) then Tween(obj, goal, time) end
    end
    apply(root)
    Walk(root, apply)
end

---------------------------------------------------------------------
-- Root GUI
---------------------------------------------------------------------
local ScreenGui = New("ScreenGui", {
    Name = "Kraxx", ResetOnSpawn = false, IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
})

do
    local parented = false
    local hui = (typeof(gethui) == "function") and gethui or nil
    if hui then parented = pcall(function() ScreenGui.Parent = hui() end) and ScreenGui.Parent ~= nil end
    if not parented then
        parented = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) and ScreenGui.Parent ~= nil
    end
    if not parented then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end
Library.ScreenGui = ScreenGui

Library.Overlay = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = ScreenGui })

Library.NotifyHolder = New("Frame", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 44), Size = UDim2.new(0, 400, 1, -52), ZIndex = 60, Parent = ScreenGui,
})
List(Library.NotifyHolder, 4)

---------------------------------------------------------------------
-- Popups
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

---------------------------------------------------------------------
-- Global input
---------------------------------------------------------------------
Library:Connect(UserInputService.InputBegan, function(input)
    if IsClick(input) and Library.ActivePopup then
        local p, pos = Library.ActivePopup, MousePos()
        if not IsOver(p.Frame, pos) and not (p.Owner and IsOver(p.Owner, pos)) then Library:ClosePopup() end
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
-- Shared object methods
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
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = parent,
    })
    List(holder, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
    return holder
end

local function BindLabelWidth(label, holder, left)
    local function update()
        local w = holder.AbsoluteSize.X
        label.Size = UDim2.new(1, -(left + w + (w > 0 and 6 or 0)), label.Size.Y.Scale, label.Size.Y.Offset)
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
    update()
end

local function Register(flag, obj, group, parent, cfg)
    obj.Flag, obj.Group, obj.ParentObj = flag, group, parent
    obj.Standalone = cfg and cfg.Standalone or nil
    if cfg and cfg.NoSave and flag then Library.IgnoreFlags[flag] = true end
    table.insert(Library.Ordered, obj)
    if not flag then return end
    Library.Options[flag] = obj
    if obj.Type == "Toggle" then Library.Toggles[flag] = obj end
end

-- standard hover/focus outline behaviour for boxes
local function HoverStroke(hit, stroke, isLocked)
    hit.MouseEnter:Connect(function() if not (isLocked and isLocked()) then Tween(stroke, { Color = Theme.Accent }, 0.12) end end)
    hit.MouseLeave:Connect(function() if not (isLocked and isLocked()) then Tween(stroke, { Color = Theme.Border }, 0.12) end end)
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
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextSize = 12,
        TextColor3 = Theme.SubText, Text = "", Parent = parentObj.AddonHolder,
    })

    local function Render()
        Btn.Text = "[" .. (picking and "..." or KB.Value) .. "]"
        local active = KB:GetState() and KB.Value ~= "None"
        Tween(Btn, { TextColor3 = (picking or active) and Theme.Accent or Theme.SubText }, 0.12)
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

    Btn.MouseEnter:Connect(function() if not picking then Tween(Btn, { TextColor3 = Theme.Text }, 0.12) end end)
    Btn.MouseLeave:Connect(function() if not picking then Render() end end)
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
        Library:Notify(("%s mode: %s"):format(KB.Text or parentObj.Text or "keybind", KB.Mode:lower()), 2)
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
    Register(flag, KB, parentObj.Group, parentObj, cfg)
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
        Type = "ColorPicker", Value = cfg.Default or Color3.new(1, 1, 1), Text = cfg.Text, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local h, s, v = CP.Value:ToHSV()
    local opened = false

    local Swatch = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = CP.Value, Size = UDim2.fromOffset(24, 12),
        Parent = parentObj.AddonHolder,
    })
    local SwatchStroke = Stroke(Swatch)
    HoverStroke(Swatch, SwatchStroke, function() return opened end)

    local W, H = 214, 232
    local Popup = New("Frame", {
        BackgroundColor3 = Theme.Main, Size = UDim2.fromOffset(W, H), Visible = false, Parent = Library.Overlay,
    })
    Stroke(Popup)
    local inner = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 5, Parent = Popup })
    Stroke(inner, Theme.Outline)
    Reg(New("Frame", { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, 1), ZIndex = 6, Parent = Popup }), "BackgroundColor3", "Accent")

    MakeText("TextLabel", {
        Text = cfg.Title or parentObj.Text or "colour", Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 0, 20), Parent = Popup,
    })

    local SV = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromHSV(h, 1, 1),
        Position = UDim2.fromOffset(8, 25), Size = UDim2.fromOffset(170, 170), Parent = Popup,
    })
    Stroke(SV)
    local Sat = New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = SV })
    New("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = Sat })
    local Val = New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), Parent = SV })
    New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = Val })
    local SVCursor = New("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), ZIndex = 3, Parent = SV,
    })
    Stroke(SVCursor)

    local Hue = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1),
        Position = UDim2.fromOffset(186, 25), Size = UDim2.fromOffset(18, 170), Parent = Popup,
    })
    Stroke(Hue)
    local keys = {}
    for i = 0, 6 do table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))) end
    New("UIGradient", { Rotation = 90, Color = ColorSequence.new(keys), Parent = Hue })
    local HueCursor = New("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(1, 0, 0, 2), ZIndex = 3, Parent = Hue,
    })
    Stroke(HueCursor)

    local HexFrame = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.fromOffset(8, 203), Size = UDim2.new(1, -16, 0, 20), Parent = Popup,
    })
    Shade(HexFrame)
    local HexStroke = Stroke(HexFrame)
    local HexBox = New("TextBox", {
        BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = Theme.Text, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "", PlaceholderText = "#ffffff", PlaceholderColor3 = Theme.SubText,
        Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), Parent = HexFrame,
    })

    local function Render()
        local col = Color3.fromHSV(h, s, v)
        SV.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        SVCursor.Position = UDim2.fromScale(s, 1 - v)
        HueCursor.Position = UDim2.new(0, 0, h, 0)
        Swatch.BackgroundColor3 = col
        if not HexBox:IsFocused() then HexBox.Text = "#" .. col:ToHex():lower() end
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

    HexBox.Focused:Connect(function() Tween(HexStroke, { Color = Theme.Accent }, 0.12) end)
    HexBox.FocusLost:Connect(function()
        Tween(HexStroke, { Color = Theme.Border }, 0.12)
        local ok, col = pcall(Color3.fromHex, (HexBox.Text:gsub("#", "")))
        if ok and col then CP:SetValueRGB(col) else Render() end
    end)

    local function Close()
        opened = false
        Tween(SwatchStroke, { Color = Theme.Border }, 0.12)
        Fade(Popup, false, 0.12)
        task.delay(0.13, function() if not opened then Popup.Visible = false end end)
    end

    local function Open()
        opened = true
        Popup.Visible = true
        Fade(Popup, true, 0.15, true)
        Tween(SwatchStroke, { Color = Theme.Accent }, 0.12)
        Library:OpenPopup({
            Frame = Popup, Owner = Swatch, Close = Close,
            Follow = function()
                local sp, ss = Swatch.AbsolutePosition, Swatch.AbsoluteSize
                local vp = Viewport()
                local x = math.clamp(sp.X + ss.X - W, 4, vp.X - W - 4)
                local y = sp.Y + ss.Y + 4
                if y + H > vp.Y - 4 then y = sp.Y - H - 4 end
                Popup.Position = UDim2.fromOffset(x, y)
            end,
        })
    end

    Swatch.MouseButton1Click:Connect(function()
        if opened then Library:ClosePopup() else Open() end
    end)

    Commit(true)
    Register(flag, CP, parentObj.Group, parentObj, cfg)
    return CP
end

function ObjectMethods:AddKeybind(flag, cfg) return CreateKeybind(self, flag, cfg) end
function ObjectMethods:AddColorPicker(flag, cfg) return CreateColorPicker(self, flag, cfg) end

---------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------
local Elements = {}
Elements.__index = Elements

function Elements:_Next()
    self.Order += 1
    return self.Order
end

local function FieldLabel(parent, text)
    return MakeText("TextLabel", { Text = text, TextColor3 = Theme.Text, Size = UDim2.new(1, 0, 0, 14), Parent = parent })
end

-- Label ------------------------------------------------------------------
function Elements:AddLabel(text, wrap)
    if type(text) == "table" then text, wrap = text.Text, text.DoesWrap end
    local Label = setmetatable({ Type = "Label", Text = text, Changed = {} }, ObjectMeta)

    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, wrap and 0 or 16),
        AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    local TL = MakeText("TextLabel", {
        Text = text or "", TextColor3 = wrap and Theme.SubText or Theme.Text, TextWrapped = wrap or false,
        Size = wrap and UDim2.new(1, 0, 0, 0) or UDim2.new(1, 0, 1, 0),
        AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        TextTruncate = wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd, Parent = Row,
    })
    Label.AddonHolder = AddonHolder(Row)
    if not wrap then BindLabelWidth(TL, Label.AddonHolder, 0) end

    function Label:SetText(t) self.Text = t; TL.Text = t end
    Register(nil, Label, self)
    return Label
end

-- Divider ----------------------------------------------------------------
function Elements:AddDivider()
    local Row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 5), LayoutOrder = self:_Next(), Parent = self.Container })
    New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 1), Parent = Row })
    Register(nil, { Type = "Divider" }, self)
end

-- Button -----------------------------------------------------------------
function Elements:AddButton(cfg, callback)
    if type(cfg) == "string" then cfg = { Text = cfg, Func = callback } end
    cfg = cfg or {}
    local func = cfg.Func or cfg.Callback or callback
    local Button = setmetatable({ Type = "Button", Text = cfg.Text or "button", Changed = {} }, ObjectMeta)
    local armed = false

    local B = MakeText("TextButton", {
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Element, Text = Button.Text,
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20),
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    Shade(B)
    local BStroke = Stroke(B)
    HoverStroke(B, BStroke)

    local function Disarm()
        armed = false
        B.Text = Button.Text
        Tween(B, { TextColor3 = Theme.Text }, 0.12)
    end

    B.MouseButton1Click:Connect(function()
        B.BackgroundColor3 = Theme.Hover
        Tween(B, { BackgroundColor3 = Theme.Element }, 0.25)
        if cfg.DoubleClick then
            if armed then
                Disarm()
                SafeCall(func)
            else
                armed = true
                B.Text = "are you sure?"
                Tween(B, { TextColor3 = Theme.Accent }, 0.12)
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

-- Toggle -----------------------------------------------------------------
function Elements:AddToggle(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local Toggle = setmetatable({
        Type = "Toggle", Value = cfg.Default == true, Text = cfg.Text or flag, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local hovering = false

    local Row = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
        LayoutOrder = self:_Next(), Parent = self.Container,
    })
    local Box = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.new(0, 1, 0.5, -6), Size = UDim2.fromOffset(12, 12), Parent = Row,
    })
    Shade(Box)
    local BoxStroke = Stroke(Box)
    local Lbl = MakeText("TextLabel", {
        Text = Toggle.Text, TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -20, 1, 0), Parent = Row,
    })
    Toggle.AddonHolder = AddonHolder(Row)
    BindLabelWidth(Lbl, Toggle.AddonHolder, 20)

    local function Render(time)
        local on = Toggle.Value
        Tween(Box, { BackgroundColor3 = on and Theme.Accent or (hovering and Theme.Hover or Theme.Element) }, time)
        Tween(BoxStroke, { Color = hovering and Theme.Accent or Theme.Border }, time)
        Tween(Lbl, { TextColor3 = (on or hovering) and Theme.Text or Theme.SubText }, time)
    end

    function Toggle:SetValue(value, silent)
        value = value and true or false
        if value == self.Value then return end
        self.Value = value
        if flag then Library.Flags[flag] = value end
        Render(0.15)
        if not silent then Fire(self, value) end
    end
    function Toggle:SetText(t) self.Text = t; Lbl.Text = t end

    Row.MouseButton1Click:Connect(function() Toggle:SetValue(not Toggle.Value) end)
    Row.MouseEnter:Connect(function() hovering = true; Render(0.12) end)
    Row.MouseLeave:Connect(function() hovering = false; Render(0.12) end)

    if flag then Library.Flags[flag] = Toggle.Value end
    Render(0)
    -- registry: keep the "on" colour following accent changes
    table.insert(Library.Registry, { Object = Box, Property = "BackgroundColor3", Key = "Accent", When = function() return Toggle.Value end })
    Register(flag, Toggle, self, nil, cfg)
    return Toggle
end

-- Slider -----------------------------------------------------------------
function Elements:AddSlider(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local min, max = cfg.Min or 0, cfg.Max or 100
    local rounding = cfg.Rounding or 0
    local suffix = cfg.Suffix or ""
    local showMax = cfg.ShowMax ~= false
    local Slider = setmetatable({
        Type = "Slider", Min = min, Max = max, Value = nil, Text = cfg.Text or flag, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local dragging = false

    local Row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = self:_Next(), Parent = self.Container })
    FieldLabel(Row, Slider.Text)
    local Bar = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Element,
        Position = UDim2.fromOffset(0, 17), Size = UDim2.new(1, 0, 0, 14), Parent = Row,
    })
    Shade(Bar)
    local BarStroke = Stroke(Bar)
    HoverStroke(Bar, BarStroke, function() return dragging end)
    local Fill = Reg(New("Frame", { Size = UDim2.fromScale(0, 1), Parent = Bar }), "BackgroundColor3", "Accent")
    Shade(Fill)
    local ValLbl = MakeText("TextLabel", {
        Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.45,
        TextStrokeColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = Bar,
    })

    local function RoundTo(n)
        local m = 10 ^ rounding
        return math.floor(n * m + 0.5) / m
    end
    local function Format(n)
        if rounding <= 0 then return tostring(math.floor(n + 0.5)) end
        return string.format("%." .. rounding .. "f", n)
    end

    function Slider:SetValue(value, silent)
        value = RoundTo(math.clamp(tonumber(value) or min, min, max))
        local changed = value ~= self.Value
        self.Value = value
        if flag then Library.Flags[flag] = value end
        local pct = (max == min) and 0 or (value - min) / (max - min)
        Tween(Fill, { Size = UDim2.fromScale(pct, 1) }, 0.08)
        ValLbl.Text = Format(value) .. suffix .. (showMax and ("/" .. Format(max) .. suffix) or "")
        if changed and not silent then Fire(self, value) end
    end
    function Slider:SetMin(n) min = n; self.Min = n; self:SetValue(self.Value) end
    function Slider:SetMax(n) max = n; self.Max = n; self:SetValue(self.Value) end

    Bar.InputBegan:Connect(function(input)
        if not IsClick(input) then return end
        dragging = true
        Tween(BarStroke, { Color = Theme.Accent }, 0.12)
        BeginDrag(function(m)
            local pct = math.clamp((m.X - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
            Slider:SetValue(min + (max - min) * pct)
        end, function()
            dragging = false
            if not IsOver(Bar, MousePos()) then Tween(BarStroke, { Color = Theme.Border }, 0.12) end
        end)
    end)

    Slider:SetValue(cfg.Default or min, true)
    Register(flag, Slider, self, nil, cfg)
    return Slider
end

-- Dropdown ---------------------------------------------------------------
function Elements:AddDropdown(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local Dropdown = setmetatable({
        Type = "Dropdown", Values = cfg.Values or {}, Multi = cfg.Multi == true, Text = cfg.Text,
        Value = nil, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)
    local opened = false
    local optionButtons = {}
    local ROW_H = 18

    local hasText = cfg.Text ~= nil
    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, hasText and 38 or 20), LayoutOrder = self:_Next(), Parent = self.Container,
    })
    if hasText then FieldLabel(Row, cfg.Text) end
    local Box = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Element,
        Position = UDim2.fromOffset(0, hasText and 18 or 0), Size = UDim2.new(1, 0, 0, 20), Parent = Row,
    })
    Shade(Box)
    local BoxStroke = Stroke(Box)
    HoverStroke(Box, BoxStroke, function() return opened end)
    local Display = MakeText("TextLabel", {
        Text = "--", TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -26, 1, 0), Parent = Box,
    })
    local Arrow = MakeText("TextLabel", {
        Text = "▼", TextSize = 8, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(12, 12), Parent = Box,
    })

    local List_ = New("Frame", {
        BackgroundColor3 = Theme.Element, Size = UDim2.fromOffset(100, 0), ClipsDescendants = true,
        Visible = false, Parent = Library.Overlay,
    })
    local ListStroke = Stroke(List_, Theme.Accent)
    local Scroll = New("ScrollingFrame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y, Parent = List_,
    })
    List(Scroll, 0)

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
        Display.Text = text or "--"
        Display.TextColor3 = text and Theme.Text or Theme.SubText
        if flag then Library.Flags[flag] = Dropdown.Value end
    end

    local function RefreshOptions(time)
        for btn, val in pairs(optionButtons) do
            Tween(btn, { TextColor3 = IsSelected(val) and Theme.Accent or Theme.SubText }, time or 0.1)
        end
    end

    local function Select(val)
        if Dropdown.Multi then
            Dropdown.Value[val] = (not Dropdown.Value[val]) or nil
        else
            if Dropdown.Value == val and cfg.AllowNull then Dropdown.Value = nil else Dropdown.Value = val end
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
                BackgroundTransparency = 0, BackgroundColor3 = Theme.Element, Text = tostring(val),
                TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd,
                Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = i, Parent = Scroll,
            })
            Padding(btn, 0, 0, 6, 6)
            optionButtons[btn] = val
            btn.MouseEnter:Connect(function() Tween(btn, { BackgroundColor3 = Theme.Hover }, 0.08) end)
            btn.MouseLeave:Connect(function() Tween(btn, { BackgroundColor3 = Theme.Element }, 0.08) end)
            btn.MouseButton1Click:Connect(function() Select(val) end)
        end
    end

    local function Close()
        opened = false
        Tween(Arrow, { TextColor3 = Theme.SubText }, 0.12)
        Tween(BoxStroke, { Color = Theme.Border }, 0.12)
        local t = Tween(List_, { Size = UDim2.fromOffset(List_.AbsoluteSize.X, 0) }, 0.12)
        t.Completed:Connect(function() if not opened then List_.Visible = false end end)
    end

    local function Open()
        opened = true
        BuildOptions()
        RefreshOptions(0)
        local height = math.clamp(#Dropdown.Values, 1, cfg.MaxVisible or 8) * ROW_H
        local width = Box.AbsoluteSize.X
        Scroll.Size = UDim2.new(1, 0, 0, height)
        Scroll.CanvasPosition = Vector2.zero
        List_.Size = UDim2.fromOffset(width, 0)
        List_.Visible = true
        ListStroke.Color = Theme.Accent
        Tween(List_, { Size = UDim2.fromOffset(width, height) }, 0.18, Enum.EasingStyle.Quart)
        Tween(Arrow, { TextColor3 = Theme.Accent }, 0.12)
        Tween(BoxStroke, { Color = Theme.Accent }, 0.12)
        Library:OpenPopup({
            Frame = List_, Owner = Box, Close = Close,
            Follow = function()
                local bp, bs = Box.AbsolutePosition, Box.AbsoluteSize
                List_.Position = UDim2.fromOffset(bp.X, bp.Y + bs.Y + 1)
            end,
        })
    end

    Box.MouseButton1Click:Connect(function()
        if opened then Library:ClosePopup() else Open() end
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

    Register(flag, Dropdown, self, nil, cfg)
    return Dropdown
end

-- Input ------------------------------------------------------------------
function Elements:AddInput(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    local Input = setmetatable({
        Type = "Input", Value = tostring(cfg.Default or ""), Text = cfg.Text, Changed = {}, Callback = cfg.Callback,
    }, ObjectMeta)

    local hasText = cfg.Text ~= nil
    local Row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, hasText and 38 or 20), LayoutOrder = self:_Next(), Parent = self.Container,
    })
    if hasText then FieldLabel(Row, cfg.Text) end
    local Box = New("Frame", {
        BackgroundColor3 = Theme.Element, Position = UDim2.fromOffset(0, hasText and 18 or 0),
        Size = UDim2.new(1, 0, 0, 20), ClipsDescendants = true, Parent = Row,
    })
    Shade(Box)
    local BoxStroke = Stroke(Box)
    local TB = New("TextBox", {
        BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = Theme.Text,
        PlaceholderText = cfg.Placeholder or "", PlaceholderColor3 = Theme.SubText, Text = Input.Value,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true,
        Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), Parent = Box,
    })
    HoverStroke(Box, BoxStroke, function() return TB:IsFocused() end)

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

    TB.Focused:Connect(function() Tween(BoxStroke, { Color = Theme.Accent }, 0.12) end)
    TB.FocusLost:Connect(function()
        Tween(BoxStroke, { Color = Theme.Border }, 0.12)
        if cfg.Finished then Commit() end
    end)
    if not cfg.Finished then TB:GetPropertyChangedSignal("Text"):Connect(Commit) end

    if flag then Library.Flags[flag] = Input.Value end
    Register(flag, Input, self, nil, cfg)
    return Input
end

-- Standalone keybind / colour picker rows ---------------------------------
function Elements:AddKeybind(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    return CreateKeybind(self:AddLabel(cfg.Text or flag or "keybind"), flag, cfg)
end

function Elements:AddColorPicker(flag, cfg)
    flag, cfg = NormArgs(flag, cfg)
    return CreateColorPicker(self:AddLabel(cfg.Text or flag or "colour"), flag, cfg)
end

---------------------------------------------------------------------
-- Groupbox / Tabbox
---------------------------------------------------------------------
local function SectionFrame(parent, order)
    local Box = New("Frame", {
        BackgroundColor3 = Theme.Main, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = order, Parent = parent,
    })
    Stroke(Box, Theme.Outline)
    List(Box, 0)
    Reg(New("Frame", { Size = UDim2.new(1, 0, 0, 1), LayoutOrder = 0, Parent = Box }), "BackgroundColor3", "Accent")
    return Box
end

local function ElementContainer(parent, order)
    local c = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = order, Parent = parent,
    })
    Padding(c, 4, 8, 8, 8)
    List(c, 5)
    return c
end

local function NewGroupbox(column, name, order)
    local Box = SectionFrame(column, order)
    local Header = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Parent = Box })
    MakeText("TextLabel", { Text = name, Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 1, -2), Parent = Header })
    local Container = ElementContainer(Box, 2)
    return setmetatable({ Frame = Box, Container = Container, Order = 0, Name = name }, Elements)
end

local function NewTabbox(column, order)
    local Box = SectionFrame(column, order)
    local Bar = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Parent = Box })
    local Holder = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = Box,
    })
    local Tabbox = { Tabs = {}, Active = nil, Frame = Box }

    local function Layout()
        local n = #Tabbox.Tabs
        for i, t in ipairs(Tabbox.Tabs) do
            t.Button.Size = UDim2.new(1 / n, 0, 1, 0)
            t.Button.Position = UDim2.new((i - 1) / n, 0, 0, 0)
            t.Divider.Visible = i > 1
        end
    end

    function Tabbox:Select(sub)
        if self.Active == sub then return end
        Library:ClosePopup()
        self.Active = sub
        for _, t in ipairs(self.Tabs) do
            local on = t == sub
            t.Container.Visible = on
            t.Bottom.Visible = not on
            Tween(t.Button, { BackgroundColor3 = on and Theme.Main or Theme.Background, TextColor3 = on and Theme.Text or Theme.SubText }, 0.12)
        end
        Fade(sub.Container, true, 0.15, true)
    end

    function Tabbox:AddTab(name)
        local Container = ElementContainer(Holder, #self.Tabs + 1)
        Container.Visible = false
        local Btn = MakeText("TextButton", {
            BackgroundTransparency = 0, BackgroundColor3 = Theme.Background, Text = name,
            TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Parent = Bar,
        })
        local bottom = New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), Parent = Btn })
        local divider = New("Frame", { BackgroundColor3 = Theme.Outline, Size = UDim2.new(0, 1, 1, 0), Parent = Btn })
        local sub = setmetatable({ Container = Container, Order = 0, Button = Btn, Bottom = bottom, Divider = divider, Name = name }, Elements)
        table.insert(self.Tabs, sub)
        Btn.MouseButton1Click:Connect(function() self:Select(sub) end)
        Btn.MouseEnter:Connect(function() if self.Active ~= sub then Tween(Btn, { TextColor3 = Theme.Text }, 0.12) end end)
        Btn.MouseLeave:Connect(function() if self.Active ~= sub then Tween(Btn, { TextColor3 = Theme.SubText }, 0.12) end end)
        Layout()
        if not self.Active then self:Select(sub) end
        return sub
    end

    return Tabbox
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
function Library:CreateWindow(cfg)
    cfg = cfg or {}
    if cfg.ToggleKey then self.ToggleKey = NormalizeKey(cfg.ToggleKey) end
    if cfg.ConfigFolder then self.ConfigFolder = cfg.ConfigFolder end

    local size = cfg.Size or UDim2.fromOffset(560, 600)
    local start = cfg.Position and Vector2.new(cfg.Position.X.Offset, cfg.Position.Y.Offset) or (Viewport() / 2)
    local Window = { Tabs = {}, Open = false, ActiveTab = nil, Current = start, Target = start, FirstOpen = true }

    local Holder = New("Frame", {
        Name = "Window", BackgroundColor3 = Theme.Main, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(start.X, start.Y), Size = size, Visible = false, Active = true, Parent = ScreenGui,
    })
    Stroke(Holder, Theme.Border)
    local Edge = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 10, Parent = Holder })
    Stroke(Edge, Theme.Outline)
    Reg(New("Frame", { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, 1), ZIndex = 11, Parent = Holder }), "BackgroundColor3", "Accent")
    local Scale = New("UIScale", { Scale = 0.97, Parent = Holder })
    New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Modal = true, Parent = Holder })

    -- title bar (drag handle)
    local TitleBar = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Parent = Holder })
    local title = cfg.Title or "Kraxx"
    if cfg.Subtitle then
        title = title .. ' <font color="#' .. Theme.SubText:ToHex() .. '">| ' .. cfg.Subtitle .. "</font>"
    end
    MakeText("TextLabel", { RichText = true, Text = title, Position = UDim2.fromOffset(9, 3), Size = UDim2.new(1, -120, 1, -3), Parent = TitleBar })
    local KeyHint = MakeText("TextLabel", {
        Text = "", TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -9, 0, 3), Size = UDim2.new(0, 110, 1, -3), Parent = TitleBar,
    })
    function Window:_UpdateHint() KeyHint.Text = "[" .. Library.ToggleKey:lower() .. "]" end
    Window:_UpdateHint()

    -- tabs + content panel
    local Body = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -16, 1, -36), Parent = Holder })
    local TabRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), ZIndex = 3, Parent = Body })
    local Marker = Reg(New("Frame", { Size = UDim2.new(0, 0, 0, 1), ZIndex = 5, Parent = TabRow }), "BackgroundColor3", "Accent")
    local Panel = New("Frame", { BackgroundColor3 = Theme.Background, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22), Parent = Body })
    Stroke(Panel, Theme.Outline)

    -- smooth drag
    TitleBar.InputBegan:Connect(function(input)
        if not IsClick(input) then return end
        local startMouse, origin = MousePos(), Window.Target
        BeginDrag(function(m)
            local t = origin + (m - startMouse)
            local view, half = Viewport(), Holder.AbsoluteSize / 2
            Window.Target = Vector2.new(
                math.clamp(t.X, -half.X + 60, view.X + half.X - 60),
                math.clamp(t.Y, half.Y, view.Y + half.Y - 26)
            )
        end)
    end)

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

    function Window:SetOpen(state)
        state = state and true or false
        if self.Open == state then return end
        self.Open = state
        Library:ClosePopup()
        if state then
            Holder.Visible = true
            Fade(Holder, true, 0.2, self.FirstOpen)
            self.FirstOpen = false
            Tween(Scale, { Scale = 1 }, 0.2)
        else
            Fade(Holder, false, 0.16)
            Tween(Scale, { Scale = 0.97 }, 0.16)
            task.delay(0.17, function() if not self.Open then Holder.Visible = false end end)
        end
    end
    function Window:Toggle() self:SetOpen(not self.Open) end

    local function LayoutTabs(animate)
        local n = #Window.Tabs
        for i, t in ipairs(Window.Tabs) do
            local on = t == Window.ActiveTab
            t.Button.Position = UDim2.new((i - 1) / n, 0, 0, 0)
            t.Button.Size = UDim2.new(1 / n, i == n and 0 or 1, 0, on and 23 or 22)
            t.Right.Visible = i == n
            if on then
                local pos, sz = UDim2.new((i - 1) / n, 1, 0, 0), UDim2.new(1 / n, i == n and -2 or -1, 0, 2)
                if animate then Tween(Marker, { Position = pos, Size = sz }, 0.2, Enum.EasingStyle.Quart)
                else Marker.Position, Marker.Size = pos, sz end
            end
        end
    end

    function Window:SelectTab(tab)
        if self.ActiveTab == tab then return end
        Library:ClosePopup()
        local old = self.ActiveTab
        self.ActiveTab = tab
        for _, t in ipairs(self.Tabs) do
            local on = t == tab
            t.Page.Visible = on
            t.Bottom.Visible = not on
            t.Button.BackgroundColor3 = on and Theme.Background or Theme.Main
            Tween(t.Button, { TextColor3 = on and Theme.Text or Theme.SubText }, 0.12)
        end
        LayoutTabs(old ~= nil)
        if old and self.Open then Fade(tab.Page, true, 0.18, true) end
    end

    function Window:AddTab(name)
        local Tab = { Name = name, LeftOrder = 0, RightOrder = 0 }

        local Btn = MakeText("TextButton", {
            BackgroundTransparency = 0, BackgroundColor3 = Theme.Main, Text = name, TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3, Parent = TabRow,
        })
        New("Frame", { BackgroundColor3 = Theme.Outline, Size = UDim2.new(1, 0, 0, 1), ZIndex = 3, Parent = Btn })
        New("Frame", { BackgroundColor3 = Theme.Outline, Size = UDim2.new(0, 1, 1, 0), ZIndex = 3, Parent = Btn })
        Tab.Right = New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 3, Parent = Btn })
        Tab.Bottom = New("Frame", { BackgroundColor3 = Theme.Outline, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3, Parent = Btn })
        Tab.Button = Btn

        local Page = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = Panel })
        Tab.Page = Page

        local function Column(xScale, xOffset)
            local col = New("ScrollingFrame", {
                BackgroundTransparency = 1, Position = UDim2.new(xScale, xOffset, 0, 8), Size = UDim2.new(0.5, -12, 1, -16),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2,
                ScrollBarImageColor3 = Theme.Accent, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = Page,
            })
            Padding(col, 1, 1, 1, 4)
            List(col, 8)
            col:GetPropertyChangedSignal("CanvasPosition"):Connect(function() Library:ClosePopup() end)
            return col
        end
        Tab.Left = Column(0, 8)
        Tab.Right_ = Column(0.5, 4)

        Btn.MouseButton1Click:Connect(function() Window:SelectTab(Tab) end)
        Btn.MouseEnter:Connect(function() if Window.ActiveTab ~= Tab then Tween(Btn, { TextColor3 = Theme.Text }, 0.12) end end)
        Btn.MouseLeave:Connect(function() if Window.ActiveTab ~= Tab then Tween(Btn, { TextColor3 = Theme.SubText }, 0.12) end end)

        function Tab:AddLeftGroupbox(n) self.LeftOrder += 1; return NewGroupbox(self.Left, n, self.LeftOrder) end
        function Tab:AddRightGroupbox(n) self.RightOrder += 1; return NewGroupbox(self.Right_, n, self.RightOrder) end
        function Tab:AddLeftTabbox() self.LeftOrder += 1; return NewTabbox(self.Left, self.LeftOrder) end
        function Tab:AddRightTabbox() self.RightOrder += 1; return NewTabbox(self.Right_, self.RightOrder) end

        local isSettings = self._BuildingSettings == true
        if self.SettingsTab and not isSettings then
            table.insert(self.Tabs, #self.Tabs, Tab)   -- settings always stays last
        else
            table.insert(self.Tabs, Tab)
        end
        if isSettings then self.SettingsTab = Tab end

        if not self.ActiveTab then
            self:SelectTab(Tab)
        elseif not isSettings and not self.UserTabSelected then
            self.UserTabSelected = true
            self:SelectTab(Tab)
        else
            LayoutTabs(false)
        end
        return Tab
    end

    if cfg.SettingsTab ~= false then
        Window._BuildingSettings = true
        Library:_BuildSettingsTab(Window, cfg.SettingsTabName)
        Window._BuildingSettings = false
    end

    table.insert(Library.Windows, Window)
    task.defer(function() Window:SetOpen(cfg.AutoShow ~= false) end)
    -- runs once your script has finished building the UI
    if cfg.AutoLoadConfig ~= false then
        task.defer(function() if not Library.AutoloadDone then Library:LoadAutoloadConfig() end end)
    end
    return Window
end

---------------------------------------------------------------------
-- Notifications (slide in from the left)
---------------------------------------------------------------------
function Library:Notify(a, b)
    local text, duration
    if type(a) == "table" then
        text = a.Title and (a.Title .. ": " .. (a.Text or "")) or (a.Text or a.Content or "")
        duration = a.Duration
    else
        text, duration = tostring(a), b
    end
    duration = duration or 4

    local width = math.min(TextSize(text).X + 22, 380)
    local textH = TextSize(text, 13, width - 18).Y
    local height = textH + 10

    self.NotifyOrder += 1
    local Slot = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(width + 2, height + 2), LayoutOrder = self.NotifyOrder, Parent = self.NotifyHolder,
    })
    local Card = New("Frame", {
        BackgroundColor3 = Theme.Main, Position = UDim2.new(0, -(width + 20), 0, 1), Size = UDim2.fromOffset(width, height), Parent = Slot,
    })
    Stroke(Card, Theme.Border)
    local edge = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 3, Parent = Card })
    Stroke(edge, Theme.Outline)
    New("Frame", { BackgroundColor3 = Theme.Accent, Size = UDim2.new(0, 2, 1, 0), ZIndex = 4, Parent = Card })
    MakeText("TextLabel", {
        Text = text, TextWrapped = true, Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -18, 0, textH), Parent = Card,
    })
    local Progress = New("Frame", {
        BackgroundColor3 = Theme.Accent, Position = UDim2.new(0, 2, 1, -1), Size = UDim2.new(1, -2, 0, 1), ZIndex = 4, Parent = Card,
    })

    Tween(Card, { Position = UDim2.fromOffset(1, 1) }, 0.3, Enum.EasingStyle.Quart)
    Tween(Progress, { Size = UDim2.new(0, 0, 0, 1) }, duration, Enum.EasingStyle.Linear)

    task.delay(duration, function()
        if not Slot.Parent then return end
        Tween(Card, { Position = UDim2.new(0, -(width + 20), 0, 1) }, 0.25, Enum.EasingStyle.Quart).Completed:Wait()
        Tween(Slot, { Size = UDim2.fromOffset(width + 2, 0) }, 0.15).Completed:Wait()
        Slot:Destroy()
    end)
end

---------------------------------------------------------------------
-- Watermark
---------------------------------------------------------------------
function Library:SetWatermark(text)
    if not self.Watermark then
        local wm = New("Frame", {
            BackgroundColor3 = Theme.Main, Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X, ZIndex = 40, Parent = ScreenGui,
        })
        Stroke(wm, Theme.Border)
        local edge = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 41, Parent = wm })
        Stroke(edge, Theme.Outline)
        Reg(New("Frame", { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, 1), ZIndex = 42, Parent = wm }), "BackgroundColor3", "Accent")
        Padding(wm, 0, 0, 8, 8)
        self.WatermarkLabel = MakeText("TextLabel", {
            Text = "", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 1), ZIndex = 41, Parent = wm,
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
    for _, e in ipairs(self.Registry) do
        if e.Key == key and (not e.When or e.When()) then
            pcall(function() e.Object[e.Property] = color end)
        end
    end
end

function Library:SetAccent(color) self:SetThemeColor("Accent", color) end

---------------------------------------------------------------------
-- Config system (JSON files + readable export)
---------------------------------------------------------------------
local MemoryStore = {}   -- fallback when the environment has no file functions (e.g. Studio)

local function HasFS()
    return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end

local function EnsureFolder(path)
    if typeof(makefolder) ~= "function" or typeof(isfolder) ~= "function" then return end
    local built = ""
    for part in path:gmatch("[^/]+") do
        built = built == "" and part or (built .. "/" .. part)
        if not isfolder(built) then pcall(makefolder, built) end
    end
end

local function ConfigPath(name) return Library.ConfigFolder .. "/" .. name .. ".json" end
local function AutoloadPath() return Library.ConfigFolder .. "/autoload.txt" end

local function CleanName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil, "enter a config name" end
    if name:find("[^%w%s%-_%.]") then return nil, "config names can only use letters, numbers, spaces, - _ ." end
    return name
end

local function KeyPretty(key)
    if not key or key == "None" then return "none" end
    return (key:gsub("(%l)(%u)", "%1 %2"):lower())
end

local function PrettyValue(obj)
    local t = obj.Type
    if t == "Toggle" then return obj.Value and "True" or "False"
    elseif t == "Slider" then return tostring(obj.Value)
    elseif t == "Input" then return '"' .. obj.Value .. '"'
    elseif t == "Keybind" then return KeyPretty(obj.Value)
    elseif t == "ColorPicker" then return "#" .. obj.Value:ToHex():upper()
    elseif t == "Dropdown" then
        if obj.Multi then
            local parts = {}
            for _, v in ipairs(obj.Values) do
                if obj.Value[v] then table.insert(parts, '"' .. tostring(v) .. '"') end
            end
            return "[" .. table.concat(parts, ", ") .. "]"
        end
        return obj.Value ~= nil and ('"' .. tostring(obj.Value) .. '"') or "none"
    end
    return nil
end

function Library:SetFolder(folder) self.ConfigFolder = folder end

function Library:SetIgnoreFlags(list)
    for _, f in ipairs(list) do self.IgnoreFlags[f] = true end
end

-- table of every saveable flag -> JSON-safe value
function Library:GetConfigTable()
    local flags = {}
    for _, obj in ipairs(self.Ordered) do
        local f = obj.Flag
        if f and not self.IgnoreFlags[f] then
            local t = obj.Type
            if t == "Toggle" or t == "Slider" or t == "Input" then
                flags[f] = obj.Value
            elseif t == "Dropdown" then
                if obj.Multi then
                    local arr = {}
                    for _, v in ipairs(obj.Values) do if obj.Value[v] then table.insert(arr, v) end end
                    flags[f] = arr
                else
                    flags[f] = obj.Value
                end
            elseif t == "Keybind" then
                flags[f] = { key = obj.Value, mode = obj.Mode }
            elseif t == "ColorPicker" then
                flags[f] = "#" .. obj.Value:ToHex():upper()
            end
        end
    end
    return { title = self.ConfigTitle, flags = flags }
end

function Library:ApplyConfigTable(data)
    local flags = type(data) == "table" and (data.flags or data) or {}
    for _, obj in ipairs(self.Ordered) do
        local f = obj.Flag
        local val = f and flags[f]
        if val ~= nil and not self.IgnoreFlags[f] then
            local ok, err = pcall(function()
                local t = obj.Type
                if t == "Toggle" then obj:SetValue(val == true)
                elseif t == "Slider" then obj:SetValue(tonumber(val))
                elseif t == "Input" then obj:SetValue(tostring(val))
                elseif t == "Dropdown" then obj:SetValue(val)
                elseif t == "Keybind" then
                    if type(val) == "table" then obj:SetValue(val.key, val.mode) else obj:SetValue(val) end
                elseif t == "ColorPicker" then obj:SetValueRGB(Color3.fromHex((tostring(val):gsub("#", ""))))
                end
            end)
            if not ok then warn("[Kraxx] failed to load flag " .. f .. ": " .. tostring(err)) end
        end
    end
end

-- readable summary, e.g.  [fake ping]: True, amount: 80
function Library:ExportConfigText()
    local lines = { "-- " .. self.ConfigTitle }
    local current, lineOf = {}, {}
    local ordered = {}
    for _, obj in ipairs(self.Ordered) do
        if not (obj.Group and obj.Group.IsSettings) then table.insert(ordered, obj) end
    end
    for _, obj in ipairs(self.Ordered) do
        if obj.Group and obj.Group.IsSettings then table.insert(ordered, obj) end
    end
    for _, obj in ipairs(ordered) do
        local g = obj.Group
        if obj.Type == "Divider" or obj.Type == "Label" then
            current[g] = nil
        elseif obj.Flag and not self.IgnoreFlags[obj.Flag] then
            local value = PrettyValue(obj)
            if value then
                local parent = obj.ParentObj
                local label = obj.Text or (parent and parent.Text) or obj.Flag
                local idx
                if parent and lineOf[parent] then
                    idx = lineOf[parent]
                    if not obj.Text then label = obj.Type == "Keybind" and "bind" or "color" end
                elseif obj.Type ~= "Toggle" and not obj.Standalone and not parent then
                    idx = current[g]
                end
                label = tostring(label):lower()
                if idx then
                    lines[idx] = lines[idx] .. ", " .. label .. ": " .. value
                    lineOf[obj] = idx
                else
                    table.insert(lines, "[" .. label .. "]: " .. value)
                    lineOf[obj] = #lines
                    current[g] = obj.Type == "Toggle" and #lines or nil
                end
            end
        end
    end
    return table.concat(lines, "\n")
end

function Library:SaveConfig(name)
    local clean, err = CleanName(name)
    if not clean then return false, err end
    local ok, json = pcall(HttpService.JSONEncode, HttpService, self:GetConfigTable())
    if not ok then return false, "failed to encode config" end
    if HasFS() then
        EnsureFolder(self.ConfigFolder)
        local wrote, werr = pcall(writefile, ConfigPath(clean), json)
        if not wrote then return false, tostring(werr) end
    else
        MemoryStore[clean] = json
    end
    return true
end

function Library:LoadConfig(name)
    local clean, err = CleanName(name)
    if not clean then return false, err end
    local json
    if HasFS() then
        if not isfile(ConfigPath(clean)) then return false, "config not found" end
        json = readfile(ConfigPath(clean))
    else
        json = MemoryStore[clean]
    end
    if not json then return false, "config not found" end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
    if not ok or type(data) ~= "table" then return false, "config file is not valid json" end
    self:ApplyConfigTable(data)
    return true
end

function Library:DeleteConfig(name)
    local clean, err = CleanName(name)
    if not clean then return false, err end
    if HasFS() then
        if typeof(delfile) ~= "function" then return false, "delfile is not available" end
        if not isfile(ConfigPath(clean)) then return false, "config not found" end
        delfile(ConfigPath(clean))
    else
        MemoryStore[clean] = nil
    end
    if self:GetAutoload() == clean then self:SetAutoload(nil) end
    return true
end

function Library:ListConfigs()
    local list = {}
    if HasFS() and typeof(listfiles) == "function" then
        EnsureFolder(self.ConfigFolder)
        local ok, files = pcall(listfiles, self.ConfigFolder)
        if ok then
            for _, path in ipairs(files) do
                local n = path:match("([^/\\]+)%.json$")
                if n then table.insert(list, n) end
            end
        end
    else
        for n in pairs(MemoryStore) do
            if n ~= "__autoload" then table.insert(list, n) end
        end
    end
    table.sort(list)
    return list
end

function Library:SetAutoload(name)
    if HasFS() then
        EnsureFolder(self.ConfigFolder)
        pcall(writefile, AutoloadPath(), name or "")
    else
        MemoryStore.__autoload = name
    end
end

function Library:GetAutoload()
    local name
    if HasFS() then
        if isfile(AutoloadPath()) then name = readfile(AutoloadPath()) end
    else
        name = MemoryStore.__autoload
    end
    if name and name ~= "" then return name end
    return nil
end

function Library:LoadAutoloadConfig()
    self.AutoloadDone = true
    local name = self:GetAutoload()
    if not name then return end
    local ok, err = self:LoadConfig(name)
    if ok then self:Notify(("loaded autoload config %q"):format(name), 3)
    else self:Notify(("autoload failed: %s"):format(err), 4) end
end

function Library:BuildConfigSection(tab, side)
    local box = (side == "Left") and tab:AddLeftGroupbox("Configuration") or tab:AddRightGroupbox("Configuration")
    local list, autoLabel

    local function Refresh()
        list:SetValues(self:ListConfigs())
    end
    local function Selected()
        if list.Value == nil then self:Notify("select a config first", 2) end
        return list.Value
    end

    local nameInput = box:AddInput("Kraxx_ConfigName", { Text = "config name", Placeholder = "my config" })
    box:AddButton({ Text = "create config", Func = function()
        local clean, err = CleanName(nameInput.Value)
        if not clean then return self:Notify(err, 3) end
        if table.find(self:ListConfigs(), clean) then
            return self:Notify(("%q already exists, use overwrite"):format(clean), 3)
        end
        local ok, serr = self:SaveConfig(clean)
        if not ok then return self:Notify("save failed: " .. serr, 4) end
        Refresh()
        list:SetValue(clean)
        self:Notify(("created config %q"):format(clean), 3)
    end })
    box:AddDivider()

    list = box:AddDropdown("Kraxx_ConfigList", { Text = "config list", Values = self:ListConfigs(), AllowNull = true })
    box:AddButton({ Text = "load config", Func = function()
        local name = Selected()
        if not name then return end
        local ok, err = self:LoadConfig(name)
        self:Notify(ok and ("loaded config %q"):format(name) or ("load failed: " .. err), 3)
    end })
    box:AddButton({ Text = "overwrite config", DoubleClick = true, Func = function()
        local name = Selected()
        if not name then return end
        local ok, err = self:SaveConfig(name)
        self:Notify(ok and ("saved config %q"):format(name) or ("save failed: " .. err), 3)
    end })
    box:AddButton({ Text = "delete config", DoubleClick = true, Func = function()
        local name = Selected()
        if not name then return end
        local ok, err = self:DeleteConfig(name)
        if ok then Refresh() end
        autoLabel:SetText("autoload: " .. (self:GetAutoload() or "none"))
        self:Notify(ok and ("deleted config %q"):format(name) or ("delete failed: " .. err), 3)
    end })
    box:AddButton({ Text = "refresh list", Func = Refresh })
    box:AddDivider()

    box:AddButton({ Text = "set as autoload", Func = function()
        local name = Selected()
        if not name then return end
        self:SetAutoload(name)
        autoLabel:SetText("autoload: " .. name)
        self:Notify(("%q will load automatically"):format(name), 3)
    end })
    box:AddButton({ Text = "clear autoload", Func = function()
        self:SetAutoload(nil)
        autoLabel:SetText("autoload: none")
    end })
    autoLabel = box:AddLabel("autoload: " .. (self:GetAutoload() or "none"))
    box:AddDivider()

    box:AddButton({ Text = "copy config", Func = function()
        local text = self:ExportConfigText()
        if typeof(setclipboard) == "function" then
            setclipboard(text)
            self:Notify("config copied to clipboard", 2)
        else
            print(text)
            self:Notify("clipboard unavailable, config printed to output", 3)
        end
    end })

    self:SetIgnoreFlags({ "Kraxx_ConfigName", "Kraxx_ConfigList" })
    return box
end

-- built into every window automatically (disable with SettingsTab = false)
function Library:_BuildSettingsTab(window, name)
    local tab = window:AddTab(name or "Settings")
    local menu = tab:AddLeftGroupbox("Menu")
    menu.IsSettings = true
    menu:AddKeybind("Kraxx_MenuBind", {
        Text = "menu bind", Default = self.ToggleKey, Mode = "Always",
        ChangedCallback = function(key) self:SetToggleKey(key) end,
    })
    menu:AddColorPicker("Kraxx_Accent", {
        Text = "accent color", Default = Theme.Accent, Callback = function(c) self:SetAccent(c) end,
    })
    menu:AddSlider("Kraxx_DragSmoothness", {
        Text = "drag smoothness", Min = 5, Max = 40, Default = self.DragSmoothness, ShowMax = false, Standalone = true,
        Callback = function(v) self.DragSmoothness = v end,
    })
    menu:AddToggle("Kraxx_Watermark", {
        Text = "watermark", Default = true, Callback = function(v) self:SetWatermarkVisibility(v) end,
    })
    menu:AddDivider()
    menu:AddButton({ Text = "unload", DoubleClick = true, Func = function() self:Unload() end })

    self:BuildConfigSection(tab, "Right").IsSettings = true
    window.Settings = { Tab = tab, Menu = menu }
    return tab
end

function Library:OnUnload(fn) table.insert(self.UnloadCallbacks, fn) end

function Library:Unload()
    if self.Unloaded then return end
    self.Unloaded = true
    for _, fn in ipairs(self.UnloadCallbacks) do SafeCall(fn) end
    self:ClosePopup()
    for _, w in ipairs(self.Windows) do w:SetOpen(false) end
    for _, c in ipairs(self.Connections) do c:Disconnect() end
    task.delay(0.2, function() ScreenGui:Destroy() end)
end

return Library
