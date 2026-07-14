# Installer ISO builder. The `sovox-install` script is the TUI wizard's
# ancestor: it takes `--plan single-zfs|mirror-zfs` and target disk(s), runs
# disko, and installs the pinned closure from the ISO's embedded store —
# offline-capable, the first breadcrumb toward fully network-free
# (sovereign-mode) installs.
{ config, lib, pkgs, inputs, ... }:
let
  targetToplevel = config.system.build.toplevel;

  sovox-install = pkgs.writeShellApplication {
    name = "sovox-install";
    text = ''
      usage() {
        cat >&2 <<EOF
      usage: sovox-install --plan single-zfs --disk /dev/DISK
             sovox-install --plan mirror-zfs --disk /dev/DISK1 --disk2 /dev/DISK2
      EOF
        exit 1
      }

      plan=""
      disk=""
      disk2=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --plan) plan=$2; shift 2 ;;
          --disk) disk=$2; shift 2 ;;
          --disk2) disk2=$2; shift 2 ;;
          *) usage ;;
        esac
      done
      [ -n "$plan" ] && [ -n "$disk" ] || usage

      echo "Sovox installer — plan=$plan (offline install from embedded store)"
      umask 077
      printf 'LUKS passphrase: ' >&2
      read -rs pass
      echo >&2
      printf 'Confirm passphrase: ' >&2
      read -rs pass2
      echo >&2
      [ "$pass" = "$pass2" ] || { echo "passphrases do not match" >&2; exit 1; }
      printf '%s' "$pass" > /tmp/disko-password

      case "$plan" in
        single-zfs)
          disko --mode destroy,format,mount --yes-wipe-all-disks \
            --arg device "\"$disk\"" ${./disko/single-zfs.nix}
          ;;
        mirror-zfs)
          [ -n "$disk2" ] || usage
          disko --mode destroy,format,mount --yes-wipe-all-disks \
            --arg devices "[ \"$disk\" \"$disk2\" ]" ${./disko/mirror-zfs.nix}
          ;;
        *) usage ;;
      esac

      nixos-install --system ${targetToplevel} --no-root-passwd --no-channel-copy
      rm -f /tmp/disko-password
      echo "Installed. Remove the medium and reboot into first boot."
    '';
  };

  installerSystem = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    specialArgs = { inherit inputs; };
    # Deliberately NOT the sovox module set: importing it here would make
    # every ISO lazily define another ISO (infinite recursion) and the
    # installer is a live medium, not a sovereign node.
    modules = [
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      ({ pkgs, lib, ... }: {
        isoImage = {
          isoName = lib.mkForce "sovox-server.iso";
          volumeID = "SOVOX";
          # Embed the target closure so installation needs no network.
          storeContents = [ targetToplevel ];
        };
        boot.supportedFilesystems.zfs = true;
        networking.hostId = "8425e349"; # live-medium only; installed system sets its own
        environment.systemPackages = [
          sovox-install
          inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko
        ];
        isoImage.appendToMenuLabel = " — Sovox installer";
      })
    ];
  };
in
{
  system.build.sovoxIso = installerSystem.config.system.build.isoImage;
}
