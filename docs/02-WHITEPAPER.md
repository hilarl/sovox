# Sovox: A Sovereign Operating System for Distributed AI Computing

**Whitepaper · Version 1.0 · July 2026**
*Unix for the sovereign era. Powered by Tenzro Protocol.*

---

## Abstract

Sovox is a Linux-based operating system, built on NixOS, that makes sovereign participation in the distributed AI economy a first-boot experience rather than a systems-engineering project. A Sovox node is defined by a single declarative configuration; runs on any machine, booting through the strongest chain of trust its hardware supports — from challenge-verified machine identity on commodity boxes, to TPM-measured boot, to TEE-confidential execution; runs the Tenzro Network reference implementation natively; and can simultaneously serve AI inference, contribute verifiable training compute, rent spare capacity, hold storage under proof-of-retrievability, provide confidential (TEE) execution, host web and email, and operate autonomous agents — earning TNZO for each, under one identity (TDIP) and one stake. Every byte of the system, from bootloader to model runtime, is reproducible from pinned sources, updateable atomically, and rollback-able instantly. We describe the motivation, the design principles, the division of labor between protocol and operating system, the trust and verification model, the economic surfaces, and the roadmap. The thesis is narrow and testable: **the missing layer between open AI protocols and real-world operators is an operating system, and sovereignty is an OS property before it is a network property.**

---

## 1. Motivation: the sovereignty gap

AI execution in 2026 is concentrated in a handful of proprietary clouds, while the counter-movement is real and funded: global spending on sovereign AI systems is projected to exceed $100B this year, forty-seven national programs treat compute as strategic infrastructure, and European procurement regimes (SecNumCloud, BSI IT-Grundschutz, EUCS) increasingly demand attestable locality and control. Yet the practical unit of sovereignty — a machine an operator owns, can audit, and can earn with — is served by nothing coherent. The pieces exist in isolation:

- **Protocols without an OS.** Tenzro Network provides open identity, settlement, verification, and AI orchestration, but its own operator guide is deliberately OS-agnostic: bring any Linux with systemd and Docker, open the right ports, tune the sysctls, pin your digests, don't expose the RPC bind. Each of those sentences is a place where a real deployment silently diverges from a secure one.
- **OSes without an economy.** Personal-server systems (Umbrel, StartOS, CasaOS) proved that sovereignty can be a consumer-grade experience, and appliance Linux (Talos, bootc image mode) proved that immutability can be an enterprise-grade one — but none of them turns hardware into attested, revenue-generating AI infrastructure.
- **Sovereignty as a slogan.** "Sovereign cloud" offerings frequently mean *rented* sovereignty: your data in someone else's region, on someone else's control plane, under someone else's update channel.

Sovox closes the gap by making four properties simultaneous OS guarantees: **ownership** (hardware, keys, and update channel under operator control), **auditability** (the running system is a reproducible function of pinned source), **verifiability** (what the node claims to the network is rooted in the strongest evidence its hardware supports, and honestly labeled with its tier), and **economic agency** (every capability of the machine is a protocol-priced service by default).

### The sovereignty stack

| Layer | Question it answers | Sovox mechanism |
|---|---|---|
| Hardware | Do you control the metal? | Runs on operator-owned x86-64/ARM64 servers; hardware auto-detection incl. GPUs and TEEs |
| Boot | Is what's running what you built? | Encrypted state on every machine; UEFI Secure Boot (Lanzaboote) + TPM 2.0 measured boot where present; TEE launch where present — tiered T0→T3, always surfaced |
| System | Can you reproduce and audit it? | NixOS: the whole OS is one pinned, diffable expression; atomic updates, instant rollback |
| Identity | Who does the network think you are? | TDIP (`did:tenzro`) key at the strongest available backend (TEE > TPM > encrypted keystore), bound to a challenge-verified machine fingerprint; W3C DID/VC, ERC-8004 mirror |
| Execution | Can others trust your compute? | Isolation classes up to SEV-SNP/TDX CVMs with NVIDIA GPU CC; on-chain `TEE_VERIFY` |
| Economy | Do you capture the value? | Multi-role Tenzro node: per-token, per-epoch, per-byte, per-attestation TNZO earnings |
| Governance | Who controls the roadmap? | Apache-2.0 core; self-mirrorable update channel; no telemetry without opt-in |

