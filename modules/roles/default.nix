# Roles: typed options mirroring the sovox.toml [roles] schema (Operator
# Docs §3). `sovox.roles.enabled` is the canonical list; each per-role
# `enable` defaults from membership in it, and the two must agree.
#
# Enabled roles render into /etc/sovox/sovox.toml and into the tenzro-node
# unit's --roles flags (modules/tenzro). Until tenzro-node is pinned to a
# real upstream release, that is declaration without execution — hence the
# warning below, not an error.
{ config, lib, ... }:
let
  cfg = config.sovox.roles;

  roleNames = [
    "validator"
    "ai"
    "ai.serve"
    "ai.train"
    "compute"
    "storage"
    "tee-provider"
    "web"
    "email"
    "agent-hub"
  ];

  inEnabled = role: lib.elem role cfg.enabled;

  mkRoleEnable = role: lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable the ${role} role. Defaults from membership in sovox.roles.enabled.";
  };

  # Per-role enable option ↔ its canonical name in the enabled list.
  roleEnables = {
    validator = cfg.validator.enable;
    ai = cfg.ai.enable;
    storage = cfg.storage.enable;
    "tee-provider" = cfg.tee.enable;
    web = cfg.web.enable;
    email = cfg.email.enable;
    "agent-hub" = cfg.agent-hub.enable;
  };

  # What each per-role enable should be, given the enabled list. "ai.serve"
  # and "ai.train" are capabilities of the ai role, so either implies it.
  expectedEnable = {
    validator = inEnabled "validator";
    ai = inEnabled "ai" || inEnabled "ai.serve" || inEnabled "ai.train";
    storage = inEnabled "storage";
    "tee-provider" = inEnabled "tee-provider";
    web = inEnabled "web";
    email = inEnabled "email";
    "agent-hub" = inEnabled "agent-hub";
  };

  inconsistent = lib.filterAttrs (name: enabled: enabled != expectedEnable.${name}) roleEnables;
in
{
  options.sovox.roles = {
    enabled = lib.mkOption {
      type = lib.types.listOf (lib.types.enum roleNames);
      default = [ ];
      description = "[roles].enabled — canonical role names per protocol docs.";
    };

    ai = {
      enable = mkRoleEnable "ai";
      profile = lib.mkOption {
        type = lib.types.enum [ "native" "throughput" ];
        default = "native";
        description = "[roles.ai].profile.";
      };
      serve = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "[roles.ai].serve.";
      };
      train = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "[roles.ai].train.";
      };
      rental = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "[roles.ai].rental.";
      };
      models = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "[roles.ai].models.";
      };
      max_vram_percent = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 90;
        description = "[roles.ai].max_vram_percent.";
      };
      train_bandwidth = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[roles.ai].train_bandwidth.";
      };
    };

    storage = {
      enable = mkRoleEnable "storage";
      capacity = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[roles.storage].capacity.";
      };
      dataset = lib.mkOption {
        type = lib.types.str;
        default = "rpool/safe/state/shards";
        description = "[roles.storage].dataset.";
      };
    };

    validator = {
      enable = mkRoleEnable "validator";
      stake_warn_below = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[roles.validator].stake_warn_below.";
      };
    };

    tee = {
      enable = mkRoleEnable "tee-provider";
      gpu_cc = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = "[roles.tee].gpu_cc.";
      };
    };

    web = {
      enable = mkRoleEnable "web";
      sites = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "[roles.web].sites.";
      };
    };

    email = {
      enable = mkRoleEnable "email";
      domains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "[roles.email].domains.";
      };
    };

    agent-hub = {
      enable = mkRoleEnable "agent-hub";
      skills_dir = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[roles.agent-hub].skills_dir.";
      };
      fuel_budget = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[roles.agent-hub].fuel_budget.";
      };
      spend_budget = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "[roles.agent-hub].spend_budget.";
      };
    };
  };

  config = {
    # enabled list → per-role enable defaults. "ai.serve"/"ai.train" imply
    # the ai role with the matching capability switched on.
    sovox.roles = {
      validator.enable = lib.mkDefault (inEnabled "validator");
      ai.enable = lib.mkDefault (inEnabled "ai" || inEnabled "ai.serve" || inEnabled "ai.train");
      ai.serve = lib.mkDefault (inEnabled "ai.serve");
      ai.train = lib.mkDefault (inEnabled "ai.train");
      storage.enable = lib.mkDefault (inEnabled "storage");
      tee.enable = lib.mkDefault (inEnabled "tee-provider");
      web.enable = lib.mkDefault (inEnabled "web");
      email.enable = lib.mkDefault (inEnabled "email");
      agent-hub.enable = lib.mkDefault (inEnabled "agent-hub");
    };

    assertions = [{
      assertion = inconsistent == { };
      message = ''
        sovox.roles: per-role enable disagrees with sovox.roles.enabled for:
        ${lib.concatStringsSep ", " (lib.attrNames inconsistent)}.
        Declare roles in sovox.roles.enabled; the per-role enable follows.
      '';
    }];

    # No node binary runs these roles yet: tenzro-node has no upstream
    # release to pin (modules/tenzro/package.nix). Declaring roles is still
    # meaningful — they render into the intent file and the unit definition —
    # but it must not pass silently as if the node were earning.
    warnings = lib.optional (cfg.enabled != [ ] && !config.sovox.tenzro.enable)
      ("sovox.roles: [" + lib.concatStringsSep ", " cfg.enabled + "] declared "
        + "but sovox.tenzro.enable is false — roles render into "
        + "/etc/sovox/sovox.toml and the tenzro-node unit, and start running "
        + "once tenzro-node is pinned and enabled.");
  };
}
