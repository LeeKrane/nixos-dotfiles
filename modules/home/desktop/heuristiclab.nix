# HeuristicLab (pkgs/heuristiclab), run under Wine. Its launcher sets up its own
# prefix in ~/.local/share/heuristiclab on first start.
{ pkgs, ... }:
{
  home.packages = [ pkgs.heuristiclab ];
}
