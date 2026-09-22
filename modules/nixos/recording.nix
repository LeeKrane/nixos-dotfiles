# GPU Screen Recorder. programs.gpu-screen-recorder installs setcap wrappers gsr-kms-server
# (cap_sys_admin, needed for KMS capture) and gsr-global-hotkeys, plus the gpu-screen-recorder
# CLI, the gsr-ui overlay, and gsr-notification. Hyprland keybinds for it live in
# modules/home/recording.nix, not here.
{ ... }:
{
  programs.gpu-screen-recorder = {
    enable = true;
    ui.enable = true;
  };
}
