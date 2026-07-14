# Eval-only check: the fleet `--intent` path (fleet/nixos-anywhere.nix)
# compiles a real intent file into a system configuration. No VM — this
# proves modules/sovox/intent.nix against fleet/example-intent.toml exactly
# as the installer applies it: intent settings over the example defaults.
{ inputs, system }:
let
  lib = inputs.nixpkgs.lib;
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  fromIntent = (import ../modules/sovox/intent.nix).fromIntent;

  cfg = (lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      inputs.self.nixosModules.sovox
      ../examples/server.nix
      (fromIntent ../fleet/example-intent.toml)
    ];
  }).config;

  ok =
    assert lib.assertMsg (cfg.sovox.node.name == "intent-example")
      "intent [node].name not applied";
    assert lib.assertMsg (cfg.networking.hostName == "intent-example")
      "intent node name did not reach networking.hostName";
    assert lib.assertMsg (cfg.sovox.roles.enabled == [ "ai" "storage" ])
      "intent [roles].enabled not applied";
    assert lib.assertMsg (cfg.sovox.roles.ai.enable && cfg.sovox.roles.storage.enable)
      "per-role enables did not follow the enabled list";
    assert lib.assertMsg (!cfg.sovox.roles.validator.enable)
      "undeclared role came out enabled";
    assert lib.assertMsg (cfg.sovox.roles.storage.capacity == "2TB")
      "intent [roles.storage].capacity not applied";
    assert lib.assertMsg (cfg.sovox.backup.snapshots == "hourly=24,daily=14,weekly=8")
      "intent [backup].snapshots not applied";
    assert lib.assertMsg (cfg.sovox.updates.window == "02:00-05:00")
      "intent [updates].window not applied";
    "intent-eval-ok";
in
pkgs.runCommand "sovox-intent-eval" { } ''
  echo ${ok} > $out
''
