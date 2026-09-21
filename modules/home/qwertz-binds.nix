# All hosts use kb_layout = "at" (QWERTZ). Upstream ii binds the cheatsheet to the keysym
# `Slash` with SUPER only (hyprland/keybinds.lua:31). On QWERTZ, `/` is Shift+7, so the
# keypress carries SUPER+SHIFT and never matches. custom/keybinds.lua loads after upstream,
# so this adds a reachable alias on the ß key without removing the upstream bind.
{ ... }:
{
  krane.hypr.binds = [
    {
      keys = "SUPER + ssharp";
      action = ''hl.dsp.global("quickshell:cheatsheetToggle")'';
      description = "Shell: Toggle cheatsheet";
    }
  ];
}
