local Core, Constants = unpack(select(2, ...))
local CT = Core:GetModule("ChatTabs")
local MC = Core:GetModule("MainContainer")

-- luacheck: push ignore 113
local C_Timer = C_Timer
local GeneralDockManager = GeneralDockManager
local GeneralDockManagerScrollFrame = GeneralDockManagerScrollFrame
local GeneralDockManagerScrollFrameChild = GeneralDockManagerScrollFrameChild
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
-- luacheck: pop

local Colors = Constants.COLORS

local tabTexs = {
  '',
  'Selected',
  'Highlight'
}

function CT:OnEnable()
  self.config = {
    holdTime = Constants.DEFAULT_CHAT_HOLD_TIME
  }
  self.state = {
    mouseOver = false
  }

  -- ChatTabDock
  GeneralDockManager:SetSize(MC:GetFrame():GetWidth(), 20)
  GeneralDockManager:ClearAllPoints()
  GeneralDockManager:SetPoint("TOPLEFT", MC:GetFrame(), "TOPLEFT")

  GeneralDockManagerScrollFrame:SetHeight(20)
  GeneralDockManagerScrollFrame:SetPoint("TOPLEFT", _G.ChatFrame2Tab, "TOPRIGHT")
  GeneralDockManagerScrollFrameChild:SetHeight(20)

  local opacity = 0.4
  local dock = {}

  dock.leftBg = GeneralDockManager:CreateTexture(nil, "BACKGROUND")
  dock.leftBg:SetPoint("LEFT")
  dock.leftBg:SetWidth(50)
  dock.leftBg:SetHeight(20)
  dock.leftBg:SetColorTexture(1, 1, 1, 1)
  dock.leftBg:SetGradientAlpha(
    "HORIZONTAL",
    Colors.black.r, Colors.black.g, Colors.black.b, 0,
    Colors.black.r, Colors.black.g, Colors.black.b, opacity
  )

  dock.centerBg = GeneralDockManager:CreateTexture(nil, "BACKGROUND")
  dock.centerBg:SetPoint("LEFT", 50, 0)
  dock.centerBg:SetWidth(150)
  dock.centerBg:SetHeight(20)
  dock.centerBg:SetColorTexture(
    Colors.black.r,
    Colors.black.g,
    Colors.black.b,
    opacity
  )

  dock.rightBg = GeneralDockManager:CreateTexture(nil, "BACKGROUND")
  dock.rightBg:SetPoint("LEFT", 200, 0)
  dock.rightBg:SetWidth(250)
  dock.rightBg:SetHeight(20)
  dock.rightBg:SetColorTexture(1, 1, 1, 1)
  dock.rightBg:SetGradientAlpha(
    "HORIZONTAL",
    Colors.black.r, Colors.black.g, Colors.black.b, opacity,
    Colors.black.r, Colors.black.g, Colors.black.b, 0
  )

  -- Customize chat tabs
  for i=1, NUM_CHAT_WINDOWS do
    local tab = _G["ChatFrame"..i.."Tab"]

    for _, texName in ipairs(tabTexs) do
      _G[tab:GetName()..texName..'Left']:SetTexture()
      _G[tab:GetName()..texName..'Middle']:SetTexture()
      _G[tab:GetName()..texName..'Right']:SetTexture()
    end

    tab:SetHeight(20)
    tab:SetNormalFontObject("MesmericFont")
    tab.Text:ClearAllPoints()
    tab.Text:SetPoint("LEFT", 15, 0)
    tab:SetWidth(tab.Text:GetStringWidth() + 15 * 2)

    self:RawHook(tab, "SetAlpha", function (alpha)
      self.hooks[tab].SetAlpha(tab, 1)
    end, true)

    -- Set width dynamically based on text width
    self:RawHook(tab, "SetWidth", function (_, width)
      self.hooks[tab].SetWidth(tab, tab:GetTextWidth() + 15 * 2)
    end, true)

    self:RawHook(tab.Text, "SetTextColor", function (...)
      self.hooks[tab.Text].SetTextColor(tab.Text, Colors.apache.r, Colors.apache.g, Colors.apache.b)
    end, true)
  end

  -- Intro animations
  self.introAg = GeneralDockManager:CreateAnimationGroup()
  local fadeIn = self.introAg:CreateAnimation("Alpha")
  fadeIn:SetFromAlpha(0)
  fadeIn:SetToAlpha(1)
  fadeIn:SetDuration(0.3)
  fadeIn:SetSmoothing("OUT")

  -- Outro animations
  self.outroAg = GeneralDockManager:CreateAnimationGroup()
  local fadeOut = self.outroAg:CreateAnimation("Alpha")
  fadeOut:SetFromAlpha(1)
  fadeOut:SetToAlpha(0)
  fadeOut:SetDuration(0.3)
  fadeOut:SetEndDelay(1)

  -- Hide the frame when the outro animation finishes
  self.outroAg:SetScript("OnFinished", function ()
    GeneralDockManager:Hide()
  end)

  -- Start intro animation when element is shown
  GeneralDockManager:SetScript("OnShow", function ()
    self.introAg:Play()

    -- Play outro after hold time
    if not self.state.mouseOver then
      self.outroTimer = C_Timer.NewTimer(self.config.holdTime, function()
        if GeneralDockManager:IsVisible() then
          self.outroAg:Play()
        end
      end)
    end
  end)

  GeneralDockManager:Hide()
end

function CT:OnEnterContainer()
  -- Don't hide tabs when mouse is over
  self.state.mouseOver = true

  if not GeneralDockManager:IsVisible() then
    GeneralDockManager:Show()
  end

  if self.outroTimer then
    self.outroTimer:Cancel()
  end

  if self.outroAg:IsPlaying() then
    self.outroAg:Stop()
    self.introAg:Play()
  end
end

function CT:OnLeaveContainer()
  -- Hide chats when mouse leaves
  self.state.mouseOver = false

  if GeneralDockManager:IsVisible() then
    self.outroAg:Play()
  end
end
