# Sovox Server on the single-zfs preset. Converting this host to Desktop is
# exactly one line: sovox.edition = "desktop".
{ lib, ... }:
{
  imports = [
    ./common.nix
    ../images/disko/single-zfs.nix
  ];

  sovox.edition = lib.mkDefault "server";
}
