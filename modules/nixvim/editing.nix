# Motions, text objects, pairs, surround, comments and directory editing.
{
  plugins.flash.enable = true;

  plugins.mini.modules = {
    ai = {
      n_lines = 500;
      custom_textobjects = {
        f.__raw = ''require("mini.ai").gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" })'';
        c.__raw = ''require("mini.ai").gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" })'';
      };
    };
    pairs = {
      modes = {
        insert = true;
        command = true;
        terminal = false;
      };
    };
    surround.mappings = {
      add = "gsa";
      delete = "gsd";
      find = "gsf";
      find_left = "gsF";
      highlight = "gsh";
      replace = "gsr";
      update_n_lines = "gsn";
    };
  };

  plugins.ts-comments.enable = true;
  plugins.todo-comments.enable = true;

  plugins.oil = {
    enable = true;
    settings.view_options.show_hidden = true;
  };
}
