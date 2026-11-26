# SPT 4.1.6 + Fika: the server and two headless raid hosts as lingering home-manager user
# services, plus the daily profile backup timer.
#
# The data is not managed by Nix: ~/spt-server, ~/spt-headless and ~/spt-headless-2. The second
# headless unit runs ~/spt-headless/run-headless.sh with SPT_HEADLESS_ROOT=~/spt-headless-2.
# Proton comes from nixpkgs proton-ge-bin through PROTONPATH instead of umu's own download.
#
# Ports: the server listens on TCP 6969, 7828, 7829 and 38473; the headless clients are Fika
# raid hosts on UDP 25565 and 25566. Players arrive through wg1 (manual start, see the wireguard
# module) or wg0, which is trusted, so the ports are opened on wg1 only. The headless clients
# reach the server over loopback.
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

  # Everything the restored scripts call (run-headless.sh, backup-profiles.sh, the wait below),
  # plus bash for their shebangs.
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
  # NixOS has no /bin/bash: run the restored scripts through bash instead of exec'ing them.
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
    # The three SPT services share this slice; its 20G/22G protects the system, CouchDB and Caddy
    # on the 27 GiB host. Per-unit caps sit below it but sum above: one leaking instance is
    # throttled first, the slice stops all three together from exceeding RAM.
    systemd.user.slices.spt = {
      Unit.Description = "SPT server and headless clients";
      Slice = {
        MemoryHigh = "20G";
        MemoryMax = "22G";
      };
    };

    systemd.user.services = {
      spt-server = {
        # No network ordering: network-online.target is not part of the user manager.
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
