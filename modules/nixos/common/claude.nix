# `claude` in fish: Claude Code with experimental Code Mode -HTTPS_PROXY-> teamclaude's MITM
# (localhost:3456) -> Anthropic. `claude-plain` is stock Claude Code: no teamclaude, no Code
# Mode. The 400K auto-compact window is autoCompactWindow in ~/.claude/settings.json.
{ pkgs, ... }:
let
  curl = "${pkgs.curl}/bin/curl";
  grep = "${pkgs.gnugrep}/bin/grep";
in
{
  # teamclaude for any claude started outside these functions. ~/.claude/settings.json does not
  # set it: its env block overrides the launch env, which would turn Code Mode off in `claude`.
  environment.sessionVariables.ANTHROPIC_BASE_URL = "http://localhost:3456";

  # In /etc/fish for the same reason as shells.nix. `env` and `command` run the real claude
  # binary (fish functions are invisible to them), so neither function recurses.
  # HTTPS_PROXY, not the base URL, because Claude Code disables its experimental Code Mode
  # whenever ANTHROPIC_BASE_URL is custom (hence `env -u`). Claude Code must trust teamclaude's
  # MITM root CA (user accepted that risk), loaded only at startup via NODE_EXTRA_CA_CERTS.
  # teamclaude writes that CA (teamclaude-ca.pem in its own $XDG_CONFIG_HOME or ~/.config; the
  # service's environment may differ from the shell's, so both are tried) only on its first
  # MITM CONNECT after each start, so every launch first requests its built-in
  # www.example.org test host, which it answers itself with no credentials and no upstream
  # request (-k: the CA may not be trusted yet). It writes the file atomically, so the PEM end
  # marker means a complete file. The CA survives restarts; teamclaude replaces it only when its
  # leaf has under 30 days left or the intercept hosts change, and open sessions then need a
  # relaunch. Only api.anthropic.com (and the test host) is intercepted; every other CONNECT is
  # a blind tunnel, so subprocess tools (git, curl, MCP servers) keep normal TLS.
  # A pre-set NODE_EXTRA_CA_CERTS is merged into a bundle at a fixed runtime path that is never
  # deleted: processes the session starts (claude-mem worker, background jobs) inherit the path
  # and may outlive the session. A nested `claude` inherits that bundle or the CA itself and
  # reuses it instead of merging again. NO_PROXY keeps loopback traffic off the proxy; pre-set
  # values are kept.
  # teamclaude down: stop with a hint rather than silently going direct. CA still missing: run
  # through teamclaude's base URL instead (no Code Mode).
  environment.etc."fish/functions/claude.fish".text = ''
    function claude --wraps claude --description 'claude with Code Mode via teamclaude (MITM)'
        # Probe the port, not the unit: teamclaude may be started by hand, and the user bus may be
        # unreachable (ssh without linger, sudo -u). Any HTTP answer counts as up.
        if not ${curl} -s -o /dev/null -m 2 http://127.0.0.1:3456/
            echo "claude: teamclaude is not answering on 127.0.0.1:3456. Start it with `systemctl --user start teamclaude`, or use claude-plain to go direct." >&2
            return 1
        end
        set -l cas $HOME/.config/teamclaude-ca.pem
        set -q XDG_CONFIG_HOME; and test -n "$XDG_CONFIG_HOME"; and set cas $XDG_CONFIG_HOME/teamclaude-ca.pem $cas
        # Every launch, not only when the CA is missing: teamclaude mints its certificates on the
        # first CONNECT after each start and may replace the CA then (leaf near expiry, new
        # intercept hosts), so reading the file before that could pin a CA about to be replaced.
        # -m 10: minting a fresh CA and leaf on a slow host (Pi) can take seconds.
        ${curl} -sk -o /dev/null -m 10 --noproxy "" --proxy http://127.0.0.1:3456 https://www.example.org/
        # Newest complete candidate wins, so a stale copy in the other location never does.
        set -l ca
        for c in $cas
            if ${grep} -qs -e '-----END CERTIFICATE-----' $c
                if test -z "$ca"; or test $c -nt $ca
                    set ca $c
                end
            end
        end
        if test -z "$ca"
            echo "claude: teamclaude's MITM CA ($cas) is missing, running through its base URL (no Code Mode)" >&2
            # Routing set explicitly: a caller inside a `claude` session has the proxy and Code
            # Mode in its env and no base URL.
            env -u HTTPS_PROXY -u https_proxy -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE \
                ANTHROPIC_BASE_URL=http://localhost:3456 \
                claude $argv
            return
        end
        # The host's own name too: NixOS maps it to a loopback address, which teamclaude's tunnel
        # refuses (403), so local HTTPS from Bash-tool commands would break.
        set -l np localhost,.localhost,127.0.0.1,::1,$hostname
        # A bare `*` would exempt api.anthropic.com too and bypass teamclaude, so it is dropped.
        for v in $NO_PROXY $no_proxy
            set v (string split , -- $v | string match -rv -- '^\*?$' | string join ,)
            test -n "$v"; and set np $v,$np
        end
        # No runtime dir (ssh without a session, sudo -u): the cache home, never the config home.
        set -l runtime $XDG_RUNTIME_DIR
        if not test -n "$runtime"; or not test -d "$runtime"
            set runtime (set -q XDG_CACHE_HOME; and test -n "$XDG_CACHE_HOME"; and echo $XDG_CACHE_HOME; or echo $HOME/.cache)
            command mkdir -p $runtime
        end
        # Not the bili-era claude-ca.pem, so a bundle left by that route is never taken as current.
        set -l bundle $runtime/claude-teamclaude-ca.pem
        set -l certs $ca
        if test "$NODE_EXTRA_CA_CERTS" = $bundle
            # Nested launch. Reuse the bundle only while it still holds the current CA (teamclaude
            # may have replaced it, or the bundle predates this route); the certs it was merged
            # from are unknown here, so a stale bundle falls back to the CA alone.
            if test -r $bundle; and string match -q -- "*"(command cat $ca | string collect)"*" (command cat $bundle | string collect)
                set certs $bundle
            else
                echo "claude: $bundle lacks teamclaude's current CA, using the CA alone" >&2
            end
        else if test -n "$XDG_RUNTIME_DIR"; and test "$NODE_EXTRA_CA_CERTS" = $XDG_RUNTIME_DIR/claude-ca.pem; or string match -q -- '*/billion-context/*' "$NODE_EXTRA_CA_CERTS"
            # The retired billion-context route's bundle or bare root CA: never merged, since it
            # holds that MITM's root; the certs it was built from are unknown, so the CA alone is used.
            echo "claude: ignoring the old billion-context bundle $NODE_EXTRA_CA_CERTS, using teamclaude's CA alone" >&2
        else if test -r "$NODE_EXTRA_CA_CERTS"; and test "$NODE_EXTRA_CA_CERTS" != $ca
            # Write a unique temp file, then rename: a running session never reads a half-written
            # bundle, and two launches at once never share a temp file.
            set -l tmp (mktemp $runtime/claude-teamclaude-ca.XXXXXX)
            if test -n "$tmp"; and command cat $NODE_EXTRA_CA_CERTS $ca >$tmp; and command mv -f $tmp $bundle
                set certs $bundle
            else
                test -n "$tmp"; and command rm -f $tmp
                echo "claude: could not merge NODE_EXTRA_CA_CERTS with teamclaude's CA, using the CA alone" >&2
            end
        end
        env -u ANTHROPIC_BASE_URL \
            CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 \
            HTTPS_PROXY=http://127.0.0.1:3456 https_proxy=http://127.0.0.1:3456 \
            NODE_EXTRA_CA_CERTS=$certs \
            NO_PROXY=$np no_proxy=$np \
            claude $argv
    end
  '';

  # Stock settings. Variables a surrounding `claude` session exports are dropped too, so a
  # claude-plain started inside one does not inherit Code Mode or the teamclaude proxy. A user's
  # own HTTPS_PROXY (any other value) is kept.
  environment.etc."fish/functions/claude-plain.fish".text = ''
    function claude-plain --wraps claude --description 'plain claude: no teamclaude, no Code Mode'
        set -l drop -u ANTHROPIC_BASE_URL -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE
        for v in HTTPS_PROXY https_proxy
            test "$$v" = http://127.0.0.1:3456; and set -a drop -u $v
        end
        env $drop claude $argv
    end
  '';
}
