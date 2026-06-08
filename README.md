# mountthor-cli

The customer CLI for [Mount Thor](https://mountthor.com), a neocloud for
dedicated Apple-silicon Mac fleets. `mthr` is the entry point for everything
you do against the Mount Thor API — register an account, manage API keys and
sessions, browse the catalog, lease bare-metal Macs, and launch VMs on top of
them.

This repo is a Nix flake that distributes the official prebuilt `mthr` binaries
(Apache-2.0). The binary was named `mountthor` through 0.3.10 and was renamed
to `mthr` upstream starting with 0.3.11.

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
./result/bin/mthr --version
```

The package also installs shell completions (bash/zsh/fish) and man pages,
generated from the CLI's own `mthr docs completions` / `mthr docs man`
subcommands.

### `mthr kubeconfig` from `nix run`

The kubeconfig that `mthr kubeconfig` writes uses a client-go exec-credential
plugin, whose `command:` field defaults to bare `mthr` — and `nix run
github:Mount-Thor/mountthor-cli-nix -- kubeconfig` never puts `mthr` on
`$PATH`, so by default `kubectl` would fail with `executable mthr not found`.

This flake wraps the binary to default `MOUNTTHOR_KUBECONFIG_EXEC_COMMAND` to
its own absolute Nix store path, so kubeconfigs generated via `nix run` work
without a separate install step. To pin a different absolute path (e.g. a
shim on `$PATH`), set `MOUNTTHOR_KUBECONFIG_EXEC_COMMAND` or pass
`--exec-command <path>` to `mthr kubeconfig` — explicit overrides win.

## Updating to a new release

Release metadata lives in [`sources.nix`](./sources.nix). Source of truth is
the per-platform `latest_by_platform` map at
<https://get.mountthor.com/manifest.json> (the global `.latest` field is
intentionally floored at the last Windows-capable release for older
self-updating clients and is not what we want here):

1. Bump `version` to the per-platform latest (macOS and Linux move in lockstep
   on each release, so one version covers all three platforms).
2. Refresh each `sha256` (hex) from the manifest, or prefetch it:

   ```sh
   nix run nixpkgs#nix-prefetch-url -- --type sha256 \
     https://get.mountthor.com/mountthor/v<VERSION>/mountthor-<TRIPLE>.tar.xz
   ```

3. `nix build .#mountthor-cli` to verify.

## License

The `mthr` binary is distributed by Mount Thor under the Apache-2.0 license
(bundled `LICENSE`, installed to `share/doc/mountthor-cli/`). On Linux the
prebuilt glibc binary is patched with `autoPatchelfHook` so it runs on
Nix-managed systems; the macOS binaries are installed as-is.
