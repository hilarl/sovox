# Sovox Server on the mirror-zfs preset — target of
# `nix run .#install -- --plan mirror-zfs` (Operator Docs §1.2).
{
  imports = [
    ./common.nix
    ../images/disko/mirror-zfs.nix
  ];

  sovox.edition = "server";
}
