# Sovox

**Unix for the sovereign era.**
*Powered by Tenzro Protocol.*

Sovox is a Linux-based operating system for sovereign AI computing. Built on NixOS for full-system reproducibility and running the [Tenzro Network](https://github.com/tenzro/tenzro-network) as its native distributed-computing and AI protocol, Sovox turns any server — from a single GPU home-lab box to racks in an independent data center — into a fully sovereign, revenue-generating node: serving AI inference, joining verifiable training runs, renting compute, holding storage, hosting web and email, running agents, and settling every unit of work in TNZO under one identity (TDIP) and one stake.

**Install once → own and monetize your compute sovereignly.**

| Layer | What it is |
|---|---|
| The protocol ("the kernel") | Tenzro Network — open, Apache-2.0, reference implementation in Rust (31 crates) |
| The distribution ("the OS") | Sovox — operator-friendly, opinionated, sovereign-first |

## Document suite (v1.0 — July 2026)

| Doc | Purpose |
|---|---|
| [`01-RESEARCH-AND-DECISIONS.md`](01-RESEARCH-AND-DECISIONS.md) | State-of-the-art research digest across every domain Sovox touches, the base-OS evaluation (NixOS vs. bootc/Talos/Ubuntu Core/Guix/…), and the Architecture Decision Records that bind the design |
| [`02-WHITEPAPER.md`](02-WHITEPAPER.md) | The Sovox whitepaper: motivation, design principles, protocol integration, trust model, economics, roadmap |
| [`03-ARCHITECTURE.md`](03-ARCHITECTURE.md) | Production-grade system architecture: boot & trust chain, platform plane, role blueprints, isolation model, networking, updates, observability, supply chain, threat model |
| [`04-GTM.md`](04-GTM.md) | Go-to-market: market thesis with 2026 data, ICPs, positioning, monetization, channels, launch plan, KPIs |
| [`05-OPERATOR-DOCS.md`](05-OPERATOR-DOCS.md) | Operator handbook: quickstart, hardware matrix, `sovox.toml` reference, CLI reference, role guides, runbooks, hardening checklist |

## Editions

- **Sovox Server** (primary) — headless appliance image; managed via the `sovox` CLI, the Sovox Dashboard, and Cockpit.
- **Sovox Desktop** — the same base with KDE Plasma for local development and experimentation.

Both share one declarative core and are interconvertible with a single configuration change.

## Status & license

Pre-release (targeting v0.1). Core is Apache-2.0; NixOS components retain their upstream licenses. All official materials carry the mark **"Powered by Tenzro Protocol."**

Brand values: **Sovereignty · Simplicity · Strength · Reproducibility.** Visual identity: deep charcoal, oxide red/orange accents, clean white; modern monospace + clean sans-serif.
