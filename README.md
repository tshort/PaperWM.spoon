# PaperWM.spoon

## Fork

The main purpose of this fork is to support virtual spaces like [Aerospace](https://github.com/nikitabobko/AeroSpace). 

Spaces are arranged vertically. All spaces are named. You can set up your own as follows:

```lua
PaperWM.space_names = {"comms", "web", "util", "code", 1, 2, 3, 4, 5, 6, 7, 8, 9}
```

The last space is a scratch space called `*`, mainly used for moving around windows.

Several commands are provided to switch spaces, including
`focus_space_0`, `focus_space_1`, `focus_space_2`, `focus_space_3`, `focus_space_4`, `focus_space_5`, `focus_space_6`, `focus_space_7`, `focus_space_8`,  and`focus_space_9`.
Custom switching commands can be added as follows:

```lua
PaperWM.actions["focus_space_comms"] = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, nil, "comms")
```

You can define defaults for where apps open in spaces using the `default_app_space` object. Each key is the application name, and the value is the name of the space. The `apps_open_in_background` specifies apps where you want new windows to open in the "background" (right next to the original). The original window maintains focus. This is handy for browsers where you often want to open pages in the background. Here are examples of both.

```lua
PaperWM.default_app_space = {
    ["Microsoft Outlook"] = "comms", Slack = "comms", 
    Finder = "util", Ghostty = "util", Terminal = "util", 
    Firefox = "web", Safari = "web", ["Google Chrome"] = "web", qutebrowser = "web",
    Code = "code", 
}
PaperWM.apps_open_in_background = {
    "Firefox", "Safari", "Google Chrome"
}
```

Here are new or changed commands:

- `move_to_scratch_space`--Move the current window to the scratch space. The scratch space (labeled "*") is the last space on the primary screen. Typically bound to `mod-Y` (yank, and `mod` is one or more modifiers like `alt` or `alt-cmd`).
- `move_from_scratch_space`--Move all windows from the scratch space to the current space. The scratch space makes it easy to move windows around. Yank multiple windows, switch to a new space then paste. Typically bound to `mod-P` (paste).
- `focus_scratch_space`--Switch to the scratch space.
- `move_right_to_scratch_space`--Move the current window and all windows to the right to the scratch space. 
- `focus_up`/`focus_down`--These now change focus up and down a space if at the top/bottom of a column.
- `swap_*`--These were renamed to `move_*`. These now move windows up and down a space if at the top/bottom of a column. 
- `close_window`--The same as cmd-W, except if it's the last window, it also closes the application.
- `close_windows_in_space`--Close all windows in the space.
- `choose_window`--This is a simple window selector that shows the available windows ordered by space. It's good enough to reduce the need for something like AltTab.

Right now, there are several bugs:

- Sometimes everything blitzes out, and spaces keep hanging, making everything flicker. Sometimes switching spaces helps. Going to sleep, and coming back out can stop it.
- Sometimes windows get stuck onscreen until that window's space gets retiled.
- When yanking windows, sometimes the focus goes to a hidden window.

It would also be nice to allow windows to be in multiple spaces, but that's a big code change and would require removing or changing `index_table`.

## Original PaperWM.spoon info

Many of the original [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) docs and issues are still appropriate.

## Installation

1. Clone to Hammerspoon Spoons directory: `git clone https://github.com/tshort/PaperWM.spoon ~/.hammerspoon/Spoons/PaperWM.spoon`.

2. Open `System Preferences` -> `Mission Control`. Uncheck "Displays have separate
Spaces".

## Usage

Add something like the following to your `~/.hammerspoon/init.lua`. Edit as needed based on preferences for keyboard shortcuts and use of spaces.

```lua
PaperWM = hs.loadSpoon("PaperWM")
local mods = {"alt"}
local shiftmods = {"shift", "alt"}
PaperWM.actions["focus_space_comms"] = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, nil, "comms")
PaperWM.actions["focus_space_web"]   = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, nil, "web")
PaperWM.actions["focus_space_util"]  = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, nil, "util")
PaperWM.actions["focus_space_code"]  = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, nil, "code")
PaperWM.actions["focus_space_s2"]  = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, nil, "S2")
PaperWM:bindHotkeys({

    -- switch windows 
    focus_left  = {mods, "left"},
    focus_right = {mods, "right"},
    focus_up    = {mods, "up"},
    focus_down  = {mods, "down"},

    -- scratch space
    move_to_scratch_space = {mods, "y"},
    move_right_to_scratch_space = {shiftmods, "y"}, 
    move_from_scratch_space = {mods, "p"},
    focus_scratch_space = {mods, "e"},

    -- move windows around
    move_left  = {shiftmods, "left"},
    move_right = {shiftmods, "right"},
    move_up    = {shiftmods, "up"},
    move_down  = {shiftmods, "down"},

    -- alternative: swap entire columns, rather than
    -- individual windows (to be used instead of
    -- swap_left / swap_right bindings)
    -- swap_column_left = {shiftmods, "left"},
    -- swap_column_right = {shiftmods, "right"},

    -- position and resize focused window
    refresh_windows      = {mods, "r"},
    cycle_width          = {mods, "c"},
    full_width           = {shiftmods, "c"},
    -- reverse_cycle_width  = {{"ctrl", "alt"}, "r"},
    -- cycle_height         = {shiftmods, "r"},
    -- reverse_cycle_height = {{"ctrl", "alt", "shift"}, "r"},

    -- increase/decrease width
    -- increase_width = {{"ctrl", "alt", "shift"}, "l"},
    -- decrease_width = {{"ctrl", "alt", "shift"}, "h"},

    -- move focused window into / out of a column
    slurp_in = {mods, "i"},
    barf_out = {mods, "o"},

    -- move the focused window into / out of the tiling layer
    toggle_floating = {shiftmods, "escape"},

    -- switch to a new Mission Control space
    focus_space_comms = {mods, "a"},
    focus_space_web   = {mods, "s"},
    focus_space_util  = {mods, "d"},
    focus_space_code  = {mods, "f"},
    focus_space_0 = {mods, "0"},
    focus_space_1 = {mods, "1"},
    focus_space_2 = {mods, "2"},
    focus_space_3 = {mods, "3"},
    focus_space_4 = {mods, "4"},
    focus_space_5 = {mods, "5"},
    focus_space_6 = {mods, "6"},
    focus_space_7 = {mods, "7"},
    focus_space_8 = {mods, "8"},
    focus_space_9 = {mods, "9"},
    focus_space_s2 = {mods, "-"},
    -- closing windows
    close_window = {mods, "w"},
    close_windows_in_space = {shiftmods, "w"},
    -- window chooser
    choose_window = {mods, "z"},
})

hs.hotkey.bind(mods, "h", PaperWM.actions.focus_left)
hs.hotkey.bind(mods, "j", PaperWM.actions.focus_down)
hs.hotkey.bind(mods, "k", PaperWM.actions.focus_up)
hs.hotkey.bind(mods, "l", PaperWM.actions.focus_right)

hs.hotkey.bind(shiftmods, "h", PaperWM.actions.move_left)
hs.hotkey.bind(shiftmods, "j", PaperWM.actions.move_down)
hs.hotkey.bind(shiftmods, "k", PaperWM.actions.move_up)
hs.hotkey.bind(shiftmods, "l", PaperWM.actions.move_right)
PaperWM.space_names = {"comms", "web", "util", "code", 1, 2, 3, 4, 5, 6, 7, 8, 9}
PaperWM.default_app_space = {
    ["Microsoft Outlook"] = "comms", Slack = "comms", 
    Finder = "util", Ghostty = "util", Terminal = "util", 
    Firefox = "web", Safari = "web", ["Google Chrome"] = "web", qutebrowser = "web",
    Code = "code", 
}
PaperWM.apps_open_in_background = {
    "Firefox", "Safari", "Google Chrome"
}
PaperWM:start()
```


`PaperWM:start()` will begin automatically tiling new and existing windows. `PaperWM:stop()` will
release control over windows.

Set `PaperWM.window_gap` to the number of pixels to space between windows and
the top and bottom screen edges.

Configure one or many `PaperWM.window_filter:rejectApp("appName")` to ignore specific applications. For example:

```lua
PaperWM.window_filter:rejectApp("iStat Menus Status")
PaperWM.window_filter:rejectApp("Finder")
PaperWM:start() -- restart for new window filter to take effect
```

Set `PaperWM.window_ratios` to the ratios to cycle window widths and heights
through. For example:

```lua
PaperWM.window_ratios = { 0.23607, 0.38195, 0.61804 }
```

## Limitations

MacOS does not allow a window to be moved fully off-screen. Windows that would
be tiled off-screen are placed in a margin on the left and right edge of the
screen. They are still visible and clickable.

It's difficult to detect when a window is dragged from one space or screen to
another. Use the yank/paste commands to move windows between spaces and
screens.

Arrange screens vertically to prevent windows from bleeding into other screens.

<img width="780" alt="Screen Shot 2022-01-07 at 14 18 27" src="https://user-images.githubusercontent.com/900731/148595785-546f9086-9add-4731-8477-233b202378f4.png">

## Add-ons

The following Spoons compliment PaperWM.spoon nicely.

- [Swipe.spoon](https://github.com/mogenson/Swipe.spoon) Perform actions when trackpad swipe gestures are recognized. Here's an example config to change PaperWM.spoon focused window:
```lua
-- focus adjacent window with 3 finger swipe
local current_id, threshold
Swipe = hs.loadSpoon("Swipe")
Swipe:start(3, function(direction, distance, id)
    if id == current_id then
        if distance > threshold then
            threshold = math.huge -- trigger once per swipe

            -- use "natural" scrolling
            if direction == "left" then
                PaperWM.actions.focus_right()
            elseif direction == "right" then
                PaperWM.actions.focus_left()
            elseif direction == "up" then
                PaperWM.actions.focus_down()
            elseif direction == "down" then
                PaperWM.actions.focus_up()
            end
        end
    else
        current_id = id
        threshold = 0.2 -- swipe distance > 20% of trackpad size
    end
end)
```

## Browsers that work well with scrolling windows

The PaperWM style works well with browsing where windows replace the use of tabs. Here's a rundown on browsers that work well with this mode of browsing.

* *Firefox*--With the [NoTabs](https://addons.mozilla.org/en-US/firefox/addon/adsum-notabs/) plugin, all pages opens in a new window. Plugins like [Surfingkeys](https://addons.mozilla.org/en-US/firefox/addon/surfingkeys_ff/?utm_source=addons.mozilla.org&utm_medium=referral&utm_content=search) can be used to open links in a new window. 
* *Safari*--Includes an option to open new tabs as windows. Then, cmd-click opens links in the window to the right.
* *qutebrowser*--Has the option `tabs.tabs_are_windows` to open tabs as new windows with cmd-click or `;b` or `;f`.

Many websites are responsive, so they work well with narrow windows. Many feel more usable to me. Some of the main search sites like Google are not responsive. For these, it helps to adjust the User Agent to an iPad or Android tablet. 

With the `PaperWM.apps_open_in_background` option, you can set new browser windows to open next to the original window, and focus stays with the original window.

## Other apps that work well with scrolling windows

Terminal-based apps, including editors like Helix work great with scrolling windows.

VS Code has the option "Move into New Window" for tabs. That works nicely.

