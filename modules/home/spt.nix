# Single Player Tarkov with Fika co-op, next to the live game of tarkov.nix. Imported by
# hosts/tarmantria/default.nix and hosts/tariognatha/default.nix, which also open Fika's ports.
#
# SPT needs an older client than live: SPT 4.1 runs on EFT 0.16.9.40743. `spt-setup` copies the
# live install into its own prefix at ~/Games/spt (~150 GB, reflinked where the filesystem can),
# downgrades the copy with the SPT team's delta patcher, then adds SPT and Fika on top. The live
# game and its prefix are never touched. Everything downloaded is looked up at run time, as
# tarkov-setup does, since the SPT team's builds move with every EFT patch; only the series
# and the Fika tags below are chosen here. Fika-Installer.exe wants admin rights and the
# Windows firewall, so the Fika files are unpacked by hand.
#
# `spt` runs the server natively, with the Nix ASP.NET Core 10, then SPT.Launcher.exe under umu
# like tarkov does. Offline: no BattlEye runtime. The server and the live game never run
# together, see exclusion in tarkov-common.nix. Layout follows MadByteDE's SPT-Linux-Guide.
# The server listens on all interfaces so Fika peers reach it; the hosts open the ports. With
# krane.spt.server set, `spt` runs no server and only checks that the remote one answers.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.krane.spt;

  # The SPT series to install, as the SPTVersion in the SPT team's release.json. It pins the
  # EFT client the copy is downgraded to and the ASP.NET Core major below.
  sptSeries = "4.1";
  # Fika releases built for that EFT client. Plugin tags come from project-fika/Fika-Plugin,
  # server tags from project-fika/Fika-Server-CSharp, which version separately.
  fikaPluginTag = "v2.4.6";
  fikaServerTag = "v2.4.2";
  # Where the SPT team publishes release.json (SPT builds) and mirrors.json (downgrade patches).
  sptMetadataUrl = "https://patcher.sp-tushonka.com";

  common = import ./tarkov-common.nix { inherit config lib pkgs; };
  # Trial: a newer GE-Proton than nixpkgs' for SPT only, for the client's post-raid hang.
  # Live Tarkov keeps the nixpkgs one from tarkov-common.nix.
  proton =
    (pkgs.proton-ge-bin.overrideAttrs (
      final: prev: {
        version = "GE-Proton11-11";
        # src comes from passthru.variants, which is overridden below.
        __intentionallyOverridingVersion = true;
        passthru = prev.passthru // {
          variants = prev.passthru.variants // {
            x86_64-linux = {
              toolName = "${final.version}-x86_64";
              src = pkgs.fetchzip {
                url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${final.version}/${final.version}-x86_64.tar.gz";
                hash = "sha256-3tVgf83IkteFtVo/bHd4yG1xCtPeuW8FXaTrHOLjvKQ=";
              };
            };
          };
        };
      }
    )).steamcompattool;
  env = common.umuEnv "$HOME/Games/spt" + ''
    export PROTONPATH="${proton}"
  '';

  # SPT 4.1's server targets .NET 10 and ASP.NET Core 10; a later SPT series needs a newer one.
  dotnet = pkgs.dotnet-aspnetcore_10;

  # hpatchz applies the patcher's deltas. Not in nixpkgs; the upstream binary is static, so it
  # runs on NixOS as is.
  hdiffpatch = pkgs.fetchzip {
    url = "https://github.com/sisong/HDiffPatch/releases/download/v5.1.3/hdiffpatch_v5.1.3_bin_linux64.zip";
    hash = "sha256-Qa9r0qHYPsbk1f7Qsy/PCbs7W4gAxdxZxWlRefGDNLo=";
    stripRoot = false;
  };

  # The live install's folder under the live prefix, and the SPT copy's under the SPT prefix.
  liveRoot = "$HOME/Games/tarkov/drive_c/Battlestate Games";
  sptDir = "$WINEPREFIX/drive_c/SPT";

  sptSetup = pkgs.writeShellApplication {
    name = "spt-setup";
    runtimeInputs = [
      pkgs.umu-launcher
      pkgs.curl
      pkgs.jq
      pkgs._7zz
      pkgs.unzip
      pkgs.xxd
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    text = ''
      ${env}
      sptseries='${sptSeries}'
      meta='${sptMetadataUrl}'
      cache="''${XDG_CACHE_HOME:-$HOME/.cache}/spt-setup"
      live_root="${liveRoot}"
      spt_dir="${sptDir}"
      hpatchz='${hdiffpatch}/linux64/hpatchz'
      mkdir -p "$cache"

      die() { echo "spt-setup: $*" >&2; exit 1; }

      # Every temp dir and the half-built copy go on exit, whether by die, a failed command or
      # Ctrl-C, so an interrupted run leaves nothing big behind.
      tmpdirs=()
      mktmp() { local d; d=$(mktemp -d "$cache/$1.XXXXXX") && tmpdirs+=("$d") && echo "$d"; }
      trap 'rm -rf "''${tmpdirs[@]}"' EXIT
      trap 'exit 130' INT TERM HUP

      # The SPT team's hashes are the base64 of the MD5.
      md5b64() { md5sum "$1" | cut -d' ' -f1 | xxd -r -p | base64; }

      # download <dest> <base64 md5> <url>...: resumes a partial file, tries each mirror in turn.
      download() {
        local dest=$1 hash=$2 url
        shift 2
        if [ -f "$dest" ] && [ "$(md5b64 "$dest")" = "$hash" ]; then return 0; fi
        for url in "$@"; do
          curl -fL --retry 3 -C - -o "$dest" "$url" || continue
          [ "$(md5b64 "$dest")" = "$hash" ] && return 0
          rm -f "''${dest:?}"
        done
        return 1
      }

      # The EFT build number, the last field of the exe's FileVersion (0.16.9.<build>).
      eft_build() {
        local out
        out=$(7zz l "$1")
        grep -m1 -o 'FileVersion:[^}]*' <<<"$out" | cut -d' ' -f2 | awk -F. '{ print $NF }'
      }

      # patch_files <patch dir> <game dir>: each file under the patch dir is a delta against, a
      # deletion of, or an addition of the game file of the same path, by its extension.
      patch_files() {
        local patches=$1 game=$2 f rel out n=0
        while IFS= read -r -d "" f; do
          rel=''${f#"$patches"/}
          out="$game/''${rel%.*}"
          case "$f" in
            *.delta)
              "$hpatchz" "$out" "$f" "$out.decoded" >/dev/null || return 1
              mv -f "$out.decoded" "$out" || return 1
              ;;
            *.del)
              rm -f "''${out:?}" || return 1
              rmdir --ignore-fail-on-non-empty "$(dirname "$out")" || return 1
              ;;
            *.new)
              mkdir -p "$(dirname "$out")" || return 1
              cp "$f" "$out" || return 1
              ;;
            *) return 1 ;;
          esac
          n=$((n + 1))
          [ $((n % 100)) -ne 0 ] || echo "  patched $n files"
        done < <(find "$patches" -type f -print0)
      }

      # stamp <name> [value]: the value last installed for that part of the SPT copy, kept in
      # the copy itself so a new copy starts with none. Without a value, prints it.
      stamp() {
        if [ "$#" -eq 2 ]; then echo "$2" >"$spt_dir/.spt-setup-$1"; return; fi
        cat "$spt_dir/.spt-setup-$1" 2>/dev/null || true
      }

      release=$(curl -fsSL "$meta/release.json" |
        jq -c --arg v "$sptseries" 'first(.Releases[] | select(.SPTVersion == $v))')
      [ -n "$release" ] || die "no SPT $sptseries in $meta/release.json"
      target=$(jq -r '.ClientVersion' <<<"$release")
      spt_hash=$(jq -r '.Mirrors[0].Hash' <<<"$release")
      mapfile -t spt_urls < <(jq -r '.Mirrors[].DownloadUrl' <<<"$release")
      # The launcher needs the version of the .NET desktop runtime that the release names.
      desktop=$(jq -r 'first(.RequiredRuntimes[] | select(.Identifier == "Microsoft.WindowsDesktop.App")) | .MinimumVersion' <<<"$release")
      [ -n "$desktop" ] && [ "$desktop" != null ] || die "release.json names no desktop runtime"

      # The prefix: Windows 8.1 as SPT's guide sets, vc++, BepInEx's winhttp.dll loaded as the
      # game's entry point (it is how the SPT client patches get in), and the empty Steam
      # library file the launcher looks for.
      mkdir -p "$WINEPREFIX"
      if [ ! -e "$WINEPREFIX/.spt-prefix-base" ]; then
        umu-run winetricks -q vcrun2022 win81
        umu-run reg add 'HKCU\Software\Wine\DllOverrides' /v winhttp /t REG_SZ /d native,builtin /f
        mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamapps"
        touch "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"
        touch "$WINEPREFIX/.spt-prefix-base"
      fi

      # The .NET desktop runtime for the launcher, the exact one the release asks for. Not
      # winetricks' dotnetdesktop9: SPT 4.1 wants 10.x. The marker holds the installed
      # version, so a prefix with another one is fixed on the next run. Microsoft's installer,
      # silent; the shared folder is checked afterwards as its exit codes vary.
      if [ "$(cat "$WINEPREFIX/.spt-desktop-runtime" 2>/dev/null || true)" != "$desktop" ]; then
        installer="$cache/windowsdesktop-runtime-$desktop-win-x64.exe"
        curl -fL --retry 3 -C - -o "$installer" \
          "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/$desktop/windowsdesktop-runtime-$desktop-win-x64.exe" ||
          die "desktop runtime $desktop download failed"
        umu-run "$installer" /install /quiet /norestart || true
        [ -d "$WINEPREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App/$desktop" ] ||
          die "desktop runtime $desktop did not install"
        rm -f "''${installer:?}"
        echo "$desktop" >"$WINEPREFIX/.spt-desktop-runtime"
      fi

      # The live client, copied then downgraded. Redone when the copy is not for the wanted
      # client, so a newer SPT series (or none yet) is picked up. The copy is built beside its
      # final place and swapped in only when patched, so an interrupted run leaves the old
      # copy; the SPT profiles are carried over.
      if [ ! -e "$spt_dir/EscapeFromTarkov.exe" ] || [ "$(stamp client)" != "$target" ]; then
        live=$(find "$live_root" -maxdepth 3 -name EscapeFromTarkov.exe -printf '%h\n' -quit 2>/dev/null || true)
        [ -n "$live" ] || die "no live EscapeFromTarkov.exe under $live_root. Install the game with tarkov first."
        build=$(eft_build "$live/EscapeFromTarkov.exe")
        [ -n "$build" ] || die "cannot read the live client version"
        echo "Live client $build, SPT $sptseries needs $target"

        work="$spt_dir.partial"
        tmpdirs+=("$work")
        rm -rf "''${work:?}" "''${spt_dir:?}.old"
        mkdir -p "$(dirname "$work")"
        echo "Copying the live game to $spt_dir (reflinked where possible)"
        cp -a --reflink=auto "$live" "$work"

        if [ "$build" != "$target" ]; then
          patch=$(curl -fsSL "$meta/mirrors.json" | jq -c --arg s "$build" --arg t "$target" '
            first(.Patches[] | select((.SourceClientVersion | tostring) == $s
              and (.TargetClientVersion | tostring) == $t))')
          [ -n "$patch" ] || die "no patcher from client $build to $target yet. The SPT team publishes one a while after each EFT patch."
          mapfile -t patch_urls < <(jq -r '.Mirrors[].Link' <<<"$patch")
          archive="$cache/patcher.7z"
          download "$archive" "$(jq -r '.Mirrors[0].Hash' <<<"$patch")" "''${patch_urls[@]}" ||
            die "patcher download failed"
          patches_tmp=$(mktmp patcher)
          7zz x -aoa -bso0 -bsp0 -o"$patches_tmp" "$archive"
          patch_dir=$(find "$patches_tmp" -type d -name '*SPT_Patches*' -print -quit)
          [ -n "$patch_dir" ] || die "no SPT_Patches in the patcher"
          echo "Downgrading $build to $target"
          patch_files "$patch_dir" "$work" || die "patching failed, the copy was removed"
          rm -rf "''${patches_tmp:?}" "''${archive:?}"
        fi

        # Move the old copy aside rather than into the new one's path, which would nest it.
        if [ -d "$spt_dir" ]; then
          if [ -d "$spt_dir/SPT_Runtime/user" ]; then
            mkdir -p "$work/SPT_Runtime"
            mv "$spt_dir/SPT_Runtime/user" "$work/SPT_Runtime/user"
          fi
          mv "$spt_dir" "$spt_dir.old"
        fi
        mv "$work" "$spt_dir"
        rm -rf "''${spt_dir:?}.old"
        stamp client "$target"
      fi

      # SPT: the BepInEx loader, the client plugins, SPT_Runtime with the server and launcher.
      # Extracted aside and copied over the game, so a failed extraction touches nothing and
      # the profiles in SPT_Runtime/user, which the archive does not contain, stay. Redone when
      # the release's archive changes.
      if [ ! -e "$spt_dir/SPT_Runtime/SPT.Server.Linux.dll" ] || [ "$(stamp spt)" != "$spt_hash" ]; then
        archive="$cache/spt.7z"
        download "$archive" "$spt_hash" "''${spt_urls[@]}" || die "SPT download failed"
        extract=$(mktmp spt)
        7zz x -aoa -bso0 -bsp0 -o"$extract" "$archive" || die "SPT extraction failed"
        cp -a --reflink=auto "$extract"/. "$spt_dir"/
        rm -rf "''${extract:?}" "''${archive:?}"
        stamp spt "$spt_hash"
      fi

      # The server listens on 127.0.0.1 by default, which Fika's other players cannot reach, so
      # bind every interface. backendIp is different: it is the address the server tells clients
      # to reach it on, so it must be one they can route to (public, LAN or VPN IP), never
      # 0.0.0.0. Left as is unless SPT_BACKEND_IP is given. Set on every run: an SPT reinstall
      # resets it.
      http="$spt_dir/SPT_Runtime/SPT_Data/configs/http.json"
      [ -f "$http" ] || die "no $http in the SPT install"
      jq --arg backend "''${SPT_BACKEND_IP:-}" \
        '.ip = "0.0.0.0" | if $backend != "" then .backendIp = $backend else . end' \
        "$http" >"$http.new"
      mv "$http.new" "$http"

      # Fika: the plugin unpacks into BepInEx/plugins/Fika, the server into
      # SPT_Runtime/user/mods/fika-server, both relative to the game root. Release notes name
      # the client each is built for. Redone when a tag below changes.
      fika() {
        local repo=$1 tag=$2 file=$3 body unpack
        body=$(curl -fsSL "https://api.github.com/repos/project-fika/$repo/releases/tags/$tag" |
          jq -r '.body' || true)
        grep -q "EFT [0-9.]*\.$target" <<<"$body" ||
          echo "warning: $repo $tag does not say it is built for client $target" >&2
        curl -fL --retry 3 -o "$cache/$file" \
          "https://github.com/project-fika/$repo/releases/download/$tag/$file"
        unpack=$(mktmp fika)
        unzip -oq "$cache/$file" -d "$unpack" || die "$file is not a valid archive"
        cp -a "$unpack"/. "$spt_dir"/
        rm -rf "''${unpack:?}" "''${cache:?}/''${file:?}"
      }
      fika_wanted='${fikaPluginTag} ${fikaServerTag}'
      if [ "$(stamp fika)" != "$fika_wanted" ]; then
        fika Fika-Plugin '${fikaPluginTag}' 'Fika.Release.${lib.removePrefix "v" fikaPluginTag}.zip'
        fika Fika-Server-CSharp '${fikaServerTag}' 'Fika.Server.Release.${lib.removePrefix "v" fikaServerTag}.zip'
        stamp fika "$fika_wanted"
      fi

      echo "Done. Start SPT with: spt"
    '';
  };

  spt = pkgs.writeShellApplication {
    name = "spt";
    # No gamemoderun, for the same reason as tarkov: the game is registered by PID instead.
    runtimeInputs = common.runtimeInputs ++ [
      dotnet
      pkgs.iproute2
      pkgs.libnotify
      pkgs.util-linux
    ];
    text = ''
      ${env}
      # Reported needed: Proton's Xalia accessibility layer hangs the launcher.
      export PROTON_USE_XALIA=0
      # The menu's TV videos (TUE_Main_Menu_Video) loop for the whole session, in raids too;
      # Wine decodes them in software on 3-4 threads at 100% each. No H.264 decoder, no videos.
      export WINEDLLOVERRIDES="msmpeg2vdec=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
      ${common.exclusion}
      ${common.gamePids}
      ensure_exclusive SPT "Escape from Tarkov" "$HOME/Games/tarkov"

      runtime="${sptDir}/SPT_Runtime"
      # krane.spt.server: the remote server to use, empty to run this install's own.
      remote=${lib.escapeShellArg (if cfg.server == null then "" else cfg.server)}
      # krane.spt.cpus: the CPUs the launcher and the game are confined to, empty for all.
      cpus=${lib.escapeShellArg (if cfg.cpus == null then "" else cfg.cpus)}
      if [ ! -e "$runtime/SPT.Launcher.exe" ] || { [ -z "$remote" ] && [ ! -e "$runtime/SPT.Server.Linux.dll" ]; }; then
        echo "No SPT in $runtime. Run spt-setup first." >&2
        exit 1
      fi

      ${common.primeEnv}
      ${common.renderEnv "SPT.Launcher.exe"}

      # alive <pid>: running, a zombie not yet reaped by us does not count.
      alive() {
        local st
        st=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
        case "''${st# }" in Z*) return 1 ;; *) return 0 ;; esac
      }

      server=
      stop_server() {
        [ -n "$server" ] || return 0
        kill "$server" 2>/dev/null || true
        for _ in $(seq 20); do
          alive "$server" || return 0
          sleep 0.5
        done
        kill -KILL "$server" 2>/dev/null || true
      }
      if [ -n "$remote" ]; then
        # A remote server (krane.spt.server): nothing to start, but the launcher only shows a
        # dead server as offline, so say so up front. The launcher keeps its own server list;
        # add the address there once with "Add new server".
        # The URL as the launcher takes it: scheme, host, then port, SPT's 6969 if none.
        hostport=''${remote#*://}
        hostport=''${hostport%%/*}
        host=''${hostport%:*}
        port=6969
        [ "$host" = "$hostport" ] || port=''${hostport##*:}
        # shellcheck disable=SC2016
        if ! timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
          msg="The SPT server at $remote does not answer."
          echo "$msg" >&2
          notify-send --urgency=critical --app-name=SPT SPT "$msg" || true
          exit 1
        fi
      else
        # The server is native. SPT.Server.Linux is a dynamically linked apphost that NixOS cannot
        # run, so run its dll on the Nix runtime instead. It has to start in SPT_Runtime, where
        # SPT_Data and user/ are. It keeps WINEPREFIX from above in its environment on purpose:
        # that is how prefix_pids finds it, for the exclusion with live Tarkov and for the
        # clean-up of a leftover one below. The Nix dotnet finds its own root, so DOTNET_ROOT is
        # not set: it would leak into umu and Wine, and break the Windows launcher's hostfxr.
        log="''${XDG_STATE_HOME:-$HOME/.local/state}/spt/server.log"
        mkdir -p "$(dirname "$log")"

        # A server left from an earlier run holds port 6969 and the profiles. Kill it, whichever
        # SPT script started it, and wait for the port.
        for pid in $(prefix_pids "$WINEPREFIX"); do
          read -r comm <"/proc/$pid/comm" 2>/dev/null || continue
          case "$comm" in dotnet*) kill -KILL "$pid" 2>/dev/null || true ;; esac
        done
        for _ in $(seq 20); do
          [ -z "$(ss -ltnH 'sport = :6969')" ] && break
          sleep 0.5
        done
        if [ -n "$(ss -ltnH 'sport = :6969')" ]; then
          echo "Port 6969 is in use by something else, not starting the SPT server." >&2
          exit 1
        fi

        trap stop_server EXIT
        (
          cd "$runtime"
          export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
          exec dotnet SPT.Server.Linux.dll
        ) >"$log" 2>&1 &
        server=$!

        # The listener on 6969 has to be our server: its process is alive and owns the port, so
        # a stranger on the port does not pass. Listening means the profile and mods are loaded;
        # the launcher cannot log in before. Checked on 127.0.0.1 although it binds all addresses.
        ours() { ss -ltnpH 'sport = :6969' | grep -q "pid=$server,"; }
        listening() { (exec 3<>/dev/tcp/127.0.0.1/6969) 2>/dev/null; }
        for _ in $(seq 120); do
          alive "$server" || { echo "SPT server exited, see $log" >&2; exit 1; }
          ours && listening && break
          sleep 1
        done
        if ! { alive "$server" && ours && listening; }; then
          echo "SPT server not listening on 6969 after 2 minutes, see $log" >&2
          exit 1
        fi
      fi

      ${common.session "Single Player Tarkov"}
      trap 'stop_server; session_end' EXIT

      cd "$runtime"
      # Unlike BSG's, the SPT launcher stays open while the game runs, and umu-run only returns
      # once it closes. Run it in the background and watch the game instead. With
      # krane.spt.cpus, taskset confines it before it starts, so every game thread inherits
      # the set; gamemoded's own pinning only comes once it has registered the game.
      if [ -n "$cpus" ]; then
        taskset -c "$cpus" umu-run SPT.Launcher.exe "$@" &
      else
        umu-run SPT.Launcher.exe "$@" &
      fi
      launcher=$!

      # Wait for the game, for as long as the launcher is open: the player may sit in it a
      # while, and on a cold prefix the game takes a while to appear after Start. Only this
      # prefix's game counts: live Tarkov's has the same name. The server has to outlive the
      # game, so the trap stops it only when this script ends.
      while alive "$launcher" && [ -z "$(game_pids "$WINEPREFIX")" ]; do
        sleep 2
      done
      while [ -n "$(game_pids "$WINEPREFIX")" ]; do
        sleep 5
      done

      # The game has exited: close the launcher with it. KILL, as for the exclusion: nothing in
      # the prefix needs a clean shutdown. That also ends umu's container and this session's
      # helpers in the prefix, the server included; prefix_pids skips this shell.
      if alive "$launcher"; then
        # shellcheck disable=SC2046
        kill -KILL $(prefix_pids "$WINEPREFIX") 2>/dev/null || true
      fi
      wait "$launcher" 2>/dev/null || true
    '';
  };

  # Greed.exe, the [SVM] Server Value Modifier's preset editor, in the SPT prefix. Presets are
  # written to this install's SPT_Runtime; a remote server needs them copied over and a restart.
  sptGreed = pkgs.writeShellApplication {
    name = "spt-greed";
    runtimeInputs = [ pkgs.umu-launcher ];
    text = ''
      ${env}
      export PROTON_USE_XALIA=0
      # Under X11 Greed dies on XI_BadDevice from X_GetDeviceButtonMapping when an input
      # device comes or goes; Wine's Wayland driver has no XInput.
      export PROTON_ENABLE_WAYLAND=1
      cd "${sptDir}"
      if [ ! -e Greed.exe ]; then
        echo "No Greed.exe in ${sptDir}. Install SVM's client part first." >&2
        exit 1
      fi
      exec umu-run Greed.exe "$@"
    '';
  };
in
{
  options.krane.spt.server = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "https://spt.example.org:6969";
    description = ''
      URL of a remote SPT server, as given to the launcher, for `spt` to use instead of
      starting its own. It must run the same SPT, Fika and server mods as this install's
      client side.
    '';
  };

  options.krane.spt.cpus = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "0-11";
    description = ''
      CPU list, in taskset's format, that `spt` confines the launcher and the game to, e.g.
      a hybrid CPU's P-cores, so Tarkov's main thread never lands on an E-core. Null for
      all CPUs.
    '';
  };

  config.home.packages = [
    sptSetup
    spt
    sptGreed
  ];

  config.xdg.desktopEntries.spt = {
    name = "SPT Tarkov";
    comment = "SPT with Fika through umu-launcher and GE-Proton, server run natively";
    exec = "${spt}/bin/spt";
    icon = "applications-games";
    categories = [ "Game" ];
  };

  config.xdg.desktopEntries.spt-greed = {
    name = "SPT Greed (SVM presets)";
    comment = "Server Value Modifier preset editor in the SPT prefix";
    exec = "${sptGreed}/bin/spt-greed";
    icon = "applications-games";
    categories = [ "Game" ];
  };
}
