# mountthor-cli (Nix flake)

A Nix flake that packages the official prebuilt [`mountthor`](https://mountthor.com)
CLI — the customer-facing tool for Mount Thor, a neocloud for dedicated
Apple-silicon Mac fleets.

These are upstream prebuilt binaries (Apache-2.0), pulled from
`https://get.mountthor.com` and verified by SHA-256. On Linux the glibc binary
is patched with `autoPatchelfHook` so it runs on NixOS and any Nix-on-Linux
host; on macOS the self-contained Mach-O binary is installed as-is. Shell
completions and man pages are generated from the binary's own
`docs completions` / `docs man` subcommands.

## Supported systems

| System           | Artifact                                  |
| ---------------- | ----------------------------------------- |
| `x86_64-linux`   | `mountthor-x86_64-unknown-linux-gnu.tar.xz` |
| `aarch64-darwin` | `mountthor-aarch64-apple-darwin.tar.xz`   |
| `x86_64-darwin`  | `mountthor-x86_64-apple-darwin.tar.xz`    |

Upstream publishes no `aarch64-linux` tarball, so it is not packaged.

## Usage

Run without installing:

```sh
nix run github:Mount-Thor/mountthor-cli-nix -- --version
```

Add to a flake:

```nix
{
  inputs.mountthor.url = "github:Mount-Thor/mountthor-cli-nix";

  outputs = { self, nixpkgs, mountthor }: {
    # e.g. in a devShell or home/system packages:
    #   mountthor.packages.${system}.default
  };
}
```

Or via the overlay:

```nix
nixpkgs.overlays = [ mountthor.overlays.default ];
# then: pkgs.mountthor-cli
```

Build locally:

```sh
nix build .#mountthor-cli
./result/bin/mountthor --version
```

## Updating to a new release

Release metadata lives in [`sources.nix`](./sources.nix), mirroring the
`.latest` entry of <https://get.mountthor.com/manifest.json>:

1. Bump `version`.
2. Refresh each `sha256` (hex) from the manifest, or prefetch it:

   ```sh
   nix run nixpkgs#nix-prefetch-url -- --type sha256 \
     https://get.mountthor.com/mountthor/v<VERSION>/mountthor-<TRIPLE>.tar.xz
   ```

3. `nix build .#mountthor-cli` to verify.

## License

The packaging in this repo is provided as-is. The `mountthor` binary itself is
distributed by Mount Thor under the Apache-2.0 license (see the bundled
`LICENSE`, installed to `share/doc/mountthor-cli/`).
