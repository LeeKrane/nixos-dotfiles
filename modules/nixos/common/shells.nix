{ pkgs, lib, ... }:
{
  # /etc/fish, not ~/.config/fish: soymou's dotfiles-copy step wipes that every switch.
  programs.fish.enable = true;

  # Valid shell for modules/home/common/zsh-fallback.nix's HM fallback via chsh.
  programs.zsh.enable = true;

  # mkDefault: the soymou module already inits starship; ../desktop/shells.nix turns this off.
  programs.starship.enable = lib.mkDefault true;

  programs.fish.shellAliases = {
    c = "clear";
    ls = "eza -h";
    ll = "eza -lh";
    la = "eza -Ah";
    lla = "eza -lAh";
    tree = "eza --tree";
    nv = "nvim";
    cat = "bat --color=always";
    cd = "z";
    zz = "z -";
    lg = "lazygit";
    htop = "btop";
    top = "btop";

    # fzf
    fzfp = ''fzf --preview="bat --color=always {}" --preview-window "~4,+{2}+4/3,<80(up)"'';
    fnv = ''fzfp --bind "enter:become:nvim {1}"'';
  };

  # Fish functions, not shellAliases: `$argv` needs an explicit join
  # since fish won't expand `(cmd)` substitution inside double quotes.
  environment.etc."fish/functions/__krane_rf_impl.fish".text = ''
    # $argv[1] is the query, $argv[2..] extra fzf args.
    function __krane_rf_impl --description 'shared rf/rfnv implementation'
        set -l query $argv[1]
        set -l extra_args $argv[2..]
        fzf --disabled --ansi \
            --bind "start:reload:rg --hidden --no-ignore --column --color=always --smart-case {q}" \
            --bind "change:reload:rg --hidden --no-ignore --column --color=always --smart-case {q}" \
            --delimiter : \
            --preview="bat --style=full --color=always --highlight-line {2} {1}" \
            --preview-window "~4,+{2}+4/3,<80(up)" \
            --query "$query" \
            $extra_args
    end
  '';

  environment.etc."fish/functions/rf.fish".text = ''
    function rf --description 'ripgrep + fzf live grep'
        __krane_rf_impl "$argv"
    end
  '';

  environment.etc."fish/functions/rfnv.fish".text = ''
    function rfnv --description 'rf, open the match in nvim at the matched line'
        __krane_rf_impl "$argv" --bind "enter:become:nvim {1} +{2}"
    end
  '';

  # Hooks fish here, not via HM `programs.*`, which write to the wiped ~/.config/fish/config.fish.
  programs.fish.interactiveShellInit = ''
    set -gx EDITOR nvim
    ${pkgs.zoxide}/bin/zoxide init fish | source
    ${pkgs.fzf}/bin/fzf --fish | source
    ${pkgs.pay-respects}/bin/pay-respects fish --alias fuck | source
    # Also clears the scrollback (\e[3J), which plain `clear` leaves in kitty.
    alias clear "printf '\e[2J\e[3J\e[1;1H'"
  '';

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    settings.global.hide_env_diff = true;
    # Also hides "direnv: error .envrc is blocked".
    silent = true;
  };
}
