# PaperWM.spoon

## Fork

The main purpose of this fork is to support virtual spaces like [Aerospace](https://github.com/nikitabobko/AeroSpace). The active spaces for each screen are shown in the menubar.

Spaces are arranged vertically. All spaces are named. You can set up your own as follows:

```lua
PaperWM.space_names = {0, "comms", "web", "util", "code", 1, 2, 3, 4, 5, 6, 7, 8, 9}
```

The last space is a scratch space called `*`, mainly used for moving around windows.

Several commands are provided to switch spaces, including
`focus_space_0`, `focus_space_1`, `focus_space_2`, `focus_space_3`, `focus_space_4`, `focus_space_5`, `focus_space_6`, `focus_space_7`, `focus_space_8`, and `focus_space_9`.
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

By default, spaces are assigned to the primary screen. Spaces can be moved to other screens. PaperWM attempts to remember which screen a space was last assigned to.

When windows are opened, PaperWM attempts to remember the last space and window ordering. This is based on the application and window title. This isn't perfect. When VS Code opens windows, the windows initially have no title, so the remembered ordering doesn't work. 

Here are new or changed commands:

- `move_to_scratch_space`--Move the current window to the scratch space. The scratch space (labeled "*") is the last space. Typically bound to `mod-Y` (yank, and `mod` is one or more modifiers like `alt` or `alt-cmd`).
- `move_from_scratch_space`--Move all windows from the scratch space to the current space. The scratch space makes it easy to move windows around. Yank multiple windows, switch to a new space then paste. Typically bound to `mod-P` (paste).
- `focus_scratch_space`--Switch to the scratch space.
- `move_right_to_scratch_space`--Move the current window and all windows to the right to the scratch space. 
- `focus_up`/`focus_down`--These now change focus up and down a space if at the top/bottom of a column.
- `swap_*`--These were renamed to `move_*`. These now move windows up and down a space if at the top/bottom of a column. 
- `close_window`--The same as cmd-W, except if it's the last window, it also closes the application.
- `close_windows_in_space`--Close all windows in the space.
- `choose_window`--This is a simple window selector that shows the available windows ordered by space. It's good enough to reduce the need for something like AltTab.
- `next_screen`--Focus the next screen (note that the next screen needs a space in which to focus).
- `space_to_next_screen`--Move the active space to the next screen.

There are still bugs:

- Sometimes, cycling window widths doesn't work right.
- After returning from full screen, the window doesn't show the right space.

It would also be nice to allow windows to be in multiple spaces, but that's a big code change and would require removing or changing `index_table`.

https://github.com/user-attachments/assets/dc567e25-ac42-42c1-b045-d526f66fb858

## Original PaperWM.spoon info

Many of the original [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) docs and issues are still appropriate.

## Installation

1. Clone to Hammerspoon Spoons directory: `git clone https://github.com/tshort/PaperWM.spoon ~/.hammerspoon/Spoons/PaperWM.spoon`.

2. Open `System Preferences` -> `Mission Control`. Uncheck "Displays have separate Spaces".

## Usage

Add configuration information to your `~/.hammerspoon/init.lua`. Here is an example configuration:

* [init.lua](./example-init.lua)
* [menuHammerCustomConfig.lua](./menuHammerCustomConfig.lua)

Edit as needed based on preferences for keyboard shortcuts and use of spaces. This configuration adds a [MenuHammer](https://github.com/FryJay/MenuHammer) menu for window management. After most operations, the menu remains active, so it's nice for multiple operations.

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

