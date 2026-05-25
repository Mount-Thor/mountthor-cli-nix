# mountthor-cli

The customer CLI for [Mount Thor](https://mountthor.com), a neocloud for
dedicated Apple-silicon Mac fleets. `mountthor` is the entry point for
everything you do against the Mount Thor API — register an account, manage API
keys and sessions, browse the catalog, lease bare-metal Macs, and launch VMs on
top of them.

This repo is a Nix flake that distributes the official prebuilt `mountthor`
binaries (Apache-2.0).

## Supported systems

|           | Linux | macOS |
| --------- | :---: | :---: |
| `x86_64`  |   ✅   |   ✅   |
| `aarch64` |   —   |   ✅   |

`aarch64-linux` is unavailable upstream, so it is not packaged.

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

The package also installs shell completions (bash/zsh/fish) and man pages,
generated from the CLI's own `mountthor docs completions` / `mountthor docs man`
subcommands.

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

The `mountthor` binary is distributed by Mount Thor under the Apache-2.0 license
(bundled `LICENSE`, installed to `share/doc/mountthor-cli/`). On Linux the
prebuilt glibc binary is patched with `autoPatchelfHook` so it runs on
Nix-managed systems; the macOS binaries are installed as-is.
