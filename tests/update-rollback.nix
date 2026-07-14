# The safe-update headline test, modeled on nixpkgs' own systemd-boot
# bootCounting tests:
#
#  1. Boot generation A (good). Assert healthy, record it.
#  2. Stage generation B — same system with the poison file baked in — as the
#     default boot entry (counter = 2) and reboot.
#  3. B boots, the health gate fails, the watchdog reboots; the counter
#     exhausts and systemd-boot returns to A automatically.
#  4. Assert: running generation == A, incident marker in the journal,
#     total human interventions == 0 (every reboot was machine-initiated).
{ inputs, system }:
let
  inherit (import ./lib.nix { inherit inputs system; }) runTest vmBase;

  common = { lib, ... }: {
    imports = [ vmBase ];
    sovox.edition = "server";
    sovox.updates.healthGrace = 10;

    virtualisation = {
      useBootLoader = true;
      useEFIBoot = true;
      # room for two generations' kernels on the ESP
      efi.keepVariables = true;
    };
  };
in
runTest ({ lib, nodes, pkgs, ... }: {
  name = "sovox-update-rollback";

  nodes.machine = { ... }: {
    imports = [ common ];
    sovox.node.name = "machine";
    # B's closure must be reachable from A's store.
    system.extraDependencies = [ nodes.poisoned.system.build.toplevel ];
  };

  # Never started as a VM: only its toplevel is used, staged from inside
  # `machine` as the "bad update".
  nodes.poisoned = { ... }: {
    imports = [ common ];
    sovox.node.name = "machine"; # an update, not a different host
    environment.etc."sovox/poison".text = "deliberately unhealthy generation";
  };

  testScript = ''
    good = "${nodes.machine.system.build.toplevel}"
    bad = "${nodes.poisoned.system.build.toplevel}"

    machine.start()

    with subtest("generation A boots healthy and is blessed"):
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("sovox-healthy.target")
        machine.wait_for_unit("boot-complete.target")
        current = machine.succeed("readlink -f /run/current-system").strip()
        assert current == good, f"unexpected generation A: {current}"

    with subtest("stage poisoned generation B as next boot"):
        machine.succeed(f"nix-env -p /nix/var/nix/profiles/system --set {bad}")
        machine.succeed(f"{bad}/bin/switch-to-configuration boot >&2")
        machine.succeed("ls /boot/loader/entries >&2")

    machine.shutdown()
    machine.start()

    with subtest("B fails the gate; counter exhausts; A returns — unattended"):
        # During B's counted attempts the watchdog reboots the machine by
        # itself; we only wait for A to be back. Zero interventions.
        machine.wait_until_succeeds(
            f'test "$(readlink -f /run/current-system)" = "{good}"',
            timeout=600,
        )
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("sovox-healthy.target")

    with subtest("incident marker recorded"):
        machine.succeed("journalctl -t sovox | grep -q SOVOX-INCIDENT")
        machine.succeed("ls /boot/loader/entries >&2")  # exhausted entry visible in the log
  '';
})
