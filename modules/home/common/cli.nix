{
  kraneUser,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../../lib/wireguard.nix) wg0;
in
{
  # zoxide and fzf stay plain home.packages: programs.zoxide/programs.fzf default
  # enableFishIntegration to true and would inject init into HM's fish config, which lands in the
  # wiped ~/.config/fish/config.fish. The real init lives in modules/nixos/common/shells.nix.
  programs.bat.enable = true;
  programs.eza.enable = true;
  # mkDefault: the desktop swaps in btop-cuda (../desktop/cli.nix).
  programs.btop = {
    enable = true;
    package = lib.mkDefault pkgs.btop;
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*".AddKeysToAgent = "yes";
    }
    # Servers and SSH desktops by name over wg0 (lib/wireguard.nix).
    // lib.genAttrs (wg0.sshServers ++ wg0.desktopSsh) (name: {
      HostName = if name == wg0.hub.name then wg0.hub.ip else wg0.peers.${name}.ip;
      User = kraneUser.name;
    });
  };

  home.packages = with pkgs; [
    zoxide
    fzf

    ripgrep
    fd
    dust
    ncdu
    tealdeer
    pay-respects # fish `fuck` alias is sourced in shells.nix
    fastfetch
    jq
    yq-go
    mc
    wireguard-tools
    rsync
    unzip
    p7zip
    wget
    curl

    # sshd is enabled (modules/nixos/common/users.nix) only so sshd-keygen creates the host key
    # sops-nix derives its age identity from; listed explicitly, not a transitive dep of the client.
    openssh
  ];
}
