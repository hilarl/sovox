{ inputs, ... }:
{
  # Spec deviation (verified): boot.loader.systemd-boot.bootCounting exists only
  # on nixpkgs master/unstable, not in nixos-26.05. The master module is
  # self-contained, so we swap it in from the lock-pinned edge input. Drop this
  # once bootCounting reaches sovox-stable.
  disabledModules = [ "system/boot/loader/systemd-boot/systemd-boot.nix" ];

  imports = [
    "${inputs.nixpkgs-edge}/nixos/modules/system/boot/loader/systemd-boot/systemd-boot.nix"
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.lanzaboote.nixosModules.lanzaboote

    ./sovox
    ./hardening/base.nix
    ./hardening/impermanence.nix
    ./hardening/boot-chain.nix
    ./roles
    ./tenzro
    ./desktop/plasma.nix

    ../images/iso.nix
    ../images/raw.nix
  ];
}
