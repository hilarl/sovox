# [observability] wiring (Operator Docs §3).
#
# prometheus = "local"  → node exporter on 127.0.0.1:9100 (scrape locally,
#                         tunnel out however you like).
# prometheus = "mesh"   → node exporter admitted only from inside the
#                         WireGuard admin mesh. Like SSH, the exporter
#                         listens wide and nftables is the single
#                         enforcement point — binding to the mesh address
#                         itself would race interface bring-up at boot.
# loki_endpoint         → renders into the intent file; the shipper is v0.1.
{ config, lib, ... }:
let
  cfg = config.sovox.observability;
in
{
  config = {
    assertions = [{
      assertion = cfg.prometheus != "mesh" || config.sovox.network.mesh;
      message = ''
        sovox.observability.prometheus = "mesh" needs sovox.network.mesh =
        true — without the mesh there is no interface to admit scrapes from,
        and falling back to a WAN-open exporter is not a fallback.
      '';
    }];

    warnings = lib.optional (cfg.loki_endpoint != "")
      ("sovox.observability.loki_endpoint is recorded in the intent file, "
        + "but log shipping is not wired in v0.0.x — nothing sends to it yet.");

    services.prometheus.exporters.node = lib.mkIf (cfg.prometheus != "off") {
      enable = true;
      port = 9100;
      listenAddress = lib.mkIf (cfg.prometheus == "local") "127.0.0.1";
      openFirewall = false;
    };

    sovox.internal.extraInputRules =
      lib.mkIf (cfg.prometheus == "mesh" && config.sovox.network.mesh) ''
        # node exporter, mesh-side only (modules/sovox/observability.nix)
        iifname "${config.sovox.internal.meshInterface}" tcp dport 9100 accept
      '';
  };
}
