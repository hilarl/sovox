# Option namespace root: `sovox.*`.
#
# The namespace mirrors the sovox.toml schema keys (Operator Docs §3) verbatim,
# so the v0.1 sovoxd intent compiler lands into prepared slots. Only what the
# prototype needs is wired to real config; the rest is typed but inert.
{ config, lib, ... }:
let
  cfg = config.sovox;
in
{
  imports = [ ./edition.nix ./updates.nix ];

  options.sovox = {
    # ── Internal plumbing (not part of the sovox.toml surface) ────────────
    internal = {
      baselinePorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = ''
          Structural inbound ports, opened tcp+udp by hardening/base.nix.
          The shared core sets 9000 (libp2p/QUIC); roles append.
        '';
      };

      meshInterface = lib.mkOption {
        type = lib.types.str;
        default = "sovox-mesh";
        readOnly = true;
        description = "Reserved WireGuard admin-mesh interface name (lands v0.1).";
      };

      impermanence.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          ZFS blank-snapshot root impermanence (prototype thesis; never
          disabled on real systems). VM tests that do not exercise the ZFS
          boot chain may switch it off.
        '';
      };
    };

    # ── [node] ─────────────────────────────────────────────────────────────
    # `edition` from [node] maps to the top-level `sovox.edition`.
    node = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "sovox";
        description = "Node hostname ([node].name).";
      };
      ring = lib.mkOption {
        type = lib.types.enum [ "edge" "beta" "stable" ];
        default = "stable";
        description = "Update ring ([node].ring). Ring tooling is v0.1; the edge/stable split is pre-shaped by the dual nixpkgs inputs.";
      };
      timezone = lib.mkOption {
        type = lib.types.str;
        default = "UTC";
        description = "System timezone ([node].timezone).";
      };
    };

    # ── [network] (typed, unwired — sovoxd compiles these in v0.1) ───────
    network = {
      mesh = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "[network].mesh — WireGuard admin mesh (v0.1).";
      };
      ipv6 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "[network].ipv6.";
      };
      upnp = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "[network].upnp.";
      };
      expose = {
        rpc = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "[network.expose].rpc — loopback-only unless exposed (v0.1).";
        };
        mcp = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "[network.expose].mcp.";
        };
        a2a = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "[network.expose].a2a.";
        };
      };
    };

    # ── [identity] (typed, unwired — identity agent is v0.1, Arch §4.4) ──
    identity.key_backend = lib.mkOption {
      type = lib.types.enum [ "tpm2" "tee" "software" ];
      default = "software";
      description = "[identity].key_backend. Trust tiers T0→T3 change what a node can prove, never whether it can participate.";
    };

    # ── [observability] (typed, unwired) ─────────────────────────────────
    observability = {
      prometheus = lib.mkOption {
        type = lib.types.enum [ "mesh" "local" "off" ];
        default = "off";
        description = "[observability].prometheus.";
      };
      loki_endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[observability].loki_endpoint.";
      };
    };

    # ── [backup] (typed, unwired) ─────────────────────────────────────────
    backup = {
      snapshots = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "[backup].snapshots.";
      };
      send_target = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[backup].send_target.";
      };
    };
  };

  config = {
    networking.hostName = cfg.node.name;
    time.timeZone = cfg.node.timezone;
  };
}
