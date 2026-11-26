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
        (modules/nixos/common/users.nix); this exists as an `exec zsh` escape hatch
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

      # `file` is explicit: HM's default `<name>.plugin.zsh` doesn't exist in these packages.
      # zsh-syntax-highlighting must load last; it wraps every other widget.
      plugins = [
        {
          name = "zsh-autosuggestions";
          src = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
          file = "zsh-autosuggestions.zsh";
        }
        {
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

    # Not in the ii wipe set (docs/II-INTEGRATION.md), so a plain symlink survives.
    home.file.".p10k.zsh".source = ../../../config/zsh/p10k.zsh;
  };
}
