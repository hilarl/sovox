# Raw disk image: preinstalled image for QEMU CI and reference
# hardware via `dd`. Built by disko's image builder, which formats inside a
# VM and understands the LUKS2→ZFS layout (nixpkgs' make-disk-image does not).
#
# The flake's `packages.raw` builds this with `disko.testMode = true` so LUKS
# secrets are substituted at build time — the raw artifact is a dev/CI
# artifact, never a release medium.
{ config, ... }:
{
  system.build.sovoxRaw = config.system.build.diskoImages;
}
