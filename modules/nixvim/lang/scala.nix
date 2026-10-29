# Scala: metals for LSP (it drives sbt through BSP), scalafmt for formatting.
{ pkgs, ... }:
{
  lsp.servers.metals.enable = true;

  plugins.conform-nvim.settings.formatters_by_ft.scala = [ "scalafmt" ];

  extraPackages = [ pkgs.scalafmt ];
}
