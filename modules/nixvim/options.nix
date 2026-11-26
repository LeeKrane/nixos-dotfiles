{
  globals = {
    mapleader = " ";
    maplocalleader = ",";
    # .tex opens as tex, not plaintex.
    tex_flavor = "latex";
    nixvim_config_dir = "~/.dotfiles/modules/nixvim";
  };

  opts = {
    number = true;
    relativenumber = true;
    tabstop = 4;
    shiftwidth = 4;
    smartindent = true;
    smarttab = true;
    cursorline = true;
    expandtab = false;
    wrap = true;
    mouse = "a";
    showmode = false;

    # LazyVim baseline
    clipboard.__raw = ''vim.env.SSH_TTY and "" or "unnamedplus"'';
    undofile = true;
    undolevels = 10000;
    ignorecase = true;
    smartcase = true;
    scrolloff = 4;
    sidescrolloff = 8;
    signcolumn = "yes";
    splitright = true;
    splitbelow = true;
    splitkeep = "screen";
    confirm = true;
    completeopt = "menu,menuone,noselect";
    laststatus = 3;
    updatetime = 200;
    timeoutlen = 300;
    pumheight = 10;
    list = true;
    # Tabs render blank; snacks.indent draws guides.
    listchars = "tab:  ,trail:·,nbsp:␣";
    virtualedit = "block";
    wildmode = "longest:full,full";
    sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds";
    foldlevel = 99;
    foldmethod = "expr";
    foldexpr = "v:lua.vim.treesitter.foldexpr()";
    foldtext = "";
    termguicolors = true;
  };
}
