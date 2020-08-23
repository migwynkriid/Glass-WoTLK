local Core, Constants, _, Object = unpack(select(2, ...))
local MC = Core:GetModule("MainContainer")
local SMF = Core:GetModule("SlidingMessageFrame")
local TP = Core:GetModule("TextProcessing")

local LSM = Core.Libs.LSM

-- luacheck: push ignore 113
local BattlePetToolTip_ShowLink = BattlePetToolTip_ShowLink
local BattlePetTooltip = BattlePetTooltip
local C_Timer = C_Timer
local CreateFont = CreateFont
local CreateFrame = CreateFrame
local CreateObjectPool = CreateObjectPool
local GameTooltip = GameTooltip
local GeneralDockManager = GeneralDockManager
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local SetItemRef = SetItemRef
local ShowUIPanel = ShowUIPanel
local UIParent = UIParent
local split = strsplit
local tinsert = table.insert
-- luacheck: pop

local lodash = Core.Libs.lodash
local drop, reduce, take = lodash.drop, lodash.reduce, lodash.take

local Colors = Constants.COLORS

local linkTypes = {
  item = true,
  enchant = true,
  spell = true,
  quest = true,
  achievement = true,
  currency = true,
  battlepet = true,
}

local SlidingMessageFrame = {}

----
-- SlidingMessageFrame
--
-- Custom frame for displaying pretty sliding messages
function SlidingMessageFrame:Create()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function SlidingMessageFrame:Initialize()
  self.config = {
    height = MC:GetFrame():GetHeight() - GeneralDockManager:GetHeight() - 5,
    width = MC:GetFrame():GetWidth(),
    messageOpacity = Core.db.profile.chatBackgroundOpacity,
    overflowHeight = 60,
    xPadding = 15
  }
  self.state = {
    mouseOver = false,
    showingTooltip = false,
    incomingMessages = {},
    messages = {}
  }

  -- Chat scroll frame
  self.scrollFrame = CreateFrame("ScrollFrame", "GlassScrollFrame", MC:GetFrame())
  self.scrollFrame:SetHeight(self.config.height + self.config.overflowHeight)
  self.scrollFrame:SetWidth(self.config.width)
  self.scrollFrame:SetPoint("BOTTOMLEFT", 0, self.config.overflowHeight * -1)

  self.scrollFrame.bg = self.scrollFrame:CreateTexture(nil, "BACKGROUND")
  self.scrollFrame.bg:SetAllPoints()
  self.scrollFrame.bg:SetColorTexture(0, 1, 0, 0)

  self.timeElapsed = 0
  self.scrollFrame:SetScript("OnUpdate", function (_, elapsed)
    self:OnUpdate(elapsed)
  end)

  -- Scrolling
  self.scrollFrame:SetScript("OnMouseWheel", function (_, delta)
    local currentScrollOffset = self.scrollFrame:GetVerticalScroll()
    local scrollRange = self.scrollFrame:GetVerticalScrollRange()

    -- Adjust scroll
    if delta < 0 and currentScrollOffset < scrollRange + self.config.overflowHeight then
      self.scrollFrame:SetVerticalScroll(math.min(currentScrollOffset + 20, scrollRange + self.config.overflowHeight))
    elseif delta > 0 and currentScrollOffset > self.scrollFrame:GetHeight() then
      self.scrollFrame:SetVerticalScroll(currentScrollOffset - 20)
    end

    -- Show hidden messages
    for _, message in ipairs(self.state.messages) do
      if not message.frame:IsVisible() then
        message.frame:Show()
      end
    end
  end)

  -- Mouse clickthrough
  self.scrollFrame:EnableMouse(false)

  -- ScrollChild
  self.slider = CreateFrame("Frame", nil, self.scrollFrame)
  self.slider:SetHeight(self.config.height + self.config.overflowHeight)
  self.slider:SetWidth(self.config.width)
  self.scrollFrame:SetScrollChild(self.slider)

  self.slider.bg = self.slider:CreateTexture(nil, "BACKGROUND")
  self.slider.bg:SetAllPoints()
  self.slider.bg:SetColorTexture(0, 0, 1, 0)

  -- Initialize slide up animations
  self.sliderAg = self.slider:CreateAnimationGroup()
  self.sliderStartOffset = self.sliderAg:CreateAnimation("Translation")
  self.sliderStartOffset:SetDuration(0)

  self.sliderTranslateUp = self.sliderAg:CreateAnimation("Translation")
  self.sliderTranslateUp:SetDuration(0.3)
  self.sliderTranslateUp:SetSmoothing("OUT")

  -- Pool for the message frames
  self.messageFramePool = CreateObjectPool(
    function () return self:MessagePoolCreator() end,
    function (_, message)
      -- Reset all animations and timers
      if message.outroTimer then
        message.outroTimer:Cancel()
      end

      message.introAg:Stop()
      message.outroAg:Stop()
      message.frame:Hide()
    end
  )
