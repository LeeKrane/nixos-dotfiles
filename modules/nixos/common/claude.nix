# `claude` in fish: Claude Code -HTTPS_PROXY-> billion-context service (local MITM for
# api.anthropic.com, compresses) -CONNECT-> teamclaude (localhost:3456) -> Anthropic.
# `claude-plain` is stock Claude Code: no teamclaude, no bili, no Code Mode. Service and its
# config: modules/home/common/billion-context.nix. Package and hardening env: pkgs/billion-context.
{ pkgs, ... }:
let
  curl = "${pkgs.curl}/bin/curl";
in
{
  # teamclaude for any claude started outside these functions. ~/.claude/settings.json does not
  # set it: its env block overrides the launch env, which would bypass the chain in `claude`.
  environment.sessionVariables.ANTHROPIC_BASE_URL = "http://localhost:3456";

  # In /etc/fish for the same reason as shells.nix. `env` and `command` run the real claude
  # binary (fish functions are invisible to them), so neither function recurses.
  # `claude` goes through HTTPS_PROXY, not the base URL, because Claude Code disables its
  # experimental Code Mode whenever ANTHROPIC_BASE_URL is custom (hence `env -u`). It must trust
  # the service's local MITM root CA (user accepted that risk), loaded only at startup via
  # NODE_EXTRA_CA_CERTS. A pre-set NODE_EXTRA_CA_CERTS is merged into a bundle at a fixed
  # runtime path that is never deleted: processes the session starts (claude-mem worker,
  # background jobs) inherit the path and may outlive the session. A nested `claude` inherits
  # that bundle or the CA itself and reuses it instead of merging again. NO_PROXY keeps loopback
  # traffic off the proxy; pre-set values are kept.
  # teamclaude down: stop with a hint rather than silently going direct. bili or its CA
  # missing: run through teamclaude's base URL instead (no compression, no Code Mode).
  # The auto-compact window is bili's modelContextLimit (modules/home/common/billion-context.nix):
  # a native full compaction then resets context before bili's 400K preflight wall.
  environment.etc."fish/functions/claude.fish".text = ''
    function claude --wraps claude --description 'claude with Code Mode via billion-context (MITM) and teamclaude'
        # Probe the ports, not the units: teamclaude may be started by hand, and the user bus
        # may be unreachable (ssh without linger, sudo -u). Any HTTP answer counts as up.
        if not ${curl} -s -o /dev/null -m 2 http://127.0.0.1:3456/
            echo "claude: teamclaude is not answering on 127.0.0.1:3456. Start it with `systemctl --user start teamclaude`, or use claude-plain to go direct." >&2
            return 1
        end
        set -l data (set -q XDG_DATA_HOME; and test -n "$XDG_DATA_HOME"; and echo $XDG_DATA_HOME; or echo $HOME/.local/share)
        set -l ca $data/billion-context/ca/root-ca.pem
        if not test -r $ca; or not ${curl} -s -o /dev/null -m 2 http://127.0.0.1:28787/
            echo "claude: billion-context or its CA missing, running through teamclaude only (no compression, no Code Mode)" >&2
            # Routing set explicitly: a caller inside a `claude` session has bili's proxy and
            # Code Mode in its env and no base URL.
            env -u HTTPS_PROXY -u https_proxy -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE \
                ANTHROPIC_BASE_URL=http://localhost:3456 \
                CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 \
                claude $argv
            return
        end
        set -l np localhost,127.0.0.1,::1
        for v in $NO_PROXY $no_proxy
            test -n "$v"; and set np $v,$np
        end
        set -l runtime (set -q XDG_RUNTIME_DIR; and test -d "$XDG_RUNTIME_DIR"; and echo $XDG_RUNTIME_DIR; or dirname $ca)
        set -l bundle $runtime/claude-ca.pem
        set -l certs $ca
        if test "$NODE_EXTRA_CA_CERTS" = $bundle; and test -r $bundle
            set certs $bundle
        else if test -r "$NODE_EXTRA_CA_CERTS"; and test "$NODE_EXTRA_CA_CERTS" != $ca
            # Write a unique temp file, then rename: a running session never reads a half-written
            # bundle, and two launches at once never share a temp file.
            set -l tmp (mktemp $runtime/claude-ca.XXXXXX)
            if test -n "$tmp"; and command cat $NODE_EXTRA_CA_CERTS $ca >$tmp; and command mv -f $tmp $bundle
                set certs $bundle
            else
                test -n "$tmp"; and command rm -f $tmp
                echo "claude: could not merge NODE_EXTRA_CA_CERTS with the billion-context CA, using the CA alone" >&2
            end
        end
        env -u ANTHROPIC_BASE_URL \
            CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 \
            CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 \
            HTTPS_PROXY=http://127.0.0.1:28787 \
            NODE_EXTRA_CA_CERTS=$certs \
            NO_PROXY=$np no_proxy=$np \
            claude $argv
    end
  '';

  # Stock settings. Variables a surrounding `claude` session exports are dropped too, so a
  # claude-plain started inside one does not inherit Code Mode, the 400K window or bili's
  # proxy. A user's own HTTPS_PROXY (any other value) is kept.
  environment.etc."fish/functions/claude-plain.fish".text = ''
    function claude-plain --wraps claude --description 'plain claude: no teamclaude, no bili, no Code Mode'
        set -l drop -u ANTHROPIC_BASE_URL -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE -u CLAUDE_CODE_AUTO_COMPACT_WINDOW
        for v in HTTPS_PROXY https_proxy
            test "$$v" = http://127.0.0.1:28787; and set -a drop -u $v
        end
        env $drop claude $argv
    end
  '';
}
