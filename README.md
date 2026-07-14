# Sovox

**Unix for the sovereign era. Powered by Tenzro Protocol.**

Sovereignty today is mostly sold as a place — a cloud region, a compliance
tier, a datacenter contract. Sovox treats it as a property of the machine
you own: **measured, proven, and earning**. Sovox is a Linux-based sovereign
AI operating system that turns any server — a single GPU box at home or
racks in an independent data center — into an attested, revenue-generating
node of the open [Tenzro network](https://github.com/tenzro/tenzro-network):
serving AI inference, contributing
verifiable training compute, renting capacity, holding storage — as a
first-boot experience, not a systems-engineering project.

Any machine can join and earn. Trust tiers (T0→T3) change what a node can
*prove* — challenge-verified identity on commodity hardware, TPM-measured
boot, TEE-confidential execution — never whether it can participate. And
because Sovox is built on NixOS, every byte of the system, from bootloader
to model runtime, is declared in one configuration: reproducible from pinned
sources, updated atomically, rolled back instantly. Sovereignty is an OS
property before it is a network property — and an OS property can be
tested.

## What this repository is

This is the **v0.0.x prototype**: it proves the substrate, not the product.
The claims above are cheap to make; this repo exists to make three of them
expensive to fake — true, testable, and CI-enforced from the first commit:

1. **Reproducible by proof.** Two independent machines building the same
   source revision produce closure-identical systems. The `repro-check` CI
   job builds the full system on two runners and diffs the hashes; a red
   check blocks merge.
2. **One system, two editions.** Server and Desktop are the same module
   tree; converting a machine is one line —
   `sovox.edition = "server" | "desktop"` — and back. A VM test asserts the
   security core (firewall, health daemon, update gate) is *bit-identical*
   across editions, then live-switches a running server to desktop and back.
3. **Updates that cannot brick a node.** Updates stage a new boot entry
   rather than mutating the running system. If the new generation fails the
   boot health gate, systemd boot counting reverts to the previous
   generation automatically, in at most one reboot, with no operator action.
   A VM test stages a deliberately broken generation and asserts the node
   comes back healthy on the old one.

Also here, in service of those claims:

- **Hardened network baseline** — default-deny inbound firewall; the node
  port (9000) is the only service exposed. An optional WireGuard admin mesh
  (`sovox.network.mesh`) closes WAN SSH and carries SSH and Cockpit over the
  tunnel instead — a VM test proves both postures.
- **Impermanence** — the root filesystem resets to a blank ZFS snapshot on
  every boot; only an explicit allowlist (host keys, machine identity, logs,
  node state) persists. Configuration drift is structurally impossible.
- **Encrypted installs** — the installer ISO partitions with LUKS2 + ZFS
  from declarative disk plans (`single-zfs`, `mirror-zfs`) and installs
  offline from its embedded store.
- **`sovoxd`** — a dependency-free Rust daemon on a Unix socket: it parses
  the rendered `/etc/sovox/sovox.toml` and answers `/health`, `/version`,
  `/status`, `/config`, and `/roles`. The boot health gate interrogates it;
  an unparseable config is a health failure.
- **Declarative intent** — the full `sovox.*` option tree renders to
  `/etc/sovox/sovox.toml`, and an operator intent file compiles back into a
  system via `nix run .#install -- --intent ./sovox.toml` (impure
  evaluation; caveat stated plainly in `fleet/README.md`). A pure-eval check
  asserts the render → parse round-trip is lossless.
- **Fleet path** — `nix run .#install` provisions a remote machine over SSH
  via nixos-anywhere.

Not here yet (v0.1+), stated plainly: upstream Tenzro has no release to pin,
so enabling `sovox.tenzro.enable` fails loudly and declared roles (`ai`,
`storage`, `validator`, …) render into config and unit definitions but run
no binary; there is no first-boot wizard; secure-boot signing is scaffolded
but unenrolled; auto-updates need an explicitly named flake source and an
unsigned channel — the signed manifest pipeline is sovoxd work.

## Layout

```
flake.nix          entrypoint: packages, modules, images, checks
modules/           sovox.* option namespace, hardening, roles, tenzro, desktop
examples/          minimal server / desktop / mirrored-server host configs
images/            installer ISO, raw disk image, disko presets (single-zfs, mirror-zfs)
packages/          sovoxd — the node daemon (health gate, config, status)
fleet/             nixos-anywhere profile (`nix run .#install`, `--intent`)
tests/             boot/impermanence, mesh, edition-switch, update-rollback, intent-eval
docs/              the published docs suite (the contract this repo conforms to)
scripts/           build-iso.sh, repro-check.sh
```

## Quick start

Requires Nix with flakes; the VM tests need Linux/KVM.

```sh
nix flake check                 # evaluates all configs, runs the four VM tests
nix build .#iso                 # Sovox Server installer ISO (offline-capable)
nix build .#raw                 # preinstalled raw image (dev/CI only)
nix run .#install -- --target root@host --plan single-zfs   # fleet install
./scripts/repro-check.sh        # local two-store reproducibility check
```

To read the system itself, start at `flake.nix`, then
`modules/sovox/edition.nix` — the one-option edition mechanism — and
`modules/sovox/updates.nix` — the health gate and rollback machinery.

## Docs

`docs/` carries the published suite: research and decisions, whitepaper,
architecture, go-to-market, and operator docs. Option paths, disk-plan
names, and dataset layouts in the code match the operator docs verbatim —
the docs are the contract; the code conforms to them, not vice versa.

## License

Everything here is Apache-2.0 from the first commit; upstream NixOS
components retain their licenses. No closed components, ever.

*Powered by Tenzro Protocol.*
