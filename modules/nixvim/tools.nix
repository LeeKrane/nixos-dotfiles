# Git hunks, diagnostics lists, search/replace and sessions.
{ pkgs, lib, ... }:
{
  plugins.lz-n.enable = true;

  plugins.gitsigns = {
    enable = true;
    settings.on_attach.__raw = ''
      function(buffer)
        local gs = package.loaded.gitsigns
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
        end
        map("n", "]h", function() gs.nav_hunk("next") end, "Next Hunk")
        map("n", "[h", function() gs.nav_hunk("prev") end, "Prev Hunk")
        map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
        map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
        map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
        map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
        map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk Inline")
        map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame Line")
        map("n", "<leader>ghd", gs.diffthis, "Diff This")
      end
    '';
  };

  # lz-n lazy loading is experimental in nixvim; drop lazyLoad if either misbehaves.
  plugins.trouble = {
    enable = true;
    lazyLoad.settings.cmd = "Trouble";
  };
  plugins.grug-far = {
    enable = true;
    lazyLoad.settings.cmd = "GrugFar";
    # Its UI tests time out under qemu (aarch64 server builds on x86 via binfmt).
    package = pkgs.vimPlugins.grug-far-nvim.overrideAttrs (
      lib.optionalAttrs pkgs.stdenv.hostPlatform.isAarch64 { doCheck = false; }
    );
  };

  plugins.persistence.enable = true;
}
