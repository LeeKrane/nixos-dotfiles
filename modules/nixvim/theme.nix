# Wallpaper-driven colorscheme, see lua/dynamic-theme.lua.
let
  # catppuccin-frappe base16, used until a valid material_colors.scss is read.
  fallback = {
    base00 = "#303446";
    base01 = "#292c3c";
    base02 = "#414559";
    base03 = "#51576d";
    base04 = "#626880";
    base05 = "#c6d0f5";
    base06 = "#f2d5cf";
    base07 = "#babbf1";
    base08 = "#e78284";
    base09 = "#ef9f76";
    base0A = "#e5c890";
    base0B = "#a6d189";
    base0C = "#81c8be";
    base0D = "#8caaee";
    base0E = "#ca9ee6";
    base0F = "#eebebe";
  };
in
{
  # mini.base16 ships in mini.nvim; setup() is called at runtime, not here.
  plugins.mini.enable = true;

  globals.dynamic_theme_fallback = fallback;

  extraFiles = {
    "lua/dynamic-theme.lua".source = ./lua/dynamic-theme.lua;
    "colors/dynamic.lua".source = ./colors/dynamic.lua;
  };

  # Post: runs after every plugin's setup, so ColorScheme reaches them all.
  extraConfigLuaPost = ''
    require("dynamic-theme").setup()
  '';
}