## 2. Design principles

1. **Sovereignty is the default, not a mode.** No mandatory accounts, stores, telemetry, or vendor endpoints. The entire artifact chain — sources, binary cache, images — can be mirrored on-prem ("sovereign mode") and the node keeps working air-gapped except for the network protocol itself.
2. **Declare intent, derive systems.** Operators state *what* the node is (`roles = ["ai", "storage"]`); Sovox derives *how* — packages, units, firewall, isolation, metrics — deterministically. Same input, same system, on one box or a thousand.
3. **The protocol is the kernel; the OS is the distribution.** Sovox adds no consensus, token, or identity scheme of its own. Everything economic and cryptographic is Tenzro; everything operational is Sovox. The boundary is explicit and inspectable.
4. **Untrusted compute never touches the trusted computing base.** Third-party workloads (rentals, training payloads, agent skills) run in microVMs or confidential VMs; consensus, keys, and mail never share a kernel with them.
5. **Verifiability over promises.** Where hardware can attest (TEE, TPM), attest; where circuits are tractable (settlement, identity, bounded inference), prove with transparent STARKs; where neither, bind identity to challenge-verified hardware fingerprints and stake-bonded receipts with Byzantine-robust aggregation. Never claim more than the mechanism supports.
6. **Trust is tiered, never gated.** Any machine can join and earn. TPM and TEE raise what a node can *prove* (T0 Declared → T1 Fingerprinted → T2 Measured → T3 Confidential); they never decide whether it may *participate*. The tier is computed from live hardware, visible to counterparties, and never silently inflated — confidentiality is exclusive to T3, but integrity and earnings are available at every tier.
7. **Boring on purpose.** Atomic A/B-style updates with health gates and automatic rollback; stateless root; one structural network port; three-command operations. Excitement belongs in what the node earns, not how it behaves.
8. **Approachable on top, rigorous underneath.** A guided installer and a TOML file for the operator; a fully pinned flake for the auditor. Both describe the same machine.

## 3. The protocol layer: Tenzro Network

Sovox builds on the Tenzro Network open-source reference implementation (Apache-2.0, Rust, 31 crates). A summary of the properties Sovox depends on; the authoritative treatment is Tenzro's own whitepaper and specification.

**Execution & settlement.** Tenzro is an open, distributed execution layer for AI: independent nodes serve models, rent compute, and hold data; consumers pay from a TNZO balance and providers earn into theirs. The ledger runs three VM environments (EVM, SVM, Canton/DAML) over HotStuff-2 BFT consensus with reputation-weighted proposer election and hybrid Ed25519 + ML-DSA-65 post-quantum signatures. TNZO is fixed-supply (1,000,000,000), serving as gas, bond, commission denominator, and governance weight; user-facing settlement may flow in stablecoins or fiat rails while TNZO remains the protocol denominator.

**One stake, many roles.** A node stakes once; the same stake underwrites model serving, compute rental, and storage. Compute rental settles per epoch strictly against availability proofs with streaming escrow and make-whole-from-stake on missed epochs; storage settles per byte-epoch against nonce-bound proof-of-retrievability over Reed–Solomon-coded shards.

**Identity.** TDIP defines four identity classes — humans, delegated agents, autonomous agents, and institutions (LEI-anchored) — with delegation scopes, credential inheritance, cascading revocation, KYC tiers, and auto-provisioned FROST-Ed25519 threshold wallets (2-of-3, ML-DSA hybrid leg). One DID works across EVM (ERC-8004 mirror), SVM, Canton, AP2 mandates, x402, and OAuth/DPoP.

