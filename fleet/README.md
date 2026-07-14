# fleet/

Placeholder for fleet tooling. The prototype ships one thing:

```
nix run .#install -- --target root@<host> --plan single-zfs|mirror-zfs
```

which drives [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
against the example server configurations (`nixos-anywhere.nix`).

## SSH posture and the admin mesh

With `[network].mesh` off (the default), the `standard` profile keeps port
22 open on all interfaces so a fresh install stays reachable. Setting
`sovox.network.mesh = true` closes WAN 22: SSH and Cockpit (9090) are then
reachable only through the WireGuard interface (`sovox-mesh`), with peers
declared under `sovox.internal.mesh.*`.

**Lockout risk:** enable the mesh only after at least one peer's public key
and allowed IPs are correct and tested — a node whose peers can't complete
a handshake is console-only. The node's own key is generated on first
activation at `/var/lib/sovox/mesh/private-key`; read its public half with
`wg show sovox-mesh public-key` *before* flipping the switch on a remote
machine. The `hardened` profile never opens WAN 22 regardless of the mesh
switch.

## Tracked issues (deferred with a home)

- `--intent ./sovox.toml` and `--migrate-tenzro <path>` need the sovoxd
  intent compiler (v0.1); the flags are reserved and error loudly today.
- Raw-image boot smoke (booting `packages.raw` directly in CI) — the boot
  test currently exercises the same module set in a framework VM instead.
- ESP mirroring for the `mirror-zfs` preset (wizard concern, v0.1).
