-- hhtwm - hackable hammerspoon tiling wm

local axuiWindowElement    = require('hs._asm.axuielement').windowElement
local layouts              = require('hhtwm.layouts')
local spaces               = require('hs._asm.undocumented.spaces')

local log                  = hs.logger.new('hhtwm', 'debug');

-- TODO: user floating vs layout floating windows?
-- now switching a layout when one of the windows was floated by user, makes this window into non-floating one
local cache                = { spaces = {}, layouts = {}, floating = {}, layoutOptions = {} }
local module               = { cache = cache }

local SWAP_BETWEEN_SCREENS = false

local getDefaultLayoutOptions = function()
  return {
    mainPaneRatio = 0.5
  }
end

local capitalize = function(str)
  return str:gsub('^%l', string.upper)
end

local ternary = function(cond, ifTrue, ifFalse)
  if cond then return ifTrue else return ifFalse end
end

local ensureCacheSpaces = function(spaceId)
  if spaceId and not cache.spaces[spaceId] then
    cache.spaces[spaceId] = {}
  end
end

local getCurrentSpacesIds = function()
  return spaces.query(spaces.masks.currentSpaces)
end

local getSpaceId = function(win)
  local spaceId

  win = win or hs.window.frontmostWindow()

  if win and #win:spaces() > 0 then
    spaceId = win:spaces()[1]
  end

  return spaceId or spaces.activeSpace()
end

local getSpacesIdsTable = function()
  local spacesLayout = spaces.layout()
  local spacesIds = {}

  hs.fnutils.each(hs.screen.allScreens(), function(screen)
    local spaceUUID = screen:spacesUUID()

    local userSpaces = hs.fnutils.filter(spacesLayout[spaceUUID], function(spaceId)
      return spaces.spaceType(spaceId) == spaces.types.user
    end)

    hs.fnutils.concat(spacesIds, userSpaces or {})
  end)

  return spacesIds
end

local getScreenBySpaceId = function(spaceId)
  local spacesLayout = spaces.layout()

  return hs.fnutils.find(hs.screen.allScreens(), function(screen)
    local spaceUUID = screen:spacesUUID()

    return hs.fnutils.contains(spacesLayout[spaceUUID], spaceId)
  end)
end

local getCurrentSpacesByScreen = function()
  local currentSpaces = spaces.query(spaces.masks.currentSpaces)

  local spacesIds = {}

  hs.fnutils.each(hs.screen.allScreens(), function(screen)
    local screenSpaces = screen:spaces()

    local visibleSpace = hs.fnutils.find(screenSpaces, function(spaceId)
      return hs.fnutils.contains(currentSpaces, spaceId)
    end)

    spacesIds[screen:id()] = visibleSpace
  end)

  return spacesIds
end

-- iterate through cache.spaces to find matching window:id()
-- returns foundInAllWindows window, its space, and index in array
module.findTrackedWindow = function(win)
  local foundSpaceId, foundWinIndex, foundWin

  local didFound = false

  for spaceId, spaceWindows in pairs(cache.spaces) do
    for winIndex, window in pairs(spaceWindows) do
      if not didFound then
        didFound = window:id() == win:id()

        if didFound then
          foundSpaceId  = spaceId
          foundWinIndex = winIndex
          foundWin      = window
        end
      end
    end
  end

  return foundWin, foundSpaceId, foundWinIndex
end

module.getLayouts = function()
  if hhtwm.enabledLayouts ~= nil then
    return hhtwm.enabledLayouts
  else
    local layoutNames  = {}

    for key in pairs(layouts) do
      table.insert(layoutNames, key)
    end

    return layoutNames
  end
end

-- sets layout for space id,
-- defaults to current windows space
module.setLayout = function(layout, spaceId)
  spaceId = spaceId or getSpaceId()
  if not spaceId then return end

  cache.layouts[spaceId] = layout

  -- remove all floating windows that are on this space,
  -- so retiling will put them back in the layout
  -- this allows us to switch back from floating layout and get windows back to layout
  cache.floating = hs.fnutils.filter(cache.floating, function(win)
    return win:spaces()[1] ~= spaceId
  end)

  module.tile()
