{
  description = "NixOS + Hyprland (illogical-impulse) dotfiles flake for tariognatha, tarmantria and taractias";

  # Mirrors nix-settings.nix's CUDA substituters for install time too.
  # Untrusted users: pass `--accept-flake-config` to skip the prompt.
  nixConfig = {
    extra-substituters = [
      "https://cuda-maintainers.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

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

      packages.${system} = import ./pkgs { inherit pkgs; };

      overlays.default = nixpkgs.lib.composeManyExtensions overlaysList;

      formatter.${system} = pkgs.nixfmt-rfc-style;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          sops
          age
          ssh-to-age
          just
          nixfmt-rfc-style
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
      };
    };
}
