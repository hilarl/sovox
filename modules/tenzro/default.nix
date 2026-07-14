# tenzro-node as a fully sandboxed systemd unit (docs/03-ARCHITECTURE.md §6).
#
# Upstream tenzro-node is CLI-driven: roles and data directory are flags,
# not a config file. The unit passes exactly the roles the binary
# understands; everything else about a role (rendering into
# /etc/sovox/sovox.toml, warnings, firewall posture) lives in
# modules/roles and modules/sovox.
#
# No `tenzro join --provider`, no wallet, no earnings: the identity agent
# (docs/03-ARCHITECTURE.md §4.4) owns those and it doesn't exist yet. Faking
# them would create migration debt. Disabled by default; only enable once
# the package is pinned to a real upstream release.
{ config, lib, pkgs, ... }:
let
  cfg = config.sovox.tenzro;
  roles = config.sovox.roles;

  # Roles tenzro-node itself understands (--roles validator,light,ai,storage).
  # Sovox-side roles — web, email, agent-hub, tee-provider, compute — are
  # served by other subsystems (or are not implemented yet) and must not be
  # passed to the node binary.
  upstreamRoles =
    lib.optional roles.validator.enable "validator"
    ++ lib.optional roles.ai.enable "ai"
    ++ lib.optional roles.storage.enable "storage";

  # A node with no earning role still participates as a light node.
  nodeRoles = if upstreamRoles == [ ] then [ "light" ] else upstreamRoles;
in
{
  options.sovox.tenzro = {
    enable = lib.mkEnableOption "tenzro-node (CPU variant only — the CUDA overlay matrix is v0.1)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "Pinned tenzro-node derivation (upstream release binary or Rust workspace build).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.package.version != "0.0.0-pin-me";
      message = ''
        sovox.tenzro.enable = true, but the tenzro-node package is still the
        placeholder pin (modules/tenzro/package.nix). Upstream has published
        no release to pin yet. Point sovox.tenzro.package at a real
        derivation, or keep the role declarations and leave enable = false.
      '';
    }];

    # Network contract: 9000/tcp+udp appended to baseline (dedup'd by
    # hardening/base.nix); RPC surfaces (ethereum/web/mcp/a2a) bind loopback
    # by upstream default — no firewall rule can re-expose what never binds
    # a routable address.
    sovox.internal.baselinePorts = [ 9000 ];

    # Unit hardening exactly per docs/03-ARCHITECTURE.md §6.
    systemd.services.tenzro-node = {
      description = "Tenzro Network node";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/tenzro-node --roles ${lib.concatStringsSep "," nodeRoles} --data-dir /var/lib/tenzro";
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        StateDirectory = "tenzro";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

        # cgroup weights: the node yields to interactive/system work
        CPUWeight = 90;
        IOWeight = 90;
      };
    };

    # /var/lib/tenzro persists across the impermanent root; on real disks it
    # is the dedicated dataset from images/disko/*.nix.
    environment.persistence."/persist".directories =
      lib.mkIf config.sovox.internal.impermanence.enable [ "/var/lib/tenzro" ];
  };
}
