# Update & rollback skeleton: staged updates that cannot brick a node.
#
# Mechanism: systemd-boot boot counting (tries = 2) + a health gate wired into
# systemd's boot-success contract. A staged generation that fails to reach
# `sovox-healthy.target` is never blessed; the counter exhausts and the
# machine returns to the previous generation in ≤1 reboot, unattended.
#
# `sovox update` semantics at this stage are `nixos-rebuild boot --flake`
# against a newer rev; the signed channel manifest, rings, and jittered
# polling are v0.1 sovoxd work layered on the contract proven here.
{ config, lib, pkgs, ... }:
let
  cfg = config.sovox.updates;
  sovoxd = pkgs.callPackage ../../packages/sovoxd { };
  socketPath = "/run/sovoxd/sovoxd.sock";
  configPath = "/etc/sovox/sovox.toml";

  # [updates].window: "HH:MM-HH:MM" local time (Operator Docs §3). The timer
  # fires at the window start with a randomized delay spanning the window,
  # so a fleet on the same intent does not update in lockstep. Empty window
  # means the docs default, 02:00-05:00.
  window = if cfg.window == "" then "02:00-05:00" else cfg.window;
  windowValid =
    builtins.match "[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}" window != null;
  # Fall back to the default window when invalid so the assertion below is
  # what fails, not an arithmetic throw inside the timer definition.
  windowStart = if windowValid then lib.elemAt (lib.splitString "-" window) 0 else "02:00";
  windowEnd = if windowValid then lib.elemAt (lib.splitString "-" window) 1 else "05:00";
  toMinutes = t:
    let p = lib.splitString ":" t;
    in lib.toInt (lib.elemAt p 0) * 60 + lib.toInt (lib.elemAt p 1);
  # Window spans past midnight when end < start.
  windowSpanSec =
    let s = toMinutes windowStart; e = toMinutes windowEnd;
    in 60 * (if e > s then e - s else e + 1440 - s);

  updateActive = cfg.auto && config.sovox.internal.updates.source != null;
