{ pkgs, ... }:
{
  # bat/eza/btop configs aren't in the ii wipe set (docs/II-INTEGRATION.md), so home-manager can
  # manage them here. zoxide and fzf stay plain home.packages, not programs.zoxide/programs.fzf:
  # both default enableFishIntegration to true and would inject init lines into HM's fish config,
  # which only lands in the wiped ~/.config/fish/config.fish. The real init (and direnv) lives in
  # modules/nixos/shells.nix instead (/etc/fish, never wiped).
  programs.bat.enable = true;
  programs.eza.enable = true;
  programs.btop.enable = true;

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
    imagemagick
    jpegoptim
    optipng
    toipe
    trivy
    scrcpy
    android-tools
    libnotify
    ani-cli

    # modules/nixos/users.nix enables sshd only so sshd-keygen creates the host key sops-nix
    # derives its age identity from (openFirewall = false). Listed explicitly, not an accidental
    # transitive dep of the ssh/scp client.
    openssh
  ];
}
