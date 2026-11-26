{ pkgs, ... }:
let
  # latexindent only (off PATH); TeX itself comes from modules/home/desktop/dev.nix.
  latexindent = pkgs.texliveBasic.withPackages (ps: [ ps.latexindent ]);
in
{
  plugins.vimtex = {
    enable = true;
    texlivePackage = null;
    settings = {
      view_method = "general";
      quickfix_mode = 0;
    };
  };

  # vimtex's syntax feeds vimtex#syntax#in_mathzone; treesitter would replace it.
  # `settings.highlight.disable` is the legacy (master-branch) option, a no-op on the main branch used here.
  plugins.treesitter.highlight.disable = [ "latex" ];

  lsp.servers.texlab.enable = true;

  plugins.conform-nvim.settings = {
    formatters_by_ft.tex = [ "latexindent" ];
    # Absolute path, not extraPackages: the env's pdflatex/bibtex/... would shadow the system
    # texliveMedium on the editor's PATH. `-g /dev/null` stops latexindent writing indent.log into the cwd.
    formatters.latexindent = {
      command = "${latexindent}/bin/latexindent";
      prepend_args = [
        "-g"
        "/dev/null"
      ];
    };
  };
}
