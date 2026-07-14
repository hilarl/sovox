# Pinned tenzro-node packaging. Two supported paths:
#   a) consume upstream's release binary (this file), or
#   b) build the Rust workspace as a pinned derivation
#      (Rust 1.85+/clang toolchain per docs/03-ARCHITECTURE.md §3).
#
# The URL/hash below are placeholders: pin them to a real upstream release
# before setting sovox.tenzro.enable = true. Nothing evaluates this file
# while the module is disabled.
{ lib, stdenv, fetchurl, autoPatchelfHook }:

stdenv.mkDerivation rec {
  pname = "tenzro-node";
  version = "0.0.0-pin-me";

  src = fetchurl {
    url = "https://github.com/tenzro/tenzro-network/releases/download/v${version}/tenzro-node-x86_64-linux.tar.gz";
    hash = lib.fakeHash; # TODO: pin to a real release hash
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 tenzro-node $out/bin/tenzro-node
    runHook postInstall
  '';

  meta = {
    description = "Tenzro Network node (CPU variant; CUDA overlay matrix is v0.1)";
    homepage = "https://github.com/tenzro/tenzro-network";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
