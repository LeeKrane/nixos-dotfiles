-- GENERATED FILE -- DO NOT EDIT.
-- Rendered by krane-ii-settings from hosts/<host>/ii-settings.json.
-- Installed as ~/.config/hypr/custom/krane_gui.lua at switch time and
-- rewritten live by the ii settings GUI. Loaded from monitors.lua.

hl.config({
    animations = {
        enabled = true
    },
    decoration = {
        active_opacity = 1.0,
        blur = {
            enabled = true,
            passes = 3,
            size = 6
        },
        inactive_opacity = 0.9,
        rounding = 12,
        shadow = {
            enabled = false,
            range = 8
        }
    },
    general = {
        border_size = 2,
        gaps_in = 4,
        gaps_out = 10,
        layout = "master"
    },
    input = {
        follow_mouse = 1,
        kb_layout = "us",
        kb_variant = "",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,
        touchpad = {
            clickfinger_behavior = false,
            disable_while_typing = true,
            natural_scroll = true,
            scroll_factor = 0.7
        }
    }
})

require("hyprland.animationPresets.fast")

KRANE_GUI_MONITORS = {}

KRANE_GUI_MONITORS["DP-2"] = {
    output = "DP-2",
    mode = "3840x2160@240",
    position = "0x0",
    scale = 1.5,
    transform = 0,
    vrr = 1,
    bitdepth = 10,
    cm = "hdr",
    sdrbrightness = 1.2,
    sdrsaturation = 1.0,
    sdr_min_luminance = 0.2,
    sdr_max_luminance = 200,
    min_luminance = 0.05,
    max_luminance = 1000,
    max_avg_luminance = 400
}
hl.monitor(KRANE_GUI_MONITORS["DP-2"])
KRANE_GUI_MONITORS["HDMI-A-1"] = {
    output = "HDMI-A-1",
    mode = "1920x1080@60",
    position = "-1920x0",
    scale = 1,
    disabled = true
}
hl.monitor(KRANE_GUI_MONITORS["HDMI-A-1"])
