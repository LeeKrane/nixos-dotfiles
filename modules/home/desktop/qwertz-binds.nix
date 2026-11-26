# kb_layout = "at" (QWERTZ): upstream ii binds actions to keysyms that need Shift or AltGr
# (Slash, Semicolon, Apostrophe, Equal), and Hyprland matches the modifier mask exactly, so they
# never fire. These move them onto unshifted keys. Super+Period and Super+Minus are taken
# upstream, so they are unbound first: Hyprland runs every matching bind and custom/keybinds.lua
# loads after the upstream file. zoomfunction is a local in hyprland/keybinds.lua, so it is
# reimplemented here.
{ ... }:
{
  krane.hypr.unbinds = [
    "SUPER + Slash"
    "SUPER + Semicolon"
    "SUPER + Apostrophe"
    "SUPER + Period"
    "SUPER + Minus"
    "SUPER + Equal"
  ];

  krane.hypr.extraKeybindsLua = ''
    local function kraneZoom(value)
        local n = hl.get_config("cursor:zoom_factor") + value
        if n > 3.0 then n = 3.0 elseif n < 1.0 then n = 1.0 end
        hl.config({ cursor = { zoom_factor = n } })
    end
  '';

  krane.hypr.binds = [
    {
      keys = "SUPER + ssharp";
      action = ''hl.dsp.global("quickshell:cheatsheetToggle")'';
      description = "Shell: Toggle cheatsheet";
    }
    {
      keys = "SUPER + Comma";
      action = ''hl.dsp.layout("splitratio -0.1")'';
      repeating = true;
      description = "Window: Shrink split";
    }
    {
      keys = "SUPER + Period";
      action = ''hl.dsp.layout("splitratio +0.1")'';
      repeating = true;
      description = "Window: Grow split";
    }
    {
      keys = "SUPER + numbersign";
      action = "function() kraneZoom(0.3) end";
      repeating = true;
      description = "Screen: Zoom in";
    }
    {
      keys = "SUPER + SHIFT + numbersign";
      action = "function() kraneZoom(-0.3) end";
      repeating = true;
      description = "Screen: Zoom out";
    }
    {
      keys = "SUPER + Minus";
      action = ''hl.dsp.global("quickshell:overviewEmojiToggle")'';
      description = "Utilities: Emoji picker";
    }
  ];
}