in
{
  options.sovox.internal.updates.source = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "github:hilarl/sovox";
    description = ''
      Flake reference the unattended updater rebuilds from. Internal knob:
      the signed channel manifest and ring resolution are sovoxd work
      (v0.1); until then the operator names the source explicitly.
      [updates].auto without a source warns and stays inert.
    '';
  };

  options.sovox.updates = {
    # ── [updates] sovox.toml mirror ────────────────────────────────────────
    auto = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "[updates].auto — unattended staged updates inside the maintenance window. Needs sovox.internal.updates.source.";
    };
    window = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "02:00-05:00";
      description = "[updates].window — local-time maintenance window \"HH:MM-HH:MM\". Empty means 02:00-05:00. Epoch-aware deferral is v0.1.";
    };
    download_only = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "[updates].download_only — build/fetch the new closure but neither stage nor reboot.";
    };

    # ── Prototype health-gate knobs ────────────────────────────────────────
    checkClock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Gate on chrony synchronization. Offline VM tests disable this single check.";
    };
    healthGrace = lib.mkOption {
      type = lib.types.ints.positive;
      default = 90;
      description = "Seconds the rollback watchdog waits for boot-complete.target before rebooting into the previous generation.";
    };
  };

  config = {
    boot.loader.systemd-boot = {
      enable = true;
      bootCounting = {
        enable = true;
        tries = 2;
      };
    };

    # systemd-bless-boot(-generator) come from upstream systemd; the counted
    # entry is only marked good once boot-complete.target is reached.
    #
    # boot-complete.target is passive and must NOT be wanted by
    # multi-user.target: target units auto-order After= their Wants=, and the
    # health gate is After=multi-user.target + Before=boot-complete.target —
    # that would be an ordering cycle systemd breaks by deleting the gate's
    # job. The rollback watchdog pulls the target in instead (service Wants=
    # carries no ordering), so every boot still activates it when healthy.

    # ── sovoxd: health gate, node status, intent introspection (Arch §4.5) ─
    systemd.services.sovoxd = {
      description = "Sovox node daemon";
      wantedBy = [ "multi-user.target" ];
      # Deliberately NO restartTriggers on the rendered intent file: the
      # daemon re-reads it per request, so a swapped generation is picked up
      # live — and referencing the edition-bearing file from the unit would
      # break the cross-edition parity invariant (tests/edition-switch.nix:
      # the sovoxd unit must be the identical derivation in both editions).
      serviceConfig = {
        ExecStart = "${sovoxd}/bin/sovoxd --socket ${socketPath} --config ${configPath}";
        RuntimeDirectory = "sovoxd";
        RuntimeDirectoryMode = "0755";
        Restart = "on-failure";
        # full unit sandboxing (docs/03-ARCHITECTURE.md §6 pattern)
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    # ── The gate. Success units use RequiredBy=boot-complete.target ────────
    systemd.services.sovox-health-check = {
      description = "Sovox boot health gate";
      requires = [ "sovoxd.service" ];
      after = [ "sovoxd.service" "multi-user.target" ]
        ++ lib.optional cfg.checkClock "chronyd.service";
      requiredBy = [ "boot-complete.target" ];
      before = [ "boot-complete.target" "sovox-healthy.target" ];
      wantedBy = [ "sovox-healthy.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 300;
      };
      path = [ pkgs.curl pkgs.chrony config.systemd.package ];
      script = ''
        # 1. sovoxd answers healthy on its local socket (poison file ⇒ 503 ⇒ fail)
        curl --silent --fail --unix-socket ${socketPath} http://localhost/health

        # 2. no failed units
        failed=$(systemctl list-units --state=failed --no-legend | wc -l)
        if [ "$failed" -ne 0 ]; then
          echo "sovox-health-check: $failed failed unit(s)" >&2
          systemctl list-units --state=failed --no-legend >&2
          exit 1
        fi

        ${lib.optionalString cfg.checkClock ''
        # 3. clock sanity (chrony synchronized)
        chronyc waitsync 20 0.5
        ''}
      '';
    };

    # Same cycle rule as boot-complete.target: pulled in by the watchdog,
    # never by multi-user.target.
    systemd.targets.sovox-healthy = {
      description = "Sovox node is healthy";
      requires = [ "sovox-health-check.service" ];
      after = [ "sovox-health-check.service" ];
    };

    # ── Watchdog: makes "zero human interventions" literal ────────────────
    # If the gate is not reached within the grace period, log an incident
    # marker and reboot; the boot counter does the rest.
    systemd.services.sovox-rollback-watchdog = {
      description = "Reboot if the boot health gate is not reached";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      wants = [ "boot-complete.target" "sovox-healthy.target" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "infinity";
      };
      path = [ config.systemd.package ];
      script = ''
        sleep ${toString cfg.healthGrace}
        if ! systemctl --quiet is-active boot-complete.target; then
          echo "SOVOX-INCIDENT: health gate failed for generation $(readlink /run/current-system); rebooting for rollback" \
            | systemd-cat -t sovox -p err
          systemctl reboot
        fi
      '';
    };

    # ── Unattended updates: stage, reboot into the gate ───────────────────
    # `nixos-rebuild boot` against the named source; if a new generation was
    # staged (and not download_only), reboot into it. The boot counter and
    # the health gate above make a bad update self-correcting — this timer
    # adds no safety logic of its own, by design.
    assertions = [{
      assertion = windowValid;
      message = ''
        sovox.updates.window must be "HH:MM-HH:MM" (local time), e.g.
        "02:00-05:00" — got "${cfg.window}".
      '';
    }];

    warnings = lib.optional (cfg.auto && config.sovox.internal.updates.source == null)
      ("sovox.updates.auto = true but sovox.internal.updates.source is unset "
        + "— the update timer is inert. Name the flake to rebuild from, or "
        + "disable auto.");

    systemd.services.sovox-update = lib.mkIf updateActive {
      description = "Sovox staged update";
      # Never race the boot health gate: only update on an already-blessed boot.
      after = [ "network-online.target" "boot-complete.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "sovox-update";
        WorkingDirectory = "/var/lib/sovox-update";
      };
      path = [ pkgs.nixos-rebuild pkgs.git config.nix.package config.systemd.package ];
      script = ''
        current="$(readlink -f /run/current-system)"

        ${if cfg.download_only then ''
        # download_only: fetch/build the closure so the window's work is
        # done, but neither stage a boot entry nor reboot.
        nixos-rebuild build --flake ${lib.escapeShellArg config.sovox.internal.updates.source}
        '' else ''
        nixos-rebuild boot --flake ${lib.escapeShellArg config.sovox.internal.updates.source}
        staged="$(readlink -f /nix/var/nix/profiles/system)"
        if [ "$staged" != "$current" ]; then
          echo "sovox-update: staged $staged (running $current); rebooting into the health gate" \
            | systemd-cat -t sovox
          systemctl reboot
        fi
        ''}
      '';
    };

    systemd.timers.sovox-update = lib.mkIf updateActive {
      description = "Sovox maintenance-window update timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${windowStart}:00";
        RandomizedDelaySec = windowSpanSec;
        Persistent = true;
      };
    };
  };
}
