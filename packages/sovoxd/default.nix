{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "sovoxd";
  version = "0.0.2";

  src = lib.cleanSource ./.;
  # Dependency-free crate: the handwritten lock needs no vendoring/network.
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Sovox node daemon — health gate, node status, and intent introspection";
    license = lib.licenses.asl20;
    mainProgram = "sovoxd";
    platforms = lib.platforms.linux;
  };
}
