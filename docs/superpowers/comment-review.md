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

## modules/nixvim

- `completion.nix:42` cmp.accept() (blink.cmp 1.10.2) returns nil when nothing selected. blink.cmp ships bytecode only.
- `lang/data.nix:7` nixpkgs has no jsonc treesitter grammar; json parser for jsonc. nixpkgs grammar set.
- `lang/default.nix:34` Gating here, not conform condition, which would block manual formatting. conform behaviour.
- `lang/default.nix:71` Timed-out format still saves unformatted, with notification. conform behaviour.
- `lang/go.nix:25` goimports wrapper references nixpkgs go, so go is in editor closure. Package internals.
- `lang/python.nix:44` venv-selector v2 API (nixvim example shows v1 keys). nixvim example.
- `lang/rust.nix:9` rustaceanvim 9.2.2 busted suite fails under neovim 0.12.6. Not reproducible here.
- `lang/rust.nix:25` completion.crates feeds LSP completion (crates.nvim common.lua). Bytecode only.
- `options.nix:27` No system clipboard over SSH (OSC 52 reads block). Terminal behaviour.
- `options.nix:55` Theme sets GUI colours only; force on where truecolor detection fails. Terminal behaviour.
- `tools.nix:35` UI tests time out under qemu (aarch64 via binfmt). Build timing.
- `lua/dynamic-theme.lua:4` colors.json ignored: written ~330 ms earlier by other generator, disagrees with scss. External generator timing.
- `tests/keymaps_spec.lua:48` Other plugins' global handlers (nvim-jdtls) would fail on fake id. Plugin internals.
- `tests/completion_spec.lua:63` blink.cmp 1.10 normalizes boolean|function fields to functions. Bytecode only.
- `tests/lang_go_spec.lua:39` gopls root_dir shells out to go env synchronously. lspconfig source not local.
- `tests/lang_rust_spec.lua:42` crates.nvim 0.7.x keeps config in crates.state.cfg. Bytecode only.
- `tests/options_spec.lua:59` vim.v.progpath is unwrapped binary (missing lz.n); use nvim on PATH. Runtime.
- `lang/default.nix:30` (lead-in restored for the :34 note above).

## hosts and templates

- `hosts/taractias/default.nix:49` QCA9377 on ath10k_pci floods AMD-Vi IO_PAGE_FAULT (before `iommu=pt`). Hardware quirk.
- `hosts/taractias/display.nix:1` VERIFY ON TARGET: IdeaPad 330S ships in several panel resolutions. Hardware fact.
- `hosts/taragarmr/couchdb.nix:~14` Entrypoint chowns `/opt/couchdb`, fails on read-only bind mount; ini copied first. Docker image.
- `hosts/taragarmr/couchdb.nix:~27` 5984 is couchdb uid/gid in image. Image internals.
- `hosts/taragarmr/spt.nix:~55` Server takes ~30 s to listen; headless gets Connection refused. Runtime timing.
- `hosts/taragarmr/spt.nix:~83` Headless leaks memory over raids; restart on exit. Runtime.
- `hosts/taragarmr/spt.nix:~98` Old /etc/hosts entry: server hands this name out as backend address. SPT server.
- `hosts/taragarmr/spt.nix:~106` Wine and headless software rendering (PROTON_USE_WINED3D) need Mesa/GL. Upstream.
- `hosts/tariognatha/default.nix:~31`, `hosts/tarmantria/default.nix:~39` SPT server hands out spt-tarkov.krane.dev as backend. SPT server.
- `hosts/tariognatha/default.nix:~35` No CPU mitigations: i9-9900KS pays heavily. Perf/security trade-off.
- `hosts/tariognatha/default.nix:~60` Wake-on-LAN block (I219-V PHY dead, board cuts USB power, poweroff suspends). Hardware.
- `hosts/tariognatha/display.nix:~22` Hyprland has no primary monitor: lowest monitor ID. Upstream.
- `hosts/tariognatha/display.nix:~26` Auto-HDR modesets DP-2, blanks 4K240 panel. Hardware/Hyprland.
- `hosts/tariognatha/easyeffects.nix:1-6` EasyEffects started by ii's hyprland/execs.lua on every host. Upstream ii source.
- `hosts/tariognatha/easyeffects.nix:~9` Autoload file naming `<node>:<route description>.json`. EasyEffects.
- `hosts/tariognatha/easyeffects.nix:~13` Worker threads fall behind at default priority under load. Perf claim.
- `hosts/tariognatha/easyeffects.nix:~22` `processAllOutputs` / `listenToMic` rationale. EasyEffects.
- `hosts/tarmantria/audio.nix:6-12` ACP mic path names; G6 exposes "External Mic"; ACP search order. ACP/hardware.
- `hosts/tarmantria/default.nix:~19` zram 200: Tarkov keeps ~9 GiB resident on 16 GiB laptop. Measurement.
- `hosts/tarmantria/default.nix:~22` lz4 vs zstd stutter. Perf claim.
- `hosts/tarmantria/default.nix:~27` nvidia-powerd 80 W base, 140 W max. Hardware figures.
- `hosts/tarmantria/default.nix:~45` i7-13700H P-cores / E-cores 12-19. Hardware fact.
- `hosts/tarmantria/display.nix:~21` MSI MAG322CQRV EDID 143.97 Hz over HDMI; Hyprland picks 59.95 Hz. EDID.
- `hosts/tarmantria/display.nix:~5` Panel eDP-1 in hybrid, eDP-2 in dgpu mode. Hardware.
- `hosts/tarmantria/ec-wake.nix:1-9` ACPI/EC wake explanation (GPE 0x02, `_L02`, `_PRW`). Firmware.
- `hosts/tarmantria/gpu-mux.nix:1-9` MUX hybrid/dgpu behaviour, `pending_reboot`. Firmware.
- `hosts/tarmantria/gpu-mux.nix:~86` SYSTEMD_WANTS fires only on add; BAT0 sends change per capacity update. udev/hardware.
- `hosts/taronychus/default.nix:~7` BOOT_ORDER 0xf461 / 0xf416 both reach NVMe. Pi firmware.
- `hosts/taragarmr/default.nix`, `hosts/tarritator/default.nix`, `hosts/tarronax/default.nix` Headers: board specs and install steps. External state.
- `hosts/tariognatha/display.nix:38` VERIFY ON TARGET: name must match `hyprctl devices`. Needs physical device.

