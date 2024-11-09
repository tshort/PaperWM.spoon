--- === PaperWM.spoon ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
---
--- # Usage
---
--- `PaperWM:start()` will begin automatically tiling new and existing windows.
--- `PaperWM:stop()` will release control over windows.
---
--- Set `PaperWM.window_gap` to the number of pixels to space between windows and
--- the top and bottom screen edges.
---
--- Overwrite `PaperWM.window_filter` to ignore specific applications. For example:
---
--- ```
--- PaperWM.window_filter = PaperWM.window_filter:setAppFilter("Finder", false)
--- PaperWM:start() -- restart for new window filter to take effect
--- ```
---
--- # Limitations
---
--- MacOS does not allow a window to be moved fully off-screen. Windows that would
--- be tiled off-screen are placed in a margin on the left and right edge of the
--- screen. They are still visible and clickable.
---
--- It's difficult to detect when a window is dragged from one space or screen to
--- another. Use the move_window_N commands to move windows between spaces and
--- screens.
---
--- Arrange screens vertically to prevent windows from bleeding into other screens.
---
---
--- Download: [https://github.com/mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon)
local Mouse <const> = hs.mouse
local Rect <const> = hs.geometry.rect
local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Timer <const> = hs.timer
local Watcher <const> = hs.uielement.watcher
local Window <const> = hs.window
local WindowFilter <const> = hs.window.filter
local leftClick <const> = hs.eventtap.leftClick
local leftMouseDown <const> = hs.eventtap.event.types.leftMouseDown
local leftMouseDragged <const> = hs.eventtap.event.types.leftMouseDragged
local leftMouseUp <const> = hs.eventtap.event.types.leftMouseUp
local newMouseEvent <const> = hs.eventtap.event.newMouseEvent
local operatingSystemVersion <const> = hs.host.operatingSystemVersion
local partial <const> = hs.fnutils.partial
local rectMidPoint <const> = hs.geometry.rectMidPoint

local PaperWM = {}
PaperWM.__index = PaperWM

-- Metadata
PaperWM.name = "PaperWM"
PaperWM.version = "0.5"
PaperWM.author = "Michael Mogenson"
PaperWM.homepage = "https://github.com/mogenson/PaperWM.spoon"
PaperWM.license = "MIT - https://opensource.org/licenses/MIT"

-- Types

---@alias PaperWM table PaperWM module object
---@alias Window userdata a ui.window
---@alias Frame table hs.geometry rect
---@alias Index { row: number, col: number, space: number }
---@alias Space number a Mission Control space ID
---@alias Screen userdata hs.screen

---@alias Mapping { [string]: (table | string)[]}
PaperWM.default_hotkeys = {
    stop_events          = { { "alt", "cmd", "shift" }, "q" },
    refresh_windows      = { { "alt", "cmd", "shift" }, "r" },
    toggle_floating      = { { "alt", "cmd", "shift" }, "escape" },
    focus_left           = { { "alt", "cmd" }, "left" },
    focus_right          = { { "alt", "cmd" }, "right" },
    focus_up             = { { "alt", "cmd" }, "up" },
    focus_down           = { { "alt", "cmd" }, "down" },
    swap_left            = { { "alt", "cmd", "shift" }, "left" },
    swap_right           = { { "alt", "cmd", "shift" }, "right" },
    swap_up              = { { "alt", "cmd", "shift" }, "up" },
    swap_down            = { { "alt", "cmd", "shift" }, "down" },
    center_window        = { { "alt", "cmd" }, "c" },
    full_width           = { { "alt", "cmd" }, "f" },
    cycle_width          = { { "alt", "cmd" }, "r" },
    cycle_height         = { { "alt", "cmd", "shift" }, "r" },
    reverse_cycle_width  = { { "ctrl", "alt", "cmd" }, "r" },
    reverse_cycle_height = { { "ctrl", "alt", "cmd", "shift" }, "r" },
    slurp_in             = { { "alt", "cmd" }, "i" },
    barf_out             = { { "alt", "cmd" }, "o" },
    switch_space_l       = { { "alt", "cmd" }, "," },
    switch_space_r       = { { "alt", "cmd" }, "." },
    switch_space_1       = { { "alt", "cmd" }, "1" },
    switch_space_2       = { { "alt", "cmd" }, "2" },
    switch_space_3       = { { "alt", "cmd" }, "3" },
    switch_space_4       = { { "alt", "cmd" }, "4" },
    switch_space_5       = { { "alt", "cmd" }, "5" },
    switch_space_6       = { { "alt", "cmd" }, "6" },
    switch_space_7       = { { "alt", "cmd" }, "7" },
    switch_space_8       = { { "alt", "cmd" }, "8" },
    switch_space_9       = { { "alt", "cmd" }, "9" },
    move_window_1        = { { "alt", "cmd", "shift" }, "1" },
    move_window_2        = { { "alt", "cmd", "shift" }, "2" },
    move_window_3        = { { "alt", "cmd", "shift" }, "3" },
    move_window_4        = { { "alt", "cmd", "shift" }, "4" },
    move_window_5        = { { "alt", "cmd", "shift" }, "5" },
    move_window_6        = { { "alt", "cmd", "shift" }, "6" },
    move_window_7        = { { "alt", "cmd", "shift" }, "7" },
    move_window_8        = { { "alt", "cmd", "shift" }, "8" },
    move_window_9        = { { "alt", "cmd", "shift" }, "9" }
}


-- filter for windows to manage
PaperWM.window_filter = WindowFilter.new():setOverrideFilter({
    visible = true,
    fullscreen = false,
    hasTitlebar = true,
    allowRoles = "AXStandardWindow"
})

-- number of pixels between windows
PaperWM.window_gap = 8

-- ratios to use when cycling widths and heights, golden ratio by default
PaperWM.window_ratios = { 0.3, 0.6, 0.8}

-- size of the on-screen margin to place off-screen windows
PaperWM.screen_margin = 1

-- logger
PaperWM.logger = hs.logger.new(PaperWM.name)

-- constants
---@enum Direction
local Direction <const> = {
    LEFT = -1,
    RIGHT = 1,
    UP = -2,
    DOWN = 2,
    WIDTH = 3,
    HEIGHT = 4,
    ASCENDING = 5,
    DESCENDING = 6
}

-- hs.settings key for persisting is_floating, stored as an array of window id
local IsFloatingKey <const> = 'PaperWM_is_floating'

-- array of windows sorted from left to right
window_list = {} -- 3D array of tiles in order of [screenid][space][x][y]
                       -- also stores 
                       --     [screenid].activespace
                       --     [screenid][space].focusedwindow
                       --     [screenid][space].visiblewindows
                       --     [screenid][space][x][y].win
                       --     [screenid][space][x][y].frame
                       
index_table = {} -- dictionary of {screenid, space, x, y} with window id for keys
local ui_watchers = {} -- dictionary of uielement watchers with window id for keys
local is_floating = {} -- dictionary of boolean with window id for keys

-- refresh window layout on screen change
local screen_watcher = Screen.watcher.new(function() PaperWM:initWindows() end)

-- https://stackoverflow.com/questions/640642/how-do-you-copy-a-lua-table-by-value
function copy(obj, seen)
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then return seen[obj] end
  local s = seen or {}
  local res = setmetatable({}, getmetatable(obj))
  s[obj] = res
  for k, v in pairs(obj) do res[copy(k, s)] = copy(v, s) end
  return res
end

---move a window offsreen
---@param windowframe window to move
---@return nil
function PaperWM:stashWindow(windowframe)
    local idx = index_table[windowframe.win:id()]
    local screenframe = hs.screen.find(idx.screenid):frame()
    local frame = windowframe.win:frame()
    local frame2 = copy(frame)      -- remember its position
    frame.x = screenframe.x2
    self:moveWindow(windowframe.win, frame)
    windowframe.frame = frame2
end        

---restore a window
---@param windowframe window to move
---@return nil
function PaperWM:restoreWindow(windowframe)
    self:moveWindow(windowframe.win, windowframe.frame)
end


---return the leftmost window that's completely on the screen
---@param columns Window[] a column of windows
---@param screen Frame the coordinates of the screen
---@return Window|nil
local function getFirstVisibleWindow(columns, screen)
    local x = screen:frame().x
    for _, windows in ipairs(columns or {}) do
        local window = windows[1].win -- take first window in column
        if window:frame().x >= x then return window end
    end
end

---get a column of windows for a space from the window_list
---@param screenid Screen
---@param space Space
---@param col number
---@return Window[]
local function getColumn(screenid, space, col) return (window_list[screenid][space] or {})[col] end

---get a window in a row, in a column, in a space from the window_list
---@param screenid Screen
---@param space Space
---@param col number
---@param row number
---@return Window
local function getWindow(screenid, space, col, row)
    return (getColumn(screenid, space, col) or {})[row].win
end

local function getWindowFrame(screenid, space, col, row)
    return (getColumn(screenid, space, col) or {})[row]
end

---get the tileable bounds for a screen
---@param screen Screen
---@return Frame
local function getCanvas(screen)
    local screen_frame = screen:frame()
    return Rect(screen_frame.x + PaperWM.window_gap,
        screen_frame.y + PaperWM.window_gap,
        screen_frame.w - (2 * PaperWM.window_gap),
        screen_frame.h - (2 * PaperWM.window_gap))
end

---update the column number in window_list to be ascending from provided column up
---@param space Space
---@param column number
local function updateIndexTable(screenid, space, column)
    local columns = window_list[screenid][space] or {}
    for col = column, #columns do
        for row, windowf in ipairs(getColumn(screenid, space, col)) do
            index_table[windowf.win:id()] = { screenid = screenid, space = space, col = col, row = row }
        end
    end
end

---save the is_floating list to settings
local function persistFloatingList()
    local persisted = {}
    for k, _ in pairs(is_floating) do
        table.insert(persisted, k)
    end
    hs.settings.set(IsFloatingKey, persisted)
end

local focused_window = nil ---@type Window|nil
local pending_window = nil ---@type Window|nil

---callback for window events
---@param window Window
---@param event string name of the event
---@param self PaperWM
local function windowEventHandler(window, event, self)
    self.logger.df("%s for [%s] id: %d", event, window, window and window:id() or -1)

    --[[ When a new window is created, We first get a windowVisible event but
    without a Space. Next we receive a windowFocused event for the window, but
    this also sometimes lacks a Space. Our approach is to store the window
    pending a Space in the pending_window variable and set a timer to try to add
    the window again later. Also schedule the windowFocused handler to run later
    after the window was added ]]
    --

    local idx = index_table[window:id()]
    local idx_prior = nil
    local space = nil
    if is_floating[window:id()] then
        -- this event is only meaningful for floating windows
        if event == "windowDestroyed" then
            is_floating[window:id()] = nil
            persistFloatingList()
        end
        -- no other events are meaningful for floating windows
        return
    end

    if event == "windowFocused" then
        if pending_window and window == pending_window then
            Timer.doAfter(Window.animationDuration,
                function()
                    self.logger.vf("pending window timer for %s", window)
                    windowEventHandler(window, event, self)
                end)
            return
        end
        if focused_window then
            idx_prior = index_table[focused_window:id()]
        end
        focused_window = window
        if idx then
            window_list[idx.screenid][idx.space].focusedwindow = focused_window:id()
            space = idx.space
            if idx_prior then
                if idx_prior.screenid ~= idx.screenid or
                   idx_prior.space ~= idx.space then
                    self:focusSpace(idx.screenid, idx.space, window)
                end
            end
        else
            space = self:addWindow(window)
        end
    elseif event == "windowVisible" or event == "windowUnfullscreened" then
        space = self:addWindow(window)
        if pending_window and window == pending_window then
            pending_window = nil -- tried to add window for the second time
        elseif not space then
            pending_window = window
            Timer.doAfter(Window.animationDuration,
                function()
                    windowEventHandler(window, event, self)
                end)
            return
        end
    elseif event == "windowNotVisible" then
        space = self:removeWindow(window)
    elseif event == "windowFullscreened" then
        space = self:removeWindow(window, true) -- don't focus new window if fullscreened
    elseif event == "AXWindowMoved" or event == "AXWindowResized" then
        -- space = Spaces.windowSpaces(window)[1]
    end

    if space then 
        self:tileSpace(window:screen(), space)
    end
end

local function between(x, x1, x2)
    return x > x1 and x < x2
end
local function isvisible(frame, screenframe)
    return (between(frame.x1, screenframe.x1 + PaperWM.screen_margin, screenframe.x2 - PaperWM.screen_margin) or
            between(frame.x2, screenframe.x1 + PaperWM.screen_margin, screenframe.x2 - PaperWM.screen_margin)) and
           (between(frame.y1, screenframe.y1, screenframe.y2) or
            between(frame.y2, screenframe.y1, screenframe.y2))
end

---make the specified space the active space
---@param space Space
---@param window Window|nil a window in the space
function PaperWM:focusSpace(screenid, space, window)
    local screen_frame = hs.screen.find(screenid):frame()
    for i, cols in ipairs(window_list[screenid][window_list[screenid].activespace]) do
        for _, wf in ipairs(cols) do
            if isvisible(wf.win:frame(), screen_frame) then
                PaperWM:stashWindow(wf)
            end
        end
    end
    window_list[screenid].activespace = space
    for i, cols in ipairs(window_list[screenid][window_list[screenid].activespace]) do
        for _, wf in ipairs(cols) do
            if isvisible(wf.frame, screen_frame) then
                PaperWM:restoreWindow(wf)
            end
        end
    end
    if window then
        window:focus()
    elseif window_list[screenid][space].focusedwindow then
        hs.window.find(window_list[screenid][space].focusedwindow):focus()
    end
end

---start automatic window tiling
---@return PaperWM
function PaperWM:start()
    -- check for some settings
    -- TODO: remove this check
    if Spaces.screensHaveSeparateSpaces() then
        self.logger.e(
            "please uncheck 'Displays have separate Spaces' in System Preferences -> Mission Control")
    end

    -- clear state
    window_list = {}
    index_table = {}
    ui_watchers = {}
    is_floating = {}

    hs.window.animationDuration = 0
    -- restore saved is_floating state, filtering for valid windows
    local persisted = hs.settings.get(IsFloatingKey) or {}
    for _, id in ipairs(persisted) do
        local window = Window.get(id)
        if window and self.window_filter:isWindowAllowed(window) then
            is_floating[id] = true
        end
    end
    persistFloatingList()

    -- populate window list, index table, ui_watchers, and set initial layout
    self:initWindows()

    -- listen for window events
    self.window_filter:subscribe({
        WindowFilter.windowFocused, WindowFilter.windowVisible,
        WindowFilter.windowNotVisible, WindowFilter.windowFullscreened,
        WindowFilter.windowUnfullscreened, WindowFilter.windowDestroyed
    }, function(window, _, event) windowEventHandler(window, event, self) end)

    -- watch for external monitor plug / unplug
    screen_watcher:start()

    return self
end

---stop automatic window tiling
---@return PaperWM
function PaperWM:stop()
    -- stop events
    self.window_filter:unsubscribeAll()
    for _, watcher in pairs(ui_watchers) do watcher:stop() end
    screen_watcher:stop()

    -- fit all windows within the bounds of the screen
    for _, window in ipairs(self.window_filter:getWindows()) do
        window:setFrameInScreenBounds()
    end

    return self
end

---tile a column of window by moving and resizing
---@param windows Window[] column of windows
---@param bounds Frame bounds to constrain column of tiled windows
---@param h number|nil set windows to specified height
---@param w number|nil set windows to specified width
---@param id number|nil id of window to set specific height
---@param h4id number|nil specific height for provided window id
---@return number width of tiled column
function PaperWM:tileColumn(windows, bounds, h, w, id, h4id)
    local last_window, frame
    for _, windowf in ipairs(windows) do
        local window = windowf.win
        frame = window:frame()
        w = w or frame.w -- take given width or width of first window
        if bounds.x then -- set either left or right x coord
            frame.x = bounds.x
        elseif bounds.x2 then
            frame.x = bounds.x2 - w
        end
        if h then              -- set height if given
            if id and h4id and window:id() == id then
                frame.h = h4id -- use this height for window with id
            else
                frame.h = h    -- use this height for all other windows
            end
        end
        frame.y = bounds.y
        frame.w = w
        frame.y2 = math.min(frame.y2, bounds.y2) -- don't overflow bottom of bounds
        self:moveWindow(window, frame)
        bounds.y = math.min(frame.y2 + self.window_gap, bounds.y2)
        last_window = window
    end
    -- expand last window height to bottom
    if frame.y2 ~= bounds.y2 then
        frame.y2 = bounds.y2
        self:moveWindow(last_window, frame)
    end
    return w -- return width of column
end

---tile all column in a space by moving and resizing windows
---@param space Space
function PaperWM:tileSpace(screen, space)
    -- if not space or Spaces.spaceType(space) ~= "user" then
    --     self.logger.e("current space invalid")
    --     return
    -- end

    -- if focused window is in space, tile from that
    local focused_window = Window.focusedWindow()
    local anchor_window = nil
    if focused_window and not is_floating[focused_window:id()] and window_list[screen:id()].activespace == space then
        anchor_window = focused_window
    else
        anchor_window = getFirstVisibleWindow(window_list[screen:id()][space], screen)
    end

    if not anchor_window then
        self.logger.e("no anchor window in space")
        return
    end

    local anchor_index = index_table[anchor_window:id()]
    if not anchor_index then
        self.logger.e("anchor index not found")
        return -- bail
    end

    -- get some global coordinates
    local screen_frame <const> = screen:frame()
    local left_margin <const> = screen_frame.x + self.screen_margin
    local right_margin <const> = screen_frame.x2 - self.screen_margin
    local canvas <const> = getCanvas(screen)

    -- make sure anchor window is on screen
    local anchor_frame = anchor_window:frame()
    anchor_frame.x = math.max(anchor_frame.x, canvas.x)
    anchor_frame.w = math.min(anchor_frame.w, canvas.w)
    anchor_frame.h = math.min(anchor_frame.h, canvas.h)
    if anchor_frame.x2 > canvas.x2 then
        anchor_frame.x = canvas.x2 - anchor_frame.w
    end

    -- adjust anchor window column
    local column = getColumn(screen:id(), space, anchor_index.col)
    if not column then
        self.logger.e("no anchor window column")
        return
    end

    -- TODO: need a minimum window height
    if #column == 1 then
        anchor_frame.y, anchor_frame.h = canvas.y, canvas.h
        self:moveWindow(anchor_window, anchor_frame)
    else
        local n = #column - 1 -- number of other windows in column
        local h =
            math.max(0, canvas.h - anchor_frame.h - (n * self.window_gap)) // n
        local bounds = {
            x = anchor_frame.x,
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2
        }
        self:tileColumn(column, bounds, h, anchor_frame.w, anchor_window:id(),
            anchor_frame.h)
    end

    -- tile windows from anchor right
    local x = math.min(anchor_frame.x2 + self.window_gap, right_margin)
    for col = anchor_index.col + 1, #(window_list[screen:id()][space] or {}) do
        local bounds = { x = x, x2 = nil, y = canvas.y, y2 = canvas.y2 }
        local column_width = self:tileColumn(getColumn(screen:id(), space, col), bounds)
        x = math.min(x + column_width + self.window_gap, right_margin)
    end

    -- tile windows from anchor left
    local x2 = math.max(anchor_frame.x - self.window_gap, left_margin)
    for col = anchor_index.col - 1, 1, -1 do
        local bounds = { x = nil, x2 = x2, y = canvas.y, y2 = canvas.y2 }
        local column_width = self:tileColumn(getColumn(screen:id(), space, col), bounds)
        x2 = math.max(x2 - column_width - self.window_gap, left_margin)
    end
end

---get all windows across all spaces and retile them
function PaperWM:initWindows()
    -- find screens and windows in screens
    -- assign these to the first space on each screen
    for _, screen in pairs(hs.screen.allScreens()) do
        local screenid = screen:id()
        window_list[screenid] = {}
        window_list[screenid].activespace = 1
        for _, w in pairs(hs.window.filter.new(true):setScreens(screenid):getWindows()) do
            local space = self:addWindow(w)
        end 
        self:tileSpace(screen, 1)
    end 
end

---add a new window to be tracked and automatically tiled
---@param add_window Window new window to be added
---@return Space|nil space that contains new window
function PaperWM:addWindow(add_window, screenid, space)
    -- A window with no tabs will have a tabCount of 0
    -- A new tab for a window will have tabCount equal to the total number of tabs
    -- All existing tabs in a window will have their tabCount reset to 0
    -- We can't query whether an exiting hs.window is a tab or not after creation
    -- if add_window:tabCount() > 0 then
    --     hs.notify.show("PaperWM", "Windows with tabs are not supported!",
    --         "See https://github.com/mogenson/PaperWM.spoon/issues/39")
    --     return
    -- end

    -- check if window is already in window list
    if index_table[add_window:id()] then return end
    screenid = screenid or add_window:screen():id()
    space = space or window_list[screenid].activespace
    if not space then
        self.logger.e("add window does not have a space")
        return
    end
    if not window_list[screenid][space] then window_list[screenid][space] = {} end

    -- find where to insert window
    local add_column = 1

    -- when addWindow() is called from a window created event:
    -- focused_window from previous window focused event will not be add_window
    -- hs.window.focusedWindow() will return add_window
    -- new window focused event for add_window has not happened yet
    if focused_window and
        ((index_table[focused_window:id()] or {}).space == space) and
        (focused_window:id() ~= add_window:id()) then
        add_column = index_table[focused_window:id()].col + 1 -- insert to the right
    else
        local x = add_window:frame().center.x
        for col, windowfs in ipairs(window_list[screenid][space]) do
            if x < windowfs[1].win:frame().center.x then
                add_column = col
                break
            end
        end
    end
    local add_windowf = {win = add_window, frame = add_window:frame()}
    -- add window
    table.insert(window_list[screenid][space], add_column, { add_windowf })

    -- update index table
    updateIndexTable(screenid, space, add_column)

    -- subscribe to window moved events
    local watcher = add_window:newWatcher(
        function(window, event, _, self)
            windowEventHandler(window, event, self)
        end, self)
    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    ui_watchers[add_window:id()] = watcher

    return space
end

---remove a window from being tracked and automatically tiled
---@param remove_window Window window to be removed
---@param skip_new_window_focus boolean|nil don't focus a nearby window if true
---@return Space|nil space that contained removed window
function PaperWM:removeWindow(remove_window, skip_new_window_focus)
    -- get index of window
    local remove_index = index_table[remove_window:id()]
    if not remove_index then
        self.logger.e("remove index not found")
        return
    end

    if not skip_new_window_focus then -- find nearby window to focus
        local focused_window = Window.focusedWindow()
        if focused_window and remove_window:id() == focused_window:id() then
            for _, direction in ipairs({
                Direction.DOWN, Direction.UP, Direction.LEFT, Direction.RIGHT
            }) do if self:focusWindow(direction, remove_index) then break end end
        end
    end

    -- remove window
    table.remove(window_list[remove_index.screenid][remove_index.space][remove_index.col],
        remove_index.row)
    if #window_list[remove_index.screenid][remove_index.space][remove_index.col] == 0 then
        table.remove(window_list[remove_index.screenid][remove_index.space], remove_index.col)
    end

    -- remove watcher
    ui_watchers[remove_window:id()]:stop()
    ui_watchers[remove_window:id()] = nil

    -- update index table
    index_table[remove_window:id()] = nil
    updateIndexTable(remove_index.screenid, remove_index.space, remove_index.space, remove_index.col)

    -- remove if space is empty
    if #window_list[remove_index.screenid][remove_index.space] == 0 then
        window_list[remove_index.screenid][remove_index.space] = nil
    end

    return remove_index.space -- return space for removed window
end

---move focus to a new window next to the currently focused window
---@param direction Direction use either Direction UP, DOWN, LEFT, or RIGHT
---@param focused_index Index index of focused window within the window_list
function PaperWM:focusWindow(direction, focused_index)
    hs.window.animationDuration = 0.2
    if not focused_index then
        -- get current focused window
        local focused_window = Window.focusedWindow()
        if not focused_window then
            self.logger.d("focused window not found")
            return
        end

        -- get focused window index
        focused_index = index_table[focused_window:id()]
    end

    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    -- get new focused window
    local new_focused_window
    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- walk down column, looking for match in neighbor column
        for row = focused_index.row, 1, -1 do
            new_focused_window = getWindow(focused_index.screenid, focused_index.space,
                focused_index.col + direction, row)
            if new_focused_window then break end
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        new_focused_window = getWindow(focused_index.screenid, focused_index.space, focused_index.col,
            focused_index.row + (direction // 2))
    end

    if not new_focused_window then
        -- self.logger.d("new focused window not found")
        return
    end

    -- focus new window, windowFocused event will be emited immediately
    new_focused_window:focus()
    local idx = index_table[new_focused_window:id()]
    window_list[idx.screenid][idx.space].focusedwindow = new_focused_window:id()
    hs.window.animationDuration = 0
    return new_focused_window
end

---swap the focused window with a window next to it
---if swapping horizontally and the adjacent window is in a column, swap the
---entire column. if swapping vertically and the focused window is in a column,
---swap positions within the column
---@param direction Direction use Direction LEFT, RIGHT, UP, or DOWN
function PaperWM:swapWindows(direction)
    -- use focused window as source window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- get focused window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    hs.window.animationDuration = 0.2
    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- get target windows
        local target_index = { col = focused_index.col + direction }
        local target_column = getColumn(focused_index.screenid, focused_index.space, target_index.col)
        if not target_column then
            self.logger.d("target column not found")
            return
        end

        -- swap place in window list
        local focused_column = getColumn(focused_index.screenid, focused_index.space, focused_index.col)
        window_list[focused_index.screenid][focused_index.space][target_index.col] = focused_column
        window_list[focused_index.screenid][focused_index.space][focused_index.col] = target_column

        -- update index table
        for row, windowf in ipairs(target_column) do
            index_table[windowf.win:id()] = {
                screenid = focused_index.screenid,
                space = focused_index.space,
                col = focused_index.col,
                row = row
            }
        end
        for row, windowf in ipairs(focused_column) do
            index_table[windowf.win:id()] = {
                screenid = focused_index.screenid,
                space = focused_index.space,
                col = target_index.col,
                row = row
            }
        end

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_column[1].win:frame()
        if direction == Direction.LEFT then
            focused_frame.x = target_frame.x
            target_frame.x = focused_frame.x2 + self.window_gap
        else -- Direction.RIGHT
            target_frame.x = focused_frame.x
            focused_frame.x = target_frame.x2 + self.window_gap
        end
        for _, windowf in ipairs(target_column) do
            local frame = windowf.win:frame()
            frame.x = target_frame.x
            self:moveWindow(windowf.win, frame)
        end
        for _, windowf in ipairs(focused_column) do
            local frame = windowf.win:frame()
            frame.x = focused_frame.x
            self:moveWindow(windowf.win, frame)
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        -- get target window
        local target_index = {
            screenid = focused_index.screenid,
            space = focused_index.space,
            col = focused_index.col,
            row = focused_index.row + (direction // 2)
        }
        local target_windowf = getWindowFrame(target_index.screenid, target_index.space, target_index.col,
            target_index.row)
        if not target_windowf then
            self.logger.d("target window not found")
            return
        end

        -- swap places in window list
        window_list[target_index.screenid][target_index.space][target_index.col][target_index.row] =
            focused_windowf
        window_list[focused_index.screenid][focused_index.space][focused_index.col][focused_index.row] =
            target_windowf

        -- update index table
        index_table[target_windowf.win:id()] = focused_index
        index_table[focused_windowf.win:id()] = target_index

        -- swap frames
        local focused_frame = focused_windowf.win:frame()
        local target_frame = target_windowf.win:frame()
        if direction == Direction.UP then
            focused_frame.y = target_frame.y
            target_frame.y = focused_frame.y2 + self.window_gap
        else -- Direction.DOWN
            target_frame.y = focused_frame.y
            focused_frame.y = target_frame.y2 + self.window_gap
        end
        self:moveWindow(focused_windowf.win, focused_frame)
        self:moveWindow(target_windowf.win, target_frame)
    end
    hs.window.animationDuration = 0

    -- update layout
    self:tileSpace(focused_index.screenid, focused_index.space)
end

---move the focused window to the center of the screen, horizontally
---don't resize the window or change it's vertical position
function PaperWM:centerWindow()
    hs.window.animationDuration = 0.2
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- get global coordinates
    local focused_frame = focused_window:frame()
    local screen_frame = focused_window:screen():frame()

    -- center window
    focused_frame.x = screen_frame.x + (screen_frame.w // 2) -
        (focused_frame.w // 2)
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    self:tileSpace(window:screen(), space)
    hs.window.animationDuration = 0
end

---set the focused window to the width of the screen
---don't change the height
function PaperWM:setWindowFullWidth()
    hs.window.animationDuration = 0.2
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- fullscreen window width
    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()
    focused_frame.x, focused_frame.w = canvas.x, canvas.w
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    self:tileSpace(focused_window:screen(), index_table[focused_window:id()].space)
    hs.window.animationDuration = 0
end

---resize the width or height of the window, keeping the other dimension the
---same. cycles through the ratios specified in PaperWM.window_ratios
---@param direction Direction use Direction.WIDTH or Direction.HEIGHT
---@param cycle_direction Direction use Direction.ASCENDING or DESCENDING
function PaperWM:cycleWindowSize(direction, cycle_direction)
    hs.window.animationDuration = 0.2
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    local function findNewSize(area_size, frame_size, cycle_direction)
        local sizes = {}
        local new_size
        if cycle_direction == Direction.ASCENDING then
            for index, ratio in ipairs(self.window_ratios) do
                sizes[index] = ratio * (area_size + self.window_gap) - self.window_gap
            end

            -- find new size
            new_size = sizes[1]
            for _, size in ipairs(sizes) do
                if size > frame_size + 10 then
                    new_size = size
                    break
                end
            end
        elseif cycle_direction == Direction.DESCENDING then
            for index, ratio in ipairs(self.window_ratios) do
                sizes[index] = ratio * (area_size + self.window_gap) - self.window_gap
            end

            -- find new size, starting from the end
            new_size = sizes[#sizes] -- Start with the largest size
            for i = #sizes, 1, -1 do
                if sizes[i] < frame_size - 10 then
                    new_size = sizes[i]
                    break
                end
            end
        else
            self.logger.e("cycle_direction must be either Direction.ASCENDING or Direction.DESCENDING")
            return
        end

        return new_size
    end

    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()

    if direction == Direction.WIDTH then
        local new_width = findNewSize(canvas.w, focused_frame.w, cycle_direction)
        focused_frame.x = focused_frame.x + ((focused_frame.w - new_width) // 2)
        focused_frame.w = new_width
    elseif direction == Direction.HEIGHT then
        local new_height = findNewSize(canvas.h, focused_frame.h, cycle_direction)
        focused_frame.y = math.max(canvas.y, focused_frame.y + ((focused_frame.h - new_height) // 2))
        focused_frame.h = new_height
        focused_frame.y = focused_frame.y - math.max(0, focused_frame.y2 - canvas.y2)
    else
        self.logger.e("direction must be either Direction.WIDTH or Direction.HEIGHT")
        return
    end

    -- apply new size
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    self:tileSpace(focused_window:screen(), index_table[focused_window:id()].space)
    hs.window.animationDuration = 0
end

---take the current focused window and move it into the bottom of
---the column to the left
function PaperWM:slurpWindow()
    -- TODO paperwm behavior:
    -- add top window from column to the right to bottom of current column
    -- if no colum to the right and current window is only window in current column,
    -- add current window to bottom of column to the left

    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- get window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    -- get column to left
    local column = getColumn(focused_index.screenid, focused_index.space, focused_index.col - 1)
    if not column then
        self.logger.d("column not found")
        return
    end

    -- remove window
    table.remove(window_list[focused_index.space][focused_index.col],
        focused_index.row)
    if #window_list[focused_index.space][focused_index.col] == 0 then
        table.remove(window_list[focused_index.space], focused_index.col)
    end

    -- append to end of column
    table.insert(column, focused_window)

    -- update index table
    local num_windows = #column
    index_table[focused_window:id()] = {
        screenid = focused_index.screenid,
        space = focused_index.space,
        col = focused_index.col - 1,
        row = num_windows
    }
    updateIndexTable(focused_index.screenid, focused_index.space, focused_index.col)

    -- adjust window frames
    local canvas = getCanvas(focused_window:screen())
    local bounds = {
        x = column[1]:frame().x,
        x2 = nil,
        y = canvas.y,
        y2 = canvas.y2
    }
    local h = math.max(0, canvas.h - ((num_windows - 1) * self.window_gap)) //
        num_windows
    self:tileColumn(column, bounds, h)

    -- update layout
    self:tileSpace(focused_index.screenid, focused_index.space)
end

---remove focused window from it's current column and place into
---a new column to the right
function PaperWM:barfWindow()
    -- TODO paperwm behavior:
    -- remove bottom window of current column
    -- place window into a new column to the right--

    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- get window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    -- get column
    local column = getColumn(focused_index.screenid, focused_index.space, focused_index.col)
    if #column == 1 then
        self.logger.d("only window in column")
        return
    end

    -- remove window and insert in new column
    table.remove(column, focused_index.row)
    table.insert(window_list[focused_index.space], focused_index.col + 1,
        { focused_window })

    -- update index table
    updateIndexTable(focused_index.space, focused_index.col)

    -- adjust window frames
    local num_windows = #column
    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()
    local bounds = { x = focused_frame.x, x2 = nil, y = canvas.y, y2 = canvas.y2 }
    local h = math.max(0, canvas.h - ((num_windows - 1) * self.window_gap)) //
        num_windows
    focused_frame.y = canvas.y
    focused_frame.x = focused_frame.x2 + self.window_gap
    focused_frame.h = canvas.h
    self:moveWindow(focused_window, focused_frame)
    self:tileColumn(column, bounds, h)

    -- update layout
    self:tileSpace(focused_index.screen, focused_index.space)
end

---switch to a Mission Control space to the left or right of current space
---@param direction Direction use Direction.LEFT or Direction.RIGHT
function PaperWM:incrementSpace(direction)
    local index = index_table[focused_window:id()]
    if direction == Direction.UP and index.space > 1 then
        self:focusSpace(index.screenid, index.space - 1)
    end
    if direction == Direction.DOWN and index.space < #(window_list[index.screenid]) then
        self:focusSpace(index.screenid, index.space + 1)
    end
end

function PaperWM:goUpSpace()
    local index = index_table[focused_window:id()]
    if index.space > 1 then
        self:focusSpace(index.screenid, index.space - 1)
    end
end
function PaperWM:goDownSpace()
    local index = index_table[focused_window:id()]
    if index.space < #(window_list[index.screenid]) then
        self:focusSpace(index.screenid, index.space + 1)
    end
end
function PaperWM:moveWindowUpSpace()
    local index = index_table[focused_window:id()]
    if index.space > 1 then
        self:moveWindowToSpace(index.screenid, index.space - 1)
    end
end
function PaperWM:moveWindowDownSpace()
    local index = index_table[focused_window:id()]
    self:moveWindowToSpace(index.screenid, index.space + 1)
end

---move focused window to a Mission Control space
---@param index number ID for space
---@param window Window|nil optional window to move
function PaperWM:moveWindowToSpace(screenid, space, window)
    local focused_window = window or Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end
    
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    hs.window.animationDuration = 0
    local old_index = copy(focused_index)
    if old_index.col > 1 then
        window_list[old_index.screenid][old_index.space].focusedwindow = window_list[old_index.screenid][old_index.space][old_index.col - 1][1].win:id()
    elseif old_index.col < #(window_list[old_index.screenid]) then
        window_list[old_index.screenid][old_index.space].focusedwindow = window_list[old_index.screenid][old_index.space][old_index.col + 1][1].win:id()
    else
        window_list[old_index.screenid][old_index.space].focusedwindow = nil
    end
    self:removeWindow(focused_window, true)
    self:tileSpace(hs.screen.find(old_index.screenid), old_index.space)
    self:addWindow(focused_window, screenid, space)
    local new_index = index_table[focused_window:id()]
    self:tileSpace(hs.screen.find(new_index.screenid), new_index.space)
    window_list[screenid][space].focusedwindow = focused_window:id()
    self:focusSpace(screenid, space)
    focused_window:focus()
end


---move and resize a window to the coordinates specified by the frame
---disable watchers while window is moving and re-enable after
---@param window Window window to move
---@param frame Frame coordinates to set window size and location
function PaperWM:moveWindow(window, frame)
    index = index_table[window:id()]
    
    window_list[index.screenid][index.space][index.col][index.row].frame = frame
    
    -- greater than 0.017 hs.window animation step time
    local padding <const> = 0.02

    local watcher = ui_watchers[window:id()]
    if not watcher then
        self.logger.e("window does not have ui watcher")
        return
    end

    if frame == window:frame() then
        self.logger.v("no change in window frame")
        return
    end

    watcher:stop()
    window:setFrame(frame)
    Timer.doAfter(Window.animationDuration + padding, function()
        watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    end)
end

---add or remove focused window from the floating layer and retile the space
function PaperWM:toggleFloating()
    local window = Window.focusedWindow()
    if not window then
        self.logger.d("focused window not found")
        return
    end

    local id = window:id()
    if is_floating[id] then
        is_floating[id] = nil
    else
        is_floating[id] = true
    end
    persistFloatingList()

    local space = nil
    if is_floating[id] then
        space = self:removeWindow(window, true)
    else
        space = self:addWindow(window)
    end
    if space then
        self:tileSpace(window:screen():id(), space)
    end
end

---supported window movement actions
PaperWM.actions = {
    up_space = partial(PaperWM.goUpSpace, PaperWM),
    down_space = partial(PaperWM.goDownSpace, PaperWM),
    move_up_space = partial(PaperWM.moveWindowUpSpace, PaperWM),
    move_down_space = partial(PaperWM.moveWindowDownSpace, PaperWM),
    stop_events = partial(PaperWM.stop, PaperWM),
    refresh_windows = partial(PaperWM.initWindows, PaperWM),
    toggle_floating = partial(PaperWM.toggleFloating, PaperWM),
    focus_left = partial(PaperWM.focusWindow, PaperWM, Direction.LEFT),
    focus_right = partial(PaperWM.focusWindow, PaperWM, Direction.RIGHT),
    focus_up = partial(PaperWM.focusWindow, PaperWM, Direction.UP),
    focus_down = partial(PaperWM.focusWindow, PaperWM, Direction.DOWN),
    swap_left = partial(PaperWM.swapWindows, PaperWM, Direction.LEFT),
    swap_right = partial(PaperWM.swapWindows, PaperWM, Direction.RIGHT),
    swap_up = partial(PaperWM.swapWindows, PaperWM, Direction.UP),
    swap_down = partial(PaperWM.swapWindows, PaperWM, Direction.DOWN),
    center_window = partial(PaperWM.centerWindow, PaperWM),
    full_width = partial(PaperWM.setWindowFullWidth, PaperWM),
    cycle_width = partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.ASCENDING),
    cycle_height = partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.ASCENDING),
    reverse_cycle_width = partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.DESCENDING),
    reverse_cycle_height = partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.DESCENDING),
    slurp_in = partial(PaperWM.slurpWindow, PaperWM),
    barf_out = partial(PaperWM.barfWindow, PaperWM),
    switch_space_u = partial(PaperWM.incrementSpace, PaperWM, Direction.UP),
    switch_space_d = partial(PaperWM.incrementSpace, PaperWM, Direction.DOWN),
    switch_space_1 = partial(PaperWM.switchToSpace, PaperWM, 1),
    switch_space_2 = partial(PaperWM.switchToSpace, PaperWM, 2),
    switch_space_3 = partial(PaperWM.switchToSpace, PaperWM, 3),
    switch_space_4 = partial(PaperWM.switchToSpace, PaperWM, 4),
    switch_space_5 = partial(PaperWM.switchToSpace, PaperWM, 5),
    switch_space_6 = partial(PaperWM.switchToSpace, PaperWM, 6),
    switch_space_7 = partial(PaperWM.switchToSpace, PaperWM, 7),
    switch_space_8 = partial(PaperWM.switchToSpace, PaperWM, 8),
    switch_space_9 = partial(PaperWM.switchToSpace, PaperWM, 9),
    move_window_1 = partial(PaperWM.moveWindowToSpace, PaperWM, 1),
    move_window_2 = partial(PaperWM.moveWindowToSpace, PaperWM, 2),
    move_window_3 = partial(PaperWM.moveWindowToSpace, PaperWM, 3),
    move_window_4 = partial(PaperWM.moveWindowToSpace, PaperWM, 4),
    move_window_5 = partial(PaperWM.moveWindowToSpace, PaperWM, 5),
    move_window_6 = partial(PaperWM.moveWindowToSpace, PaperWM, 6),
    move_window_7 = partial(PaperWM.moveWindowToSpace, PaperWM, 7),
    move_window_8 = partial(PaperWM.moveWindowToSpace, PaperWM, 8),
    move_window_9 = partial(PaperWM.moveWindowToSpace, PaperWM, 9)
}

---bind userdefined hotkeys to PaperWM actions
---use PaperWM.default_hotkeys for suggested defaults
---@param mapping Mapping table of actions and hotkeys
function PaperWM:bindHotkeys(mapping)
    local spec = self.actions
    hs.spoons.bindHotkeysToSpec(spec, mapping)
end

return PaperWM


-- TODO

-- Fix left and right when at end
-- DONE Change focusedwindow for the space where a window was moved out of
-- Fix alt-tab to another space