end

-- get layout for space id, priorities:
-- 1. layout selected by setLayout
-- 2. layout assigned by tilign.displayLayouts
-- 3. hhtwm.defaultLayout
module.getLayout = function(spaceId)
  spaceId = spaceId or getSpaceId()

  local layout = spaces.layout()
  local foundScreenUUID

  for screenUUID, layoutSpaces in pairs(layout) do
    if not foundScreenUUID then
      if hs.fnutils.contains(layoutSpaces, spaceId) then
        foundScreenUUID = screenUUID
      end
    end
  end

  local screen = hs.fnutils.find(hs.screen.allScreens(), function(screen)
    return screen:spacesUUID() == foundScreenUUID
  end)

  return cache.layouts[spaceId]
      or (screen and hhtwm.displayLayouts and hhtwm.displayLayouts[screen:id()])
      or (screen and hhtwm.displayLayouts and hhtwm.displayLayouts[screen:name()])
      or hhtwm.defaultLayout
end

module.resizeLayout = function(resizeOpt)
  local spaceId = getSpaceId()
  if not spaceId then return end

  if not cache.layoutOptions[spaceId] then
    cache.layoutOptions[spaceId] = getDefaultLayoutOptions()
  end

  local calcResizeStep = hhtwm.calcResizeStep or function() return 0.1 end
  local screen         = getScreenBySpaceId(spaceId)
  local step           = calcResizeStep(screen)

  if resizeOpt == 'thinner' then
    cache.layoutOptions[spaceId].mainPaneRatio = math.max(cache.layoutOptions[spaceId].mainPaneRatio - step, 0)
  elseif resizeOpt == 'wider' then
    cache.layoutOptions[spaceId].mainPaneRatio = math.min(cache.layoutOptions[spaceId].mainPaneRatio + step, 1)
  end

  module.tile()
end

module.equalizeLayout = function()
  local spaceId = getSpaceId()
  if not spaceId then return end

  if cache.layoutOptions[spaceId] then
    cache.layoutOptions[spaceId] = getDefaultLayoutOptions()

    module.tile()
  end
end

-- swap windows in direction
-- works between screens
module.swapInDirection = function(win, direction)
  win = win or hs.window.frontmostWindow()

  if module.isFloating(win) then return end

  local windowsInDirection = win['windowsTo' .. capitalize(direction)](win)

  windowsInDirection = hs.fnutils.filter(windowsInDirection, function(testWin)
    return testWin:isStandard() and not hhtwm.isFloating(testWin)
  end)

  if #windowsInDirection >= 1 then
    local winInDirection = windowsInDirection[1]

    local _, winInDirectionSpaceId, winInDirectionIdx = module.findTrackedWindow(winInDirection)
    local _, winSpaceId, winIdx                       = module.findTrackedWindow(win)

    if hs.fnutils.some({
      win,
      winInDirection,
      winInDirectionSpaceId,
      winInDirectionIdx,
      winSpaceId,
      winIdx
    }, function(_) return _ == nil end) then
      log.d('swapInDirection error', hs.inspect({ winInDirectionSpaceId, winInDirectionIdx, winSpaceId, winIdx }));
      return
    end

    local winInDirectionScreen = winInDirection:screen()
    local winScreen            = win:screen()

    local winInDirectionFrame  = winInDirection:frame()
    local winFrame             = win:frame()

    -- if swapping between screens is disabled, then return early if screen ids differ
    if not SWAP_BETWEEN_SCREENS and winScreen:id() ~= winInDirectionScreen:id() then
      return
    end

    -- otherwise, move to screen if they differ
    if winScreen:id() ~= winInDirectionScreen:id() then
      win:moveToScreen(winInDirectionScreen)
      winInDirection:moveToScreen(winScreen)
    end

    ensureCacheSpaces(winSpaceId)
    ensureCacheSpaces(winInDirectionSpaceId)

    -- swap frames
    winInDirection:setFrame(winFrame)
    win:setFrame(winInDirectionFrame)

    -- swap positions in arrays
    cache.spaces[winSpaceId][winIdx]                       = winInDirection
    cache.spaces[winInDirectionSpaceId][winInDirectionIdx] = win

    -- no need to retile, assuming both windows were previously tiled!
  end
