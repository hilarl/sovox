# Shared example-host settings. Real machines get these from the first-boot
# wizard (v0.1) or an intent file (`nix run .#install -- --intent …`);
# examples hardcode the minimum, as defaults an intent file may override.
{ lib, ... }:
{
  sovox.node.name = lib.mkDefault "sovox-example";

  # Required by ZFS; the wizard derives a per-machine value (v0.1).
  networking.hostId = "5ec5330f";

  # Console-only credential for the example/preinstalled images:
  # hardening/base.nix forces key-only SSH, so this password cannot be used
  # remotely. Real machines should set a key and drop it —
  #   users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA…" ];
  # Never ship a default password on a release image.
  users.users.root.initialPassword = "sovox";

  system.stateVersion = "26.05";
}
