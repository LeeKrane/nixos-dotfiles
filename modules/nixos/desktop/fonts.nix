{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.hack
    nerd-fonts.meslo-lg
    nerd-fonts.fira-code
    nerd-fonts.caskaydia-cove
    nerd-fonts.iosevka
    nerd-fonts.ubuntu
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    rubik
    # The soymou module installs Material Symbols only into the user profile, which system
    # fontconfig never reads, so ii renders icon names as text.
    material-symbols
  ];

  fonts.enableDefaultPackages = true;

  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font" ];
    sansSerif = [ "Noto Sans" ];
    serif = [ "Noto Serif" ];
    emoji = [ "Noto Color Emoji" ];
  };
}
