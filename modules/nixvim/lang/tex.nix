# LaTeX: vimtex (compile/view/motions, uses the system texliveMedium) + texlab + latexindent.
{ pkgs, ... }:
let
  # Only latexindent is bundled (off PATH); TeX itself stays in modules/home/dev.nix.
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

  # vimtex's syntax is what vimtex#syntax#in_mathzone reads; treesitter would replace it.
  # `settings.highlight.disable` is the legacy (master-branch) nvim-treesitter option and is a
  # no-op on the main branch this repo uses; the modern equivalent is the top-level option below.
  plugins.treesitter.highlight.disable = [ "latex" ];

  lsp.servers.texlab.enable = true;

  plugins.conform-nvim.settings = {
    formatters_by_ft.tex = [ "latexindent" ];
    # Absolute path, not extraPackages: the env's pdflatex/bibtex/... must not
    # shadow the system texliveMedium on the editor's PATH. `-g /dev/null`
    # stops latexindent writing indent.log into the cwd.
    formatters.latexindent = {
      command = "${latexindent}/bin/latexindent";
      prepend_args = [
        "-g"
        "/dev/null"
      ];
    };
  };
}
