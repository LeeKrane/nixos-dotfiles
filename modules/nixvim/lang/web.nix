# TypeScript/JavaScript, Tailwind, HTML and CSS.
{ lib, pkgs, ... }:
{
  lsp.servers = {
    ts_ls.enable = true;
    tailwindcss.enable = true;
    html.enable = true;
    cssls = {
      enable = true;
      # Tailwind's @tailwind/@apply/@layer are unknown at-rules to plain CSS.
      config.settings = lib.genAttrs [ "css" "scss" "less" ] (_: {
        lint.unknownAtRules = "ignore";
      });
    };
  };

  plugins.ts-autotag.enable = true;

  plugins.conform-nvim.settings.formatters_by_ft = lib.genAttrs [
    "javascript"
    "javascriptreact"
    "typescript"
    "typescriptreact"
    "html"
    "css"
    "scss"
  ] (_: [ "prettierd" ]);

  extraPackages = [ pkgs.prettierd ];
}
