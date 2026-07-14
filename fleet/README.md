# fleet/

Fleet tooling. The prototype ships one thing:

```
nix run .#install -- --target root@<host> --plan single-zfs|mirror-zfs [--intent ./sovox.toml]
```

which drives [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
against the example server configurations (`nixos-anywhere.nix`).

## `--intent`

`--intent ./sovox.toml` compiles an operator intent file
(`example-intent.toml` here; schema in Operator Docs §3) into the installed
system: only the keys you set are applied, everything else keeps its option
default, and intent settings win over the example defaults.

**Caveat, stated plainly:** the intent file reaches the flake through the
`SOVOX_INTENT` environment variable, which requires *impure* evaluation —
the script passes `--option pure-eval false` to every nix invocation
nixos-anywhere makes. The build reads a file outside the flake; the
rendered result on the machine is still fully declarative
(`/etc/sovox/sovox.toml`). The signed-intent pipeline that removes the
impurity is sovoxd work (v0.1). `nix flake check` never sees any of this:
under pure evaluation the `intent` configurations simply don't exist, and
the `intent-eval` check exercises the same code path with the committed
example file.

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

- `--migrate-tenzro <path>` needs the sovoxd migration path (v0.1); the
  flag is reserved and errors loudly today.
- Raw-image boot smoke (booting `packages.raw` directly in CI) — the boot
  test currently exercises the same module set in a framework VM instead.
- ESP mirroring for the `mirror-zfs` preset (wizard concern, v0.1).
