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

local mods = { "alt", "cmd" }
local shiftmods = { "alt", "cmd", "shift" }

---@alias Mapping { [string]: (table | string)[]}
PaperWM.default_hotkeys = {
    stop_events          = { shiftmods, "q" },
    refresh_windows      = { shiftmods, "r" },
    toggle_floating      = { shiftmods, "escape" },
    focus_left           = { mods, "left" },
    focus_right          = { mods, "right" },
    focus_up             = { mods, "up" },
    focus_down           = { mods, "down" },
    move_left            = { shiftmods, "left" },
    move_right           = { shiftmods, "right" },
    move_up              = { shiftmods, "up" },
    move_down            = { shiftmods, "down" },
    center_window        = { mods, "c" },
    full_width           = { mods, "f" },
    cycle_width          = { mods, "r" },
    cycle_height         = { shiftmods, "r" },
    reverse_cycle_width  = { { "ctrl", "alt", "cmd" }, "r" },
    reverse_cycle_height = { { "ctrl", "alt", "cmd", "shift" }, "r" },
    slurp_in             = { mods, "i" },
    barf_out             = { mods, "o" },
}


-- filter for windows to manage
PaperWM.window_filter = WindowFilter.new():setOverrideFilter({
    visible = true,
    fullscreen = false,
    hasTitlebar = true,
    allowRoles = "AXStandardWindow"
})

-- default space_names
PaperWM.space_names = {1, 2, 3, 4, 5, 6, 7, 8, 9}

PaperWM.appsOpenNextTo = {}

function indexOf(array, value)
    for i, v in ipairs(array) do
        if v == value then
            return i
        end
    end
    return nil
end

-- number of pixels between windows
PaperWM.window_gap = 4

-- ratios to use when cycling widths and heights, golden ratio by default
PaperWM.window_ratios = { 0.5, 0.7, 0.9}

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
window_list = {} -- 3D array of tiles in order of [screennum].spaces[space][x][y]
                       -- also stores 
                       --     [screennum].activespace
                       --     [screennum].spaces[space].focusedwindow
                       --     [screennum].spaces[space][x][y].win
                       --     [screennum].spaces[space][x][y].frame
                       
index_table = {} -- dictionary of {screennum, space, x, y} with window id for keys
-- local ui_watchers = {} -- dictionary of uielement watchers with window id for keys
ui_watchers = {} -- dictionary of uielement watchers with window id for keys
-- local is_floating = {} -- dictionary of boolean with window id for keys
is_floating = {} -- dictionary of boolean with window id for keys
menubar = hs.menubar.new(true, "spaceindicator")
last_focused_app = "" -- stores the name of the last app with focus
local animation_duration = 0

local function updatemenu()
    local title = ""
    for i, screen in ipairs(hs.screen.allScreens()) do
        title = title .. window_list[i].activespace
        if screen == hs.screen.mainScreen() then
            local idt = index_table[hs.window.focusedWindow():id()]
            if idt.space == window_list[screen:id()].activespace then
                title = title .. "-" .. idt.col
            end
        end
        if i < #hs.screen.allScreens() then
            title = title .. ":"
        end
    end
    menubar:setTitle(title)
end

-- refresh window layout on screen change
local screen_watcher = Screen.watcher.new(function() 
    PaperWM:tileAll() 
end)

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

---move a window offscreen
---@param windowframe window to move
---@return nil
function PaperWM:stashWindow(windowframe)
    local idx = index_table[windowframe.win:id()]
    local screenframe = hs.screen.find(idx.screennum):frame()
    local frame = windowframe.win:frame()
    local frame2 = copy(frame)      -- remember its position
    frame.x = screenframe.x2 - 1
    self:moveWindow(windowframe.win, frame)
    windowframe.frame = frame2
end        

function PaperWM:hideWindow(window)
    -- if not window then return end
    local idx = index_table[window:id()]
    local screenframe = window:screen():frame()
    local frame = window:frame()
    frame.x = screenframe.x2 - 1
    self:moveWindow(window, frame)
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
---@param screennum Screen
---@param space Space
---@param col number
---@return Window[]
local function getColumn(screennum, space, col) 
    return (window_list[screennum].spaces[space] or {})[col] 
