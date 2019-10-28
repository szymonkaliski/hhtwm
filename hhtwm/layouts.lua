-- hhtwm layouts

return function(hhtwm)
  local layouts = {}

  local getInsetFrame = function(screen)
    local screenFrame  = screen:fullFrame()
    local screenMargin = hhtwm.screenMargin or { top = 0, bottom = 0, right = 0, left = 0 }

    return {
      x = screenFrame.x + screenMargin.left,
      y = screenFrame.y + screenMargin.top,
      w = screenFrame.w - (screenMargin.left + screenMargin.right),
      h = screenFrame.h - (screenMargin.top + screenMargin.bottom)
    }
  end

  layouts["floating"] = function()
    return nil
  end

  layouts["monocle"] = function(_, _, screen)
    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)

    local frame = {
      x = insetFrame.x + margin / 2,
      y = insetFrame.y + margin / 2,
      w = insetFrame.w - margin,
      h = insetFrame.h - margin
    }

    return frame
  end

  layouts["cards"] = function(_, windows, screen, index)
    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)
    local offset     = margin / 2

    local x = (insetFrame.x + margin / 2) + offset * (index - 1)
    local y = (insetFrame.y + margin / 2) + offset * (index - 1)
    local w = (insetFrame.w - margin) - offset * (#windows - 1)
    local h = (insetFrame.h - margin) - offset * (#windows - 1)

    local frame = {
      x = x,
      y = y,
      w = w,
      h = h
    }

    return frame
  end

  layouts["columns"] = function(window, windows, screen, index, layoutOptions)
    if #windows < 3 then
      return layouts["main-left"](window, windows, screen, index, layoutOptions)
    end

    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)

    local mainColumnWidth = (insetFrame.w / 3) + (layoutOptions.mainPaneRatio - 0.5) * insetFrame.w

    if index == 1 then
      return {
        x = insetFrame.x + (insetFrame.w - mainColumnWidth) / 2,
        y = insetFrame.y + margin / 2,
        w = mainColumnWidth - margin,
        h = insetFrame.h - margin
      }
    end

    local frame = {
      x = insetFrame.x,
      y = 0,
      w = (insetFrame.w - mainColumnWidth) / 2 - margin,
      h = 0,
    }

    if (index - 1) % 2 == 0 then
      local divs = math.floor((#windows - 1) / 2)
      local h    = insetFrame.h / divs

      frame.x = frame.x + (insetFrame.w - frame.w - margin) - margin / 2
      frame.h = h - margin
      frame.y = insetFrame.y + h * math.floor(index / 2 - 1) + margin / 2
    else
      local divs = math.ceil((#windows - 1) / 2)
      local h    = insetFrame.h / divs

      frame.x = frame.x + margin / 2
      frame.h = h - margin
      frame.y = insetFrame.y + h * math.floor(index / 2 - 1) + margin / 2
    end

    return frame
  end

  layouts["rows"] = function(window, windows, screen, index, layoutOptions)
    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)
    local rowHeight  = insetFrame.h / #windows

    local frame = {
      x = insetFrame.x + margin / 2,
      y = insetFrame.y + rowHeight * (index - 1) + margin / 2,
      w = insetFrame.w - margin,
      h = rowHeight - margin,
    }

    return frame
  end

  layouts["equal-left"] = function(window, windows, screen, index, layoutOptions)
    if #windows == 1 then
      return layouts.monocle(window, windows, screen)
    end

    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)

    local frame = {
      x = insetFrame.x,
      y = insetFrame.y,
      w = 0,
      h = 0
    }

    -- swap direction just for first two windows
    if #windows >= 2 then
      if index == 1 then
        index = 2
      elseif index == 2 then
        index = 1
      end
    end

    if index % 2 == 0 then
      local divs = math.floor(#windows / 2)
      local h    = insetFrame.h / divs

      frame.h = h - margin
      frame.w = insetFrame.w * layoutOptions.mainPaneRatio - margin
      frame.x = frame.x + margin / 2
      frame.y = frame.y + h * math.floor(index / 2 - 1) + margin / 2
    else
      local divs = math.ceil(#windows / 2)
      local h    = insetFrame.h / divs

      frame.h = h - margin
      frame.w = insetFrame.w * (1 - layoutOptions.mainPaneRatio) - margin
      frame.x = frame.x + insetFrame.w * layoutOptions.mainPaneRatio + margin / 2
      frame.y = frame.y + h * math.floor(index / 2) + margin / 2
    end

    return frame
  end

  layouts["equal-right"] = function(window, windows, screen, index, layoutOptions)
    if #windows == 1 then
      return layouts.monocle(window, windows, screen)
    end

    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)

    local frame = {
      x = insetFrame.x,
      y = insetFrame.y,
      w = 0,
      h = 0
    }

    frame.w = insetFrame.w / 2 - margin

    -- swap direction just for first two windows
    if #windows >= 2 then
      if index == 1 then
        index = 2
      elseif index == 2 then
        index = 1
      end
    end

    if index % 2 == 0 then
      local divs = math.floor(#windows / 2)
      local h    = insetFrame.h / divs

      frame.h = h - margin
      frame.w = insetFrame.w * (1 - layoutOptions.mainPaneRatio) - margin
      frame.x = frame.x + insetFrame.w * layoutOptions.mainPaneRatio + margin / 2
      frame.y = frame.y + h * math.floor(index / 2 - 1) + margin / 2
    else
      local divs = math.ceil(#windows / 2)
      local h    = insetFrame.h / divs

      frame.h = h - margin
      frame.w = insetFrame.w * layoutOptions.mainPaneRatio - margin
      frame.x = frame.x + margin / 2
      frame.y = frame.y + h * math.floor(index / 2) + margin / 2
    end

    return frame
  end

  layouts["main-left"] = function(window, windows, screen, index, layoutOptions)
    if #windows == 1 then
      return layouts.monocle(window, windows, screen)
    end

    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)

    local frame = {
      x = insetFrame.x,
      y = insetFrame.y,
      w = 0,
      h = 0
    }

    if index == 1 then
      frame.x = frame.x + margin / 2
      frame.y = frame.y + margin / 2
      frame.h = insetFrame.h - margin
      frame.w = insetFrame.w * layoutOptions.mainPaneRatio - margin
    else
      local divs = #windows - 1
      local h    = insetFrame.h / divs

      frame.h = h - margin
      frame.w = insetFrame.w * (1 - layoutOptions.mainPaneRatio) - margin
      frame.x = frame.x + insetFrame.w * layoutOptions.mainPaneRatio + margin / 2
      frame.y = frame.y + h * (index - 2) + margin / 2
    end

    return frame
  end

  layouts["main-right"] = function(window, windows, screen, index, layoutOptions)
    if #windows == 1 then
      return layouts.monocle(window, windows, screen)
    end

    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)

    local frame = {
      x = insetFrame.x,
      y = insetFrame.y,
      w = 0,
      h = 0
    }

    if index == 1 then
      frame.x = frame.x + insetFrame.w * layoutOptions.mainPaneRatio + margin / 2
      frame.y = frame.y + margin / 2
      frame.h = insetFrame.h - margin
      frame.w = insetFrame.w * (1 - layoutOptions.mainPaneRatio) - margin
    else
      local divs = #windows - 1
      local h    = insetFrame.h / divs

      frame.x = frame.x + margin / 2
      frame.y = frame.y + h * (index - 2) + margin / 2
      frame.w = insetFrame.w * layoutOptions.mainPaneRatio - margin
      frame.h = h - margin
    end

    return frame
  end

  layouts["main-center"] = function(window, windows, screen, index, layoutOptions)
    local insetFrame      = getInsetFrame(screen)
    local margin          = hhtwm.margin or 0
    local mainColumnWidth = insetFrame.w * layoutOptions.mainPaneRatio + margin / 2

    if index == 1 then
      return {
        x = insetFrame.x + (insetFrame.w - mainColumnWidth) / 2 + margin / 2,
        y = insetFrame.y + margin / 2,
        w = mainColumnWidth - margin,
        h = insetFrame.h - margin
      }
    end

    local frame = {
      x = insetFrame.x,
      y = 0,
      w = (insetFrame.w - mainColumnWidth) / 2 - margin,
      h = 0,
    }

    if (index - 1) % 2 == 0 then
      local divs = math.floor((#windows - 1) / 2)
      local h    = insetFrame.h / divs

      frame.x = frame.x + margin / 2
      frame.h = h - margin
      frame.y = insetFrame.y + h * math.floor(index / 2 - 1) + margin / 2
    else
      local divs = math.ceil((#windows - 1) / 2)
      local h    = insetFrame.h / divs

      frame.x = frame.x + (insetFrame.w - frame.w - margin) + margin / 2
      frame.h = h - margin
      frame.y = insetFrame.y + h * math.floor(index / 2 - 1) + margin / 2
    end

    return frame
  end

  layouts["side-by-side"] = function(window, windows, screen, index, layoutOptions)
    local margin     = hhtwm.margin or 0
    local insetFrame = getInsetFrame(screen)

    local frame = {
      x = 0,
      y = insetFrame.y + margin / 2,
      w = 0,
      h = insetFrame.h - margin
    }

    if index % 2 == 0 then
      frame.x = insetFrame.x + margin / 2
      frame.w = insetFrame.w * layoutOptions.mainPaneRatio - margin
    else
      frame.x = insetFrame.x + insetFrame.w * layoutOptions.mainPaneRatio + margin / 2
      frame.w = insetFrame.w * (1 - layoutOptions.mainPaneRatio) - margin
    end

    return frame
  end

  return layouts
end
