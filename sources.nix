# Prebuilt mountthor release artifacts.
#
# Mirrors the ".latest" entry of https://get.mountthor.com/manifest.json. These
# are official prebuilt binaries (Apache-2.0), not built from source here.
#
# To update for a new release:
#   1. Bump `version` to the manifest's ".latest".
#   2. Refresh each sha256 (hex) from the matching artifact in the manifest, e.g.
#        nix run nixpkgs#nix-prefetch-url -- --type sha256 \
#          https://get.mountthor.com/mountthor/v<VERSION>/mountthor-<TRIPLE>.tar.xz
#
# Only platforms with a published .tar.xz are listed (the manifest also ships
# .deb/.rpm/.zip artifacts, which are not useful as a Nix source).
{
  version = "0.3.5";

  artifacts = {
    "x86_64-linux" = {
      triple = "x86_64-unknown-linux-gnu";
      sha256 = "b0a597965bc28a3262aedf64953c3f8259b039f8693a64c38864c88b572844c0";
    };
    "aarch64-darwin" = {
      triple = "aarch64-apple-darwin";
      sha256 = "55d5c463e93025dd15bb2dfb2e93b9c9a469dfcb1c9d510abcc19fc0ccfc2524";
    };
    "x86_64-darwin" = {
      triple = "x86_64-apple-darwin";
      sha256 = "dd51a48e3caeab51dc16e4a929fcafda383a02a7785f7920953cd3b89fbe6b0c";
    };
  };
}
