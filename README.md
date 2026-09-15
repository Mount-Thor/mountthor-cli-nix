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
| `aarch64` |   ✅   |   ✅   |

`aarch64-linux` was unavailable upstream until 0.3.62 and is packaged from
that release on. The system list is derived from whichever artifacts
[`sources.nix`](./sources.nix) lists, so a platform appears here as soon as
upstream publishes a tarball for it and `./update.sh` picks it up.

## Usage

Run without installing:

```sh
nix run github:Mount-Thor/mountthor-cli-nix -- version
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
./result/bin/mthr version
```

## What's bundled

`mthr` shells out to other programs, and under Nix none of them are on `$PATH`
by default. The default package wraps the CLI so they resolve:

| Tool                     | Used by                                       |
| ------------------------ | --------------------------------------------- |
| `ssh`, `ssh-keygen`      | `mthr vm ssh`, derived VM identities           |
| `tsh` (Teleport client)  | `mthr bm ssh`, `mthr bm desktop`               |
| `vncviewer` (TigerVNC)   | `mthr vm desktop`, `mthr bm desktop` — Linux   |

`PATH` is appended to rather than prepended, so a `tsh` you already run wins
over the bundled one. Teleport clients are version-sensitive against the
cluster, and your own pin should keep working.

Those tools dominate the closure:

| Package                 | Closure  |
| ----------------------- | -------- |
| `mountthor-cli`         | ~1.40 GB |
| `mountthor-cli-minimal` | ~0.09 GB |

If you only want the CLI itself and will bring your own `tsh` and viewer:

```sh
nix build .#mountthor-cli-minimal
```

Or, from a flake, `mountthor.packages.${system}.mountthor-cli-minimal`. Via
`callPackage`, the two knobs are `withTeleport` and `withVncClient`, and
`vncClient` swaps the viewer for something other than TigerVNC.

## Remote desktops (`mthr vm desktop` / `mthr bm desktop`)

Opening a viewer automatically is macOS-only upstream. On Linux the CLI
brokers the session and prints the loopback URL, but only holds the tunnel
open if you pass `--no-browser`. Without it, 0.3.62 exits with `automatic
desktop launch requires macOS` and tears the tunnel down on the way out.

So on Linux, start the tunnel in one terminal and leave it running:

```sh
mthr bm desktop my-mac --local-port 5999 --no-browser
```

It prints the Screen Sharing username and password for the session, then
`vnc://127.0.0.1:5999`. Connect from a second terminal with the bundled
viewer:

```sh
mthr-vnc 5999
# or paste the URI: mthr-vnc vnc://127.0.0.1:5999
```

The viewer asks for those credentials. TigerVNC negotiates Apple's `DH(30)`
security type natively, so macOS Screen Sharing accepts it as-is. To skip
the prompt, hand the credentials to the viewer through its environment
rather than its arguments, which keeps them out of `ps`:

```sh
VNC_USERNAME=mt-user VNC_PASSWORD=<printed password> mthr-vnc 5999
```

Arguments after the target go to `vncviewer` unchanged, and `MTHR_VNC_VIEWER`
points `mthr-vnc` at a different viewer binary.

Without installing, that second terminal is:

```sh
nix run github:Mount-Thor/mountthor-cli-nix#vnc -- 5999
```

`mthr vm desktop` has no `--no-browser` flag as of 0.3.62, so it currently
has no way to hold a tunnel open on Linux.

On macOS there is nothing to bundle — the system Screen Sharing app already
handles `vnc://` — so `mthr-vnc` is not built there. Mac users get the same
credential prompt, since the CLI opens a bare URL.

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

1. Bump `version` to the per-platform latest. Every packaged platform moves in
   lockstep on each release, so one version covers them all, and `update.sh`
   fails loudly if they ever diverge.
2. Refresh each `sha256` (hex) from the manifest, or prefetch it:

   ```sh
   nix run nixpkgs#nix-prefetch-url -- --type sha256 \
     https://get.mountthor.com/mthr/v<VERSION>/mthr-<TRIPLE>.tar.xz
   ```

3. `nix flake check --all-systems` to verify.

[`update.sh`](./update.sh) does all three. To package a platform upstream has
newly published, add a row to the `PLATFORMS` table at the top of that script
and rerun it. Nothing else is platform-specific: the flake derives its system
list from `sources.nix`.

[`.github/workflows/update.yml`](./.github/workflows/update.yml) runs the
script daily and merges its own PR. It builds the new pin *before* opening
that PR, which it has to do for two reasons. Upstream reshuffles the command
tree between patch releases, so 0.3.59 replaced `mthr --version` with a
`version` subcommand and dropped `mthr docs completions` / `mthr docs man`
outright. And a PR opened with `GITHUB_TOKEN` does not trigger
`pull_request` workflows, so
[`build.yml`](./.github/workflows/build.yml) never runs on the bump branch.
Gating on the PR's own checks would wave a broken bump through on CodeQL
alone.

## License

The `mthr` binary is distributed by Mount Thor under the Apache-2.0 license
(bundled `LICENSE`, installed to `share/doc/mountthor-cli/`). On Linux the
prebuilt glibc binary is patched with `autoPatchelfHook` so it runs on
Nix-managed systems; the macOS binaries are installed as-is.
