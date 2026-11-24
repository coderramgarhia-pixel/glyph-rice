-- Title bars with minimize / maximize / close (hyprbars plugin, Fedora package hyprland-plugin-hyprbars).
-- Colours: Glyph's dark palette, fixed — a Style change in Prefs doesn't recolour these bars.
local bars = "/usr/lib64/hyprland/libhyprbars.so"
local f = io.open(bars)
if f then
    f:close()
    hl.plugin.load(bars)
end

-- the plugin registers hl.plugin.hyprbars on load and reloads the config, so the first pass may not have it yet
if hl.plugin.hyprbars then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height         = 26,
                bar_color          = "rgb(0e0e0e)",
                ["col.text"]       = "rgb(f2f2f2)",
                bar_text_font      = "Space Grotesk",
                bar_text_size      = 11,
                bar_padding        = 10,
                bar_button_padding = 8,
                bar_precedence_over_border = true, -- border wraps bar + window, not just the window
                -- border is off (Prefs → border 0), so focus shows as the red ✕: unfocused windows' buttons go grey
                inactive_button_color = "rgb(2a2a2a)",
                on_double_click    = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
            },
        },
    })

    -- apps with their own top bar keep only theirs (variables.ownBarApps)
    hl.window_rule({ match = { class = require("variables").ownBarApps }, ["hyprbars:no_bar"] = true })

    -- added right → left: shows as  −  □  ✕
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(d71921)", fg_color = "rgb(f2f2f2)", size = 14, icon = "✕",
        action = "hyprctl dispatch 'hl.dsp.window.close()'",
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(2a2a2a)", fg_color = "rgb(f2f2f2)", size = 14, icon = "□",
        action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    })
    -- Hyprland has no minimize: hide into the scratchpad, Super+S brings it back
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(2a2a2a)", fg_color = "rgb(f2f2f2)", size = 14, icon = "−",
        action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:special" })']],
    })
end

-- an app's own minimize button: Hyprland has no minimized state, so hide it in the scratchpad (Super+S brings it back)
hl.on("window.minimize", function(win, on)
    if on then hl.dispatch(hl.dsp.window.move({ workspace = "special:special", follow = false, window = win })) end
end)

-- X11 apps at native pixels: sharp instead of 1.5× upscaled-blurry (scrcpy-iphone/-pixel are X11). X11 apps that don't
-- scale themselves show smaller; delete this line to go back
hl.config({ xwayland = { force_zero_scaling = true } })

-- Spotlight search (quickshell/glyph/spot). Takes Ctrl+Space from every app, IDE code completion included
hl.bind("CTRL + Space", hl.dsp.global("shell:spot"))

-- One app per screen, many per workspace: the scrolling layout with full-width columns — a new app opens as a column to the
-- right of the current one and the view slides to it. 3 fingers ←/→ (or Super+←/→) between apps, ↑/↓ between workspaces
-- (gestures.lua); quickshell/glyph/pages shows where you are
hl.config({
    general   = { layout = "scrolling" },
    scrolling = { column_width = 1.0 },
    gestures  = { scrolling = { move_snap_to_grid = true } }, -- a swipe ends on one app, never between two
})

-- Snappy swipe: window slides (swipe tracking + the snap after you lift) in 300 ms on a curve that moves at once, instead
-- of 600 ms that starts from a standstill. Two-finger scroll speed is Prefs → scroll % (~/.config/demonshot/rules.json)
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "emphasizedDecel" })

-- buds app (quickshell/glyph/buds/Ears.qml): same fade as the power menu
hl.layer_rule({ match = { namespace = "glyph-buds" }, animation = "fade" })