end

-- throw window to screen - de-attach and re-attach
module.throwToScreen = function(win, direction)
  win = win or hs.window.frontmostWindow()

  if module.isFloating(win) then return end

  local directions = {
    next = 'next',
    prev = 'previous'
  }

  if not directions[direction] then
    log.d('can\'t throw in direction:', direction)
    return
  end

  local screen            = win:screen()
  local screenInDirection = screen[directions[direction]](screen)

  if screenInDirection then
    local _, winSpaceId, winIdx = module.findTrackedWindow(win)

    if hs.fnutils.some({ winSpaceId, winIdx }, function(_) return _ == nil end) then
      log.d('throwToScreen error', hs.inspect({ winSpaceId, winIdx }));
      return
    end

    -- remove from tiling so we re-tile that window after it was moved
    if cache.spaces[winSpaceId] then
      table.remove(cache.spaces[winSpaceId], winIdx)
    else
      log.d('throwToScreen no cache.spaces for space id:', winSpaceId)
    end

    -- move window to screen
    win:moveToScreen(screenInDirection)

    -- retile to update layouts
    if hs.window.animationDuration > 0 then
      hs.timer.doAfter(hs.window.animationDuration * 1.2, module.tile)
    else
      module.tile()
    end
  end
end

module.throwToScreenUsingSpaces = function(win, direction)
  win = win or hs.window.frontmostWindow()

  if module.isFloating(win) then return end

  local directions = {
    next = 'next',
    prev = 'previous'
  }

  if not directions[direction] then
    log.d('can\'t throw in direction:', direction)
    return
  end

  local screen            = win:screen()
  local screenInDirection = screen[directions[direction]](screen)
  local currentSpaces     = getCurrentSpacesByScreen()
  local throwToSpaceId    = currentSpaces[screenInDirection:id()]

  if not throwToSpaceId then
    log.d('no space to throw to')
    return
  end

  local _, winSpaceId, winIdx = module.findTrackedWindow(win)

  if hs.fnutils.some({ winSpaceId, winIdx }, function(_) return _ == nil end) then
    log.d('throwToScreenUsingSpaces error', hs.inspect({ winSpaceId, winIdx }));
    return
  end

  -- remove from tiling so we re-tile that window after it was moved
  if cache.spaces[winSpaceId] then
    table.remove(cache.spaces[winSpaceId], winIdx)
  else
    log.d('throwToScreenUsingSpaces no cache.spaces for space id:', winSpaceId)
  end

  local newX = screenInDirection:frame().x
  local newY = screenInDirection:frame().y

  spaces.moveWindowToSpace(win:id(), throwToSpaceId)
  win:setTopLeft(newX, newY)

  module.tile()
end

-- throw window to space, indexed
module.throwToSpace = function(win, spaceIdx)
  local spacesIds = getSpacesIdsTable()
  local spaceId = spacesIds[spaceIdx]
  local targetScreen = getScreenBySpaceId(spaceId)
  local targetScreenFrame = targetScreen:frame()

  if not spaceId then
    log.d('throwToSpace tried to move to non-existing space', spaceId, hs.inspect(spacesIds))
    return false
  end

  if module.isFloating(win) then
    -- adjust frame for new screen offset
    local newX = win:frame().x - win:screen():frame().x + targetScreen:frame().x
    local newY = win:frame().y - win:screen():frame().y + targetScreen:frame().y

    -- move to space
    spaces.moveWindowToSpace(win:id(), spaceId)

    -- ensure window is visible
    win:setTopLeft(newX, newY)

    return true
  end

  local _, winSpaceId, winIdx = module.findTrackedWindow(win)

  if hs.fnutils.some({ winSpaceId, winIdx }, function(_) return _ == nil end) then
    log.d('throwToSpace error', hs.inspect({ winSpaceId, winIdx }));
    return false
  end

  -- remove from tiling so we re-tile that window after it was moved
  if cache.spaces[winSpaceId] then
    table.remove(cache.spaces[winSpaceId], winIdx)
  else
    log.d('throwToSpace no cache.spaces for space id:', winSpaceId)
  end

  -- move to space
  spaces.moveWindowToSpace(win:id(), spaceId)

  -- ensure window is visible
  win:setTopLeft(targetScreenFrame.x, targetScreenFrame.y)

  -- retile when finished
  module.tile()

  return true
