local vars = require("variables")

hl.config({
    gestures = {
        workspace_swipe_distance                 = 700,
        workspace_swipe_cancel_ratio             = 0.15,
        workspace_swipe_min_speed_to_force       = 5,
        workspace_swipe_direction_lock           = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new               = true,
    },
})

hl.gesture({ fingers = vars.workspaceSwipeFingers, direction = "vertical", action = "workspace" })
-- local change: ←/→ slides between the apps of this workspace (scrolling layout, one full-width app per screen — user.lua)
-- scale 2.5: the view moves 2.5× finger travel, so a short swipe already passes half a screen and lands on the next app
hl.gesture({ fingers = vars.workspaceSwipeFingers, direction = "horizontal", action = "scroll_move", scale = 2.5 })
hl.gesture({ fingers = vars.gestureFingers, direction = "up", action = "special", workspace_name = "special" })
hl.gesture({
    fingers   = vars.gestureFingers,
    direction = "down",
    action    = function()
        hl.dispatch(hl.dsp.workspace.toggle_special("special"))
    end,
})
hl.gesture({
    fingers   = vars.gestureFingersMore,
    direction = "down",
    action    = function()
        hl.exec_cmd(vars.sleepGestureCmd)
    end,
})
