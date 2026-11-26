{
  description = "NixOS + Hyprland (illogical-impulse) dotfiles flake, one nixosConfiguration per hosts/ directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Stable channel for server hosts; mk-host.nix swaps these in under the unstable names.
    # Follows nixos-raspberrypi's pin so the Pis use its binary cache.
    nixpkgs-stable.follows = "nixos-raspberrypi/nixpkgs";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # Not following our nixpkgs: the cache only holds what its own pin builds.
    };
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    nixvim-stable.url = "github:nix-community/nixvim/nixos-26.05";

    dots-hyprland = {
      url = "git+https://github.com/end-4/dots-hyprland?submodules=1";
      flake = false;
    };

    illogical-flake = {
      url = "github:soymou/illogical-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dotfiles.follows = "dots-hyprland";
      inputs.quickshell.follows = "quickshell";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell?rev=9b0f339b19057f4731bf3b48293307d7ef241671";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    disko.url = "github:nix-community/disko";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    nix-index-database.url = "github:nix-community/nix-index-database";

    # No `nixpkgs.follows`: nixvim is tested against its own pin.
    nixvim.url = "github:nix-community/nixvim";

    # No `nixpkgs.follows`: its modules aren't pinned to a nixpkgs revision.
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  # No flake-level nix config: nix prompts to accept it on every invocation, which hangs direnv.

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      overlaysList = import ./overlays;
      pkgs = import nixpkgs {
        inherit system;
        overlays = overlaysList;
        config.allowUnfree = true;
      };
      mkHost = import ./lib/mk-host.nix { inherit inputs; };

      # Built with this flake's pkgs so overlays and allowUnfree apply; nixvim's pin only evaluates its library.
      nvimEval = inputs.nixvim.lib.evalNixvim {
        modules = [
          ./modules/nixvim
          { nixpkgs.pkgs = pkgs; }
        ];
      };
      nvim = nvimEval.config.build.package;

      nvimStableEvalFor =
        sys:
        inputs.nixvim-stable.lib.evalNixvim {
          modules = [
            ./modules/nixvim
            {
              nixpkgs.pkgs = import inputs.nixpkgs-stable {
                system = sys;
                overlays = overlaysList;
                config.allowUnfree = true;
              };
            }
          ];
        };
      nvimStableEval = nvimStableEvalFor system;
      nvimStableFor = sys: (nvimStableEvalFor sys).config.build.package;
      nvim-stable = nvimStableEval.config.build.package;

      hosts = nixpkgs.lib.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      );

      hostMeta = nixpkgs.lib.genAttrs hosts (
        name:
        let
          file = ./hosts/${name}/host.nix;
          given = if builtins.pathExists file then import file else { };
          board = given.board or null;
          meta = {
            system = if board == null then system else "aarch64-linux";
            role = if board == null then "desktop" else "server";
            inherit board;
            image = null;
          }
          // given;
          unknown = builtins.filter (
            a:
            !builtins.elem a [
              "system"
              "role"
              "board"
              "image"
            ]
          ) (builtins.attrNames given);
        in
        assert nixpkgs.lib.assertMsg (builtins.isAttrs given)
          "hosts/${name}/host.nix: must evaluate to an attribute set { system, role, board, image }, got ${builtins.typeOf given}";
        assert nixpkgs.lib.assertMsg (unknown == [ ])
          "hosts/${name}/host.nix: unknown attribute(s) ${toString unknown}; only system, role, board and image are allowed";
        assert nixpkgs.lib.assertMsg (builtins.elem meta.role [
          "desktop"
          "server"
        ]) "hosts/${name}/host.nix: role must be \"desktop\" or \"server\", got \"${toString meta.role}\"";
        assert nixpkgs.lib.assertMsg (builtins.elem meta.board [
          null
          "rpi4"
          "rpi5"
        ]) "hosts/${name}/host.nix: board must be \"rpi4\" or \"rpi5\", got \"${toString meta.board}\"";
        assert nixpkgs.lib.assertMsg (builtins.elem meta.image [
          null
          "sd"
        ]) "hosts/${name}/host.nix: image must be \"sd\" or absent, got \"${toString meta.image}\"";
        assert nixpkgs.lib.assertMsg (
          meta.image == null || meta.board != null
        ) "hosts/${name}/host.nix: image \"${toString meta.image}\" needs a board";
        assert nixpkgs.lib.assertMsg
          (meta.board == null || (meta.system == "aarch64-linux" && meta.role == "server"))
          "hosts/${name}/host.nix: board ${toString meta.board} needs system aarch64-linux and role \"server\"";
        meta
      );
      # Pi hosts: CI builds x86_64 only, so they are evaluated (checks.pi-eval) and exposed as image packages.
      piHosts = builtins.filter (name: hostMeta.${name}.board != null) hosts;
      sdImageHosts = builtins.filter (name: hostMeta.${name}.image == "sd") piHosts;
      desktopHosts = builtins.filter (name: hostMeta.${name}.role == "desktop") hosts;
      serverHosts = builtins.filter (name: hostMeta.${name}.role == "server") hosts;
      upgradeExpectationsFor =
        name:
        let
          cfg = self.nixosConfigurations.${name}.config;
          au = cfg.system.autoUpgrade;
          upgrade = cfg.systemd.services.nixos-upgrade;
        in
        [
          {
            ok = au.enable && au.allowReboot && au.flake == "github:LeeKrane/nixos-dotfiles/deploy#${name}";
            what = "${name}: system.autoUpgrade does not follow the deploy branch with reboots allowed";
          }
          {
            ok =
              upgrade.onFailure == [ "server-upgrade-failed.service" ]
              && nixpkgs.lib.hasSuffix " post" (toString upgrade.serviceConfig.ExecStartPost)
              && nixpkgs.lib.hasSuffix " condition" (toString upgrade.serviceConfig.ExecCondition);
            what = "${name}: the upgrade hooks (condition, post, OnFailure) are not wired";
          }
          {
            ok = cfg.krane.autoUpgrade.allHealthChecks != [ ];
            what = "${name}: no health check configured for the upgrade";
          }
        ];
    in
    {
      lib.hostMeta = hostMeta;

      nixosConfigurations =
        nixpkgs.lib.genAttrs hosts (
          hostName:
          mkHost {
            inherit hostName;
            inherit (hostMeta.${hostName}) system role board;
          }
        )
        // {
          tariognatha-vm = mkHost {
            hostName = "tariognatha";
            inherit (hostMeta.tariognatha) system role;
            extraModules = [
              ./hosts/tariognatha/vm-overrides.nix
              { networking.hostName = nixpkgs.lib.mkForce "tariognatha-vm"; }
            ];
          };
        };

      packages.aarch64-linux.nvim-stable = nvimStableFor "aarch64-linux";

      # Pi images sit under x86_64-linux: built from this machine via qemu binfmt or a remote aarch64 builder.
      packages.${system} =
        import ./pkgs { inherit pkgs; }
        // {
          inherit nvim nvim-stable;
          image-installer-rpi4 = inputs.nixos-raspberrypi.installerImages.rpi4;
          image-installer-rpi5 =
            (inputs.nixos-raspberrypi.nixosConfigurations.rpi5-installer.extendModules {
              modules = [
                { users.users.root.openssh.authorizedKeys.keys = builtins.attrValues (import ./lib/ssh-keys.nix); }
              ];
            }).config.system.build.sdImage;
        }
        // nixpkgs.lib.genAttrs (map (h: "image-${h}") sdImageHosts) (
          name: self.nixosConfigurations.${nixpkgs.lib.removePrefix "image-" name}.config.system.build.sdImage
        );

      overlays.default = nixpkgs.lib.composeManyExtensions overlaysList;

      formatter.${system} = pkgs.nixfmt-tree;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          sops
          age
          ssh-to-age
          just
          nixfmt
          deadnix
          statix
          gum
          dmidecode
          pciutils
          shellcheck
        ];
      };

      checks.${system} = {
        # A top-level nix config attribute makes direnv's `use flake` stop at an interactive prompt.
        # The pattern is split so this file doesn't match.
        no-flake-nixconfig =
          let
            src = builtins.readFile ./flake.nix;
            found = builtins.match ".*\n  ${"nix" + "Config"} *=.*" src != null;
          in
          nixpkgs.lib.throwIf found
            "checks.no-flake-nixconfig: flake.nix sets a top-level nix config attribute; move it to nix.settings (modules/nixos/common/nix-settings.nix)"
            (pkgs.runCommand "krane-no-flake-nixconfig" { } "touch $out");

        # Checks the NixOS pkgs; home-manager shares them through useGlobalPkgs.
        ii-overlay =
          let
            pname = self.nixosConfigurations.tariognatha.pkgs.gnome-icon-theme.pname;
          in
          nixpkgs.lib.throwIf (pname != "adwaita-icon-theme")
            "checks.ii-overlay: gnome-icon-theme is '${pname}', expected the ii-fixes alias to adwaita-icon-theme"
            (pkgs.runCommand "krane-ii-overlay" { } "touch $out");

        # custom/*.lua is parsed only at Hyprland session start. Parse-only, undefined globals are fine.
        # Desktop hosts only: other roles have no krane.hypr.
        lua-syntax =
          let
            renderedFiles = nixpkgs.lib.concatMap (
              host:
              let
                cfg = self.nixosConfigurations.${host}.config;
              in
              nixpkgs.lib.attrValues cfg.home-manager.users.${cfg.krane.user.name}.krane.hypr._rendered
            ) desktopHosts;
          in
          nixpkgs.lib.throwIf (renderedFiles == [ ])
            "checks.lua-syntax: krane.hypr._rendered is empty for all hosts; the check would pass vacuously"
            (
              pkgs.runCommand "krane-hypr-lua-syntax" { } ''
                count=0
                for f in ${nixpkgs.lib.escapeShellArgs renderedFiles}; do
                  echo "luac -p $f"
                  ${pkgs.lua5_4}/bin/luac -p "$f"
                  count=$((count + 1))
                done
                if [ "$count" -eq 0 ]; then
                  echo "no rendered Lua files were checked" >&2
                  exit 1
                fi
                echo "checked $count rendered Lua files"
                touch "$out"
              ''
            );

        user-option =
          let
            base = self.nixosConfigurations.taractias.config;
            moved =
              (self.nixosConfigurations.taractias.extendModules {
                modules = [
                  {
                    krane.user = {
                      name = "tester";
                      gitName = "Test Er";
                      gitEmail = "tester@example.invalid";
                    };
                    krane.keyboard = {
                      layout = "de";
                      variant = "";
                    };
                  }
                ];
              }).config;
            nameOnly =
              (self.nixosConfigurations.taractias.extendModules {
                modules = [ { krane.user.name = "solo"; } ];
              }).config;
            hm = moved.home-manager.users.tester;
            expectations = [
              {
                ok = base.krane.user.name == "krane";
                what = "default krane.user.name is not krane";
              }
              {
                ok = base.krane.user.gitName == "krane" && base.krane.user.gitEmail == "chris@krane.dev";
                what = "default git identity is not krane <chris@krane.dev>";
              }
              {
                ok = base.users.users ? krane && base.home-manager.users ? krane;
                what = "default account krane is missing from users.users or home-manager.users";
              }
              {
                ok = nameOnly.krane.user.gitName == "solo";
                what = "krane.user.gitName does not default to krane.user.name";
              }
              {
                ok = moved.users.users ? tester && !(moved.users.users ? krane);
                what = "users.users does not follow krane.user.name";
              }
              {
                ok = moved.users.users.tester.home == "/home/tester" && hm.home.homeDirectory == "/home/tester";
                what = "home directory does not follow krane.user.name";
              }
              {
                ok = hm.home.username == "tester";
                what = "home.username does not follow krane.user.name";
              }
              {
                ok =
                  hm.programs.git.settings.user.name == "Test Er"
                  && hm.programs.git.settings.user.email == "tester@example.invalid";
                what = "git identity does not follow krane.user.gitName/gitEmail";
              }
              {
                ok =
                  builtins.elem "tester" moved.nix.settings.trusted-users
                  && !(builtins.elem "krane" moved.nix.settings.trusted-users);
                what = "nix trusted-users does not follow krane.user.name";
              }
              {
                ok = moved.services.greetd.settings.initial_session.user == "tester";
                what = "greetd autologin does not follow krane.user.name";
              }
              {
                ok =
                  let
                    server = builtins.head (import ./lib/wireguard.nix).wg0.sshServers;
                  in
                  hm.programs.ssh.settings.${server}.data.User == "tester";
                what = "ssh server aliases do not follow krane.user.name";
              }
              {
                ok = base.krane.keyboard.layout == "at" && base.krane.keyboard.variant == "nodeadkeys";
                what = "default krane.keyboard is not at/nodeadkeys";
              }
              {
                ok = moved.services.xserver.xkb.layout == "de" && moved.services.xserver.xkb.variant == "";
                what = "services.xserver.xkb does not follow krane.keyboard";
              }
            ];
            failed = map (e: e.what) (builtins.filter (e: !e.ok) expectations);
          in
          nixpkgs.lib.throwIf (failed != [ ])
            "checks.user-option: ${nixpkgs.lib.concatStringsSep "; " failed}"
            (pkgs.runCommand "krane-user-option" { } "touch $out");

        # Server-role configs from tests/server-host/ (not under hosts/) on the stable channel; eval-only.
        server-eval =
          let
            inherit (nixpkgs) lib;
            fixtureFor =
              hostName:
              mkHost {
                inherit hostName system;
                role = "server";
                hostDir = ./tests/server-host;
              };
            fixture = fixtureFor "server-fixture";
            hub = (fixtureFor "taragarmr").config;
            spoke = (fixtureFor "tarronax").config;
            lanSpoke = (fixtureFor "taronychus").config;
            inherit (fixture) config;
            release = config.system.nixos.release;
            hmUser = config.home-manager.users.${config.krane.user.name};
            wgTable = import ./lib/wireguard.nix;
            wg0Hub = hub.networking.wg-quick.interfaces.wg0;
            wg0Spoke = spoke.networking.wg-quick.interfaces.wg0;
            expectations = [
              {
                ok = release == "26.05";
                what = "server role evaluated on NixOS ${release}, expected 26.05 (stable inputs not swapped in)";
              }
              {
                ok = builtins.elem nvim-stable hmUser.home.packages;
                what = "the server home does not install packages.nvim-stable";
              }
              {
                ok = lib.length config.users.users.krane.openssh.authorizedKeys.keys == 4;
                what = "krane has ${toString (lib.length config.users.users.krane.openssh.authorizedKeys.keys)} authorized keys, expected 4";
              }
              {
                ok =
                  config.services.openssh.enable
                  && config.services.openssh.openFirewall
                  && !config.services.openssh.settings.PasswordAuthentication
                  && config.services.openssh.settings.PermitRootLogin == "no";
                what = "sshd is not enabled, open and keys-only without root login";
              }
              {
                ok =
                  config.virtualisation.docker.enable
                  && config.virtualisation.oci-containers.backend == "docker"
                  && builtins.elem "docker" config.users.users.krane.extraGroups
                  && config.virtualisation.docker.autoPrune.enable;
                what = "docker, the oci-containers backend, the docker group or autoPrune is not set up";
              }
              {
                ok = builtins.elem "krane" config.nix.settings.trusted-users && config.nix.gc.automatic;
                what = "krane is not a trusted nix user, or nix gc is off";
              }
              {
                ok = config.services.restic.backups ? default && config.services.restic.backups.default.initialize;
                what = "krane.backup did not define services.restic.backups.default";
              }
              {
                ok = !(config.networking.wg-quick.interfaces ? wg0) && !config.krane.wireguard.enable;
                what = "a host outside lib/wireguard.nix got a wg0 interface";
              }
              {
                ok = lib.length wg0Hub.peers == 7 && lib.all (p: lib.length p.allowedIPs == 1) wg0Hub.peers;
                what = "the hub's wg0 does not have exactly 7 /32 peers";
              }
              {
                ok =
                  wg0Hub.listenPort == 13231
                  && wg0Hub.autostart
                  && builtins.elem 13231 hub.networking.firewall.allowedUDPPorts
                  && builtins.elem "wg0" hub.networking.firewall.trustedInterfaces
                  && hub.boot.kernel.sysctl."net.ipv4.ip_forward" == 1
                  && lib.hasInfix "FORWARD -i wg0" wg0Hub.postUp;
                what = "the hub's wg0 is not an autostarting, forwarding server on UDP 13231";
              }
              {
                ok =
                  hub.networking.wg-quick.interfaces.wg1.autostart == false
                  && lib.length hub.networking.wg-quick.interfaces.wg1.peers == 4
                  && !(hub.systemd.services.wg-quick-wg1.wantedBy or [ ] != [ ])
                  && builtins.elem 51821 hub.networking.firewall.allowedUDPPorts;
                what = "the hub's wg1 is not a 4-peer interface that stays down at boot with UDP 51821 open";
              }
              {
                ok =
                  wg0Spoke.address == [ "192.168.82.4/24" ]
                  && lib.length wg0Spoke.peers == 1
                  && (lib.head wg0Spoke.peers).publicKey == wgTable.wg0.hub.publicKey
                  && (lib.head wg0Spoke.peers).endpoint == "wg.krane.dev:13231"
                  && (lib.head wg0Spoke.peers).allowedIPs == [ "192.168.82.0/24" ]
                  && (lib.head wg0Spoke.peers).persistentKeepalive == 25
                  && !(spoke.networking.wg-quick.interfaces ? wg1);
                what = "a spoke's wg0 is not a keepalive client of the hub with address 192.168.82.4/24 and no wg1";
              }
              {
                # Spokes on the hub's LAN reach it over the switch, not through the Fritzbox's NAT loopback.
                ok =
                  map (p: p.endpoint) lanSpoke.networking.wg-quick.interfaces.wg0.peers == [
                    "192.168.178.23:13231"
                  ];
                what = "a spoke on the hub's LAN does not use the hub's LAN endpoint 192.168.178.23:13231";
              }
            ];
            x86Servers = builtins.filter (n: hostMeta.${n}.system == "x86_64-linux") serverHosts;
            windows = lib.genAttrs serverHosts (
              n: self.nixosConfigurations.${n}.config.system.autoUpgrade.rebootWindow
            );
            upgradeExpectations = lib.concatMap upgradeExpectationsFor x86Servers ++ [
              {
                ok =
                  lib.sort (a: b: a < b) (map (w: w.lower) (builtins.attrValues windows)) == [
                    "01:59"
                    "02:59"
                    "03:59"
                    "04:59"
                  ];
                what = "the servers' reboot windows are not four distinct hours 02:00 to 06:00 (lower bounds one minute early)";
              }
              {
                ok =
                  windows.taragarmr.lower == "04:59" && lib.all (w: w.upper > w.lower) (builtins.attrValues windows);
                what = "taragarmr's reboot window is not the last, or a window ends before it starts";
              }
              {
                ok = lib.all (
                  n: self.nixosConfigurations.${n}.config.services.ntfy-sh.enable == (n == "taragarmr")
                ) hosts;
                what = "services.ntfy-sh is not enabled on taragarmr alone";
              }
              {
                ok =
                  let
                    tg = self.nixosConfigurations.taragarmr.config;
                    ntfy = tg.services.ntfy-sh.settings;
                  in
                  ntfy.listen-http == "192.168.82.1:2586"
                  && ntfy.auth-default-access == "deny-all"
                  && builtins.elem "wg-quick-wg0.service" tg.systemd.services.ntfy-sh.after
                  && builtins.elem "wg0" tg.networking.firewall.trustedInterfaces
                  && !builtins.elem 2586 tg.networking.firewall.allowedTCPPorts;
                what = "ntfy does not listen on taragarmr's WireGuard address alone with deny-all as the default, ordered after wg0 and closed on other interfaces";
              }
              {
                ok = lib.all (n: !self.nixosConfigurations.${n}.config.system.autoUpgrade.enable) desktopHosts;
                what = "a desktop has system.autoUpgrade enabled";
              }
              {
                # The subscriber needs the ntfy/read-token secret, so give each desktop one.
                ok = lib.all (
                  n:
                  let
                    c =
                      (self.nixosConfigurations.${n}.extendModules {
                        modules = [ { sops.secrets."ntfy/read-token" = { }; } ];
                      }).config;
                  in
                  lib.hasPrefix "/nix/store" (
                    toString
                      c.home-manager.users.${c.krane.user.name}.systemd.user.services.server-upgrade-notify.Service.ExecStart
                  )
                ) desktopHosts;
                what = "a desktop has no server-upgrade-notify user service once it has the ntfy/read-token secret";
              }
              {
                ok = lib.all (
                  n:
                  let
                    c = self.nixosConfigurations.${n}.config;
                  in
                  (import ./lib/host-secrets.nix {
                    inherit lib;
                    hostName = n;
                  }).hasSection
                    "ntfy"
                  || (
                    !(c.sops.secrets ? "ntfy/read-token")
                    && !(c.home-manager.users.${c.krane.user.name}.systemd.user.services ? server-upgrade-notify)
                  )
                ) desktopHosts;
                what = "a desktop without an ntfy secrets section defines the ntfy/read-token secret or the server-upgrade-notify unit";
              }
              {
                ok =
                  let
                    wg = (import ./lib/wireguard.nix).wg0;
                    sshKeys = import ./lib/ssh-keys.nix;
                  in
                  lib.all (
                    n:
                    let
                      c = self.nixosConfigurations.${n}.config;
                      fw = c.networking.firewall;
                      wgPorts = fw.interfaces.wg0.allowedTCPPorts or [ ];
                      keys = c.users.users.${c.krane.user.name}.openssh.authorizedKeys.keys;
                      enabled = builtins.elem n wg.desktopSsh;
                    in
                    !c.services.openssh.openFirewall
                    && !builtins.elem 22 fw.allowedTCPPorts
                    && (builtins.elem 22 wgPorts) == enabled
                    # authorized_keys in the home dir would skip the from= restriction.
                    && c.services.openssh.authorizedKeysInHomedir == !enabled
                    && (
                      if enabled then
                        keys == map (o: ''from="${wg.peers.${o}.ip}" ${sshKeys.${o}}'') (
                          lib.remove n wg.desktopSsh ++ wg.desktopSshClients.${n} or [ ]
                        )
                      else
                        keys == [ ]
                    )
                  ) desktopHosts;
                what = "desktop SSH is not limited to wg0 and the other wg0.desktopSsh hosts";
              }
              {
                ok =
                  let
                    c = self.nixosConfigurations.tariognatha.config;
                  in
                  lib.all (
                    n:
                    let
                      hc = self.nixosConfigurations.${n}.config;
                    in
                    !(hc.environment.shellAliases ? poweroff)
                    && lib.any (p: lib.getName p == "poweroff") hc.environment.systemPackages == (n == "tariognatha")
                  ) hosts
                  && lib.hasInfix (import ./lib/lan.nix).wol.tariognatha.mac c.services.udev.extraRules;
                what = "poweroff does not suspend on tariognatha alone, or its Wake-on-LAN rule is missing";
              }
            ];
            failed = map (e: e.what) (builtins.filter (e: !e.ok) (expectations ++ upgradeExpectations));
          in
          lib.throwIf (failed != [ ]) "checks.server-eval: ${lib.concatStringsSep "; " failed}" (
            pkgs.runCommand "krane-server-eval" {
              toplevel = builtins.unsafeDiscardOutputDependency config.system.build.toplevel.drvPath;
              hubToplevel = builtins.unsafeDiscardOutputDependency hub.system.build.toplevel.drvPath;
              spokeToplevel = builtins.unsafeDiscardOutputDependency spoke.system.build.toplevel.drvPath;
            } "echo \"$toplevel $hubToplevel $spokeToplevel\" > $out"
          );

        # The x86_64 CI cannot build the Pi hosts, so force their toplevel (and sdImage) derivation paths.
        pi-eval =
          let
            inherit (nixpkgs) lib;
            cfgOf = name: self.nixosConfigurations.${name}.config;
            expectations = lib.concatMap (
              name:
              let
                cfg = cfgOf name;
                board = hostMeta.${name}.board;
                loader = cfg.boot.loader;
              in
              [
                {
                  ok = cfg.nixpkgs.hostPlatform.system == "aarch64-linux" && cfg.system.nixos.release == "26.05";
                  what = "${name}: not aarch64-linux on NixOS 26.05";
                }
                {
                  ok = loader.raspberry-pi.enable && !loader.grub.enable && !loader.systemd-boot.enable;
                  what = "${name}: the nixos-raspberrypi loader is off, or grub/systemd-boot is on";
                }
                {
                  ok = loader.raspberry-pi.bootloader == (if board == "rpi5" then "kernel" else "uboot");
                  what = "${name}: bootloader ${loader.raspberry-pi.bootloader} is wrong for ${board}";
                }
                {
                  ok = loader.raspberry-pi.variant == (if board == "rpi5" then "5" else "4");
                  what = "${name}: loader variant does not match board ${board}";
                }
                {
                  ok =
                    name != "tarronax"
                    || lib.any (p: lib.getName p == "wake-tariognatha") cfg.environment.systemPackages;
                  what = "${name}: the wake-tariognatha command is missing";
                }
              ]
            ) piHosts;
            upgradeExpectations = lib.concatMap upgradeExpectationsFor piHosts;
            failed = map (e: e.what) (builtins.filter (e: !e.ok) (expectations ++ upgradeExpectations));
            drv = name: self.nixosConfigurations.${name}.config.system.build.toplevel.drvPath;
          in
          nixpkgs.lib.throwIf (piHosts == [ ] || failed != [ ])
            "checks.pi-eval: ${
              if piHosts == [ ] then "no board hosts" else nixpkgs.lib.concatStringsSep "; " failed
            }"
            (
              pkgs.runCommand "krane-pi-eval"
                {
                  drvs = map (n: builtins.unsafeDiscardOutputDependency (drv n)) piHosts;
                  images = map (
                    n: builtins.unsafeDiscardOutputDependency (cfgOf n).system.build.sdImage.drvPath
                  ) sdImageHosts;
                }
                ''
                  echo "$drvs $images" > $out
                ''
            );

        ii-settings-writer =
          pkgs.runCommand "ii-settings-writer-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              export PYTHONDONTWRITEBYTECODE=1
              cd ${./pkgs/krane-ii-settings}
              python3 -m unittest discover -s tests -v
              touch "$out"
            '';

        # Fixed stock host: this exercises the render machinery, not host values.
        ii-settings-render =
          let
            writer = pkgs.callPackage ./pkgs/krane-ii-settings { };
            cfg = self.nixosConfigurations.taractias.config;
            manifest = cfg.home-manager.users.${cfg.krane.user.name}.krane.iiSettings.manifestFile;
          in
          pkgs.runCommand "ii-settings-render" { } ''
            ${writer}/bin/krane-ii-settings --manifest ${manifest} \
              render --json ${./pkgs/krane-ii-settings/tests/fixtures/all-keys.json} > krane_gui.lua
            ${pkgs.lua5_4}/bin/luac -p krane_gui.lua
            grep -q 'require("hyprland.animationPresets.fast")' krane_gui.lua
            grep -q 'cm = "hdr"' krane_gui.lua
            touch "$out"
          '';

        nvim = nvimEval.config.build.test;

        nvim-stable = nvimStableEval.config.build.test;

        # Each spec runs in a fresh nvim under `timeout 120`, then :messages is checked for an escaped
        # vim.schedule/vim.defer_fn error, which pcall around dofile cannot see.
        # :messages, not v:errmsg: LuaSnip's internal `silent!` calls set v:errmsg and false-fail snippet specs.
        # format_on_save timeout is 10 s: a loaded CI runner missed 500 ms for prettierd and conform saved unformatted.
        nvim-specs =
          pkgs.runCommand "nvim-specs"
            {
              nativeBuildInputs = [
                nvim
                pkgs.coreutils
              ];
            }
            ''
              export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
              export XDG_CACHE_HOME="$TMPDIR/cache" XDG_DATA_HOME="$TMPDIR/data"
              export SPEC_FIXTURES=${./modules/nixvim/tests/fixtures}
              mkdir -p "$HOME"
              count=0
              for spec in ${./modules/nixvim/tests}/*_spec.lua; do
                echo "== $(basename "$spec")"
                export XDG_STATE_HOME="$TMPDIR/state-$count"
                mkdir -p "$XDG_STATE_HOME"
                if ! timeout 120 nvim --headless -c "lua vim.g.format_on_save_timeout_ms = 10000; local function messages() return vim.api.nvim_exec2('messages', { output = true }).output end; local ok, err = pcall(dofile, '$spec'); if not ok then io.stderr:write(tostring(err) .. '\n:messages:\n' .. messages() .. '\n'); local log = vim.fn.stdpath('log') .. '/conform.log'; if vim.fn.filereadable(log) == 1 then io.stderr:write('conform.log:\n' .. table.concat(vim.fn.readfile(log), '\n') .. '\n') end; vim.cmd('cquit 1') end; vim.wait(200); local m = messages(); if m:find('callback:', 1, true) or m:find('E5108', 1, true) then io.stderr:write(m .. '\n'); vim.cmd('cquit 1') end; vim.cmd('qall!')"; then
                  echo "nvim-specs: $(basename "$spec") failed or timed out after 120s" >&2
                  exit 1
                fi
                count=$((count + 1))
              done
              if [ "$count" -eq 0 ]; then
                echo "no specs found" >&2
                exit 1
              fi
              echo "ran $count specs"
              touch "$out"
            '';
      };
    };
}