end

-- check if window is floating
module.isFloating = function(win)
  local trackedWin, _, _  = module.findTrackedWindow(win)
  local isTrackedAsTiling = trackedWin ~= nil

  if isTrackedAsTiling then
    return false
  end

  local isTrackedAsFloating = hs.fnutils.find(cache.floating, function(floatingWin)
    return floatingWin:id() == win:id()
  end)

  -- if window is not floating and not tiling, then default to floating?
  if isTrackedAsFloating == nil and trackedWin == nil then
    return true
  end

  return isTrackedAsFloating ~= nil
end

-- toggle floating state of window
module.toggleFloat = function(win)
  win = win or hs.window.frontmostWindow()

  if not win then return end

  if module.isFloating(win) then
    local spaceId = win:spaces()[1]
    local foundIdx

    for index, floatingWin in pairs(cache.floating) do
      if not foundIdx then
        if floatingWin:id() == win:id() then
          foundIdx = index
        end
      end
    end

    ensureCacheSpaces(spaceId)

    table.insert(cache.spaces[spaceId], win)
    table.remove(cache.floating, foundIdx)
  else
    local foundWin, winSpaceId, winIdx = module.findTrackedWindow(win)

    if cache.spaces[winSpaceId] then
      table.remove(cache.spaces[winSpaceId], winIdx)
    else
      log.d('window made floating without previous :space()', hs.inspect(foundWin))
    end

    table.insert(cache.floating, win)
  end

  -- update tiling
  module.tile()
end

-- internal function for deciding if window should float when recalculating tiling
local shouldFloat = function(win)
  -- if window is in tiling cache, then it is not floating
  local inTilingCache, _, _ = module.findTrackedWindow(win)
  if inTilingCache then return false end

  -- if window is already tracked as floating, then leave it be
  local isTrackedAsFloating = hs.fnutils.find(cache.floating, function(floatingWin)
    return floatingWin:id() == win:id()
  end) ~= nil
  if isTrackedAsFloating then return true end

  -- otherwise detect if window should be floated/tiled
  return not hhtwm.detectTile(win)
end

