# CLI basics for every host. modules/nixos/common/shells.nix aliases (eza, bat, z, lazygit,
# btop, ...) and its fish init call these tools. Desktop-only extras: ../desktop/cli.nix.
{ lib, pkgs, ... }:
{
  # bat/eza/btop configs aren't in the ii wipe set (docs/II-INTEGRATION.md), so home-manager can
  # manage them here. zoxide and fzf stay plain home.packages, not programs.zoxide/programs.fzf:
  # both default enableFishIntegration to true and would inject init lines into HM's fish config,
  # which only lands in the wiped ~/.config/fish/config.fish. The real init (and direnv) lives in
  # modules/nixos/common/shells.nix instead (/etc/fish, never wiped).
  programs.bat.enable = true;
  programs.eza.enable = true;
  # mkDefault: the desktop swaps in btop-cuda (../desktop/cli.nix).
  programs.btop = {
    enable = true;
    package = lib.mkDefault pkgs.btop;
  };

  programs.ssh = {
    enable = true;
    # This HM version deprecated matchBlocks/addKeysToAgent in favor of raw
    # ssh_config directive names under settings, and warns on
    # enableDefaultConfig unless it's explicitly turned off.
    enableDefaultConfig = false;
    settings."*".AddKeysToAgent = "yes";
  };

  home.packages = with pkgs; [
    zoxide
    fzf

    ripgrep
    fd
    dust
    ncdu
    tealdeer
    pay-respects # fish `fuck` alias sourced at the NixOS level (shells.nix), package lives here
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

    # modules/nixos/common/users.nix enables sshd only so sshd-keygen creates the host key sops-nix
    # derives its age identity from (openFirewall = false). Listed explicitly, not an accidental
    # transitive dep of the ssh/scp client.
    openssh
  ];
}
