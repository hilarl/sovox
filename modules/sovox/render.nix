# Renders the sovox.* option tree to /etc/sovox/sovox.toml — the intent file
# (Operator Docs §3) as the machine actually runs it. sovoxd parses this at
# request time and serves it back on /status, /config, and /roles; a file
# that fails to parse fails the boot health gate.
#
# The rendered file stays inside the TOML subset sovoxd parses: table
# headers, strings, booleans, integers, string arrays — no inline tables.
# That is why agent-hub.spend_budget is a string here (the docs show an
# inline table; the string form carries the same "per_tx=…,per_day=…"
# policy until the option is restructured).
#
# One deliberate divergence from the docs schema: the [roles.tee] key is
# `enabled` in the docs, while the option follows module convention
# (`sovox.roles.tee.enable`); the render maps between them.
{ config, lib, pkgs, ... }:
let
  cfg = config.sovox;
  settingsFormat = pkgs.formats.toml { };

  intent = {
    node = {
      name = cfg.node.name;
      edition = cfg.edition;
      ring = cfg.node.ring;
      timezone = cfg.node.timezone;
    };

    network = {
      mesh = cfg.network.mesh;
      ipv6 = cfg.network.ipv6;
      upnp = cfg.network.upnp;
      expose = {
        rpc = cfg.network.expose.rpc;
        mcp = cfg.network.expose.mcp;
        a2a = cfg.network.expose.a2a;
      };
    };

    roles = {
      enabled = cfg.roles.enabled;
      ai = {
        profile = cfg.roles.ai.profile;
        serve = cfg.roles.ai.serve;
        train = cfg.roles.ai.train;
        rental = cfg.roles.ai.rental;
        models = cfg.roles.ai.models;
        max_vram_percent = cfg.roles.ai.max_vram_percent;
        train_bandwidth = cfg.roles.ai.train_bandwidth;
      };
      storage = {
        capacity = cfg.roles.storage.capacity;
        dataset = cfg.roles.storage.dataset;
      };
      validator = {
        stake_warn_below = cfg.roles.validator.stake_warn_below;
      };
      tee = {
        enabled = cfg.roles.tee.enable;
        gpu_cc = cfg.roles.tee.gpu_cc;
      };
      web = {
        sites = cfg.roles.web.sites;
      };
      email = {
        domains = cfg.roles.email.domains;
      };
      agent-hub = {
        skills_dir = cfg.roles.agent-hub.skills_dir;
        fuel_budget = cfg.roles.agent-hub.fuel_budget;
        spend_budget = cfg.roles.agent-hub.spend_budget;
      };
    };

    updates = {
      auto = cfg.updates.auto;
      window = cfg.updates.window;
      download_only = cfg.updates.download_only;
    };

    identity = {
      key_backend = cfg.identity.key_backend;
    };

    observability = {
      prometheus = cfg.observability.prometheus;
      loki_endpoint = cfg.observability.loki_endpoint;
    };

    backup = {
      snapshots = cfg.backup.snapshots;
      send_target = cfg.backup.send_target;
    };
  };
in
{
  environment.etc."sovox/sovox.toml".source =
    settingsFormat.generate "sovox.toml" intent;
}
