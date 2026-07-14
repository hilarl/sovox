# [backup] wiring (Operator Docs §3, docs/03-ARCHITECTURE.md §10).
#
# snapshots = "hourly=24,daily=14,weekly=8" — retention policy compiled to
# sanoid over rpool/safe, recursively: everything that survives the blank-
# snapshot root gets snapshotted, nothing else does. Gated on impermanence
# because rpool/safe only exists on the real disk layout; framework VMs
# have no pool to snapshot.
#
# send_target renders into the intent file; `backup send` replication is
# v0.1 (the tenzro-storage client path is v0.2).
{ config, lib, ... }:
let
  cfg = config.sovox.backup;

  periodNames = [ "frequently" "hourly" "daily" "weekly" "monthly" "yearly" ];
  pairRe = "(${lib.concatStringsSep "|" periodNames})=[0-9]+";
  policyValid = builtins.match "${pairRe}(,${pairRe})*" cfg.snapshots != null;

  policy = lib.listToAttrs (map
    (pair:
      let kv = lib.splitString "=" pair;
      in lib.nameValuePair (lib.elemAt kv 0) (lib.toInt (lib.elemAt kv 1)))
    (lib.splitString "," cfg.snapshots));
in
{
  config = {
    assertions = [{
      assertion = cfg.snapshots == "" || policyValid;
      message = ''
        sovox.backup.snapshots must be comma-separated period=count pairs
        (periods: ${lib.concatStringsSep ", " periodNames}), e.g.
        "hourly=24,daily=14,weekly=8" — got "${cfg.snapshots}".
      '';
    }];

    warnings = lib.optional (cfg.send_target != "")
      ("sovox.backup.send_target is recorded in the intent file, but "
        + "off-node replication is not wired in v0.0.x — snapshots stay local.");

    services.sanoid = lib.mkIf
      (cfg.snapshots != "" && policyValid
        && config.sovox.internal.impermanence.enable)
      {
        enable = true;
        datasets."rpool/safe" = {
          recursive = true;
          autosnap = true;
          autoprune = true;
        } // policy;
      };
  };
}
