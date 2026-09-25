{
  description = "NixOS + Hyprland (illogical-impulse) dotfiles flake for tariognatha, tarmantria and taractias";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # end-4's dots-hyprland is a git checkout, pinned here as `dotfiles`.
    dots-hyprland = {
      url = "git+https://github.com/end-4/dots-hyprland?submodules=1";
      flake = false;
    };

    # soymou/illogical-flake wraps dots-hyprland. quickshell and NUR
    # inputs aren't followed, to avoid pulling in unvetted changes.
    illogical-flake = {
      url = "github:soymou/illogical-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dotfiles.follows = "dots-hyprland";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    disko.url = "github:nix-community/disko";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    nix-index-database.url = "github:nix-community/nix-index-database";

    # No `nixpkgs.follows`, per nixvim's advice: it is tested against its
    # own pin. The editor still builds with this flake's pkgs, see nvimEval.
    nixvim.url = "github:nix-community/nixvim";

    # No `nixpkgs.follows`: nixos-hardware's modules aren't pinned to a
    # nixpkgs revision. Applied only to taractias.
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
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

      # Single source of truth for this flake's host list, checked
      # against hosts/ by checks.lua-syntax below.
      hosts = [
        "tariognatha"
        "tarmantria"
        "taractias"
      ];

      # Sorted the same way as `hosts` for comparison below.
      hostDirs = nixpkgs.lib.sort (a: b: a < b) (
        nixpkgs.lib.attrNames (
          nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
        )
      );
      hostsSorted = nixpkgs.lib.sort (a: b: a < b) hosts;
    in
    {
      nixosConfigurations =
        nixpkgs.lib.genAttrs hosts (hostName: mkHost { inherit hostName system; })
        // {
          # QEMU/UEFI check target: tariognatha with GPU/disko/real fs
          # switched off.
          tariognatha-vm = mkHost {
            hostName = "tariognatha";
            inherit system;
            extraModules = [
              ./hosts/tariognatha/vm-overrides.nix
              # mkForce: overrides mk-host.nix's plain hostName definition.
              { networking.hostName = nixpkgs.lib.mkForce "tariognatha-vm"; }
            ];
          };
        };

      packages.${system} = import ./pkgs { inherit pkgs; } // {
        inherit nvim;
      };

      overlays.default = nixpkgs.lib.composeManyExtensions overlaysList;

      formatter.${system} = pkgs.nixfmt;

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
        # syntax errors here instead. Parse-only, undefined globals are fine.
        lua-syntax =
          let
            renderedFiles = nixpkgs.lib.concatMap (
              host:
              nixpkgs.lib.attrValues
                self.nixosConfigurations.${host}.config.home-manager.users.krane.krane.hypr._rendered
            ) hosts;
          in
          # Keeps `hosts` honest against hosts/: a mismatch fails loudly
          # instead of silently skipping a host.
          nixpkgs.lib.throwIf (hostDirs != hostsSorted)
            "checks.lua-syntax: flake.nix's `hosts` list [${nixpkgs.lib.concatStringsSep ", " hostsSorted}] does not match hosts/ directory contents [${nixpkgs.lib.concatStringsSep ", " hostDirs}] -- add/remove a hosts/<name>/ directory or update `hosts` in flake.nix so they match"
            (
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
                )
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
                if ! timeout 120 nvim --headless -c "lua local ok, err = pcall(dofile, '$spec'); if not ok then io.stderr:write(tostring(err) .. '\n'); vim.cmd('cquit 1') end; vim.wait(200); local m = vim.api.nvim_exec2('messages', { output = true }).output; if m:find('callback:', 1, true) or m:find('E5108', 1, true) then io.stderr:write(m .. '\n'); vim.cmd('cquit 1') end; vim.cmd('qall!')"; then
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