-- tile windows - combine caches with current state, and apply layout
module.tile = function()
  -- this allows us to have tabs and do proper tiling!
  local tilingWindows   = {}
  local floatingWindows = {}

  local currentSpaces = getCurrentSpacesIds()

  hs.fnutils.each(hs.window.allWindows() or {}, function(win)
    -- we don't care about minimized or fullscreen windows
    if win:isMinimized() or win:isFullscreen() then
      return
    end

    -- we also don't care about special windows that have no spaces
    if not win:spaces() or #win:spaces() == 0 then
      return
    end

    if shouldFloat(win) then
      table.insert(floatingWindows, win)
    else
      table.insert(tilingWindows, win)
    end
  end)

  -- add new tiling windows to cache
  hs.fnutils.each(tilingWindows, function(win)
    if not win or #win:spaces() == 0 then return end

    local spaces                        = win:spaces()
    local spaceId                       = spaces[1]
    local tmp                           = cache.spaces[spaceId] or {}
    local trackedWin, trackedSpaceId, _ = module.findTrackedWindow(win)

    -- -- window is "new" if it's not in cache at all, or if it changed space
    -- log.d('update cache.spaces', hs.inspect({
    --   win = win,
    --   spaces = spaces,
    --   spaceId = spaceId,
    --   trackedWin = trackedWin or 'none',
    --   trackedSpaceId = trackedSpaceId or 'none',
    --   shouldInsert = not trackedWin or trackedSpaceId ~= spaceId
    -- }))

    if not trackedWin or trackedSpaceId ~= spaceId then
      -- table.insert(tmp, 1, win)
      table.insert(tmp, win)
    end

    cache.spaces[spaceId] = tmp
  end)

  -- clean up tiling cache
  hs.fnutils.each(currentSpaces, function(spaceId)
    local spaceWindows = cache.spaces[spaceId] or {}
    local i = 1

    while i <= #spaceWindows do
      -- window exists in cache if there's spaceId and windowId match
      local existsOnScreen = hs.fnutils.find(tilingWindows, function(win)
        return win:id() == spaceWindows[i]:id() and win:spaces()[1] == spaceId
      end)

      -- window is duplicated (why?) if it's tracked more than once
      -- this shouldn't happen, but helps for now...
      local duplicateIdx = 0

      for j = i + 1, #spaceWindows do
        if spaceWindows[i]:id() == spaceWindows[j]:id() then
          duplicateIdx = j
        end
      end

      if duplicateIdx > 0 then
        log.d('duplicateIdx', i, duplicateIdx, spaceWindows[i]:id(), spaceWindows[duplicateIdx]:id(), hs.inspect(spaceWindows))
      end

      -- log.d('existsOnScreen', hs.inspect({
      --   existsOnScreen = existsOnScreen and true or false,
      --   spaceWindow = spaceWindows[i],
      --   -- spaceWindows = spaceWindows
      -- }))

      if not existsOnScreen or duplicateIdx > 0 then
        table.remove(spaceWindows, i)
      else
        i = i + 1
      end
    end

    cache.spaces[spaceId] = spaceWindows
  end)

  -- add new windows to floating cache
  hs.fnutils.each(floatingWindows, function(win)
    if not module.isFloating(win) then
      table.insert(cache.floating, win)
    end
  end)

  -- clean up floating cache
  cache.floating = hs.fnutils.filter(cache.floating, function(cacheWin)
    return hs.fnutils.find(floatingWindows, function(win)
      return cacheWin:id() == win:id()
    end)
  end)

  -- apply layout window-by-window
  local moveToFloat = {}

  hs.fnutils.each(currentSpaces, function(spaceId)
    local spaceWindows = cache.spaces[spaceId] or {}

    hs.fnutils.each(hs.screen.allScreens(), function(screen)
      local screenWindows = hs.fnutils.filter(spaceWindows, function(win) return win:screen():id() == screen:id() end)
      local layoutName    = module.getLayout(spaceId)

      if not layoutName or not layouts[layoutName] then
        log.d('layout doesn\'t exist: ' .. layoutName)
      else
        for index, window in pairs(screenWindows) do
          local frame = layouts[layoutName](
            window,
            screenWindows,
            screen,
            index,
            cache.layoutOptions[spaceId] or getDefaultLayoutOptions()
          )

          -- only set frame if returned,
          -- this allows for layout to decide if window should be floating
          if frame then
            window:setFrame(frame)
          else
            table.insert(moveToFloat, window)
          end
        end
      end
    end)
  end)

  hs.fnutils.each(moveToFloat, function(win)
    local _, spaceId, winIdx = module.findTrackedWindow(win)

    table.remove(cache.spaces[spaceId], winIdx)
    table.insert(cache.floating, win)
  end)
end

