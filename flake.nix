{
  description = "mountthor — customer CLI for Mount Thor, a dedicated bare-metal Apple-silicon macOS cloud";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # The set of systems is driven entirely by which prebuilt artifacts exist.
      systems = builtins.attrNames (import ./sources.nix).artifacts;
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;

          # Batteries included: the CLI plus the tools it shells out to
          # (OpenSSH, the Teleport client `tsh`, and a VNC viewer on Linux).
          mountthor-cli = pkgs.callPackage ./package.nix { };

          # Just the CLI: ~90 MB of closure instead of ~1.4 GB, at the cost of
          # `mthr bm ssh`, `mthr bm desktop` and `mthr vm desktop` needing
          # those tools to come from somewhere else on your PATH.
          mountthor-cli-minimal = mountthor-cli.override {
            withTeleport = false;
            withVncClient = false;
          };
        in
        {
          inherit mountthor-cli mountthor-cli-minimal;
          default = mountthor-cli;
        }
      );

      apps = forAllSystems (
        system:
        {
          default = {
            type = "app";
            program = lib.getExe self.packages.${system}.default;
            meta.description = "Customer CLI for Mount Thor";
          };
        }
        // lib.optionalAttrs (self.packages.${system}.default.withVncClient) {
          # `nix run github:Mount-Thor/mountthor-cli-nix#vnc -- vnc://127.0.0.1:5999`
          vnc = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/mthr-vnc";
            meta.description = "Open a Mount Thor desktop tunnel in the bundled VNC viewer";
          };
        }
      );

      # `nix flake check` builds both variants, so the daily version-bump bot
      # cannot merge a release whose CLI surface the package no longer matches.
      checks = forAllSystems (system: {
        inherit (self.packages.${system}) mountthor-cli mountthor-cli-minimal;
      });

      # For consumers who'd rather pull the package into their own nixpkgs.
      overlays.default = _final: prev: {
        mountthor-cli = prev.callPackage ./package.nix { };
      };

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
