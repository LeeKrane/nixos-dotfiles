# Java via nvim-jdtls; one workspace per project under the nvim cache dir.
#
# Not using nixvim's `plugins.jdtls` module: its `settings.cmd`/`root_dir` are
# rendered as plain `vim.lsp.config(...)` values, evaluated once at startup
# rather than per buffer (confirmed via nixvim-print-init), and the module
# also unconditionally enables its own `lsp.servers.jdtls` start hook even
# with empty settings. Instead: install the plugin/server manually and start
# jdtls per buffer from an explicit FileType autocmd, as the phase 2 plan's
# fallback describes.
{ pkgs, ... }:
{
  extraPlugins = [ pkgs.vimPlugins.nvim-jdtls ];
  extraPackages = [ pkgs.jdt-language-server ];

  autoGroups.nixvim_jdtls.clear = true;
  autoCmd = [
    {
      event = "FileType";
      group = "nixvim_jdtls";
      pattern = "java";
      callback.__raw = ''
        function(event)
          local root = vim.fs.root(event.buf, { "gradlew", "mvnw", "pom.xml", "build.gradle", ".git" }) or vim.fn.getcwd()
          -- Workspace keyed by the full root path, so same-basename projects don't share one.
          local workspace = vim.fn.stdpath("cache") .. "/jdtls/" .. root:gsub("/", "%%")
          require("jdtls").start_or_attach({
            cmd = { "jdtls", "-data", workspace },
            root_dir = root,
            capabilities = require("blink.cmp").get_lsp_capabilities(),
          }, nil, { bufnr = event.buf })
        end
      '';
    }
  ];
}
