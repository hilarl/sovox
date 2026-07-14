# Edition interconvertibility test, in three parts:
#  (a) both example configs evaluate from the same rev (pure eval);
#  (b) sovereign-core parity: hardening artifacts are *identical derivations*
#      in both editions — a stronger, testable form of "the closure diff
#      contains no hardening paths" (which plasma's closure makes
#      unfalsifiable as worded);
#  (c) a running server VM activates the desktop configuration (and back)
#      via a specialisation — same module tree, one option changed.
{ inputs, system }:
let
  inherit (import ./lib.nix { inherit inputs system; }) runTest vmBase;
  lib = inputs.nixpkgs.lib;

  serverCfg = inputs.self.nixosConfigurations.server-example.config;
  desktopCfg = inputs.self.nixosConfigurations.desktop-example.config;

  # Round-trip: the rendered intent file (render.nix), parsed back through
  # intent.nix, must reproduce the option values it came from. Reading the
  # rendered derivation is import-from-derivation — deliberate: the check
  # exercises the real serializer output, not a copy of its input.
  roundTrip = ((import ../modules/sovox/intent.nix).fromTable
    (builtins.fromTOML (builtins.readFile
      serverCfg.environment.etc."sovox/sovox.toml".source))).sovox;

  # (a) + (b): evaluation-time invariants over the published example configs.
  parity =
    assert lib.assertMsg
      (serverCfg.networking.nftables.tables.sovox.content
        == desktopCfg.networking.nftables.tables.sovox.content)
      "editions diverge: nftables firewall policy differs";
    assert lib.assertMsg
      (serverCfg.systemd.units."sovoxd.service".unit.outPath
        == desktopCfg.systemd.units."sovoxd.service".unit.outPath)
      "editions diverge: sovoxd unit differs";
    assert lib.assertMsg
      (serverCfg.systemd.units."sovox-health-check.service".unit.outPath
        == desktopCfg.systemd.units."sovox-health-check.service".unit.outPath)
      "editions diverge: health gate differs";
    assert lib.assertMsg
      (serverCfg.boot.initrd.systemd.services.sovox-rollback.script
        == desktopCfg.boot.initrd.systemd.services.sovox-rollback.script)
      "editions diverge: impermanence rollback differs";
    assert lib.assertMsg
      (serverCfg.sovox.edition == "server" && desktopCfg.sovox.edition == "desktop")
      "example configs do not cover both editions";
    assert lib.assertMsg
      (roundTrip.node.name == serverCfg.sovox.node.name
        && roundTrip.edition == serverCfg.sovox.edition
        && roundTrip.node.ring == serverCfg.sovox.node.ring)
      "render → parse round-trip mangles [node]";
    assert lib.assertMsg
      (roundTrip.network.ipv6 == serverCfg.sovox.network.ipv6
        && roundTrip.network.mesh == serverCfg.sovox.network.mesh
        && roundTrip.network.expose.rpc == serverCfg.sovox.network.expose.rpc)
      "render → parse round-trip mangles [network]";
    assert lib.assertMsg
      (roundTrip.roles.enabled == serverCfg.sovox.roles.enabled
        && roundTrip.roles.tee.enable == serverCfg.sovox.roles.tee.enable
        && roundTrip.roles.ai.max_vram_percent == serverCfg.sovox.roles.ai.max_vram_percent)
      "render → parse round-trip mangles [roles] (tee enabled↔enable mapping?)";
    assert lib.assertMsg
      (roundTrip.updates.auto == serverCfg.sovox.updates.auto
        && roundTrip.backup.snapshots == serverCfg.sovox.backup.snapshots
        && roundTrip.identity.key_backend == serverCfg.sovox.identity.key_backend)
      "render → parse round-trip mangles [updates]/[backup]/[identity]";
    "parity-ok";
in
runTest ({ pkgs, ... }: {
  # seq forces the eval-time parity assertions before any VM boots.
  name = builtins.seq parity "sovox-edition-switch";

  nodes.machine = { lib, ... }: {
    imports = [ vmBase ];
    sovox.node.name = "machine";
    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;

    # The conversion under test: exactly one option.
    specialisation.desktop.configuration = {
      sovox.edition = "desktop";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sovoxd.service")

    ruleset_before = machine.succeed("nft list ruleset")

    with subtest("server → desktop activates"):
        machine.succeed(
            "/run/current-system/specialisation/desktop/bin/switch-to-configuration test >&2"
        )
        machine.wait_for_unit("display-manager.service")

    with subtest("sovereign core unchanged by the conversion"):
        machine.succeed("systemctl is-active sovoxd.service")
        ruleset_after = machine.succeed("nft list ruleset")
        assert ruleset_before == ruleset_after, "firewall changed across edition switch"

    with subtest("desktop → server activates back"):
        machine.succeed("/run/current-system/bin/switch-to-configuration test >&2")
        machine.succeed("systemctl is-active sovoxd.service")
  '';
})
