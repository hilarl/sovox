# WireGuard admin mesh — the [network].mesh switch (Operator Docs §3).
#
# The toml key is the whole public surface: a bare bool. Everything
# operational (addresses, peers, key location) lives under
# sovox.internal.mesh.* because peer sets are fleet wiring, not node
# intent, and must never round-trip through /etc/sovox/sovox.toml.
#
# Key lifecycle: the private key is generated on first activation
# (generatePrivateKeyFile) under /var/lib/sovox, which persists across the
# impermanent root. Nothing secret ever enters the Nix store.
#
# Posture consequence (enforced in hardening/base.nix): enabling the mesh
# on the standard profile closes WAN port 22 — SSH and Cockpit (9090,
# docs/03-ARCHITECTURE.md §3) are then reachable only from inside the
# mesh. Get the peer keys right BEFORE enabling, or the node is console-
# only; fleet/README.md documents the lockout risk.
{ config, lib, ... }:
let
  cfg = config.sovox;
  mesh = cfg.internal.mesh;
  iface = cfg.internal.meshInterface;
in
{
  options.sovox.internal.mesh = {
    address = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "10.42.0.1/24";
      description = "This node's mesh address in CIDR form. Required when [network].mesh is on.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "WireGuard listen port (opened udp on all interfaces for handshakes).";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sovox/mesh/private-key";
      description = "Private key path; generated on first activation if absent (never in the store).";
    };

    peers = lib.mkOption {
      default = [ ];
      description = "Mesh peers. Static fleet wiring in v0.0.x; the enrollment ceremony is v0.1.";
      type = lib.types.listOf (lib.types.submodule {
        options = {
          publicKey = lib.mkOption {
            type = lib.types.str;
            description = "Peer WireGuard public key.";
          };
          allowedIPs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            example = [ "10.42.0.2/32" ];
            description = "Mesh addresses routed to this peer.";
          };
          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "203.0.113.7:51820";
            description = "Peer WAN endpoint; null for peers that only dial in.";
          };
          persistentKeepalive = lib.mkOption {
            type = lib.types.int;
            default = 25;
            description = "Keepalive seconds — keeps NAT mappings alive for dial-in peers.";
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.network.mesh {
    assertions = [{
      assertion = mesh.address != "";
      message = ''
        sovox.network.mesh = true needs sovox.internal.mesh.address (this
        node's mesh CIDR, e.g. "10.42.0.1/24") — an interface with no
        address would close WAN SSH while offering nothing in return.
      '';
    }];

    networking.wireguard.interfaces.${iface} = {
      ips = [ mesh.address ];
      listenPort = mesh.listenPort;
      privateKeyFile = mesh.privateKeyFile;
      generatePrivateKeyFile = true;
      peers = map
        (p: {
          publicKey = p.publicKey;
          allowedIPs = p.allowedIPs;
          persistentKeepalive = p.persistentKeepalive;
        } // lib.optionalAttrs (p.endpoint != null) { endpoint = p.endpoint; })
        mesh.peers;
    };

    # Handshakes arrive on WAN; the admin surfaces (SSH, Cockpit) accept
    # only from inside the tunnel. sshd keeps listening on 0.0.0.0 —
    # nftables is the single enforcement point.
    sovox.internal.extraInputRules = ''
      # WireGuard admin mesh (modules/sovox/mesh.nix)
      udp dport ${toString mesh.listenPort} accept
      iifname "${iface}" tcp dport 22 accept
      iifname "${iface}" tcp dport 9090 accept
    '';

    # Holds the mesh key: survive the blank-snapshot root.
    environment.persistence."/persist".directories =
      lib.mkIf cfg.internal.impermanence.enable [
        { directory = "/var/lib/sovox"; mode = "0700"; }
      ];
  };
}
