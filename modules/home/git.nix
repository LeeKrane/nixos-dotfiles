{ pkgs, ... }:
{
  programs.git = {
    enable = true;

    settings = {
      # programs.git.userName/.userEmail are renamed to settings.user.{name,email} on this revision.
      user.name = "krane";
      user.email = "chris@krane.dev";

      core.editor = "nvim";
      core.autocrlf = "input";
      pull.rebase = true;
      fetch.prune = true;
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
      init.defaultBranch = "main";

      # From the previous dotfiles' .gitconfig, with `aa` fixed from the invalid `add all` to
      # `add -A`.
      alias = {
        st = "status -sb";
        co = "checkout";
        cm = "commit -m";
        ca = "commit --amend";
        ll = "log --oneline";
        pr = "pull --rebase";
        aa = "add -A";
        dc = "diff --cached";
      };
    };
    # core.pager/interactive.diffFilter aren't set here: programs.delta.enableGitIntegration
    # below wires both, avoiding a competing second definition.
  };

  # delta is its own top-level module, programs.delta, not programs.git.delta, on this
  # home-manager revision. enableGitIntegration reproduces the original core.pager and
  # diffFilter, options.navigate reproduces [delta] navigate = true.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options.navigate = true;
  };

  programs.lazygit.enable = true;

  home.packages = with pkgs; [
    gitleaks
    pre-commit
  ];
}
