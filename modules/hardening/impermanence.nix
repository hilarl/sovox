# ZFS blank-snapshot root impermanence — one of the three prototype theses.
# rpool/local/root is rolled back to @blank in initrd on every boot; the
# persist-path allowlist lives on rpool/safe/state (mounted at /persist,
# the impermanence-conventional mount name; dataset names stay contract-exact).
{ config, lib, ... }:
lib.mkIf config.sovox.internal.impermanence.enable {
  boot.initrd.systemd.enable = true; # required by the UKI/lanzaboote path and boot counting
  boot.supportedFilesystems.zfs = true;
  boot.initrd.supportedFilesystems.zfs = true;
  boot.zfs.forceImportRoot = false;

  # Scripted-initrd hooks (postDeviceCommands) are ignored under systemd
  # initrd; the rollback is a proper unit ordered inside the import→mount gap.
  boot.initrd.systemd.services.sovox-rollback = {
    description = "Rollback rpool/local/root to @blank (impermanence)";
    wantedBy = [ "initrd.target" ];
    after = [ "zfs-import-rpool.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r rpool/local/root@blank
    '';
  };

  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/machine-id"
    ];
    directories = [
      "/etc/ssh" # host keys — the boot test asserts these survive reboot
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/log"
    ];
  };
}
