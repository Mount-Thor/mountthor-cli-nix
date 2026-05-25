{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  installShellFiles,
  xz,
}:

let
  manifest = import ./sources.nix;
  inherit (manifest) version;

  inherit (stdenvNoCC.hostPlatform) system;
  source =
    manifest.artifacts.${system}
      or (throw "mountthor-cli: no prebuilt artifact published for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mountthor-cli";
  inherit version;

  # Prebuilt tarball straight from the upstream distribution endpoint.
  src = fetchurl {
    url = "https://get.mountthor.com/mountthor/v${version}/mountthor-${source.triple}.tar.xz";
    inherit (source) sha256;
  };

  # Each tarball unpacks to a single mountthor-<triple>/ directory.
  sourceRoot = "mountthor-${source.triple}";

  nativeBuildInputs =
    [ installShellFiles ]
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

    install -Dm755 mountthor -t $out/bin
    install -Dm644 LICENSE   $out/share/doc/${finalAttrs.pname}/LICENSE
    install -Dm644 README.md $out/share/doc/${finalAttrs.pname}/README.md

    runHook postInstall
  '';

  # installCheckPhase runs after fixupPhase, so on Linux the binary is already
  # autoPatchelf'd and runnable here (and the Darwin binary always is). Smoke
  # test it, then let the CLI emit its own completions and man pages.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME=$(mktemp -d)
    $out/bin/mountthor --version

    installShellCompletion --cmd mountthor \
      --bash <($out/bin/mountthor docs completions bash) \
      --zsh <($out/bin/mountthor docs completions zsh) \
      --fish <($out/bin/mountthor docs completions fish)

    mandir=$(mktemp -d)
    $out/bin/mountthor docs man --out "$mandir"
    installManPage "$mandir"/*.1

    runHook postInstallCheck
  '';

  meta = {
    description = "Customer CLI for Mount Thor, a dedicated bare-metal Apple-silicon macOS cloud";
    longDescription = ''
      mountthor is the customer-facing CLI for Mount Thor (https://mountthor.com),
      a neocloud for dedicated Apple-silicon Mac fleets. It is the entry point for
      registering an account, managing API keys and sessions, leasing bare-metal
      Macs, and launching VMs on top of them.

      This package distributes the official prebuilt binaries; on Linux they are
      patched with autoPatchelfHook to run on Nix-managed systems.
    '';
    homepage = "https://mountthor.com";
    downloadPage = "https://get.mountthor.com";
    changelog = "https://github.com/Mount-Thor/mount-thor/releases/tag/mountthor-v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "mountthor";
    platforms = builtins.attrNames manifest.artifacts;
    maintainers = [ ];
  };
})