end

function SlidingMessageFrame:Show()
  self.scrollFrame:Show()
end

function SlidingMessageFrame:Hide()
  self.scrollFrame:Hide()
end

function SlidingMessageFrame:IsVisible()
  return self.scrollFrame:IsVisible()
end

local Message = Object:Subclass()
function Message:Initialize(config, parent, mouseOverFn)
  self.frame       = nil;
  self.leftBg      = nil;
  self.centerBg    = nil;
  self.rightBg     = nil;
  self.text        = nil;
  self.introAg     = nil;
  self.outroAg     = nil;
  self.outroTimer  = nil;
  self.config      = nil;
  self.prevLine    = nil;
  self.config      = config;
  self.isMouseOver = mouseOverFn

  self.frame = CreateFrame("Frame", nil, parent)
  self.frame:SetWidth(self.config.width)

  -- Gradient background
  self.leftBg = self.frame:CreateTexture(nil, "BACKGROUND")
  self.leftBg:SetPoint("LEFT")
  self.leftBg:SetWidth(50)
  self.leftBg:SetColorTexture(1, 1, 1, 1)
  self.leftBg:SetGradientAlpha(
    "HORIZONTAL",
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, 0,
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, self.config.messageOpacity
  )

  self.centerBg = self.frame:CreateTexture(nil, "BACKGROUND")
  self.centerBg:SetPoint("LEFT", 50, 0)
  self.centerBg:SetPoint("RIGHT", -250, 0)
  self.centerBg:SetColorTexture(
    Colors.codGray.r,
    Colors.codGray.g,
    Colors.codGray.b,
    self.config.messageOpacity
  )

  self.rightBg = self.frame:CreateTexture(nil, "BACKGROUND")
  self.rightBg:SetPoint("RIGHT")
  self.rightBg:SetWidth(250)
  self.rightBg:SetColorTexture(1, 1, 1, 1)
  self.rightBg:SetGradientAlpha(
    "HORIZONTAL",
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, self.config.messageOpacity,
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, 0
  )

  self.text = self.frame:CreateFontString(nil, "ARTWORK", "GlassMessageFont")
  self.text:SetPoint("LEFT", self.config.xPadding, 0)
  self.text:SetWidth(self.config.width - self.config.xPadding * 2)

  -- Intro animations
  self.introAg = self.frame:CreateAnimationGroup()
  local fadeIn = self.introAg:CreateAnimation("Alpha")
  fadeIn:SetFromAlpha(0)
  fadeIn:SetToAlpha(1)
  fadeIn:SetDuration(0.6)
  fadeIn:SetSmoothing("OUT")

  -- Outro animations
  self.outroAg = self.frame:CreateAnimationGroup()
  local fadeOut = self.outroAg:CreateAnimation("Alpha")
  fadeOut:SetFromAlpha(1)
  fadeOut:SetToAlpha(0)
  fadeOut:SetDuration(0.6)

  -- Hide the frame when the outro animation finishes
  self.outroAg:SetScript("OnFinished", function ()
    self.frame:Hide()
  end)

  -- Start intro animation when element is shown
  self.frame:SetScript("OnShow", function ()
    self.introAg:Play()

    -- Play outro after hold time
    if not self.isMouseOver() then
      self.outroTimer = C_Timer.NewTimer(Core.db.profile.chatHoldTime, function()
        if self.frame:IsVisible() then
          self.outroAg:Play()
        end
      end)
    end
  end)
