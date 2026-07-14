# Boot chain scaffolding: Lanzaboote present but Secure Boot
# unenrolled by default — key enrollment is the wizard's guided step (v0.1).
#
# Note (verified): lanzaboote replaces the systemd-boot installer, so Secure
# Boot enrollment and systemd-boot boot counting (modules/sovox/updates.nix)
# are mutually exclusive today. The prototype keeps counting and defers SB.
{ lib, pkgs, ... }:
{
  boot.lanzaboote.enable = false;
  # boot.lanzaboote.pkiBundle = "/persist/secrets/secure-boot";

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # TPM2 LUKS binding (v0.1 — requires the recovery-key ceremony UX in the
  # first-boot wizard before it may be enabled; T0/T1 passphrase path is the
  # prototype default):
  #
  #   boot.initrd.systemd.tpm2.enable = true;
  #   environment.systemPackages = [ pkgs.tpm2-tss ];
  #   # systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 \
  #   #   /dev/disk/by-partlabel/disk-main-luks
}
