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
          mountthor-cli = (pkgsFor system).callPackage ./package.nix { };
        in
        {
          inherit mountthor-cli;
          default = mountthor-cli;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/mountthor";
          meta.description = "Customer CLI for Mount Thor";
        };
      });

      # For consumers who'd rather pull the package into their own nixpkgs.
      overlays.default = _final: prev: {
        mountthor-cli = prev.callPackage ./package.nix { };
      };

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
