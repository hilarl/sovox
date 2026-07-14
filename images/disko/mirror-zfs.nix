# Wizard preset "mirror-zfs" (Operator Docs §1.1): two-disk ZFS mirror,
# same dataset plan as single-zfs. ESP lives on the first disk (ESP
# mirroring is a wizard concern, v0.1).
{ devices ? [ "/dev/vda" "/dev/vdb" ], ... }:
{
  disko.devices = {
    disk = {
      mirror-a = {
        type = "disk";
        device = builtins.elemAt devices 0;
        imageSize = "12G";
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
                name = "cryptroot-a";
                passwordFile = "/tmp/disko-password";
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
      mirror-b = {
        type = "disk";
        device = builtins.elemAt devices 1;
        imageSize = "12G";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot-b";
                passwordFile = "/tmp/disko-password";
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
    };

    zpool.rpool = {
      type = "zpool";
      mode = "mirror";
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