end

function Message:UpdateFrame()
  local Ypadding = self.text:GetLineHeight() * 0.25
  local messageLineHeight = (self.text:GetStringHeight() + Ypadding * 2)
  self.frame:SetHeight(messageLineHeight)
  self.leftBg:SetHeight(messageLineHeight)
  self.centerBg:SetHeight(messageLineHeight)
  self.rightBg:SetHeight(messageLineHeight)

  self.frame:SetWidth(self.config.width)
  self.text:SetWidth(self.config.width - self.config.xPadding * 2)
end

function Message:UpdateTextures()
  self.config.messageOpacity = Core.db.profile.chatBackgroundOpacity

  self.leftBg:SetGradientAlpha(
    "HORIZONTAL",
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, 0,
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, self.config.messageOpacity
  )

  self.centerBg:SetColorTexture(
    Colors.codGray.r,
    Colors.codGray.g,
    Colors.codGray.b,
    self.config.messageOpacity
  )

  self.rightBg:SetGradientAlpha(
    "HORIZONTAL",
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, self.config.messageOpacity,
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, 0
  )
end

function SlidingMessageFrame:MessagePoolCreator()
  local result = Object.New(Message)
  result:Initialize(self.config, self.slider, function() return self.state.isMouseOver; end)
    -- Hyperlink handling
  result.frame:SetHyperlinksEnabled(true)

  result.frame:SetScript("OnHyperlinkClick", function (_, link, text, button)
    SetItemRef(link, text, button)
  end)

  result.frame:SetScript("OnHyperlinkEnter", function (...)
    if Core.db.profile.mouseOverTooltips then
      local args = {...}
      self:OnHyperlinkEnter(unpack(args))
    end
  end)

  result.frame:SetScript("OnHyperlinkLeave", function (...)
    local args = {...}
    self:OnHyperlinkLeave(unpack(args))
  end)

  return result
end

---
--Takes a texture escape string and adjusts its yOffset
local function adjustTextureYOffset(texture)
  -- Texture has 14 parts
  -- path, height, width, offsetX, offsetY,
  -- texWidth, texHeight
  -- leftTex, topTex, rightTex, bottomText,
  -- rColor, gColor, bColor

  -- Strip escape characters
  -- Split into parts
  local parts = {split(':', strsub(texture, 3, -3))}
  local yOffset = Core.db.profile.iconTextureYOffset

  if #parts < 5 then
    -- Pad out ommitted attributes
    for i=1, 5 do
      if parts[i] == nil then
        if i == 3 then
          -- If width is not specified, the width should equal the height
          parts[i] = parts[2]
        else
          parts[i] = '0'
        end
      end
    end
  end

  -- Adjust yOffset by -4
  parts[5] = tostring(tonumber(parts[5]) - yOffset)

  -- Rejoin into strings
  local newTex = reduce(parts, function (acc, part)
    if acc then
      return acc..":"..part
    end
    return part
  end)

  -- Re-add escape codes
  return '|T'..newTex..'|t'
end

---
-- Gets all inline textures found in the string and adjusts their yOffset
local function transformTextures(text)
  local cursor = 1
  local origLen = strlen(text)

  local parts = {}

  while cursor <= origLen do
    local mStart, mEnd = strfind(text, '%|T.-%|t', cursor)

    if mStart then
      tinsert(parts, strsub(text, cursor, mStart - 1))
      tinsert(parts, adjustTextureYOffset(strsub(text, mStart, mEnd)))
      cursor = mEnd + 1
    else
      -- No more matches
      tinsert(parts, strsub(text, cursor, origLen))
      cursor = origLen + 1
    end
  end

  local newText = reduce(parts, function (acc, part)
    return acc..part
  end, "")

  return newText
end