**AI as protocol activity.** The model registry and inference router (price/latency/reputation strategies) meter multi-modal serving — LLMs via llama.cpp, and forecast/vision/embedding/segmentation/detection/ASR via ONNX runtimes — with per-token or per-call settlement, micropayment channels, license-tier gating, and MTP speculative decoding. Mixture-of-Experts models serve full-replica where they fit and, where they do not, as **decentralized expert shards whose weights live across many providers' memory so no single node holds the whole model** — the dispatch planner fans per-token top-k expert batches to their holders over iroh and combines the results into one forward pass; `tenzro-cluster` similarly lets several LAN machines jointly serve a model none fits alone. **Tenzro Train** coordinates Decoupled-DiLoCo-class distributed training: sponsors fund runs from on-chain escrow; GPU participants earn per accepted outer gradient; every gradient yields a signed receipt and every run a run-root commitment; sponsors select a trust tier (Open / Verified / Confidential). Phase 1 aggregates by mean; Byzantine-robust rules (TrimmedMean/Krum) are the Phase 2 roadmap.

**Verification.** Plonky3 STARKs over the KoalaBear field (transparent setup, post-quantum-conjectured soundness) cover inference/settlement/identity AIRs via the `ZK_VERIFY` precompile; hardware attestation for Intel TDX, AMD SEV-SNP, AWS Nitro, and NVIDIA GPU Confidential Computing is verified on-chain via `TEE_VERIFY` — and TEE-attested validators receive a 1.5× leader-selection multiplier, making confidential execution a consensus-level incentive.

**Networking.** A libp2p control plane (gossipsub, Kademlia, AutoNAT v2, relay+DCUtR hole punching) and an iroh content-addressed data plane (QUIC; blobs, gradients, shards, manifests as `tenzro://` URIs; Pkarr discovery bound byte-for-byte to the TDIP key). One structural port (9000 TCP+UDP) carries peer traffic; RPC/MCP/A2A surfaces are local by design.

