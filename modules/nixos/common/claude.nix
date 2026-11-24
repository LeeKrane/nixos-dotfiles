# `claude` in fish runs through billion-context: Claude Code -> bili (loopback) -> teamclaude
# (localhost:3456) -> Anthropic. Package and its hardening env: pkgs/billion-context.
_: {
  # ~/.claude/settings.json no longer sets ANTHROPIC_BASE_URL: its env block overrides the
  # launch env, which would bypass bili. bili finds the upstream only in the process env, so
  # both variables name the teamclaude proxy and bili rewrites the one claude sees.
  environment.sessionVariables = {
    ANTHROPIC_BASE_URL = "http://localhost:3456";
    BILI_CLAUDE_UPSTREAM = "http://localhost:3456";
  };

  # In /etc/fish for the same reason as shells.nix. bili runs the real claude from PATH (fish
  # functions are invisible to it), so this does not recurse. BILI_LAUNCHER_DIRECT=1 is needed:
  # the default MITM launch ignores ANTHROPIC_BASE_URL/BILI_CLAUDE_UPSTREAM, so teamclaude
  # would be bypassed (and the wrapper turns MITM off). `--` hands every arg to claude verbatim.
  environment.etc."fish/functions/claude.fish".text = ''
    function claude --wraps claude --description 'claude via billion-context (bili) in front of teamclaude'
        if command -q bili
            BILI_LAUNCHER_DIRECT=1 bili claude -- $argv
        else
            command claude $argv
        end
    end
  '';
}
