{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  xz,
  openssh,
  teleport,
  tigervnc,

  # `mthr bm ssh` / `mthr bm desktop` shell out to the Teleport client `tsh`.
  # Without it on PATH they abort with an install hint that recommends
  # Homebrew, which is no help under Nix — so bundle the client-only output
  # (`tsh` alone, not the server) and put it on the wrapper's PATH.
  withTeleport ? true,

  # Bundle a VNC viewer. On Linux `mthr vm desktop` / `mthr bm desktop` do not
  # launch a viewer themselves; they print `vnc://127.0.0.1:<port>` and hold
  # the tunnel open, expecting you to supply a client. On Darwin the system
  # Screen Sharing app already handles `vnc://`, and tigervnc has no Darwin
  # build in nixpkgs, so this is Linux-only.
  withVncClient ? stdenvNoCC.hostPlatform.isLinux,
  vncClient ? tigervnc,
}:

let
  manifest = import ./sources.nix;
  inherit (manifest) version;

  inherit (stdenvNoCC.hostPlatform) system;
  source =
    manifest.artifacts.${system}
      or (throw "mountthor-cli: no prebuilt artifact published for ${system}");

  # Tools mthr expects to find on PATH at runtime. Baked into the wrapper so
  # they resolve the same way under `nix run`, `nix profile install`, and a
  # bare `nix build ./result/bin/mthr`.
  runtimeTools = [
    openssh # `ssh`, and `ssh-keygen` for the derived VM identity
  ]
  ++ lib.optional withTeleport teleport.client
  ++ lib.optional withVncClient vncClient;

  runtimeBinDirs = map (drv: "${lib.getBin drv}/bin") runtimeTools;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mountthor-cli";
  inherit version;

  # Prebuilt tarball straight from the upstream distribution endpoint.
  # Upstream renamed the release path + filename from `mountthor` to `mthr`
  # starting with 0.3.19, mirroring the earlier binary rename.
  src = fetchurl {
    url = "https://get.mountthor.com/mthr/v${version}/mthr-${source.triple}.tar.xz";
    inherit (source) sha256;
  };

  # Each tarball unpacks to a single mthr-<triple>/ directory.
  sourceRoot = "mthr-${source.triple}";

  nativeBuildInputs = [
    makeWrapper
  ]
  # The Linux binary is a glibc dynamic ELF; rewrite its interpreter + RPATH
  # to the Nix store so it runs on NixOS (and any Nix-on-Linux host).
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  # NEEDED libraries beyond libc/libm (which autoPatchelfHook resolves against
  # glibc automatically): liblzma.so.5 from xz, and libgcc_s.so.1 from the gcc
  # runtime. Linux-only — the Darwin binaries are self-contained Mach-O.
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    (lib.getLib stdenv.cc.cc)
    (lib.getLib xz)
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 mthr      -t $out/bin
    install -Dm644 LICENSE   $out/share/doc/${finalAttrs.pname}/LICENSE
    install -Dm644 README.md $out/share/doc/${finalAttrs.pname}/README.md

    runHook postInstall
  '';

  # A launcher that points the bundled viewer at a desktop tunnel, since the
  # CLI will not open one for you on Linux. See mthr-vnc.sh for the reasoning.
  postInstall = lib.optionalString withVncClient ''
    install -Dm755 ${./mthr-vnc.sh} $out/bin/mthr-vnc
    substituteInPlace $out/bin/mthr-vnc \
      --replace-fail '@vncviewer@' ${lib.escapeShellArg (lib.getExe' vncClient "vncviewer")}
  '';

  # `mthr kubeconfig` writes a client-go exec-credential plugin whose
  # `command:` field defaults to bare `mthr`, which kubectl resolves against
  # $PATH. The `nix run github:Mount-Thor/mountthor-cli-nix -- kubeconfig`
  # entrypoint never puts `mthr` on $PATH, so kubectl would fail with
  # `executable mthr not found`. Default the upstream override env var
  # (`MOUNTTHOR_KUBECONFIG_EXEC_COMMAND`) to this derivation's absolute path
  # so generated kubeconfigs keep working without a separate install step.
  # `--set-default` preserves an explicit user override.
  #
  # PATH is suffixed, not prefixed, so a `tsh` the user already runs wins over
  # the bundled one — Teleport clients and clusters are version-sensitive.
  postFixup = ''
    wrapProgram $out/bin/mthr \
      --set-default MOUNTTHOR_KUBECONFIG_EXEC_COMMAND $out/bin/mthr \
      --suffix PATH : ${lib.escapeShellArg (lib.makeBinPath runtimeTools)}
  '';

  # installCheckPhase runs after fixupPhase, so on Linux the binary is already
  # autoPatchelf'd and runnable here (and the Darwin binary always is).
  #
  # Keep this to surface-independent checks. Upstream reshuffles the command
  # tree between patch releases — 0.3.59 dropped `--version` for a `version`
  # subcommand and removed `docs completions` / `docs man` entirely — and the
  # daily bump bot merges on green, so anything asserted here is a thing that
  # can break the flake unattended.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME=$(mktemp -d)

    reported=$($out/bin/mthr version)
    echo "mthr version: $reported"
    case "$reported" in
      *${finalAttrs.version}*) ;;
      *)
        echo "installCheck: sources.nix pins ${finalAttrs.version}, but the binary reports '$reported'" >&2
        exit 1
        ;;
    esac

    # Every tool mthr shells out to has to be present, and the wrapper has to
    # actually put it on mthr's PATH. Both halves break silently otherwise.
    runtimeBins=${lib.escapeShellArg (lib.concatStringsSep ":" runtimeBinDirs)}

    for tool in ${
      lib.escapeShellArgs (
        [
          "ssh"
          "ssh-keygen"
        ]
        ++ lib.optional withTeleport "tsh"
        ++ lib.optional withVncClient "vncviewer"
      )
    }; do
      if ! (
        PATH=$runtimeBins
        command -v "$tool" >/dev/null
      ); then
        echo "installCheck: bundled runtime tool '$tool' is missing from $runtimeBins" >&2
        exit 1
      fi
    done

    # makeWrapper emits one dedup block per PATH entry, so check them one by one.
    for bindir in ${lib.escapeShellArgs runtimeBinDirs}; do
      if ! grep -qF "$bindir" $out/bin/mthr; then
        echo "installCheck: the mthr wrapper does not put $bindir on PATH" >&2
        exit 1
      fi
    done
    ${lib.optionalString withVncClient ''
      # The viewer launcher has to be runnable and fully substituted.
      $out/bin/mthr-vnc --help >/dev/null
      if grep -q '@vncviewer@' $out/bin/mthr-vnc; then
        echo "installCheck: mthr-vnc still carries an unsubstituted @vncviewer@ placeholder" >&2
        exit 1
      fi
    ''}

    runHook postInstallCheck
  '';

  # What this build actually bundled, so consumers can branch on it instead of
  # re-deriving the defaults.
  passthru = {
    inherit withTeleport withVncClient;
  }
  // lib.optionalAttrs withVncClient { inherit vncClient; };

  meta = {
    description = "Customer CLI for Mount Thor, a dedicated bare-metal Apple-silicon macOS cloud";
    longDescription = ''
      mountthor is the customer-facing CLI for Mount Thor (https://mountthor.com),
      a neocloud for dedicated Apple-silicon Mac fleets. It is the entry point for
      registering an account, managing API keys and sessions, leasing bare-metal
      Macs, and launching VMs on top of them.

      This package distributes the official prebuilt binaries; on Linux they are
      patched with autoPatchelfHook to run on Nix-managed systems. The tools the
      CLI shells out to are bundled and wired onto its PATH: OpenSSH, the
      Teleport client `tsh` that backs bare-metal access, and — on Linux, where
      the CLI declines to open one itself — a TigerVNC viewer for the remote
      desktop commands, reachable as `mthr-vnc`.
    '';
    homepage = "https://mountthor.com";
    downloadPage = "https://get.mountthor.com";
    changelog = "https://github.com/Mount-Thor/mount-thor/releases/tag/mountthor-v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "mthr";
    platforms = builtins.attrNames manifest.artifacts;
    maintainers = [ ];
  };
})