**Agent surfaces.** The node natively speaks the converged agent stack — MCP (416 tools) and A2A (42 skills), both now Linux Foundation-governed standards — plus the payment rails agents actually use in 2026: x402 v1 (four schemes; the protocol now stewarded by the LF's x402 Foundation with hyperscaler edge support), AP2 v0.2 mandates, ERC-8004 registries, ERC-4337 v0.8 accounts, and card-network adapters (Visa TAP, Mastercard Agent Pay). Sandboxed skills run in a WASI 0.2 component host with deterministic fuel metering.

## 4. The operating system layer: what Sovox adds

Sovox's contribution is the disciplined systems engineering between "clone the repo" and "trustworthy earning node." Condensed here; the full treatment is `03-ARCHITECTURE.md`.

```
┌────────────────────────────────────────────────────────────────────┐
│  Operator surfaces:  sovox CLI · Sovox Dashboard · Cockpit · TOML  │
├────────────────────────────────────────────────────────────────────┤
│  Platform plane:  sovoxd (intent compiler · update orchestrator ·  │
│                   health/attestation supervisor · local API)       │
├────────────────────────────────────────────────────────────────────┤
│  Roles:  Validator │ AI Serve/Train │ Compute │ Storage │ TEE │    │
│          Web (Caddy) │ Email (Stalwart) │ Agent Hub (MCP/A2A)      │
├────────────────────────────────────────────────────────────────────┤
│  Protocol:  tenzro-node (roles, wallet, proofs, RPC/MCP/A2A)       │
├────────────────────────────────────────────────────────────────────┤
│  Isolation:  C0 systemd-hardened │ C1 rootless OCI │ C2 microVM │  │
│              C3 confidential VM (SEV-SNP/TDX + NVIDIA GPU CC)      │
├────────────────────────────────────────────────────────────────────┤
│  Base:  NixOS (pinned flake · atomic generations · impermanence)   │
│         kernel 6.12 LTS · ZFS · nftables · Podman · microvm.nix    │
├────────────────────────────────────────────────────────────────────┤
│  Trust tiers: T0 keys+stake · T1 hw fingerprint · T2 TPM measured  │
│               boot · T3 TEE  —  encrypted state at every tier      │
└────────────────────────────────────────────────────────────────────┘
```

Five properties distinguish this from "a distro with the daemon preinstalled":

1. **Configuration is identity.** The node's flake closure hash is part of what it can attest. Two operators with the same `sovox.toml` and channel pin run bit-comparable systems; an auditor can rebuild and diff.
2. **The deployment guide is enforced, not documented.** Tenzro's operational guidance — loopback-bound RPC behind a TLS proxy, 9000/tcp+udp reachability, cross-region keepalive sysctls, digest pinning, non-root service execution — is compiled into the system unconditionally.
3. **Updates cannot brick earnings.** A staged closure activates only after health gates (boot-target reached, node liveness, attestation re-validation, role probes) pass; systemd boot counting rolls back automatically otherwise. Availability-proof obligations are respected: updates schedule around epoch deadlines so a reboot never forfeits a rental slice.
4. **Trust is tiered and labeled, never asserted.** The TDIP key lives at the strongest backend the machine offers (TEE > TPM > encrypted keystore); from T1 upward the identity is bound to a deep, challenge-verified hardware fingerprint, so stake and reputation attach to a physical machine even without a TPM; on T3 hosts, TEE-provider workloads launch as SNP/TDX CVMs whose reports (plus GPU CC evidence on Hopper/Blackwell-class parts) flow to `TEE_VERIFY` without operator ceremony.
5. **Sovereignty includes the supply chain.** Signed, reproducible images; SPDX SBOMs; a self-hostable binary cache; and a documented full-mirror mode. The vendor disappearing must be an inconvenience, not an outage.

## 5. Trust & verification model

**The trust ladder.** Every Sovox node climbs as high as its hardware allows, and the network sees exactly which rung it stands on:

- **T0 — Declared.** Software identity (hybrid Ed25519 + ML-DSA keys in an encrypted keystore), stake, and reputation. The OS closure is reproducibly auditable by anyone, but not remotely proven.
- **T1 — Fingerprinted.** A deep machine fingerprint (board/CPU/GPU/disk/NIC/RAM identifiers, salted and selectively disclosable) is bound to the TDIP identity and re-signed each boot; randomized challenges (memory-hard VRAM probes, SKU-matched compute benchmarks, disk and bandwidth probes) verify that declared hardware matches measured behavior. Cloning and silent migration become detectable; stake and reputation attach to a physical machine.
- **T2 — Measured.** TPM 2.0: Secure Boot (Lanzaboote) → PCR measurements of firmware, bootloader, kernel, initrd → LUKS2 unlock bound to the PCR policy → TDIP key sealed to the measured state. A node whose boot chain changes unexpectedly fails to unseal and — by design — fails to sign. TPM quotes plus the manufacturer EK certificate give counterparties manufacturer-rooted evidence of *which closure booted on which genuine machine*.
- **T3 — Confidential.** SEV-SNP/TDX CVMs, optionally with NVIDIA GPU CC, attested on-chain via `TEE_VERIFY`; the host operator stands outside the TCB.

Confidentiality is exclusive to T3. Integrity is not: it is available at every tier, at rising verification cost as the tier falls — which is precisely what the spectrum below prices.

**Verification spectrum (what a counterparty can know, and at what cost):**

| Mechanism | Tier | Guarantee | Cost profile | Sovox/Tenzro use |
|---|---|---|---|---|
| TEE attestation (TDX/SNP/Nitro/GPU CC) | T3 | Code+data confidentiality & integrity in a measured environment | ~free at runtime (Hopper CC ≈2–5% overhead; Blackwell TEE-I/O near parity) | Confidential inference/training, TEE-provider role, validator 1.5× multiplier |
| TPM quote + reference measurements | T2 | Genuine hardware ran exactly this boot chain and closure | ~free; verifier compares against published measurements | Compliance profiles, integrity-sensitive routing, fleet audit |
| Transparent STARKs (Plonky3/KoalaBear) | any | Publicly verifiable correctness of bounded computations | Prover-heavy; tractable for settlement/identity/bounded-inference AIRs | `ZK_VERIFY` anchoring of receipts and claims |
| Challenge-verified hardware fingerprint | T1 | A consistent physical machine of the claimed class; cloning detectable | Cheap, randomized, repeatable | Sybil resistance, hardware-class pricing, capacity honesty |
| Stake-bonded receipts + robust aggregation | T0+ | Economic guarantee; outliers excluded (TrimmedMean/Krum) | Cheap; probabilistic | Open-tier training, availability proofs, redundant-sampling spot checks, reputation |
| Reproducible build + SBOM | all | Anyone can rebuild and diff the OS itself | One-time CI cost | Sovox release process |

The model's honesty matters: full zkML for frontier-scale models remains uneconomical industry-wide, so Sovox never markets it; TEE attestation carries vendor-root trust assumptions, so Sovox records *which* root vouched; below T2, fingerprints and challenge responses come from operator-controlled software — they raise spoofing cost, they are not attestation, and Sovox labels them accordingly; economic guarantees are exactly as strong as the bond behind them, so the Dashboard shows bonds and slashing exposure alongside earnings.

## 6. Sovereign services

Each role is a blueprint: components, isolation class, resource model, metrics, and the protocol surface it monetizes (operational detail in `03-ARCHITECTURE.md` §7 and `05-OPERATOR-DOCS.md`).

- **AI Inference** — native engine (llama.cpp CUDA / ONNX EPs) under the price/latency/reputation router; per-token/per-call TNZO; optional high-throughput profile; LAN scale-out via deterministic HRW placement.
- **AI Training** — Tenzro Train participant in C2/C3 isolation; earns per accepted outer gradient; bandwidth-shaped so sync never starves consensus.
- **Compute** — epoch-booked rental of declared capacity, gated on availability proofs; rides the same `ai` role and stake.
- **Storage** — PoR-challenged, erasure-coded object custody on dedicated ZFS datasets; per byte-epoch earnings.
- **TEE Provider** — SNP/TDX CVMs (GPU CC where hardware allows) sold as attested execution; per-attestation and per-use fees.
- **Validator** — HotStuff-2 participation with bonded stake; priority fees, leader rewards, governance weight; TEE attestation multiplier.
- **Web Hosting** — Caddy-fronted static and containerized sites with automatic TLS; the same ingress publishes the node's paid endpoints.
- **Sovereign Email** — Stalwart (JMAP/IMAP/SMTP) with DKIM/DMARC/ARC and TDIP-anchored key custody; deliverability tooling in the Dashboard.
- **Agent Hub** — MCP + A2A endpoints with TDIP-scoped auth; WASI 0.2 skills with fuel and spend budgets; x402/AP2 payment adapters for agents that buy and sell.

## 7. Economics

**Operator P&L, made legible.** The Dashboard renders one ledger: revenue per role (tokens served, epochs proven, byte-epochs held, attestations issued, blocks led), minus bonded capital at risk and power draw (measured via RAPL/NVML). Sovox itself takes no cut of protocol earnings — network economics accrue to operators and the Tenzro protocol per its tokenomics (fees to validators and providers; demand-driven burn; provider bonds such as the current 100 TNZO compute bond; slashing for misbehavior). Sovox's commercial layer is tooling and support (`04-GTM.md` §5), keeping OS incentives aligned with operator incentives.

**Why multi-role matters.** Single-purpose DePIN hardware suffers utilization cliffs. A Sovox node arbitrages its own capacity across inference demand, rental bookings, storage commitments, and training runs under one stake — the protocol's shared coverage tracker is what makes an "always earning something" posture safe rather than reckless.

**Demand honesty.** The agentic-payment rails Sovox speaks (x402 at hyperscaler edges, AP2 mandates with 60+ finserv participants) are deployed infrastructure with early organic demand; independent analyses show real settled volume well below headline transaction counts. Sovox's economic story therefore leads with today's provable demand — sovereign inference, storage, and compute for parties who must own their stack — and treats the agent economy as convex upside, not baseline.

## 8. Governance, licensing, and the sovereignty covenant

Apache-2.0 core; NixOS components under upstream licenses. Sovox commits to: (i) reproducible releases with published SBOMs and provenance; (ii) a self-hostable, documented mirror of every artifact channel; (iii) no telemetry, phone-home, or account requirement without explicit opt-in; (iv) protocol neutrality — Tenzro is the native and default network, and the module boundary that makes it so is open for others to study; (v) no Sovox-controlled admission: any hardware meeting the matrix may join, subject only to protocol rules. Trademark ("Sovox") is defended solely to prevent misrepresentation of modified builds as official.

## 9. Related work & positioning

| System | What it proves | What it lacks for this mission |
|---|---|---|
| Umbrel / StartOS / CasaOS | Sovereign personal servers can be consumer-simple | No AI economics, no attestation, no reproducibility guarantee |
| HiveOS (mining era) | Operators will adopt a purpose-built earning OS at fleet scale | Wrong workload; no verifiability; centralized control plane |
| Talos / bootc image mode | Immutable, API-managed Linux is production-mature | No economic layer; k8s-only or vendor-gravity bases |
| Akash / io.net-class marketplaces | Decentralized compute demand exists | Marketplaces, not operating systems; nodes remain artisanal |
| Petals / exo | Community inference across owners is feasible | No settlement, identity, or attestation; latency-bound sharding |
| Prime Intellect / Psyche / Templar | Internet-scale training works (10B–100B class) | Training networks, not general sovereign nodes |
| Hyperscaler "sovereign cloud" | Compliance demand is enormous | Rented sovereignty on a foreign control plane |

Sovox is the intersection none of them occupies: **consumer-grade onboarding × reproducible immutable base × tiered trust from any commodity machine up to confidential hardware × a full-surface AI protocol economy.**

## 10. Roadmap

- **v0.1 (Alpha)** — Server edition image; installer wizard + `nixos-anywhere` path; roles: validator, ai (inference+compute), storage; sovoxd intent compiler; Cockpit + Dashboard read-only; signed update channel with health-gated rollback; 100-node cohort.
- **v0.2 (Beta)** — Desktop edition (KDE Plasma 6); web + email + agent-hub roles; TEE-provider role on SNP/TDX + Hopper-class GPU CC; Dashboard write-path (pricing, model pulls); Sovox Fleet preview; high-throughput serving profile; 1,000-node cohort.
- **v1.0 (GA)** — Production hardening & third-party audit; reproducibility attestations; certified-hardware partner program; sovereign-mode (full mirror) documentation & tooling; compliance mapping packs (SecNumCloud/BSI-aligned deployment profiles); LTS channel policy.

## 11. Conclusion

Every era of computing ended its infrastructure phase the same way: a protocol found its operating system. TCP/IP had BSD; containers had the immutable-Linux wave; the open AI economy — identity, settlement, verification, and execution now standardized in the open — still boots on hand-rolled Ubuntu. Sovox is the deliberate correction: an OS where sovereignty is measured, not marketed; where the machine you own is the machine you can prove; and where owning compute means earning from it. Install once. Own and monetize your compute sovereignly.

---

*References for all externally sourced claims are consolidated in `01-RESEARCH-AND-DECISIONS.md` §10; Tenzro protocol facts reference the repository's README, WHITEPAPER, SPECIFICATION, TDIP, COMPUTE, STORAGE, TOKENOMICS, and deploy documents at `github.com/tenzro/tenzro-network`.*

*Powered by Tenzro Protocol.*