end

---get a window in a row, in a column, in a space from the window_list
---@param screennum Screen
---@param space Space
---@param col number
---@param row number
---@return Window
local function getWindow(screennum, space, col, row)
    local col = getColumn(screennum, space, col) or {}
    if col[row] then
        return col[row].win
    else
        return nil
    end
end

local function getWindowFrame(screennum, space, col, row)
    return (getColumn(screennum, space, col) or {})[row]
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
local function updateIndexTable(screennum, space, column)
    local columns = window_list[screennum].spaces[space] or {}
    for col = column, #columns do
        for row, windowf in ipairs(getColumn(screennum, space, col)) do
            index_table[windowf.win:id()] = { screennum = screennum, space = space, col = col, row = row }
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

focused_window = nil ---@type Window|nil
local pending_window = nil ---@type Window|nil

---callback for window events
---@param window Window
---@param event string name of the event
---@param self PaperWM
local function windowEventHandler(window, event, self)
    if not window or not window.id then
        return
    end
    self.logger.df("%s for [%s] id: %d", event, window, window and window:id() or -1)
    -- print(hs.inspect(window))

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
        if window:isFullScreen() then    -- NEEDED?
            return
        end
        if pending_window and window == pending_window then
            Timer.doAfter(animation_duration,
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
        local focused_app = window:application():title()
        Timer.doAfter(2,
            -- kludgy way to check to make sure the last_focused_app wasn't triggered automatically
            function()
                if focused_window and focused_window:application():title() == focused_app then
                    last_focused_app = focused_app
                end
            end)
        if idx then
            -- hs.alert.show(idx.col)
            updatemenu()
            local prior_focusedwindow = window_list[idx.screennum].spaces[idx.space].focusedwindow
            if prior_focusedwindow and prior_focusedwindow ~= focused_window:id() then
                window_list[idx.screennum].spaces[idx.space].focusedwindow = focused_window:id()
                space = idx.space     -- forces retiling
            end
            space = idx.space     -- forces retiling
            if idx_prior then
                if idx_prior.screennum ~= idx.screennum or
                   idx_prior.space ~= idx.space then
                    self:focusSpace(idx.screennum, idx.space, window)
                end
            end
        else
            space = self:addWindow(window)
        end
    elseif event == "windowVisible" or event == "windowUnfullscreened" then
        if window:isFullScreen() then    -- NEEDED?
            return
        end
        space = self:addWindow(window)
        if pending_window and window == pending_window then
            pending_window = nil -- tried to add window for the second time
        elseif not space then
            pending_window = window
            Timer.doAfter(animation_duration,
                function()
                    windowEventHandler(window, event, self)
                end)
            return
        end
    elseif event == "windowNotVisible" then
        space = self:removeWindow(window)
    elseif event == "windowFullscreened" then
        space = self:removeWindow(window, true) -- don't focus new window if fullscreened
        return
    elseif event == "AXWindowMoved" or event == "AXWindowResized" then
        -- space = Spaces.windowSpaces(window)[1]
    elseif event == "windowDestroyed" and idx then
        window_list[idx.screennum].spaces[idx.space].focusedwindow = nil
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
function PaperWM:focusSpace(screennum, space, window)
    if not screennum then
        screennum = PaperWM:findScreenIDWithSpace(space)
    end
    if window_list[screennum].activespace == space then
        return
    end
    window_list.activescreennum = screennum
    local screen_frame = hs.screen.find(screennum):frame()
    if window_list[screennum].spaces[window_list[screennum].activespace] then
        for _, cols in ipairs(window_list[screennum].spaces[window_list[screennum].activespace]) do
            for _, wf in ipairs(cols) do
                if isvisible(wf.win:frame(), screen_frame) then
                    PaperWM:stashWindow(wf)
                end
            end
        end
    end
    window_list[screennum].activespace = space
    for i, cols in ipairs(window_list[screennum].spaces[window_list[screennum].activespace]) do
        for _, wf in ipairs(cols) do
            if isvisible(wf.frame, screen_frame) then
                PaperWM:restoreWindow(wf)
            end
        end
    end
    if window then
        focused_window = window
        window:focus()
    elseif window_list[screennum].spaces[space].focusedwindow and 
           #window_list[screennum].spaces[space] > 0 and 
           hs.window.find(window_list[screennum].spaces[space].focusedwindow) and
           hs.window.find(window_list[screennum].spaces[space].focusedwindow).focus then
        hs.window.find(window_list[screennum].spaces[space].focusedwindow):focus()
    else
        local w = getFirstVisibleWindow(window_list[screennum].spaces[space], hs.screen.find(screennum))
        if w then 
            focused_window = w
            w:focus()
        end
    end
    -- PaperWM:tileSpace(hs.screen.find(screennum), space)
    updatemenu()
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

    animation_duration = 0
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
    self.logger.df("Tiling" .. space)

    -- if focused window is in space, tile from that
    local focused_window = Window.focusedWindow()
    local anchor_window = nil
    if focused_window and not is_floating[focused_window:id()] and 
       window_list[screen:id()].activespace == space and 
       window_list[screen:id()].spaces[space].focusedwindow then
        anchor_window = hs.window.find(window_list[screen:id()].spaces[space].focusedwindow)
    end
    if not anchor_window then
        anchor_window = getFirstVisibleWindow(window_list[screen:id()].spaces[space], screen)
    end

    if not anchor_window then
        return      -- no windows in this space
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
    for col = anchor_index.col + 1, #(window_list[screen:id()].spaces[space] or {}) do
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
    focused_window = nil
    pending_window = nil
    index_table = {}
    -- find screens and windows in screens
    -- assign these to the first space on each screen
    window_list.screens = {}
    for screennum, screen in pairs(hs.screen.allScreens()) do
        local screenid = screen:id()
        window_list[screennum] = {}
        window_list[screennum].space_names = {"S" .. screennum}
        window_list[screennum].spaces = {}
        window_list.screens[screennum] = screenid
        if screenid == hs.screen.primaryScreen():id() then
            window_list.activescreennum = screennum
            for _, space in ipairs(PaperWM.space_names) do
                table.insert(window_list[screennum].space_names, space)
                window_list[screennum].spaces[space] = {}
            end
            table.insert(window_list[screennum].space_names, "*")
            window_list[screennum].spaces["*"] = {}
        end
        window_list[screennum].activespace = window_list[screennum].space_names[1]
        for _, w in pairs(hs.window.filter.new(true):setScreens(screenid):getWindows()) do
            local space = self:addWindow(w)
        end
        local screen_frame = screen:frame()
        for space, cols in pairs(window_list[screennum].spaces) do
            self:tileSpace(screen, space)
            for i, col in ipairs(cols) do
                for _, wf in ipairs(col) do
                    if isvisible(wf.win:frame(), screen_frame) then
                        PaperWM:stashWindow(wf)
                    end
                end
            end
        end 
    end 
    self:focusSpace(hs.screen.primaryScreen():id(), "S1")
    focused_window = Window.focusedWindow()
    updatemenu()
end

---add a new window to be tracked and automatically tiled
---@param add_window Window new window to be added
---@return Space|nil space that contains new window
function PaperWM:addWindow(add_window, screennum, space)
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
    local window_stay = nil
    if not screennum and not space then
        local defaultspace = PaperWM.default_app_space[add_window:application():title()]  
        local same_app = last_focused_app == add_window:application():title()
        if defaultspace and not same_app then    -- open next to the original
            screennum = PaperWM:findScreenNumWithSpace(defaultspace)
            space = defaultspace
        end
        if same_app and focused_window and indexOf(PaperWM.apps_open_in_background, focused_window:application():title()) then
            window_stay = copy(focused_window)
        end
    end
    screennum = screennum or indexOf(add_window.screens, add_window:screen():id())
    space = space or window_list[screennum].activespace
    if not space then
        self.logger.e("add window does not have a space")
        return
    end
    if not window_list[screennum].spaces[space] then window_list[screennum].spaces[space] = {} end

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
        for col, windowfs in ipairs(window_list[screennum].spaces[space]) do
            if x < windowfs[1].win:frame().center.x then
                add_column = col
                break
            end
        end
    end
    local add_windowf = {win = add_window, frame = add_window:frame()}
    -- add window
    table.insert(window_list[screennum].spaces[space], add_column, { add_windowf })

    -- update index table
    updateIndexTable(screennum, space, add_column)

    -- subscribe to window moved events
    local watcher = add_window:newWatcher(
        function(window, event, _, self)
            windowEventHandler(window, event, self)
        end, self)
    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    ui_watchers[add_window:id()] = watcher
    if window_stay then
        window_stay:focus()
    else 
        window_list[screennum].spaces[space].focusedwindow = add_window:id()
        -- add_window:focus()
    end
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
    table.remove(window_list[remove_index.screennum].spaces[remove_index.space][remove_index.col],
        remove_index.row)
    if #window_list[remove_index.screennum].spaces[remove_index.space][remove_index.col] == 0 then
        table.remove(window_list[remove_index.screennum].spaces[remove_index.space], remove_index.col)
    end

    -- remove watcher
    ui_watchers[remove_window:id()]:stop()
    ui_watchers[remove_window:id()] = nil

    -- update index table
    index_table[remove_window:id()] = nil
    updateIndexTable(remove_index.screennum, remove_index.space, remove_index.col)

    -- remove if space is empty
    -- if #window_list[remove_index.screennum].spaces[remove_index.space] == 0 then
    --     window_list[remove_index.screennum].spaces[remove_index.space] = nil
    -- end

    return remove_index.space -- return space for removed window
end

---move focus to a new window next to the currently focused window
---@param direction Direction use either Direction UP, DOWN, LEFT, or RIGHT
---@param focused_index Index index of focused window within the window_list
function PaperWM:focusWindow(direction, focused_index)
    if not focused_index then
        -- get current focused window
        local focused_window = Window.focusedWindow()
        -- focused_window = focused_window or Window.focusedWindow()
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
            new_focused_window = getWindow(focused_index.screennum, focused_index.space,
                focused_index.col + direction, row)
            if new_focused_window then break end
        end
    elseif direction == Direction.UP and focused_index.row == 1 then
        PaperWM:goUpSpace()
    elseif direction == Direction.DOWN and 
           focused_index.row == #window_list[focused_index.screennum].spaces[focused_index.space][focused_index.col] then
        PaperWM:goDownSpace()
    elseif direction == Direction.UP or direction == Direction.DOWN then
        new_focused_window = getWindow(focused_index.screennum, focused_index.space, focused_index.col,
            focused_index.row + (direction // 2))
        
    end

    if not new_focused_window then
        -- self.logger.d("new focused window not found")
        return
    end

    -- focus new window, windowFocused event will be emited immediately
    if new_focused_window:isMinimized() then
        new_focused_window:unminimize()
    end
    new_focused_window:focus()
    local idx = index_table[new_focused_window:id()]
    window_list[idx.screennum].spaces[idx.space].focusedwindow = new_focused_window:id()
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

    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- get target windows
        local target_index = { col = focused_index.col + direction }
        local target_column = getColumn(focused_index.screennum, focused_index.space, target_index.col)
        if not target_column then
            self.logger.d("target column not found")
            return
        end

        -- swap place in window list
        local focused_column = getColumn(focused_index.screennum, focused_index.space, focused_index.col)
        window_list[focused_index.screennum].spaces[focused_index.space][target_index.col] = focused_column
        window_list[focused_index.screennum].spaces[focused_index.space][focused_index.col] = target_column

        -- update index table
        for row, windowf in ipairs(target_column) do
            index_table[windowf.win:id()] = {
                screennum = focused_index.screennum,
                space = focused_index.space,
                col = focused_index.col,
                row = row
            }
        end
        for row, windowf in ipairs(focused_column) do
            index_table[windowf.win:id()] = {
                screennum = focused_index.screennum,
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
            screennum = focused_index.screennum,
            space = focused_index.space,
            col = focused_index.col,
            row = focused_index.row + (direction // 2)
        }
        if direction == Direction.UP and focused_index.row == 1 then
            PaperWM:moveWindowUpSpace()
        elseif direction == Direction.DOWN and 
               focused_index.row == #window_list[focused_index.screennum].spaces[focused_index.space][focused_index.col] then
            PaperWM:moveWindowDownSpace()
        end
        local target_windowf = getWindowFrame(target_index.screennum, target_index.space, target_index.col,
            target_index.row)
        if not target_windowf then
            self.logger.d("target window not found")
            return
        end
        local focused_windowf = getWindowFrame(focused_index.screennum, focused_index.space, focused_index.col,
            focused_index.row)
        if not focused_windowf then
            self.logger.d("focused window not found")
            return
        end

        -- swap places in window list
        window_list[target_index.screennum].spaces[target_index.space][target_index.col][target_index.row] =
            focused_windowf
        window_list[focused_index.screennum].spaces[focused_index.space][focused_index.col][focused_index.row] =
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

    -- update layout
    self:tileSpace(target_windowf.win:screen(), focused_index.space)
end

---move the focused window to the center of the screen, horizontally
---don't resize the window or change it's vertical position
function PaperWM:centerWindow()
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
end

---set the focused window to the width of the screen
---don't change the height
function PaperWM:setWindowFullWidth()
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
    animation_duration = 0.3
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    self:tileSpace(focused_window:screen(), index_table[focused_window:id()].space)
end

---resize the width or height of the window, keeping the other dimension the
---same. cycles through the ratios specified in PaperWM.window_ratios
---@param direction Direction use Direction.WIDTH or Direction.HEIGHT
---@param cycle_direction Direction use Direction.ASCENDING or DESCENDING
function PaperWM:cycleWindowSize(direction, cycle_direction)
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
        animation_duration = 0.3
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
    local column = getColumn(focused_index.screennum, focused_index.space, focused_index.col - 1)
    if not column then
        self.logger.d("column not found")
        return
    end

    -- remove window
    table.remove(window_list[focused_index.screennum].spaces[focused_index.space][focused_index.col],
        focused_index.row)
    if #window_list[focused_index.screennum].spaces[focused_index.space][focused_index.col] == 0 then
        table.remove(window_list[focused_index.screennum].spaces[focused_index.space], focused_index.col)
    end

    -- append to end of column
    table.insert(column, {win = focused_window, frame = focused_window:frame()})

    -- update index table
    local num_windows = #column
    index_table[focused_window:id()] = {
        screennum = focused_index.screennum,
        space = focused_index.space,
        col = focused_index.col - 1,
        row = num_windows
    }
    updateIndexTable(focused_index.screennum, focused_index.space, focused_index.col)

    -- adjust window frames
    local canvas = getCanvas(focused_window:screen())
    local bounds = {
        x = column[1].win:frame().x,
        x2 = nil,
        y = canvas.y,
        y2 = canvas.y2
    }
    local h = math.max(0, canvas.h - ((num_windows - 1) * self.window_gap)) //
        num_windows
    self:tileColumn(column, bounds, h)

    -- update layout
    self:tileSpace(focused_window:screen(), focused_index.space)
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
    local column = getColumn(focused_index.screennum, focused_index.space, focused_index.col)
    if #column == 1 then
        self.logger.d("only window in column")
        return
    end

    -- remove window and insert in new column
    table.remove(column, focused_index.row)
    table.insert(window_list[focused_index.screennum].spaces[focused_index.space], focused_index.col + 1,
        {{win = focused_window, frame = focused_window:frame()}})

    -- update index table
    updateIndexTable(focused_index.screennum, focused_index.space, focused_index.col)

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
    self:tileSpace(focused_window:screen(), focused_index.space)
end

---switch to a Mission Control space to the left or right of current space
---@param direction Direction use Direction.UP or Direction.DOWN
function PaperWM:incrementSpace(direction)
    local index = index_table[focused_window:id()]
    local space = window_list[index.screennum].activespace
    local space_names = window_list[index.screennum].space_names
    local tagidx = indexOf(space_names, space)
    if direction == Direction.UP and tagidx > 1 then
        self:focusSpace(index.screennum, space_names[tagidx - 1])
    end
    if direction == Direction.DOWN and tagidx < #(window_list[index.screennum]) then
        self:focusSpace(index.screennum, space_names[tagidx + 1])
    end
end

function PaperWM:goUpSpace()
    local index = index_table[focused_window:id()]
    local space = window_list[index.screennum].activespace
    local space_names = window_list[index.screennum].space_names
    local tagidx = indexOf(space_names, space)
    if tagidx > 1 then
        self:focusSpace(index.screennum, space_names[tagidx - 1])
    end
end
function PaperWM:goDownSpace()
    local index = index_table[focused_window:id()]
    local space = window_list[index.screennum].activespace
    local space_names = window_list[index.screennum].space_names
    local tagidx = indexOf(space_names, space)
    if tagidx < #space_names then
        self:focusSpace(index.screennum, space_names[tagidx + 1])
    end
end
function PaperWM:moveWindowUpSpace()
    local index = index_table[focused_window:id()]
    local space = window_list[index.screennum].activespace
    local space_names = window_list[index.screennum].space_names
    local tagidx = indexOf(space_names, index.space)
    if tagidx > 1 then
        self:moveWindowToSpace(index.screennum, space_names[tagidx - 1])
    end
end
function PaperWM:moveWindowDownSpace()
    local index = index_table[focused_window:id()]
    local space = window_list[index.screennum].activespace
    local space_names = window_list[index.screennum].space_names
    local tagidx = indexOf(space_names, index.space)
    if tagidx < #space_names then
        self:moveWindowToSpace(index.screennum, space_names[tagidx + 1])
    end
end

---move focused window to a Mission Control space
---@param index number ID for space
---@param window Window|nil optional window to move
function PaperWM:moveWindowToSpace(screennum, space, window, stay)
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

    local old_index = copy(focused_index)
    if old_index.col > 1 then
        window_list[old_index.screennum].spaces[old_index.space].focusedwindow = window_list[old_index.screennum].spaces[old_index.space][old_index.col - 1][1].win:id()
    elseif old_index.col < #(window_list[old_index.screennum].spaces[old_index.space]) then
        window_list[old_index.screennum].spaces[old_index.space].focusedwindow = window_list[old_index.screennum].spaces[old_index.space][old_index.col + 1][1].win:id()
    else
        window_list[old_index.screennum].spaces[old_index.space].focusedwindow = nil
    end
    self:hideWindow(focused_window)
    self:removeWindow(focused_window, true)
    self:tileSpace(hs.screen.find(old_index.screennum), old_index.space)
    self:addWindow(focused_window, screennum, space)
    local new_index = index_table[focused_window:id()]
    window_list[screennum].spaces[space].focusedwindow = focused_window:id()
    if stay then
        self:focusSpace(screennum, old_index.space)
    else
        self:tileSpace(hs.screen.find(new_index.screennum), new_index.space)
        self:focusSpace(screennum, space, focused_window)
    end
end

function PaperWM:moveWindowToScratchSpace()
    PaperWM:moveWindowToSpace(hs.screen.primaryScreen():id(), "*", focused_window, true)
end

function PaperWM:moveWindowsFromScratchSpace()
    local screennum = window_list.activescreennum
    local space = window_list[screennum].activespace
    for i, cols in ipairs(copy(window_list[hs.screen.primaryScreen():id()].spaces["*"])) do
        for _, wf in ipairs(cols) do
            PaperWM:moveWindowToSpace(screennum, space, wf.win)
        end
    end
end

function PaperWM:moveWindowsRightToScratchSpace()
    local screennum = window_list.activescreennum
    local space = window_list[screennum].activespace
    local focused_window = Window.focusedWindow()
    if not focused_window then
        return
    end
    local focused_col = index_table[focused_window:id()].col
    for col, cols in ipairs(copy(window_list[screennum].spaces[space])) do
        for row, wf in ipairs(cols) do
            if col >= focused_col then
                PaperWM:moveWindowToSpace(hs.screen.primaryScreen():id(), "*", wf.win, true)
            end
        end
    end
end

function PaperWM:focusScratchSpace()
    PaperWM:focusSpace(hs.screen.primaryScreen():id(), "*")
end

function PaperWM:moveWindowTo(space, window, stay)
    local screennum = PaperWM:findScreenIDWithSpace(space)
    if screennum then
        PaperWM:moveWindowToSpace(screennum, space, window, stay)
    end
end

function PaperWM:closeWindow()
    local win = Window.focusedWindow()
    if win then
        local app = win:application()
        win:close()
        if #app:allWindows() == 0 then
            app:kill()
        end
    end
end

function PaperWM:closeWindowsInSpace()
    local screennum = window_list.activescreennum
    local space = window_list[screennum].activespace
    for col, cols in ipairs(copy(window_list[screennum].spaces[space])) do
        for row, wf in ipairs(cols) do
            PaperWM:closeWindow(wf.win)
        end
    end
end

function PaperWM:tileAll()
    for _, screen in pairs(hs.screen.allScreens()) do
        local screennum = screen:id()
        for _, space in ipairs(window_list[screennum].space_names) do
            PaperWM:tileSpace(screen, space)
            for col, cols in ipairs(window_list[screennum].spaces[space]) do
                for row, wf in ipairs(cols) do
                    PaperWM:hideWindow(wf.win)
                end
            end
        end
    end
end

function PaperWM:findScreenNumWithSpace(space)
    -- Look for the display with the space
    for screennum, spaces in ipairs(window_list) do
        if indexOf(spaces.space_names, space) then   -- check for space in space_names
            return screennum
        end
    end
end


---move and resize a window to the coordinates specified by the frame
---disable watchers while window is moving and re-enable after
---@param window Window window to move
---@param frame Frame coordinates to set window size and location
function PaperWM:moveWindow(window, frame)
    index = index_table[window:id()]
    
    window_list[index.screennunum.spaces[index.space][index.col][index.row].frame = frame
    
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
    local ax_app = hs.axuielement.applicationElement(window:application())
    local was_enhanced = ax_app.AXEnhancedUserInterface
    ax_app.AXEnhancedUserInterface = false
    if frame.w == window:frame().w and frame.h == window:frame().h then
        window:move(frame, animation_duration)
    else
        window:setFrame(frame, animation_duration)
    end
    if was_enhanced then
        ax_app.AXEnhancedUserInterface = true
    end
    Timer.doAfter(animation_duration + padding, function()
        watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    end)
    animation_duration = 0
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
        self:tileSpace(window:screen(), space)
    end
end

function PaperWM:chooseWindow()
    local windows = hs.window.visibleWindows()
    local chooserData = {}

    local chooser = hs.chooser.new(function(choice)
        if not choice then return end
        local windows = hs.window.filter.new():getWindows()
        for _, w in ipairs(windows) do
            if w:id() == choice.uuid then
                w:focus()
                return
            end
        end
        -- local window = hs.window.get(choice.uuid)  -- doesn't work for fullscreen windows
        -- print(window)
        -- if window then
        --     window:focus()
        -- end
    end)

    local screenFrame = hs.screen.mainScreen():frame()
    local rowHeight = 55  
    local maxRows = math.floor(screenFrame.h / rowHeight)

    chooser:searchSubText(false):rows(maxRows)

    local function buildChoices(query)
        local q = (query or ""):lower()
        local results = {}

        for screennum, wl in ipairs(window_list) do
            for _, tag in ipairs(wl.space_names) do
                local cols = wl.spaces[tag]
                for _, col in ipairs(cols) do
                    for _, wf in ipairs(col) do
                        local win = wf.win
                        local app = win:application()
                        local icon = hs.image.imageFromAppBundle(app:bundleID())
                        local title = win:title() or ""
                        local appName = app and app:name() or ""
                        if q == "" or title:lower():find(q, 1, true) or appName:lower():find(q, 1, true) or tag:lower():find(q, 1, true) then
                            table.insert(results, {
                                text = title,
                                subText = tag,
                                image = icon,
                                uuid = win:id(),
                            })
                        end
                    end
                end
            end
        end
        for _, win in ipairs(hs.window.filter.new():setOverrideFilter{fullscreen=true}:getWindows()) do
            local app = win:application()
            local icon = hs.image.imageFromAppBundle(app:bundleID())
            local title = win:title() or ""
            local appName = app and app:name() or ""
            if q == "" or title:lower():find(q, 1, true) or appName:lower():find(q, 1, true) or tag:lower():find(q, 1, true) then
                table.insert(results, {
                    text = title,
                    subText = "Fullscreen",
                    image = icon,
                    uuid = win:id(),
                })
            end
        end
        return results
    end

    chooser:choices(buildChoices(""))

    chooser:queryChangedCallback(function(query)
        chooser:choices(buildChoices(query))
        -- chooser:refreshChoices()
    end)

    chooser:show()
end

---supported window movement actions
PaperWM.actions = {
    move_to_scratch_space = partial(PaperWM.moveWindowToScratchSpace, PaperWM),
    move_from_scratch_space = partial(PaperWM.moveWindowsFromScratchSpace, PaperWM),
    focus_scratch_space = partial(PaperWM.focusScratchSpace, PaperWM),
    move_right_to_scratch_space = partial(PaperWM.moveWindowsRightToScratchSpace, PaperWM),
    stop_events = partial(PaperWM.stop, PaperWM),
    refresh_windows = partial(PaperWM.initWindows, PaperWM),
    toggle_floating = partial(PaperWM.toggleFloating, PaperWM),
    focus_left = partial(PaperWM.focusWindow, PaperWM, Direction.LEFT),
    focus_right = partial(PaperWM.focusWindow, PaperWM, Direction.RIGHT),
    focus_up = partial(PaperWM.focusWindow, PaperWM, Direction.UP),
    focus_down = partial(PaperWM.focusWindow, PaperWM, Direction.DOWN),
    up_space = partial(PaperWM.goUpSpace, PaperWM),
    down_space = partial(PaperWM.goDownSpace, PaperWM),
    move_up_space = partial(PaperWM.moveWindowUpSpace, PaperWM),
    move_down_space = partial(PaperWM.moveWindowDownSpace, PaperWM),
    close_window = partial(PaperWM.closeWindow, PaperWM),
    close_windows_in_space = partial(PaperWM.closeWindowsInSpace, PaperWM),
    focus_space_0 = partial(PaperWM.focusSpace, PaperWM, hs.screen.mainScreen():id(), "S" .. hs.screen.mainScreen():id()),
    focus_space_1 = partial(PaperWM.focusSpace, PaperWM, nil, 1),
    focus_space_2 = partial(PaperWM.focusSpace, PaperWM, nil, 2),
    focus_space_3 = partial(PaperWM.focusSpace, PaperWM, nil, 3),
    focus_space_4 = partial(PaperWM.focusSpace, PaperWM, nil, 4),
    focus_space_5 = partial(PaperWM.focusSpace, PaperWM, nil, 5),
    focus_space_6 = partial(PaperWM.focusSpace, PaperWM, nil, 6),
    focus_space_7 = partial(PaperWM.focusSpace, PaperWM, nil, 7),
    focus_space_8 = partial(PaperWM.focusSpace, PaperWM, nil, 8),
    focus_space_9 = partial(PaperWM.focusSpace, PaperWM, nil, 9),
    move_left = partial(PaperWM.swapWindows, PaperWM, Direction.LEFT),
    move_right = partial(PaperWM.swapWindows, PaperWM, Direction.RIGHT),
    move_up = partial(PaperWM.swapWindows, PaperWM, Direction.UP),
    move_down = partial(PaperWM.swapWindows, PaperWM, Direction.DOWN),
    center_window = partial(PaperWM.centerWindow, PaperWM),
    full_width = partial(PaperWM.setWindowFullWidth, PaperWM),
    cycle_width = partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.ASCENDING),
    cycle_height = partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.ASCENDING),
    reverse_cycle_width = partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.DESCENDING),
    reverse_cycle_height = partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.DESCENDING),
    slurp_in = partial(PaperWM.slurpWindow, PaperWM),
    barf_out = partial(PaperWM.barfWindow, PaperWM),
    choose_window = partial(PaperWM.chooseWindow, PaperWM),
    -- switch_space_u = partial(PaperWM.incrementSpace, PaperWM, Direction.UP),
    -- switch_space_d = partial(PaperWM.incrementSpace, PaperWM, Direction.DOWN),
}

---bind userdefined hotkeys to PaperWM actions
---use PaperWM.default_hotkeys for suggested defaults
---@param mapping Mapping table of actions and hotkeys
function PaperWM:bindHotkeys(mapping)
    local spec = self.actions
    hs.spoons.bindHotkeysToSpec(spec, mapping)
end

return PaperWM

