# Steam opens its Friends List window on every client start since the 2023 UI rewrite, even with
# the window closed at last exit, and has no setting to stop it short of disabling "Sign in to
# Friends when Steam Client starts". This closes only the first Friends List window each Steam
# process maps, so friends sign-in stays on and opening the list by hand later still works.
#
# Steam's "Add desktop shortcut" writes only to ~/Desktop, which app launchers never scan, and
# sets Icon=steam. A path unit watches ~/Desktop and copies every Steam shortcut into
# ~/.local/share/applications with Icon=steam_icon_<appid>, the name Steam itself uses and
# Papirus themes. The game's 32x32 icon from Steam's library cache goes into hicolor as the
# fallback for themes without one, such as breeze-dark. Copies whose shortcut was deleted go too.
{ lib, pkgs, ... }:
let
  syncSteamShortcuts = pkgs.writeShellScript "sync-steam-shortcuts" ''
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.imagemagick ]}
    desktop="$HOME/Desktop"
    share="''${XDG_DATA_HOME:-$HOME/.local/share}"
    apps="$share/applications"
    icons="$share/icons/hicolor/32x32/apps"
    cache="$share/Steam/appcache/librarycache"
    marker="X-Steam-Shortcut-Source="
    mkdir -p "$apps" "$icons"

    # Point Icon= at the game and install that icon into hicolor. Non-Steam games added to
    # Steam have no library cache entry and keep Icon=steam.
    set_icon() {
      id=$(grep -m1 -o 'steam://rungameid/[0-9]*' "$1" | cut -d/ -f4)
      [ -n "$id" ] || return 0
      src=$(find "$cache/$id" -maxdepth 1 -name '*.jpg' 2>/dev/null | head -n1)
      [ -n "$src" ] || return 0
      [ -e "$icons/steam_icon_$id.png" ] || magick "$src" "$icons/steam_icon_$id.png"
      sed -i "s|^Icon=steam$|Icon=steam_icon_$id|" "$1"
    }

    for f in "$apps"/*.desktop; do
      [ -f "$f" ] || continue
      source=$(grep -m1 "^$marker" "$f" | cut -d= -f2-)
      if [ -n "$source" ] && [ ! -e "$source" ]; then rm "$f"; fi
    done

    for f in "$desktop"/*.desktop; do
      [ -f "$f" ] || continue
      grep -q '^Exec=.*steam://rungameid/' "$f" || continue
      target="$apps/$(basename "$f")"
      # Entries Steam itself wrote here only get their icon fixed.
      if [ -e "$target" ] && ! grep -q "^$marker" "$target"; then continue; fi
      { cat "$f"; echo "$marker$f"; } > "$target.tmp"
      set_icon "$target.tmp"
      mv "$target.tmp" "$target"
    done

    for f in "$apps"/*.desktop; do
      [ -f "$f" ] && grep -q '^Exec=.*steam://rungameid/' "$f" && set_icon "$f"
    done
    true
  '';
in
{
  systemd.user.services.sync-steam-shortcuts = {
    Unit.Description = "Copy Steam desktop shortcuts into the application menu";
    Service = {
      Type = "oneshot";
      ExecStart = "${syncSteamShortcuts}";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.paths.sync-steam-shortcuts = {
    Unit.Description = "Watch ~/Desktop for Steam shortcuts";
    Path = {
      PathChanged = "%h/Desktop";
      MakeDirectory = true;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # ii's activation deletes and re-copies ~/.local/share/icons, so reinstall the icons after it.
  home.activation.syncSteamShortcuts = lib.hm.dag.entryAfter [ "copyIllogicalImpulseConfigs" ] ''
    run ${syncSteamShortcuts}
  '';

  krane.hypr.extraGeneralLua = ''
    local steam_friends_closed = {}
    local function close_steam_startup_friends(w)
      if w and w.class == "steam" and w.title == "Friends List" and not steam_friends_closed[w.pid] then
        steam_friends_closed[w.pid] = true
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
      end
    end
    -- window.title too: Steam can map the window before it sets the final title.
    hl.on("window.open", close_steam_startup_friends)
    hl.on("window.title", close_steam_startup_friends)
  '';
}
