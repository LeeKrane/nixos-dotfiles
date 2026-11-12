# SPT 4.1.6 + Fika: the server and two headless raid hosts, as home-manager user services of the
# login account (lingering, so they run without a session), plus the daily profile backup timer.
# The unit files follow the old Fedora host's ~/.config/systemd/user, minus everything Vagabond.
#
# The data is not managed by Nix: ~/spt-server (SPT_Runtime, backup-profiles.sh, backups),
# ~/spt-headless and ~/spt-headless-2 (game, pfx, HeadlessConfig.json, run-headless.sh) are
# restored from the old host. Note the second headless unit runs ~/spt-headless/run-headless.sh
# with SPT_HEADLESS_ROOT=~/spt-headless-2, as the old unit did.
#
# Runtime deps replace the Fedora system packages on the units' PATH: ASP.NET Core 10 (the old
# host had 10.0.12; SPT 4.1 targets .NET 10), umu-launcher, xvfb-run, jq and what the scripts call
# (ss, grep, tar, gzip, xargs). Proton comes from the nixpkgs proton-ge-bin through PROTONPATH
# instead of umu's own download; unset it in the unit to let umu fetch its default again.
#
# Ports: the server listens on TCP 6969, 7828, 7829 and 38473 (dotnet, inventory); the
# headless clients are Fika raid hosts on UDP 25565 and 25566 that players connect to. Players
# arrive through wg1 (manual start, see the wireguard module) or wg0, which is trusted, so the
# ports are opened on wg1 only. The headless clients reach the server over loopback.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.krane.user.name;
  tcpPorts = [
    6969
    7828
    7829
    38473
  ];
  udpPorts = [
    25565
    25566
  ];

  dotnet = pkgs.dotnet-aspnetcore_10;
  proton = pkgs.proton-ge-bin.steamcompattool;

  # Everything the restored scripts call (run-headless.sh: jq, xvfb-run, umu-run; backup-profiles.sh:
  # tar, gzip, date, ls, tail, xargs, rm; the wait below: ss, grep), plus bash for their
  # `#!/usr/bin/env bash` / `#!/bin/bash` shebangs. One list for all units: they are small.
  sptPath = lib.makeBinPath [
    dotnet
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.gnutar
    pkgs.gzip
    pkgs.iproute2
    pkgs.procps
    pkgs.jq
    pkgs.curl
    pkgs.xvfb-run
    pkgs.umu-launcher
  ];
  # The restored scripts may carry a Fedora `#!/bin/bash` shebang, and NixOS has no /bin/bash,
  # so the units run them through bash explicitly instead of exec'ing them.
  bash = "${pkgs.bash}/bin/bash";

  # The server takes ~30 s to listen after a (re)start, which systemd also restarts the
  # headless units with; a headless that starts first gets "Connection refused" and hangs.
  waitFor6969 = pkgs.writeShellScript "wait-for-6969" ''
    export PATH=${sptPath}
    for i in $(seq 120); do
      ss -ltnH 'sport = :6969' | grep -q . && exit 0
      sleep 2
    done
    exit 1
  '';

  headless = description: memHigh: memMax: extraEnv: {
    Unit = {
      Description = description;
      After = [ "spt-server.service" ];
      Requires = [ "spt-server.service" ];
    };
    Service = {
      Type = "simple";
      Environment = [
        "PATH=${sptPath}"
        "PROTONPATH=${proton}"
      ]
      ++ extraEnv;
      ExecStartPre = "${waitFor6969}";
      TimeoutStartSec = 300;
      Slice = "spt.slice";
      ExecStart = "${bash} %h/spt-headless/run-headless.sh";
      # The headless leaks memory over raids; restart it on exit. The per-unit caps keep one
      # leaking instance from eating the slice; spt.slice below is the real guard.
      Restart = "always";
      RestartSec = 15;
      MemoryHigh = memHigh;
      MemoryMax = memMax;
      TimeoutStopSec = 30;
      KillMode = "control-group";
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  users.users.${user}.linger = true;

  # The old /etc/hosts entry: the server hands this name out as its backend address.
  networking.hosts."127.0.0.1" = [ "spt-tarkov.krane.dev" ];

  networking.firewall.interfaces.wg1 = {
    allowedTCPPorts = tcpPorts;
    allowedUDPPorts = udpPorts;
  };

  # Wine and the headless client's software rendering (PROTON_USE_WINED3D) need Mesa/GL.
  hardware.graphics.enable = true;

  home-manager.users.${user} = {
    # The three SPT services share this slice. The host has 27 GiB: the slice's 20G/22G is what
    # actually protects the system, CouchDB and Caddy (~5 GiB left). The per-unit caps are
    # lower than the slice's, and they sum to more than it on purpose: one leaking instance
    # is throttled on its own first, while the slice stops all three together from exceeding RAM.
    systemd.user.slices.spt = {
      Unit.Description = "SPT server and headless clients";
      Slice = {
        MemoryHigh = "20G";
        MemoryMax = "22G";
      };
    };

    systemd.user.services = {
      spt-server = {
        # No network ordering (network-online.target is not part of the user manager, so it
        # would be ignored): the server and backup-profiles.sh only touch local files and bind
        # local ports, and Restart=on-failure covers anything else.
        Unit.Description = "SPT 4.1.6 server (Fika backend, TCP 6969)";
        Service = {
          Type = "simple";
          Environment = [ "PATH=${sptPath}" ];
          Slice = "spt.slice";
          WorkingDirectory = "%h/spt-server/SPT_Runtime";
          ExecStartPre = "${bash} %h/spt-server/backup-profiles.sh";
          ExecStart = "${dotnet}/bin/dotnet SPT.Server.Linux.dll";
          Restart = "on-failure";
          RestartSec = 10;
          MemoryHigh = "5G";
          MemoryMax = "6G";
          TimeoutStopSec = 120;
        };
        Install.WantedBy = [ "default.target" ];
      };

      spt-headless = headless "Fika headless client 1 (main server raid host, UDP 25565)" "9G" "11G" [ ];
      spt-headless-2 = headless "Fika headless client 2 (main server raid host, UDP 25566)" "9G" "11G" [
        "SPT_HEADLESS_ROOT=%h/spt-headless-2"
      ];

      spt-backup = {
        Unit.Description = "Back up SPT profiles";
        Service = {
          Type = "oneshot";
          Environment = [ "PATH=${sptPath}" ];
          ExecStart = "${bash} %h/spt-server/backup-profiles.sh";
        };
      };
    };

    systemd.user.timers.spt-backup = {
      Unit.Description = "Daily SPT profile backup";
      Timer = {
        OnCalendar = "*-*-* 05:00";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
