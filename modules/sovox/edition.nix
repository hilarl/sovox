# Editions. One module tree; editions are deltas selected by a single enum
# option, never separate configurations. Desktop relaxes only
# interactive-shell and enrollment ergonomics — never the measurement chain,
# firewall posture, or impermanence (docs/03-ARCHITECTURE.md §2.1 invariant).
{ config, lib, pkgs, ... }:
let
  cfg = config.sovox;
in
{
  options.sovox = {
    edition = lib.mkOption {
      type = lib.types.enum [ "server" "desktop" ];
      default = "server";
      description = ''
        Sovox edition. "server" is the headless appliance;
        "desktop" adds KDE Plasma 6 on the same declarative core.
        Conversion between editions is exactly this one option.
      '';
    };

    profile = lib.mkOption {
      type = lib.types.enum [ "standard" "hardened" ];
      default = "standard";
      description = ''
        "hardened" (Server only): no interactive shell, SSH via
        WireGuard mesh only, no WAN-listening admin surface.
      '';
    };
  };

  config = lib.mkMerge [
    # ── Shared sovereign core: identical in both editions ──────────
    {
      # hardening/base.nix, impermanence.nix imported unconditionally
      networking.firewall.enable = false; # nftables module owns policy
      sovox.internal.baselinePorts = [ 9000 ]; # tcp+udp; roles append
      services.chrony = { enable = true; enableNTS = true; };
      documentation.nixos.enable = false; # appliance posture
    }

    # ── Server edition ──────────────────────────────────────────────
    (lib.mkIf (cfg.edition == "server") {
      services.xserver.enable = false;
      services.cockpit = { enable = true; openFirewall = false; }; # mesh/localhost only
      boot.kernelParams = [ "console=ttyS0" ]; # headless serial
    })

    # ── Hardened profile constraint ────────────────────────────────
    (lib.mkIf (cfg.profile == "hardened") {
      assertions = [{
        assertion = cfg.edition == "server";
        message = "sovox.profile = \"hardened\" is only valid with edition = \"server\".";
      }];
      # no-interactive-shell, mesh-only SSH — lands with the WireGuard mesh (v0.1)
    })

    # ── Desktop edition (modules/desktop/plasma.nix carries detail) ─
    (lib.mkIf (cfg.edition == "desktop") {
      services.desktopManager.plasma6.enable = true;
      services.displayManager.sddm.enable = true;
      # Firewall, impermanence, boot chain: unchanged — deltas are UX only.
    })
  ];
}
