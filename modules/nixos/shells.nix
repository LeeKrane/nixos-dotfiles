{ pkgs, ... }:
{
  # `just`/`gum` on the installed system too, since install.sh's setup UI
  # and `just check` need them without `nix develop`.
  environment.systemPackages = with pkgs; [
    just
    gum
  ];

  # /etc/fish, not ~/.config/fish: soymou's dotfiles-copy step wipes that
  # every switch. This is the only place fish config survives.
  programs.fish.enable = true;

  # Valid shell for modules/home/zsh-fallback.nix's HM fallback via chsh.
  programs.zsh.enable = true;

  # Explicit false: the soymou module's starship already inits the
  # prompt. A second one here would double-init.
  programs.starship.enable = false;

  # Ported from the old dotfiles' aliases/main.sh. rebos aliases dropped.
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
    # Shared by rf/rfnv, not meant to be called directly. $argv[1] is the
    # query. $argv[2..] are extra fzf args, such as rfnv's --bind.
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
    # ripgrep + fzf live grep, reloaded on every keystroke.
    function rf --description 'ripgrep + fzf live grep'
        __krane_rf_impl "$argv"
    end
  '';

  environment.etc."fish/functions/rfnv.fish".text = ''
    # Same as rf, but enter opens the match in nvim.
    function rfnv --description 'rf, open the match in nvim at the matched line'
        __krane_rf_impl "$argv" --bind "enter:become:nvim {1} +{2}"
    end
  '';

  # zoxide/fzf/direnv/pay-respects hook fish only here, not via their HM
  # `programs.*` modules: those would write to the wiped
  # ~/.config/fish/config.fish instead. Full store paths, not bare names.
  programs.fish.interactiveShellInit = ''
    set -gx EDITOR nvim
    ${pkgs.zoxide}/bin/zoxide init fish | source
    ${pkgs.fzf}/bin/fzf --fish | source
    ${pkgs.pay-respects}/bin/pay-respects fish --alias fuck | source
  '';

  # NixOS-level `programs.direnv`, not modules/home/cli.nix. Hooks fish
  # via enableFishIntegration.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
