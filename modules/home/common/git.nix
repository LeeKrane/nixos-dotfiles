{ kraneUser, pkgs, ... }:
{
  programs.git = {
    enable = true;

    settings = {
      # From krane.user.gitName/gitEmail (modules/nixos/common/user.nix).
      user.name = kraneUser.gitName;
      user.email = kraneUser.gitEmail;

      core.editor = "nvim";
      core.autocrlf = "input";
      pull.rebase = true;
      fetch.prune = true;
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
      init.defaultBranch = "main";

      # For ii's config.json (.gitattributes): ii saves it with 4-space indent, switchwall.sh via jq
      # with 2-space. The filter stores 2-space so diffs show real changes. A failing jq leaves the
      # content unfiltered (filter not required).
      filter.ii-json.clean = "${pkgs.jq}/bin/jq --indent 2 .";

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
    # core.pager/interactive.diffFilter come from programs.delta.enableGitIntegration.
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options.navigate = true;
  };

  programs.lazygit.enable = true;

  home.packages = with pkgs; [
    gh
    gitleaks
    pre-commit
  ];
}
