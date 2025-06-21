hs.alert.show("Hammerspoon config loaded")

I = hs.inspect     -- for debugging

PaperWM = hs.loadSpoon("PaperWM")
PaperWM.window_ratios = { 0.38195, 0.61804, 0.8 }
local mods = {"alt"}
local shiftmods = {"shift", "alt"}
PaperWM.actions["focus_space_comms"] = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, "comms")
PaperWM.actions["focus_space_web"]   = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, "web")
PaperWM.actions["focus_space_util"]  = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, "util")
PaperWM.actions["focus_space_code"]  = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, "code")
PaperWM.actions["focus_space_0"]  = hs.fnutils.partial(PaperWM.focusSpace, PaperWM, 0)
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
    refresh_windows      = {shiftmods, "r"},
    cycle_width          = {mods, "c"},
    full_width           = {shiftmods, "c"},
    -- reverse_cycle_width  = {{"ctrl", "alt"}, "r"},
    -- cycle_height         = {shiftmods, "r"},
    -- reverse_cycle_height = {{"ctrl", "alt", "shift"}, "r"},

    -- increase/decrease width
    -- increase_width = {mods, "l"},
    -- decrease_width = {mods, "h"},

    -- move focused window into / out of a column
    slurp_in = {mods, "i"},
    barf_out = {mods, "o"},

    -- focus or move space to the next screen
    next_screen = {mods, "n"},
    space_to_next_screen = {shiftmods, "n"},

    -- move the focused window into / out of the tiling layer
    toggle_floating = {shiftmods, "escape"},

    -- switch to a new space
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
hs.hotkey.bind(mods, "pad0", PaperWM.actions.focus_space_0)
hs.hotkey.bind(mods, "pad1", PaperWM.actions.focus_space_1)
hs.hotkey.bind(mods, "pad2", PaperWM.actions.focus_space_2)
hs.hotkey.bind(mods, "pad3", PaperWM.actions.focus_space_3)
hs.hotkey.bind(mods, "pad4", PaperWM.actions.focus_space_4)
hs.hotkey.bind(mods, "pad5", PaperWM.actions.focus_space_5)
hs.hotkey.bind(mods, "pad6", PaperWM.actions.focus_space_6)
hs.hotkey.bind(mods, "pad7", PaperWM.actions.focus_space_7)
hs.hotkey.bind(mods, "pad8", PaperWM.actions.focus_space_8)
hs.hotkey.bind(mods, "pad9", PaperWM.actions.focus_space_9)
PaperWM.space_names = {
    0,
    "comms", "web", "util", "code", 
    1, 2, 3, 4, 5, 6, 7, 8, 9,
}
PaperWM.default_app_space = {
    ["Microsoft Outlook"] = "comms", Webex = "comms", 
    Finder = "util", Ghostty = "util", Terminal = "util", 
    Firefox = "web", Safari = "web", ["Google Chrome"] = "web", qutebrowser = "web",
    Code = "code", 
}
PaperWM.apps_open_in_background = {
    "Firefox", "Safari", "Google Chrome"
}
PaperWM.window_gap = 4
PaperWM:start()
PaperWM.logger.setLogLevel(2)


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
            elseif direction == "down" then
                PaperWM.actions.up_space()
            elseif direction == "up" then
                PaperWM.actions.down_space()
            end
        end
    else
        current_id = id
        threshold = 0.07 -- swipe distance > 20% of trackpad size
    end
end)

menuHammer = hs.loadSpoon("MenuHammer")
menuHammer:enter()