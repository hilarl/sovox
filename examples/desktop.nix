# Sovox Desktop — same declarative core as server.nix; the edition enum is
# the only sovereign-relevant difference.
{ lib, ... }:
{
  imports = [
    ./common.nix
    ../images/disko/single-zfs.nix
  ];

  sovox.edition = lib.mkDefault "desktop";
}
