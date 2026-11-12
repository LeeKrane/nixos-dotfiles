{
  description = "NixOS + Hyprland (illogical-impulse) dotfiles flake, one nixosConfiguration per hosts/ directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Stable channel for role = "server" hosts (lib/mk-host.nix swaps these in under the
    # names nixpkgs/home-manager/nixvim). Bump all three together at each NixOS release.
    # Follows nixos-raspberrypi's pin (nixos-26.05) so every server, the Pis included, shares
    # one nixpkgs revision and the Pi kernels/firmware come from their binary cache. The pin
    # is checked against nixos-26.05 when bumping.
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

    # end-4's dots-hyprland is a git checkout, pinned here as `dotfiles`.
    dots-hyprland = {
      url = "git+https://github.com/end-4/dots-hyprland?submodules=1";
      flake = false;
    };

    # soymou/illogical-flake wraps dots-hyprland. NUR isn't followed, to avoid
    # pulling in unvetted changes.
    illogical-flake = {
      url = "github:soymou/illogical-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dotfiles.follows = "dots-hyprland";
      inputs.quickshell.follows = "quickshell";
    };

    # Pinned past soymou's May 2026 quickshell, which fails to build against Qt 6.12
    # (MOC "Meta Types must be fully defined"). Fixed upstream in 5d5d498 / 1c1cc91.
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell?rev=9b0f339b19057f4731bf3b48293307d7ef241671";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    disko.url = "github:nix-community/disko";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    nix-index-database.url = "github:nix-community/nix-index-database";

    # No `nixpkgs.follows`, per nixvim's advice: it is tested against its
    # own pin. The editor still builds with this flake's pkgs, see nvimEval.
    nixvim.url = "github:nix-community/nixvim";

    # No `nixpkgs.follows`: nixos-hardware's modules aren't pinned to a
    # nixpkgs revision. Imported by taractias and by hosts scaffolded from
    # templates/host/ (GPU profile and form-factor imports).
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  # The Pi kernels, firmware and images are cached here; flake nixConfig needs
  # `--accept-flake-config` (or trusted-users) to take effect.
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

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

      # Standalone NixVim build, see modules/nixvim/. Uses this flake's pkgs
      # so overlays and allowUnfree apply; nixvim's own nixpkgs pin (see the
      # `nixvim` input above) is used only to evaluate its library, not to
      # build the editor.
      nvimEval = inputs.nixvim.lib.evalNixvim {
        modules = [
          ./modules/nixvim
          { nixpkgs.pkgs = pkgs; }
        ];
      };
      nvim = nvimEval.config.build.package;

      # The same editor for role = "server" hosts: nixvim and nixpkgs both from the stable
      # inputs (modules/home/common/neovim.nix picks it by role).
      nvimStableFor =
        sys:
        (inputs.nixvim-stable.lib.evalNixvim {
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
        }).config.build.package;
      nvim-stable = nvimStableFor system;

      # Every directory under hosts/ is a host. install.sh's new-host flow adds one by
      # scaffolding hosts/<name>/ from templates/host/. install.sh, bootstrap-sops.sh's
      # known_hosts() and docker-check.sh's HOSTS glob the same directories. Plain files
      # under hosts/ are ignored.
      hosts = nixpkgs.lib.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      );

      # Per-host metadata: an optional hosts/<name>/host.nix attrset `{ system, role, board, image }`. A
      # missing file, or a missing attribute in it, takes the default: x86_64-linux, role
      # "desktop", no board. role picks the module set mk-host.nix imports
      # (modules/{nixos,home}/{common,<role>}). board ("rpi4" | "rpi5") marks a Raspberry Pi:
      # it adds the nixos-raspberrypi modules, and defaults system to aarch64-linux and role
      # to "server" (both may only be given as those values). image ("sd" or absent/null) says the
      # host builds a flashable SD image (it imports the nixos-raspberrypi sd-image module);
      # it needs a board and is what `packages.image-<host>` is derived from, so listing the
      # packages does not evaluate every Pi. Unknown attribute names, roles
      # or boards fail evaluation instead of silently falling back to the defaults.
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
      # Raspberry Pi hosts (aarch64-linux). Never built here: CI builds x86_64 hosts only
      # (scripts/hosts.nix), but they are evaluated by checks.pi-eval, and their images are
      # exposed as packages (`nix build .#image-<host>`, via qemu binfmt or an aarch64 builder).
      piHosts = builtins.filter (name: hostMeta.${name}.board != null) hosts;
      # Pis that build an SD image, from host.nix metadata (no evaluation of the Pi configs).
      sdImageHosts = builtins.filter (name: hostMeta.${name}.image == "sd") piHosts;
      desktopHosts = builtins.filter (name: hostMeta.${name}.role == "desktop") hosts;
    in
    {
      nixosConfigurations =
        nixpkgs.lib.genAttrs hosts (
          hostName:
          mkHost {
            inherit hostName;
            inherit (hostMeta.${hostName}) system role board;
          }
        )
        // {
          # QEMU/UEFI check target: tariognatha with GPU/disko/real fs
          # switched off.
          tariognatha-vm = mkHost {
            hostName = "tariognatha";
            inherit (hostMeta.tariognatha) system role;
            extraModules = [
              ./hosts/tariognatha/vm-overrides.nix
              # mkForce: overrides mk-host.nix's plain hostName definition.
              { networking.hostName = nixpkgs.lib.mkForce "tariognatha-vm"; }
            ];
          };
        };

      # aarch64-linux: only the server editor, which the Pi hosts' home-manager installs
      # (modules/home/common/neovim.nix reads inputs.self.packages.<hostPlatform>).
      packages.aarch64-linux.nvim-stable = nvimStableFor "aarch64-linux";

      # The Pi images below sit under x86_64-linux on purpose: they are built from this machine
      # (qemu binfmt or a remote aarch64 builder), so `nix build .#image-<host>` works where
      # the flake is used; nothing keys them under packages.aarch64-linux.
      packages.${system} =
        import ./pkgs { inherit pkgs; }
        // {
          inherit nvim nvim-stable;
          # nixos-raspberrypi's installer SD images, for hosts that are installed with
          # nixos-anywhere (taronychus: hosts/taronychus/default.nix).
          image-installer-rpi4 = inputs.nixos-raspberrypi.installerImages.rpi4;
          image-installer-rpi5 = inputs.nixos-raspberrypi.installerImages.rpi5;
        }
        # Ready-to-flash SD images of the Pi hosts that use the sd-image module.
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
        # custom/*.lua is parsed only at Hyprland session start. Catch
        # syntax errors here instead. Parse-only, undefined globals are fine. Desktop
        # hosts only: other roles have no krane.hypr.
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
          # Refuse an empty `_rendered` list here, at eval time, and
          # again in the builder, so this check can't pass vacuously.
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

        # krane.user wiring (modules/nixos/common/user.nix): the stock hosts keep "krane", and
        # overriding it moves the account, the home-manager user, the git identity,
        # nix trusted-users and greetd autologin with it. Eval-only: the derivation is
        # trivial, the assertions run while evaluating it.
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

        # Evaluates role = "server" configs built from tests/server-host/ (not under hosts/, so
        # they are no nixosConfigurations) on the stable channel, so server-role regressions
        # surface here before a real server host exists: a plain fixture, the WireGuard hub
        # (taragarmr) and a spoke (tarronax), each with the fixture's dummy secret paths. Eval-only:
        # nothing is built, the assertions run while evaluating.
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
                ok =
                  config.services.restic.server.enable
                  && config.services.restic.server.appendOnly
                  && config.services.restic.server.listenAddress == "192.168.82.2:8000"
                  && builtins.elem 8000 config.networking.firewall.interfaces.wg0.allowedTCPPorts;
                what = "krane.backupServer is not an append-only REST server on 192.168.82.2:8000 with port 8000 open on wg0";
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
            ];
            failed = map (e: e.what) (builtins.filter (e: !e.ok) expectations);
          in
          lib.throwIf (failed != [ ]) "checks.server-eval: ${lib.concatStringsSep "; " failed}" (
            pkgs.runCommand "krane-server-eval" {
              toplevel = builtins.unsafeDiscardOutputDependency config.system.build.toplevel.drvPath;
              hubToplevel = builtins.unsafeDiscardOutputDependency hub.system.build.toplevel.drvPath;
              spokeToplevel = builtins.unsafeDiscardOutputDependency spoke.system.build.toplevel.drvPath;
            } "echo \"$toplevel $hubToplevel $spokeToplevel\" > $out"
          );

        # Evaluates every Raspberry Pi host (aarch64-linux, role server) on the stable channel and
        # forces its toplevel (and sdImage) derivation paths: the x86_64 CI cannot build them, but
        # evaluating works. Also asserts the Pi boot setup: nixos-raspberrypi's loader, the
        # Pi 5 hosts on the generational "kernel" one, and no systemd-boot/grub.
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
              ]
            ) piHosts;
            failed = map (e: e.what) (builtins.filter (e: !e.ok) expectations);
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

        # NixVim's own startup test: fails on errors or warnings at startup.
        nvim = nvimEval.config.build.test;

        # Headless Lua specs in modules/nixvim/tests/, one fresh nvim each.
        # Each run is bounded by `timeout 120` (a hung spec, e.g. from an
        # unresolved async callback, fails the build instead of hanging it
        # forever) and, after letting scheduled callbacks flush, checks
        # :messages for an escaped scheduled-callback error, so an error
        # raised from vim.schedule(...)/vim.defer_fn(...) -- which pcall
        # around dofile can't see, since it escapes on the event loop after
        # dofile returns -- still fails the spec.
        #
        # This replaced an earlier vim.v.errmsg-based check (round 2):
        # v:errmsg is also set by LuaSnip 2.5.0's internal `silent!` calls
        # (`silent! call repeat#set(...)` in luasnip/init.lua:667,
        # `:silent! foldopen!` in luasnip/util/feedkeys.lua:119), which
        # `silent!` suppresses on screen but not in v:errmsg, false-failing
        # any spec that expands/jumps a snippet. :messages does not record
        # `silent!`-suppressed errors at all (confirmed: a throwaway
        # `vim.cmd("silent! call nosuch#fn()")` spec exits 0 against this
        # check), so it needs no such workaround and catches strictly more:
        # a scheduled error crashes with "Error in command line: vim.schedule
        # callback: ..." (or E5108 for some deferred-callback paths), both
        # matched below. Errors raised inside a spec's own internal
        # vim.wait() window are also caught now, since :messages accumulates
        # for the whole nvim session rather than being reset per-window.
        #
        # Specs run with a 10 s format_on_save budget (vim.g.format_on_save_timeout_ms,
        # read by modules/nixvim/lang/default.nix; interactive default 500 ms): a
        # loaded CI runner once missed 500 ms for prettierd, and conform then saves
        # unformatted without an error, failing a formatting assertion for a
        # reason unrelated to the gating logic under test. A failing spec also
        # prints :messages and conform.log, so the next failure shows its cause.
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
