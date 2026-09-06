{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.krane.zshFallback;
in
{
  options.krane.zshFallback = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install a zsh + oh-my-zsh + powerlevel10k fallback shell, ported from
        the previous Stow-managed dotfiles' .zshrc. krane's actual login shell is fish
        (modules/nixos/users.nix); this exists as an `exec zsh` escape hatch
        during the fish/ii transition, not as the default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh = {
      enable = true;

      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "history"
        ];
      };

      # zsh-autosuggestions and zsh-syntax-highlighting come straight from nixpkgs (HM's
      # programs.zsh.plugins) instead of being vendored like the previous dotfiles did. `file`
      # is set explicitly since HM's default `<name>.plugin.zsh` doesn't exist in these packages,
      # and zsh-syntax-highlighting must load last since it wraps every other widget.
      plugins = [
        {
          name = "zsh-autosuggestions";
          src = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
          file = "zsh-autosuggestions.zsh";
        }
        {
          # Sources the nixpkgs theme file directly, same effect as the previous dotfiles'
          # manually cloned $ZSH_CUSTOM theme, without oh-my-zsh's theme-lookup machinery.
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
        {
          name = "zsh-syntax-highlighting";
          src = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
          file = "zsh-syntax-highlighting.zsh";
        }
      ];

      initContent = ''
        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      '';
    };

    # ~/.p10k.zsh isn't in the ii wipe set (only ~/.config/zshrc.d is, docs/II-INTEGRATION.md),
    # so this plain symlink survives every switch.
    home.file.".p10k.zsh".source = ../../config/zsh/p10k.zsh;
  };
}
