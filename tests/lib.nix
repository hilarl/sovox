# Shared test plumbing: every test VM goes through the same sovox module set
# (the mkSovox discipline), with the VM-only adjustments collected
# here so each test states only its deltas.
{ inputs, system }:
rec {
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  nixos-lib = import (inputs.nixpkgs + "/nixos/lib") { };

  runTest = module: nixos-lib.runTest {
    hostPkgs = pkgs;
    node.specialArgs = { inherit inputs; };
    defaults.imports = [ inputs.self.nixosModules.sovox ];
    imports = [ module ];
  };

  # VM-only baseline: framework VMs are not installed systems, so the ZFS
  # boot chain and disk layouts do not apply unless a test opts back in.
  vmBase = { lib, ... }: {
    sovox.internal.impermanence.enable = lib.mkDefault false;
    sovox.updates.checkClock = false; # no NTP inside the sandbox
    # never let the rollback watchdog fire mid-test unless a test asks for it
    sovox.updates.healthGrace = lib.mkDefault 3600;
    disko.devices = lib.mkForce { };
    networking.hostId = "deadbeef";
    system.stateVersion = "26.05";
  };
}
