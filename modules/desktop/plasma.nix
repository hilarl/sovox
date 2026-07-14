# KDE Plasma 6 deltas only. Everything here is UX; the sovereign
# core (firewall, impermanence, boot chain, health gate) is untouched — the
# edition-switch test asserts exactly that at the derivation level.
{ config, lib, pkgs, ... }:
lib.mkIf (config.sovox.edition == "desktop") {
  # plasma6/sddm enable flags live in edition.nix (the one-option contract);
  # this module carries the detail.
  services.displayManager.sddm.wayland.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    elisa
    khelpcenter
  ];

  # Enrollment ergonomics only — never the measurement chain or firewall.
  programs.kde-pim.enable = false;
}
