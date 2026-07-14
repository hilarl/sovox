# fleet/

Placeholder for fleet tooling. The prototype ships one thing:

```
nix run .#install -- --target root@<host> --plan single-zfs|mirror-zfs
```

which drives [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
against the example server configurations (`nixos-anywhere.nix`).

## Tracked issues (deferred with a home)

- `--intent ./sovox.toml` and `--migrate-tenzro <path>` need the sovoxd
  intent compiler (v0.1); the flags are reserved and error loudly today.
- SSH listens on all interfaces in the `standard` profile *for the prototype
  only* — moves behind the WireGuard admin mesh when `sovox mesh` lands
  (interface name already reserved: `sovox.internal.meshInterface`).
- Raw-image boot smoke (booting `packages.raw` directly in CI) — the boot
  test currently exercises the same module set in a framework VM instead.
- ESP mirroring for the `mirror-zfs` preset (wizard concern, v0.1).
