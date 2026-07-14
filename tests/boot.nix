# Boot & impermanence test: boots the sovox module set with a real ZFS root,
# proves impermanence (file on / gone after reboot), persistence (SSH host key
# unchanged via /persist), the health gate, and the network posture.
#
# Deliberate test-design choices, stated plainly:
#  - This boots the same module set in a framework VM, not the raw artifact
#    (raw-image boot smoke is a tracked issue, fleet/README.md).
#  - LUKS is dropped in the test VM only: interactive unlock in a VM test
#    proves nothing about impermanence.
#  - Port 22 answers in addition to 9000 — the documented prototype exception
#    (standard profile, modules/hardening/base.nix); "hardened" removes it.
{ inputs, system }:
let
  inherit (import ./lib.nix { inherit inputs system; }) runTest vmBase;
in
runTest ({ lib, pkgs, ... }: {
  name = "sovox-boot";

  nodes.server = { lib, config, ... }: {
    imports = [ vmBase ];
    sovox.node.name = "server";
    sovox.edition = "server";
    # The point of this test: the real ZFS impermanence chain.
    sovox.internal.impermanence.enable = true;
    sovox.updates.healthGrace = 3600; # watchdog must not fire mid-test

    virtualisation = {
      # No prebuilt root image: the pool below is the root.
      diskImage = null;
      emptyDiskImages = [ 4096 ]; # /dev/vda — backing device for rpool
      useDefaultFilesystems = false;
      mountHostNixStore = true;
      fileSystems = lib.mkForce { };
    };

    fileSystems."/" = {
      device = "rpool/local/root";
      fsType = "zfs";
    };
    fileSystems."/nix/store" = {
      device = "nix-store";
      fsType = "9p";
      neededForBoot = true;
      options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "msize=16384" ];
    };
    fileSystems."/persist" = {
      device = "rpool/safe/state";
      fsType = "zfs";
    };

    # First boot only: create the pool + contract datasets + @blank, then
    # export so the regular zfs-import-rpool path owns the import.
    boot.initrd.systemd.services.sovox-test-mkpool = {
      description = "Create test rpool (first boot only)";
      wantedBy = [ "initrd.target" ];
      before = [ "zfs-import-rpool.service" ];
      after = [ "systemd-udev-settle.service" ];
      wants = [ "systemd-udev-settle.service" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        for _ in $(seq 50); do [ -e /dev/vda ] && break; sleep 0.2; done
        if ! zpool import -N rpool 2>/dev/null; then
          zpool create -f -o ashift=12 \
            -O mountpoint=none -O compression=zstd -O atime=off \
            -O xattr=sa -O acltype=posixacl rpool /dev/vda
          zfs create -o mountpoint=none rpool/local
          zfs create -o mountpoint=legacy rpool/local/root
          zfs create -o mountpoint=none rpool/safe
          zfs create -o mountpoint=legacy rpool/safe/state
          zfs snapshot rpool/local/root@blank
        fi
        zpool export rpool
      '';
    };
  };

  # Plain observer for the external network-posture assertion.
  nodes.probe = {
    imports = [ vmBase ];
    sovox.node.name = "probe";
    environment.systemPackages = [ pkgs.netcat ];
  };

  testScript = ''
    server.start()
    probe.start()

    with subtest("boots to multi-user with ZFS root"):
        server.wait_for_unit("multi-user.target")
        server.succeed("zfs list rpool/local/root")
        assert "zfs" in server.succeed("findmnt -n -o FSTYPE /")

    with subtest("health gate reached on a healthy system"):
        server.wait_for_unit("sovox-healthy.target")
        server.wait_for_unit("boot-complete.target")

    with subtest("host key persists, root file does not"):
        server.wait_for_unit("sshd.service")
        hostkey = server.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub")
        server.succeed("touch /root/ephemeral-file")
        server.succeed("test -e /root/ephemeral-file")

    server.shutdown()
    server.start()

    with subtest("impermanence: file gone, host key unchanged after reboot"):
        server.wait_for_unit("multi-user.target")
        server.fail("test -e /root/ephemeral-file")
        hostkey2 = server.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub")
        assert hostkey == hostkey2, "SSH host key changed across reboot"

    with subtest("network posture: default-deny, 9000 allowed, 22 prototype exception"):
        probe.wait_for_unit("multi-user.target")
        server.succeed("nft list ruleset | grep -q 'policy drop'")
        # 22: reachable (prototype exception, modules/hardening/base.nix)
        probe.succeed("nc -z server 22")
        # 9000: firewall passes it — connection refused (rc 1), not filtered
        probe.succeed("rc=0; timeout 3 nc -z server 9000 || rc=$?; test $rc -eq 1")
        # anything else: dropped — nc hangs until timeout kills it (rc 124)
        probe.succeed("rc=0; timeout 3 nc -z server 80 || rc=$?; test $rc -eq 124")
        probe.succeed("rc=0; timeout 3 nc -z server 9090 || rc=$?; test $rc -eq 124")
  '';
})