function SlidingMessageFrame:CreateMessageFrame(_, text, red, green, blue, _, _)
  red = red or 1
  green = green or 1
  blue = blue or 1

  local message = self.messageFramePool:Acquire()
  message.frame:SetPoint("BOTTOMLEFT")

  -- Attach previous message to this one
  if self.prevLine and self.prevLine.frame then
    self.prevLine.frame:ClearAllPoints()
    self.prevLine.frame:SetPoint("BOTTOMLEFT", message.frame, "TOPLEFT")
  end

  self.prevLine = message

  message.text:SetTextColor(red, green, blue, 1)
  message.text:SetText(TP:ProcessText(text))

  -- Adjust height to contain text
  message:UpdateFrame()

  return message
end

function SlidingMessageFrame:OnEnterContainer()
  -- Don't hide chats when mouse is over
  self.state.mouseOver = true

  for _, message in ipairs(self.state.messages) do
    if Core.db.profile.chatShowOnMouseOver and not message.frame:IsVisible() then
      message.frame:Show()
    end

    if message.outroTimer then
      message.outroTimer:Cancel()
    end
  end
end

function SlidingMessageFrame:OnLeaveContainer()
  -- Hide chats when mouse leaves
  self.state.mouseOver = false

  for _, message in ipairs(self.state.messages) do
    if message.frame:IsVisible() then
      message.outroTimer = C_Timer.NewTimer(Core.db.profile.chatHoldTime, function()
        if message.frame:IsVisible() then
          message.outroAg:Play()
        end
      end)
    end
  end
end

function SlidingMessageFrame:OnHyperlinkEnter(_, link, text)
  local t = string.match(link, "^(.-):")

  if linkTypes[t] then
    if t == "battlepet" then
      self.state.showingTooltip = BattlePetTooltip
      GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
      BattlePetToolTip_ShowLink(text)
    else
      self.state.showingTooltip = GameTooltip
      ShowUIPanel(GameTooltip)
      GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(link)
      GameTooltip:Show()
    end
  end
end

function SlidingMessageFrame:OnHyperlinkLeave(_, _)
  if self.state.showingTooltip then
    self.state.showingTooltip:Hide()
    self.state.showingTooltip = false
  end
end

function SlidingMessageFrame:AddMessage(...)
  -- Enqueue messages to be displayed
  local args = {...}
  tinsert(self.state.incomingMessages, args)
end


function SlidingMessageFrame:OnUpdate(elapsed)
  self.timeElapsed = self.timeElapsed + elapsed
  while (self.timeElapsed > 0.1) do
    self.timeElapsed = self.timeElapsed - 0.1
    self:Update()
  end
end

function SlidingMessageFrame:Update()
  -- Make sure previous iteration is complete before running again
  if #self.state.incomingMessages > 0 and not self.sliderAg:IsPlaying() then
    -- Create new message frame for each message
    local newMessages = {}

    for _, message in ipairs(self.state.incomingMessages) do
      tinsert(newMessages, self:CreateMessageFrame(unpack(message)))
    end

    -- Update slider offsets animation
    local offset = reduce(newMessages, function(acc, message)
      return acc + message.frame:GetHeight()
    end, 0)

    local newHeight = self.slider:GetHeight() + offset
    self.slider:SetHeight(newHeight)
    self.sliderStartOffset:SetOffset(0, offset * -1)
    self.sliderTranslateUp:SetOffset(0, offset)

    -- Display and run everything
    self.scrollFrame:SetVerticalScroll(newHeight - self.scrollFrame:GetHeight() + self.config.overflowHeight)

    for _, message in ipairs(newMessages) do
      message.frame:Show()
      tinsert(self.state.messages, message)
    end

    self.sliderAg:Play()

    -- Release old messages
    local historyLimit = 128
    if #self.state.messages > historyLimit then
      local overflow = #self.state.messages - historyLimit
      local oldMessages = take(self.state.messages, overflow)
      self.state.messages = drop(self.state.messages, overflow)

      for _, message in ipairs(oldMessages) do
        self.messageFramePool:Release(message)
      end
    end

    -- Reset
    self.state.incomingMessages = {}
  end
