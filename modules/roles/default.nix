# Role stubs: typed options mirroring the sovox.toml [roles] schema
# (Operator Docs §3) with no logic. Role implementations are v0.1 sovoxd work;
# enabling any role in the prototype fails at evaluation.
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

  mkRoleEnable = role: lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable the ${role} role (v0.1; forbidden in the prototype).";
  };
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

  config.assertions = [{
    assertion =
      cfg.enabled == [ ]
      && !cfg.ai.enable && !cfg.storage.enable && !cfg.validator.enable
      && !cfg.tee.enable && !cfg.web.enable && !cfg.email.enable
      && !cfg.agent-hub.enable;
    message = "sovox.roles.*: roles land in v0.1; the prototype forbids enabling them.";
  }];
}