-- tile detection:
-- 1. test tiling.filters if exist
-- 2. check if there's fullscreen button -> yes = tile, no = float
module.detectTile = function(win)
  local app     = win:application():name()
  local role    = win:role()
  local subrole = win:subrole()
  local title   = win:title()

  if hhtwm.filters then
    local foundMatch = hs.fnutils.find(hhtwm.filters, function(obj)
      local appMatches     = ternary(obj.app ~= nil and app ~= nil, string.match(app, obj.app or ''), true)
      local titleMatches   = ternary(obj.title ~= nil and title ~= nil, string.match(title, obj.title or ''), true)
      local roleMatches    = ternary(obj.role ~= nil, obj.role == role, true)
      local subroleMatches = ternary(obj.subrole ~= nil, obj.subrole == subrole, true)

      return appMatches and titleMatches and roleMatches and subroleMatches
    end)

    if foundMatch then
      return foundMatch.tile
    end
  end

  local shouldTileDefault = axuiWindowElement(win):isAttributeSettable('AXSize')
  return shouldTileDefault
end

-- mostly for debugging
module.reset = function()
  cache.spaces   = {}
  cache.layouts  = {}
  cache.floating = {}

  module.tile()
end

local loadSettings = function()
  -- load from cache
  local jsonTilingCache   = hs.settings.get('hhtwm.tilingCache')
  local jsonFloatingCache = hs.settings.get('hhtwm.floatingCache')

  log.d('reading from hs.settings')
  log.d('hhtwm.tilingCache', jsonTilingCache)
  log.d('hhtwm.floatingCache', jsonFloatingCache)

  -- decode tiling cache
  if jsonTilingCache then
    local tilingCache = hs.json.decode(jsonTilingCache)

    hs.fnutils.each(tilingCache, function(obj)
      cache.spaces[obj.spaceId]        = {}
      cache.layouts[obj.spaceId]       = obj.layout
      cache.layoutOptions[obj.spaceId] = obj.layoutOptions

      hs.fnutils.each(obj.windowIds, function(winId)
        local win = hs.window.find(winId)
        if win then table.insert(cache.spaces[obj.spaceId], win) end
      end)
    end)
  end

  -- decode floating cache
  if jsonFloatingCache then
    local floatingCache = hs.json.decode(jsonFloatingCache)

    hs.fnutils.each(floatingCache, function(winId)
      local win = hs.window.find(winId)
      if win then table.insert(cache.floating, win) end
    end)
  end
end

local saveSettings = function()
  local tilingCache   = {}
  local floatingCache = hs.fnutils.map(cache.floating, function(win) return win:id() end)

  for spaceId, spaceWindows in pairs(cache.spaces) do
    -- only save spaces with windows on them
    if #spaceWindows > 0 then
      local tmp = {}

      for _, window in pairs(spaceWindows) do
        table.insert(tmp, window:id())
      end

      table.insert(tilingCache, {
        spaceId       = spaceId,
        layout        = module.getLayout(spaceId),
        layoutOptions = cache.layoutOptions[spaceId],
        windowIds     = tmp
      })
    end
  end

  local jsonTilingCache   = hs.json.encode(tilingCache)
  local jsonFloatingCache = hs.json.encode(floatingCache)

  log.d('storing to hs.settings')
  log.d('hhtwm.tiling', jsonTilingCache)
  log.d('hhtwm.floating', jsonFloatingCache)

  hs.settings.set('hhtwm.tilingCache',   jsonTilingCache)
  hs.settings.set('hhtwm.floatingCache', jsonFloatingCache)
end

module.start = function()
  -- load window/floating status from saved state
  loadSettings()

  cache.filter = hs.window.filter.new()
    :setDefaultFilter()
    :setOverrideFilter({
      visible    = true,  -- only allow visible windows
      fullscreen = false, -- ignore fullscreen windows
      allowRoles = { 'AXStandardWindow' }
    })
    :setSortOrder(hs.window.filter.sortByCreated)

  -- retile automatically when windows change
  cache.filter:subscribe({ hs.window.filter.windowsChanged }, module.tile)

  -- update on screens change
  cache.screenWatcher = hs.screen.watcher.new(module.tile):start()

  -- tile on start
  module.tile()
end

module.stop = function()
  -- store cache so we persist layouts between restarts
  saveSettings()

  -- stop filter
  cache.filter:unsubscribeAll()

  -- stop watching screens
  cache.screenWatcher:stop()
end

return module