## lib, flake.nix, overlays

- `flake.nix:43` Pinned past soymou's May 2026 quickshell (fails vs Qt 6.12), fixed upstream 5d5d498 / 1c1cc91. Unlinked upstream.
- `flake.nix:255` rpi5 installer image: no keys, empty root password, console only. Upstream image.
- `flake.nix:668` tariognatha suspends instead of poweroff (WoL); ii search runs bash -c ignoring aliases. ii/hardware.
- `lib/mk-host.nix:43` RPi: only plain overlays injected, else miss nixos-raspberrypi cache. Upstream cache.
- `lib/mk-host.nix:105` soymou activation replaces ~/.config/fish each switch. soymou module.
- `lib/mk-host.nix:117` HM level, not NixOS: soymou #19 dconf error. Upstream issue.
- `lib/wireguard.nix:42` Android WireGuard app needs PersistentKeepalive = 25. Android app.
- `lib/lan.nix:13` Second LAN; tariognatha USB adapter wakes it; tarronax sends magic packet. Network/hardware.
- `overlays/ani-cli.nix:1` nixpkgs ani-cli 5.0 provider down (503); master 5.1.4 moved to hianime.at. Upstream status.
- `overlays/dolphin-darkly-selection.nix:1` Dolphin 26.08 selection-text colour note. Upstream.
- `overlays/gsr-ui-fractional-scale.nix:1` gsr-ui fractional-scale note. Upstream.

## scripts, install.sh, justfile, .github

- `install.sh:665-670` taractias live ISO DNS timed out on cache.nixos-cuda.org. Observed, unrecorded.
- `install.sh:1403-1405` Under 24 GiB: eval heap ~5 GiB plus C++ compiles. Measured.
- `install.sh:1555-1559` Live ISO no swap; nixos-install one job at half cores. Measured.
- `install.sh:1864-1867` sops exits 200 on unchanged file, 128 on undecryptable (sops 3.13.3). sops binary.
- `install.sh:1953-1954` hyprctl exits 0 on errors; stdout/stderr split. hyprctl binary.
- `scripts/ani-cli-launcher.sh:17` Termux refuses RUN_COMMAND unless allow-external-apps. Termux.
- `scripts/ani-cli-termux.sh:18` Termux package lags working provider. External.
- `scripts/ani-cli-termux.sh:30` full-upgrade first; stale Termux breaks libcurl. Termux.
- `scripts/ani-cli-termux.sh:38` No recommends: ffmpeg pulls ~340 MB clang. Termux deps.
- `scripts/ani-cli-termux.sh:41` Termux:Widget shortcuts. Termux.
- `scripts/docker-check.sh:20` filter-syscalls=false works around seccomp in Nix sandbox. Docker.
- `scripts/docker-check.sh:57` libgit2 refuses unowned bind-mounted repo. libgit2.
- `scripts/update-select-lanes.sh:6` mergeable computed lazily; UNKNOWN polled. GitHub API.
- `.github/workflows/update-lane.yml:171` git restore --worktree deletes path missing at ref. git semantics.
- `.github/workflows/update-lane.yml:192` vulnix exit codes 0/1/2. External.
- `scripts/flake-update-notify.sh:55` Not up yet at login retries silently. Login timing.
- `scripts/server-upgrade-report.sh:100` Close only issues whose SHA is ancestor. GitHub compare API.
- `install.sh:181` LC_ALL=C keeps [@-~] a byte range under UTF-8 sed. sed locale.
- `install.sh:1374` nixos-install resumes from copied paths; transient failure costs 10 s. Nix behaviour.
- `.github/workflows/update-lane.yml:3` Called workflow sharing caller's concurrency group deadlocks. GitHub Actions.
