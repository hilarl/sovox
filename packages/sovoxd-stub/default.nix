{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "sovoxd-stub";
  version = "0.0.1";

  src = lib.cleanSource ./.;
  # Dependency-free crate: the handwritten lock needs no vendoring/network.
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Sovox health/version stub daemon (seed of the sovoxd health supervisor)";
    license = lib.licenses.asl20;
    mainProgram = "sovoxd-stub";
    platforms = lib.platforms.linux;
  };
}
