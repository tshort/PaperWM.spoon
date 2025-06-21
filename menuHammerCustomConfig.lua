function menu(modifiers, key, title, fun, go)
    return {cons.cat.action, modifiers, key, title, {
                {
                    cons.act.func,                                                -- Action type
                    fun,
                }},
                not go
            }
end

    menuHammerMenuList = {
        mainMenu = {
            parentMenu = nil,
            menuHotkey = {{'alt'}, 'space'},
            menuItems =  {
                menu('', 'j', "Focus down", PaperWM.actions.focus_down),
                menu('', 'k', "Focus up", PaperWM.actions.focus_up),
                menu('', 'h', "Focus left", PaperWM.actions.focus_left),
                menu('', 'l', "Focus right", PaperWM.actions.focus_right),
                menu('shift', 'j', "Move down", PaperWM.actions.move_down),
                menu('shift', 'k', "Move up", PaperWM.actions.move_up),
                menu('shift', 'h', "Move left", PaperWM.actions.move_left),
                menu('shift', 'l', "Move right", PaperWM.actions.move_right),
                menu('', 'y', "Yank to scratch", PaperWM.actions.move_to_scratch_space),
                menu('shift', 'y', "Yank right to scratch", PaperWM.actions.move_right_to_scratch_space),
                menu('', 'p', "Paste from scratch", PaperWM.actions.move_from_scratch_space),
                menu('', 'i', "Slurp in", PaperWM.actions.slurp_in),
                menu('', 'o', "Barf out", PaperWM.actions.barf_out),
                menu('', 'w', "Close window", PaperWM.actions.close_window),
                menu('shift', 'w', "Close windows in space", PaperWM.actions.close_windows_in_space),
                menu('', 'z', "Choose windows", PaperWM.actions.choose_window, true),
                menu('shift', 'r', "Refresh windows", PaperWM.actions.refresh_windows),
                menu('', 'c', "Cycle width", PaperWM.actions.cycle_width),
                menu('shift', 'c', "Full width", PaperWM.actions.full_width),
                menu('', 'n', "Focus next screen", PaperWM.actions.next_screen),
                menu('shift', 'n', "Space to next screen", PaperWM.actions.space_to_next_screen),
            },
        },
    }
