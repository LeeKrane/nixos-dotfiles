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
