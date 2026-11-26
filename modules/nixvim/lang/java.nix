# Not nixvim's `plugins.jdtls`: it renders `settings.cmd`/`root_dir` once at startup, not per
# buffer, and enables its own `lsp.servers.jdtls`. jdtls starts per buffer from a FileType autocmd instead.
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