end

function SlidingMessageFrame:OnUpdateFont()
  for _, message in ipairs(self.state.messages) do
    message:UpdateFrame()
  end
end

function SlidingMessageFrame:OnUpdateChatBackgroundOpacity()
  for _, message in ipairs(self.state.messages) do
    message:UpdateTextures()
  end
end

function SlidingMessageFrame:OnUpdateFrame()
  self.config.height = MC:GetFrame():GetHeight() - GeneralDockManager:GetHeight() - 5
  self.config.width = MC:GetFrame():GetWidth()

  self.scrollFrame:SetHeight(self.config.height + self.config.overflowHeight)
  self.scrollFrame:SetWidth(self.config.width)

  self.slider:SetHeight(self.config.height + self.config.overflowHeight)
  self.slider:SetWidth(self.config.width)

  for _, message in ipairs(self.state.messages) do
    message:UpdateFrame()
  end
end

----
-- SMF Module
function SMF:OnInitialize()
  self.state = {
    frames = {}
  }

end

function SMF:OnEnable()
  -- Message font
  self.font = CreateFont("GlassMessageFont")
  self.font:SetFont(
    LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
    Core.db.profile.messageFontSize
  )
  self.font:SetShadowColor(0, 0, 0, 1)
  self.font:SetShadowOffset(1, -1)
  self.font:SetJustifyH("LEFT")
  self.font:SetJustifyV("MIDDLE")
  self.font:SetSpacing(Core.db.profile.messageFontSpacing)

  -- Replace default chat frames with SlidingMessageFrames
  local containerFrame = MC:GetFrame()
  local dockHeight = GeneralDockManager:GetHeight() + 5
  local height = containerFrame:GetHeight() - dockHeight

  for i=1, NUM_CHAT_WINDOWS do
    repeat
      local chatFrame = _G["ChatFrame"..i]

      _G[chatFrame:GetName().."ButtonFrame"]:Hide()

      chatFrame:SetClampRectInsets(0,0,0,0)
      chatFrame:SetClampedToScreen(false)
      chatFrame:SetResizable(false)
      chatFrame:SetParent(containerFrame)
      chatFrame:ClearAllPoints()
      chatFrame:SetHeight(height - 20)

      self:RawHook(chatFrame, "SetPoint", function ()
        self.hooks[chatFrame].SetPoint(chatFrame, "TOPLEFT", containerFrame, "TOPLEFT", 0, -45)
      end, true)

      -- Skip combat log
      if i == 2 then
        do break end
      end

      local smf = SlidingMessageFrame:Create()
      self.state.frames[i] = smf

      smf:Initialize()
      smf:Hide()

      self:Hook(chatFrame, "AddMessage", function (...)
        local args = {...}
        smf:AddMessage(unpack(args))
      end, true)

      -- Hide the default chat frame and show the sliding message frame instead
      self:RawHook(chatFrame, "Show", function ()
        smf:Show()
      end, true)

      self:RawHook(chatFrame, "Hide", function (f)
        self.hooks[chatFrame].Hide(f)
        smf:Hide()
      end, true)

      chatFrame:Hide()
    until true
  end
end

function SMF:OnEnterContainer()
  for _, smf in ipairs(self.state.frames) do
    smf:OnEnterContainer()
  end
end

function SMF:OnLeaveContainer()
  for _, smf in ipairs(self.state.frames) do
    smf:OnLeaveContainer()
  end
end

function SMF:OnUpdateFont()
  self.font:SetFont(
    LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
    Core.db.profile.messageFontSize
  )

  self.font:SetSpacing(Core.db.profile.messageFontSpacing)

  for _, frame in ipairs(self.state.frames) do
    frame:OnUpdateFont()
  end
end

function SMF:OnUpdateChatBackgroundOpacity()
  for _, frame in ipairs(self.state.frames) do
    frame:OnUpdateChatBackgroundOpacity()
  end
end

function SMF:OnUpdateFrame()
  for _, frame in ipairs(self.state.frames) do
    frame:OnUpdateFrame()
  end
end
