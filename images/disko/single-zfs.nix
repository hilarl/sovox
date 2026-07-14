# Wizard preset "single-zfs" (Operator Docs §1.1) — names are load-bearing.
# GPT: ESP (1 GiB, FAT32) │ LUKS2 → zpool "rpool" per Arch §2:
#   rpool/local/root   ← rolled back to @blank every boot (impermanence)
#   rpool/local/nix    ← the closure; content-addressed
#   rpool/safe/state   ← declared persistent state (mounted at /persist)
#   rpool/safe/secrets ← reserved for operator secret material. No secrets
#                        manager ships in v0.0.x because nothing consumes
#                        one: the only machine secret (the mesh key) is
#                        generated at runtime under /var/lib/sovox, never
#                        provisioned. Tooling arrives with its first consumer.
#
# Dual-use file: imported as a NixOS module (examples/, `device` defaults)
# and consumed by the disko CLI from the installer ISO
# (`disko --arg device '"/dev/sdX"' single-zfs.nix`).
{ device ? "/dev/vda", ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      inherit device;
      imageSize = "12G"; # ZFS needs headroom when building raw images
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              # T0/T1 path: passphrase only. TPM binding via systemd-cryptenroll
              # is scaffolded in hardening/boot-chain.nix (v0.1 wizard ceremony).
              passwordFile = "/tmp/disko-password"; # written by sovox-install
              settings.allowDiscards = true;
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };

    zpool.rpool = {
      type = "zpool";
      options = {
        ashift = "12";
        autotrim = "on";
      };
      rootFsOptions = {
        mountpoint = "none";
        compression = "zstd";
        atime = "off";
        xattr = "sa";
        acltype = "posixacl";
        "com.sun:auto-snapshot" = "false";
      };
      datasets = {
        "local" = {
          type = "zfs_fs";
          options.mountpoint = "none";
        };
        "local/root" = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
          postCreateHook = "zfs snapshot rpool/local/root@blank";
        };
        "local/nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        "safe" = {
          type = "zfs_fs";
          options.mountpoint = "none";
        };
        "safe/state" = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options.mountpoint = "legacy";
        };
        # tenzro-node data layout (docs/03-ARCHITECTURE.md §6): recordsize=16K, fsync honored.
        "safe/state/tenzro" = {
          type = "zfs_fs";
          mountpoint = "/persist/var/lib/tenzro";
          options = {
            mountpoint = "legacy";
            recordsize = "16K";
          };
        };
        "safe/secrets" = {
          type = "zfs_fs";
          mountpoint = "/persist/secrets";
          options.mountpoint = "legacy";
        };
      };
    };
  };
}
