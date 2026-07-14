{
  description = "Sovox — Unix for the sovereign era. Powered by Tenzro Protocol.";

  inputs = {
    # Pinned curated channel; the prototype pins the current stable.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-edge.url = "github:NixOS/nixpkgs/nixos-unstable"; # sovox-edge ring
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux"; # ARM64 added post-prototype
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};

      # The only constructor. Every host — example, test VM, image — goes
      # through the same module set; that is what makes the edition claim
      # and the reproducibility claim testable.
      mkSovox = modules: lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ self.nixosModules.sovox ] ++ modules;
      };
    in
    {
      nixosModules.sovox = { imports = [ ./modules ]; };

      nixosConfigurations = {
        server-example = mkSovox [ ./examples/server.nix ]; # sovox.edition = "server"
        desktop-example = mkSovox [ ./examples/desktop.nix ]; # sovox.edition = "desktop"
        # Fleet target for `nix run .#install -- --plan mirror-zfs`
        # (Operator Docs §1.2; same server profile, mirror-zfs layout).
        server-mirror-example = mkSovox [ ./examples/server-mirror.nix ];
      };

      packages.${system} = {
        iso = self.nixosConfigurations.server-example.config.system.build.sovoxIso;
        # disko.testMode substitutes LUKS secrets so the image is CI-buildable;
        # the raw artifact is therefore a dev/CI artifact, never a release.
        raw = (self.nixosConfigurations.server-example.extendModules {
          modules = [{ disko.testMode = true; }];
        }).config.system.build.sovoxRaw;
        sovoxd-stub = pkgs.callPackage ./packages/sovoxd-stub { };
        default = self.packages.${system}.sovoxd-stub;
      };

      apps.${system}.install = {
        type = "app";
        program = "${pkgs.callPackage ./fleet/nixos-anywhere.nix { inherit inputs; }}/bin/sovox-fleet-install";
      };

      checks.${system} = {
        boot = import ./tests/boot.nix { inherit inputs system; };
        edition-switch = import ./tests/edition-switch.nix { inherit inputs system; };
        update-rollback = import ./tests/update-rollback.nix { inherit inputs system; };
      };
    };
}
