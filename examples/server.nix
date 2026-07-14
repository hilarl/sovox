# Sovox Server on the single-zfs preset. Converting this host to Desktop is
# exactly one line: sovox.edition = "desktop".
{
  imports = [
    ./common.nix
    ../images/disko/single-zfs.nix
  ];

  sovox.edition = "server";
}
