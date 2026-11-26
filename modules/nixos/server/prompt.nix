# ii's starship.toml, read from the pinned dots-hyprland input so a flake update changes desktops
# and servers together, plus $hostname before $directory (ii's format has none), always shown.
{ inputs, lib, ... }:
let
  ii = lib.importTOML "${inputs.dots-hyprland}/dots/.config/starship.toml";
in
{
  # Fails the build if ii's format loses $directory, instead of silently dropping the hostname.
  assertions = [
    {
      assertion = lib.hasInfix "$directory" ii.format;
      message = "prompt.nix: ii's starship format no longer contains $directory; update where $hostname goes.";
    }
  ];

  programs.starship = {
    settings = ii // {
      format = lib.replaceStrings [ "$directory" ] [ "$hostname$directory" ] ii.format;
      hostname = {
        ssh_only = false;
        format = "[$hostname]($style) ";
        style = "bold fg:246";
      };
    };
    transientPrompt.enable = true;
  };

  programs.fish.interactiveShellInit = ''
    set fish_greeting
  '';
}
