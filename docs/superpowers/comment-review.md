# Comment review list

Why/workaround notes that could not be verified from the repo. They are unchanged in the code.
For each: keep, trim, or delete. This file is deleted before `doc-cleanup` merges.

## modules/nixos

- `modules/nixos/common/claude.nix:1-3` Header: 400K auto-compact window is `autoCompactWindow` in `~/.claude/settings.json`. settings.json is not in the repo.
- `modules/nixos/common/claude.nix:10-34` teamclaude/Claude Code behaviour (Code Mode off with custom base URL, CA on first MITM CONNECT, 30-day leaf, only api.anthropic.com intercepted). External tool.
- `modules/nixos/common/claude.nix:37-40` teamclaude relays unknown paths to api.anthropic.com. External behaviour.
- `modules/nixos/common/claude.nix:69-70` NixOS maps host name to loopback, teamclaude tunnel refuses it (403). External behaviour.
- `modules/nixos/desktop/bluetooth.nix:6` Needed by headset/battery profiles the ii widgets poll. ii and BlueZ behaviour.
- `modules/nixos/desktop/bluetooth.nix:10-34` agent-helper.c EOF / `RequestPinCode` crash analysis, reason for `startLimitIntervalSec = 0`. Upstream bluez-tools source.
- `modules/nixos/desktop/desktop.nix:29-35` greetd 0.10.3 `/run/greetd.run` gates autologin once per boot; NixOS restart=false on pre-0.9 assumption. greetd/NixOS internals.
- `modules/nixos/desktop/hardware.nix:3-4` iwlwifi firmware off by default breaks Wi-Fi on tarmantria. Hardware quirk.
- `modules/nixos/desktop/gaming.nix:21-22` Split-lock slowdown and Steam Deck kernel. Kernel/hardware.
- `modules/nixos/gpu/nvidia-desktop.nix:3-6` Key confirmed independently; cachix CUDA cache returns 401 (also contains a "do not re-add" rule). External service.
- `modules/nixos/gpu/nvidia-desktop.nix:26-27`, `modules/nixos/gpu/nvidia-prime.nix:50-51` Stable 595 has NVENC API 13.0, gpu-screen-recorder needs 13.1. Driver/gsr versions.
- `modules/nixos/gpu/nvidia-prime.nix:24` No default for `hardware.nvidia.open` on this nixpkgs rev. nixpkgs option default.
- `modules/nixos/server/networking.nix:17-21` Fritzbox IPv6 DNS did not answer on taragarmr (2026-11-14). Dated network incident.
- `modules/nixos/server/auto-upgrade.nix:104-105` Upstream already adds --refresh and `--flake <this>`. nixpkgs autoUpgrade internals.
- `modules/nixos/server/base.nix:3-4` `--sudo --ask-sudo-password` work on both nixos-rebuild-ng generations. Tool version behaviour.

## modules/home

- `desktop/apps.nix:10-13` Upstream bundles Electron 40; Electron 44 clipboard returns Promises; 43 newest sync. Upstream Electron/APT.
- `desktop/apps.nix:15-21` APT overlay X11-only; Windowed Fullscreen, "Confine Mouse to Window" off in PoE. Wine/Hyprland runtime.
- `desktop/proton-drive.nix:42` `fuse` (2.x) not `fuse3`: rclone mount needs classic `fusermount`. rclone behaviour.
- `desktop/hypr-config.nix:4-8` Hyprland sourcing order of `dots/.config/hypr/hyprland.lua`. External pinned repo.
- `desktop/hypr-config.nix:56-58` Hyprland Lua config rewrites `-` to `_` and `:` to `.` in keys. Upstream.
- `desktop/hypr-config.nix:121-123` Color fields checked against Hyprland 0.56 Lua monitor parser; unknown field is hard error. Upstream source.
- `desktop/tarkov.nix:20-21` Launcher refuses to start game unless BattlEye service registered. BSG launcher.
- `desktop/tarkov.nix:51-53` gamemoderun preload cannot see libgamemode.so in umu's container. Runtime.
- `desktop/tarkov.nix:60-62` Proton swaps BEClient for runtime's Linux one; else BATTLEYE_ServiceNotRunningProperly. BattlEye/Proton.
- `desktop/tarkov.nix:87` Launcher is CEF-based, hangs on software rasterizer under Proton. Upstream.
- `desktop/tarkov-common.nix:70` umu-default: GE-Proton's Tarkov protonfix expects Steam layout. GE-Proton.
- `desktop/tarkov-common.nix:83-86` pressure-vessel imports host MangoHud layer; blacklist keeps it off launcher. Container layers.
- `desktop/tarkov-common.nix:88-93` vkBasalt reaches DXVK in umu container, tints launcher; GE-Proton bundled vkBasalt applied LUT twice. Container/GE-Proton.
- `desktop/tarkov-common.nix:101-103` Replay buffer holds ~220 MiB VRAM, keeps NVENC busy; Tarkov fills 8 GiB. Measurement.
- `desktop/spt.nix:285-287` Proton's Xalia layer hangs launcher; menu TV videos decode on 3-4 threads at 100%. Proton/Wine.
- `desktop/spt.nix:437-438` Under X11 Greed dies on XI_BadDevice on input hotplug; Wayland driver has no XInput. Wine.
- `desktop/recording.nix:15-31` config_ui format, gsr-ui defaults and hotkey grabbing, Config.cpp line refs. Upstream source.
- `desktop/recording.nix:37-55` PRIME offload, NVENC API 13.0 vs 13.1 on nvidia 595, 20% FPS cost, overlay freeze. Hardware/driver.
- `desktop/recording.nix:81` Peripheral batteries report scope Device. Kernel.
- `desktop/recording.nix:93` simpledrm has no vendor; skip connectors. Kernel.
- `desktop/recording.nix:111-112` Hyprland exec_cmd detaches script; logind keeps leftovers. Hyprland/logind.
- `desktop/recording.nix:118-120` gsr-ui ignores SIGTERM; force-kill leaves replay recorder running. Upstream.
- `desktop/recording.nix:133-134` Regular recording holds unsaved work; replay restarts with gsr-ui. Upstream.
- `desktop/recording.nix:165-167` Power plug events arrive as `power_supply` change uevents; 30 s read timeout. Kernel.
- `desktop/recording.nix:226-229` gsr-ui rewrites config_ui when settings page closes. Upstream source.
- `desktop/illogical-impulse.nix:31-32` Hardcoded `$HOME/.config` must match soymou module's `targetPath` (also a keep-in-sync rule). External flake input.
