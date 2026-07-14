# Shared example-host settings. Real machines get these from the first-boot
# wizard / sovoxd intent compiler (v0.1); examples hardcode the minimum.
{ lib, ... }:
{
  sovox.node.name = "sovox-example";

  # Required by ZFS; the wizard derives a per-machine value (v0.1).
  networking.hostId = "5ec5330f";

  # PROTOTYPE ONLY: console access for the example/preinstalled images.
  # Credentials are wizard work (v0.1); never ship this on a release image.
  users.users.root.initialPassword = "sovox";

  system.stateVersion = "26.05";
}
