# Admin-mesh test: WireGuard handshake, WAN SSH closed, SSH over the mesh,
# baseline network contract unchanged. No ZFS/bootloader machinery — this
# is the fast check of the posture switch in modules/sovox/mesh.nix +
# modules/hardening/base.nix.
#
# Keys are nixpkgs' own wireguard test snakeoil pairs
# (nixos/tests/wireguard/snakeoil-keys.nix) — fixed keys so each side can
# pin the other. Real nodes generate their key on first activation.
{ inputs, system }:
let
  inherit (import ./lib.nix { inherit inputs system; }) runTest vmBase;

  serverKey = {
    private = "OPuVRS2T0/AtHDp3PXkNuLQYDiqJaBEEnYe42BSnJnQ=";
    public = "IujkG119YPr2cVQzJkSLYCdjpHIDjvr/qH1w1tdKswY=";
  };
  probeKey = {
    private = "uO8JVo/sanx2DOM0L9GUEtzKZ82RGkRnYgpaYc7iXmg=";
    public = "Ks9yRJIi/0vYgRmn14mIOQRwkcUGBujYINbMpik2SBI=";
  };
in
runTest ({ lib, pkgs, ... }:
  let
    sshKeys = import (inputs.nixpkgs + "/nixos/tests/ssh-keys.nix") pkgs;
  in
  {
    name = "sovox-mesh";

    nodes.server = {
      imports = [ vmBase ];
      sovox.node.name = "server";
      sovox.edition = "server";
      sovox.network.mesh = true;
      sovox.internal.mesh = {
        address = "10.42.0.1/24";
        peers = [{
          publicKey = probeKey.public;
          allowedIPs = [ "10.42.0.2/32" ];
        }];
      };

      # Test-only fixed key (see header). f+ truncates, so re-runs are
      # deterministic; the wireguard unit orders after tmpfiles setup.
      systemd.tmpfiles.rules = [
        "d /var/lib/sovox 0700 root root -"
        "d /var/lib/sovox/mesh 0700 root root -"
        "f+ /var/lib/sovox/mesh/private-key 0400 root root - ${serverKey.private}"
      ];

      users.users.root.openssh.authorizedKeys.keys = [ sshKeys.snakeOilPublicKey ];
    };

    # The peer: plain WireGuard client, deliberately not using the sovox
    # mesh module — it plays the operator's admin machine.
    nodes.probe = {
      imports = [ vmBase ];
      sovox.node.name = "probe";
      environment.systemPackages = [ pkgs.netcat ];
      networking.wireguard.interfaces.wg0 = {
        ips = [ "10.42.0.2/24" ];
        privateKey = probeKey.private; # test-only: a real key never sits in the store
        peers = [{
          publicKey = serverKey.public;
          allowedIPs = [ "10.42.0.1/32" ];
          endpoint = "server:51820";
          persistentKeepalive = 25;
        }];
      };
    };

    testScript = ''
      start_all()
      server.wait_for_unit("multi-user.target")
      probe.wait_for_unit("multi-user.target")

      with subtest("mesh comes up: handshake and tunnel routing work"):
          server.wait_for_unit("wireguard-sovox-mesh.service")
          probe.wait_for_unit("wireguard-wg0.service")
          probe.wait_until_succeeds("ping -c1 -W2 10.42.0.1", timeout=60)

      with subtest("WAN port 22 is dropped once the mesh is on"):
          probe.succeed("rc=0; timeout 3 nc -z server 22 || rc=$?; test $rc -eq 124")

      with subtest("SSH rides the mesh"):
          server.wait_for_unit("sshd.service")
          probe.succeed("nc -z 10.42.0.1 22")
          probe.succeed("install -m 0600 ${sshKeys.snakeOilPrivateKey} /root/id_test")
          probe.succeed(
              "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "
              "-i /root/id_test root@10.42.0.1 true"
          )

      with subtest("baseline network contract unchanged: 9000 passed, others dropped"):
          # 9000: firewall passes it — connection refused (rc 1), not filtered
          probe.succeed("rc=0; timeout 3 nc -z server 9000 || rc=$?; test $rc -eq 1")
          probe.succeed("rc=0; timeout 3 nc -z server 80 || rc=$?; test $rc -eq 124")
    '';
  })
