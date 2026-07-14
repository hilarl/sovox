# Sovox — Production Architecture

**Version 1.0 · July 2026 · Audience: systems engineers, security reviewers, protocol integrators**
Binding decisions live in `01-RESEARCH-AND-DECISIONS.md` (ADR-001…014); this document specifies how they compose into a production system. The layer diagram is in the whitepaper §4.

---

## 1. Goals, non-goals, service objectives

**Goals.** G1 A first-time operator reaches "earning node" in ≤60 minutes from USB or one remote command. G2 The complete system is reproducible from pinned sources; two nodes with identical intent + channel pin are closure-identical. G3 No update, crash, or power loss can leave a node unbootable or half-configured; rollback is automatic and ≤1 reboot. G4 Untrusted third-party compute is kernel-isolated from consensus, keys, and operator data. G5 Every operational requirement in Tenzro's deployment guidance is enforced by construction. G6 The node is fully operable with zero non-protocol external dependencies (sovereign/mirror mode). G7 **Any machine can join**: TPM and TEE are trust *tiers*, never entry requirements — capabilities strengthen what a node can prove, their absence degrades gracefully and visibly.

**Non-goals.** Sovox is not a Kubernetes distribution, not a general-purpose cloud OS, not a fork of Tenzro (protocol changes go upstream), and not a multi-tenant hypervisor product beyond the protocol's rental/TEE semantics.

**Service objectives (node-local).**

| SLO | Target |
|---|---|
| Update activation → healthy or rolled back | ≤ 10 min, unattended |
| Unclean-power recovery to serving | ≤ 5 min (ZFS import + generation boot) |
| Availability-proof continuity across planned update | 100% (epoch-aware maintenance windows) |
| Host attack surface (Server, hardened profile) | Ports: 9000/tcp+udp; 443/80 iff web role; 25/465/993 iff mail role; SSH via WG mesh only |
| Time-to-rollback on failed health gates | 1 automatic reboot (systemd boot counting) |

## 2. Trust architecture: tiers, machine identity, boot chain

**Any machine can run Sovox and earn.** Trust is tiered, not gated: each hardware capability present (TPM 2.0, SEV-SNP/TDX, GPU CC) strengthens what the node can *prove to counterparties*; none is required to install, operate, or join the network. The diagram below shows the maximal (T2/T3) chain — on hardware without a TPM, LUKS unlock falls back to passphrase/keyfile and the identity key moves to an encrypted software keystore, with the resulting tier computed at boot and surfaced everywhere (status, Dashboard, capability advertisement) rather than hidden.

```
UEFI (operator-enrolled SB keys)
 └─ Lanzaboote signed UKI (kernel 6.12 LTS + systemd-initrd)      PCRs 0–7,11 measured
     └─ systemd-cryptenroll: LUKS2 unlock bound to TPM2 PCR policy (+ recovery key)
         └─ ZFS pool import
             ├─ rpool/local/root   ← rolled back to @blank every boot (impermanence)
             ├─ rpool/local/nix    ← the closure (content-addressed, verified)
             ├─ rpool/safe/state   ← declared persistent state (see §8)
             └─ rpool/safe/secrets ← sops-nix material, tmpfs-decrypted
                 └─ sovoxd starts → unseals node TDIP key (TPM2, or TEE-resident)
                     └─ tenzro-node starts with roles from compiled intent
```

### 2.1 Trust tiers (T0–T3)

| Tier | Name | Root of trust | What a counterparty can verify | Typical eligibility |
|---|---|---|---|---|
| **T0** | Declared | Software keypair (Ed25519 + ML-DSA-65) in encrypted keystore | Key continuity, stake, reputation history; the OS closure hash is *claimed* (reproducibly auditable, not remotely proven) | Open inference under output verification; training at the Open tier (stake-bonded mean aggregation now, robust aggregation absorbing bad actors on the Phase 2 roadmap); storage (PoR is tier-independent); validator (protocol stake rules apply) |
| **T1** | Fingerprinted | T0 + machine identity from deep hardware fingerprint, **challenge-verified** | A specific physical machine of a *verified hardware class* stands behind the identity; cloning/migration is detectable; declared specs match measured behavior | Everything in T0 with better router weight; hardware-class-priced jobs; sybil-resistant capacity accounting |
| **T2** | Measured | TPM 2.0: measured boot (PCRs), sealed identity key, EK certificate | Manufacturer-rooted evidence of *which closure booted on which genuine machine* (TPM quote + event log vs. published reference measurements) | Integrity-sensitive jobs; compliance/fleet profiles; strongest non-TEE assurance |
| **T3** | Confidential | SEV-SNP/TDX CVM launch (+ NVIDIA GPU CC), anchored via `TEE_VERIFY` | Runtime confidentiality *and* integrity with the host operator outside the TCB | Confidential jobs, `tee-provider` role, protocol's TEE-attested validator weighting |

Invariants at every tier: root impermanence and closure-defined state hold identically; the recovery key restores data, never identity (re-attestation/re-binding is deliberate); tier is recomputed at each boot from live hardware inventory. At T2+ these invariants become *provable* (an unmeasured chain cannot unlock state and therefore cannot sign as the node); at T0/T1 they are enforced locally and evidenced behaviorally. Desktop edition relaxes only interactive-shell and SB-enrollment ergonomics, never the measurement chain available at its tier.

### 2.2 Machine identity & hardware fingerprinting (T1)

The identity agent derives a canonical machine fingerprint from stable identifiers — SMBIOS/DMI board and chassis serials, CPU identity (CPUID + microcode revision), GPU die UUIDs, NVMe/disk WWNs, NIC MACs, RAM SPD serials, and a PCI-topology hash — each salted and hashed per-field so the node can selectively disclose components without leaking the raw inventory. The fingerprint is bound to the TDIP identity at join, re-signed on every boot, and continuity-monitored: bounded drift (a swapped disk) is logged; wholesale change (identity moved to different hardware) flags re-verification and is visible to routing.

Declared hardware is **verified, not trusted**: a challenge responder answers randomized proofs on demand — memory-hard VRAM occupancy probes sized to the claimed GPU, compute benchmarks matched against the claimed SKU's performance envelope, disk-latency/fsync probes backing storage commitments, sustained-bandwidth probes backing training commitments. Honest limits, stated plainly: below T2, all evidence is produced by software the operator controls, so a determined adversary can emulate a fingerprint at cost. T1's purpose is raising sybil and misdeclaration cost, binding stake and reputation to physical machines, detecting cloning, and pricing hardware classes honestly — **not** confidentiality, which only T3 provides.

### 2.3 Integrity without TEEs

Integrity for open workloads never depended on enclaves. The protocol's tier-independent mechanisms — storage proof-of-retrievability, rental availability proofs, signed per-job receipts, training's aggregation defenses (Phase 1 stake-bonded mean aggregation, with Byzantine-robust Krum/TrimmedMean and redundant-assignment slashing on the Phase 2 roadmap), redundant-sampling spot checks for deterministic inference, and STARK verification via `ZK_VERIFY` where a computation warrants the proving cost — compose with tiers so a counterparty assembles exactly the assurance it needs. The routing rule Sovox encodes: **confidentiality requires T3; integrity is available at every tier, at increasing verification cost as the tier decreases.** Jobs declare a minimum tier (and isolation class); the node's advertisement carries its current tier and challenge-response standing.

## 3. Base system specification

| Component | Selection | Notes |
|---|---|---|
| Distribution | NixOS, `sovox-stable` channel pinned to current upstream stable (26.05 "Yarara" at writing) | Flake-pinned; `sovox-edge` tracks unstable for canaries |
| Init/stage-1 | systemd, systemd-initrd | Upstream default since 26.05; enables boot counting + cryptenroll cleanly |
| Kernel | 6.12 LTS (default) / `linux_latest` (opt-in) | SNP+TDX host & guest, NVIDIA open modules |
| Filesystem | ZFS (native encryption optional under LUKS2 outer) | Datasets per concern; snapshots power backup + impermanence |
| GPU userspace | NVIDIA proprietary userland + open kernel modules; CUDA 12.6+ (SM 75–90 + SM100/120 overlay); ROCm 6+ | Mirrors Tenzro's CUDA build matrix; DCGM exporter included |
| Containers | Podman (rootless default) + crun | C1 class |
| MicroVMs | `microvm.nix` + cloud-hypervisor (QEMU fallback for exotic passthrough) | C2/C3 classes |
| Ingress | Caddy | Auto-TLS; publishes RPC/MCP/A2A/web per policy |
| Mail | Stalwart | Single binary; JMAP/IMAP/SMTP; DKIM/ARC/MTA-STS/DANE |
| Host admin | Cockpit (+ Sovox Dashboard, §5) | Cockpit bound to WG mesh/localhost by default |
| Secrets | sops-nix, age keys wrapped by TPM2 | Never in the Nix store in plaintext |
| Firewall | nftables, default-deny inbound | Rules compiled from roles |
| Time | chrony (NTS-enabled pools; operator-overridable) | Consensus needs sane clocks |

**Toolchain note.** Tenzro requires Rust 1.85+/clang to build; **operators never build it.** The Sovox cache ships `tenzro-node`/`tenzro` as reproducibly built, signed derivations in CPU and CUDA variants (plus ROCm/Vulkan variants as upstream features stabilize), digest-equivalent in role to upstream's container images.

## 4. Platform plane: `sovoxd`

A single supervised Rust daemon (C0) owning the node lifecycle. Subsystems:

**4.1 Intent compiler.** Input: `/etc/sovox/sovox.toml` (schema in `05-OPERATOR-DOCS.md` §3) + hardware inventory (`sovox-hw.json`, produced at install and re-probed on boot: CPUs, RAM, GPUs incl. CC capability, TEE type, TPM presence, disks, NICs — from which the canonical fingerprint and the node's trust tier are derived). Output: a Nix module set instantiated against the pinned channel → one derivation = the next system generation. Validation is two-phase: schema (types, ranges) then semantic (role↔hardware feasibility, e.g. `tee-provider` requires SNP/TDX; port collisions; stake sufficiency warnings via node RPC). The compiler is a pure function; its inputs and output hash are logged, making every configuration change auditable and bisectable.

**4.2 Update orchestrator.** Pull-based: polls the signed channel manifest (TUF-style: versioned, threshold-signed metadata over closure hashes) on a jittered timer or on `sovox update`. Flow: fetch closure → verify signatures → stage as boot entry (not default) → **epoch-aware scheduling**: consult tenzro-node for active rental/storage proof deadlines and consensus participation; choose a window that cannot forfeit an availability slice; leader-scheduled validators defer → reboot into staged entry with `boot-counting` armed → health gates (§4.3) → on pass, promote to default; on fail, automatic fallback to previous generation and incident report. `--download-only` and maintenance-window pinning supported for change-controlled fleets. Rings: `edge` → `beta` → `stable`, per-node selectable.

**4.3 Health & attestation supervisor.** Gates: systemd `sovox-healthy.target` (all C0 units up, no failed units), tenzro-node liveness + peer count ≥ threshold + RPC sanity (`eth_blockNumber` advancing), role probes (model responds; storage PoR self-check; Caddy/Stalwart endpoints), attestation re-validation at the node's tier (T2: PCR policy unseal succeeded; T3: TEE stack functional; T1: fingerprint continuity within drift policy), and clock sanity. A tier *downgrade* (e.g. TPM cleared, TEE disabled in firmware) is never fatal — the node keeps running, re-advertises at the new tier, and raises an alert. The same supervisor runs continuously post-boot, feeding Dashboard status and Prometheus.

**4.4 Identity agent.** Generates/unseals the TDIP key with the strongest backend the machine offers, automatically: TEE-resident (T3, key never exists in host memory) → TPM2-sealed against the PCR policy (T2) → encrypted software keystore, argon2id-wrapped with passphrase or auto-unlock keyfile (T0/T1, with the tradeoff stated at setup rather than buried). The same subsystem owns the machine-identity lifecycle: fingerprint derivation and per-boot re-signing, continuity monitoring against the drift policy, and the hardware-challenge responder (§2.2). Wraps `tenzro join`/wallet provisioning; exposes signing only via an authenticated local socket with per-caller scopes (tenzro-node full; Dashboard read-only; agents per delegation).

**4.5 Local API.** gRPC/JSON over a Unix socket (group-gated) + optional mesh-bound HTTPS with mTLS. Consumers: `sovox` CLI, Dashboard backend, Cockpit plugin, Fleet agent. Every mutating call is an intent-compiler transaction — there is no imperative side channel.

**4.6 TDIP as system authorization authority.** The same TDIP identity graph that governs *network* participation — humans (`did:tenzro:human`), delegated agents (`did:tenzro:machine:{controller}`), autonomous agents (`did:tenzro:machine`), and institutions (`did:tenzro:institution:{lei}`), each with delegation scopes and cascading revocation — is wired to govern *the host itself*, so administration runs on the built-in sovereign identity rather than a parallel `/etc/passwd`.

- **Authentication (PAM).** A `pam_tdip` module (declared via NixOS `security.pam`; internally a thin PAM plugin that calls the identity agent's authenticated local socket, §4.4) verifies a presented TDIP credential for login, SSH, and `sudo`/privilege escalation. Human and delegated-machine identities authenticate against their controller chain; the agent validates the credential and its live revocation status before PAM returns success.
- **SSH key resolution (dynamic).** `sshd`'s `AuthorizedKeysCommand` (NixOS `services.openssh.authorizedKeysCommand`) resolves keys per-connection from the identity graph rather than a static `authorized_keys` file. On-chain **cascading revocation** therefore takes effect on the next connection with no file to edit or push: revoke a controller and every delegated machine's host access drops with it.
- **Authorization (polkit).** polkit rules (which integrate with PAM-established identity) map a subject's **TDIP delegation scope** to the set of host actions it may perform — so a human controller, a scoped delegated machine, and an institution identity each administer the box under exactly the authority its DID carries, not an all-or-nothing local admin flag.
- **Mandatory local-root / recovery fallback.** A passphrase-gated local admin path is always present and always works **air-gapped and when the ledger is unreachable**. TDIP is the *default* authority, never the *only* one; the recovery-key ceremony (§10) re-establishes local administration on new hardware. The box can never be bricked out of its own administration by a network condition.
- **Tier-agnostic.** OS login and administration never require a hardware trust tier — a T0 machine authenticates and is administered exactly as a T3 one. Trust tiers (§2) strengthen what a node *proves to counterparties*; they do not decide *who may operate the machine*. This preserves the first-boot, any-hardware principle end to end.

## 5. Operator surfaces

- **`sovox` CLI** — verb-level wrapper over sovoxd + `tenzro` (full reference: `05-OPERATOR-DOCS.md` §4).
- **Sovox Dashboard** — web UI (Caddy-served, mesh/local by default): earnings & reputation (node RPC), role control, model catalog pulls, bonds/slashing exposure, update ring & history, attestation status, power draw. Write actions round-trip through the intent compiler.
- **Cockpit** — generic host administration (journal, storage, network) with a Sovox status plugin; kept because it's battle-tested and operators know it.
- **First-boot wizard** — TUI (Server) / Qt (Desktop): locale, disk plan (disko), SB enrollment guidance, network, role selection with live hardware-feasibility hints, `tenzro join --provider` handoff, recovery-key ceremony.

## 6. Tenzro node integration

**Units (C0, systemd-hardened):** `tenzro-node.service` (DynamicUser, `ProtectSystem=strict`, dedicated state dir, `NoNewPrivileges`, syscall filter, `RestrictAddressFamilies`, cgroup weights guaranteeing consensus CPU/IO under load), `sovoxd.service`, `caddy.service`, `stalwart.service` (role-gated), exporters.

**Network contract (enforced):** 9000/tcp+udp open to WAN (libp2p + QUIC on the same port, both protocols opened for maximal NAT reachability); 8545/8080/3001/3002 bound to 127.0.0.1 and published *only* through Caddy routes the operator enables, with TLS and auth (public-RPC nodes are an explicit `expose.rpc = true` decision); upstream keepalive sysctls (`tcp_keepalive_time=120/intvl=30/probes=5`) applied; libp2p idle timeout honored. UPnP/NAT-PMP attempted for home NATs; relay/DCUtR path always available as fallback.

**Data layout:** `rpool/safe/state/tenzro` (RocksDB, `recordsize=16K`, fsync-honoring), `rpool/safe/state/models` (large-recordsize dataset; content-addressed cache shared read-only into serving contexts), `rpool/safe/state/shards` (storage role; quota = declared capacity + proof margin), `rpool/safe/state/gradients` (training scratch, snapshotted at outer-step boundaries). Wallet/keystore lives with the identity agent, not in the node state dir.

**Version coupling.** Each Sovox release pins one audited tenzro-node version per ring; the channel manifest carries the protocol-compatibility window so a node refuses (with a clear message) to update across a consensus-breaking boundary outside an announced coordinated upgrade.

## 7. Role blueprints

| Role | Isolation | Key components | Meters (protocol) | Hardware floor |
|---|---|---|---|---|
| `validator` | C0 | tenzro-node consensus | priority fees, leader rewards | 4 vCPU / 16 GB / 100 GB SSD (per upstream guide) |
| `ai.serve` | C0 engine + C2 for untrusted adapters | llama.cpp-CUDA / ONNX EPs, router registration | per-token / per-call | GPU tiered (see docs §2); CPU-only allowed for small/ONNX modalities |
| `ai.train` | C2 (C3 for sealed-data runs) | tenzro-training worker + reference trainer | per accepted outer gradient | ≥24 GB VRAM recommended; bandwidth-shaped |
| `compute` | C2 mandatory | rental runtime → microVM per booking | per proven epoch (streaming escrow) | rides `ai` stake; capacity declared ≤ measured |
| `storage` | C0 daemon, data on quota'd dataset | tenzro-storage-provider, PoR responder | per byte-epoch | disk + fsync-capable; ECC recommended |
| `tee-provider` | C3 | SNP/TDX CVMs via cloud-hypervisor; GPU CC passthrough (Hopper/Blackwell class) | per attestation / confidential use | SEV-SNP or TDX host; CC-capable GPU optional |
| `web` | C0 Caddy; sites in C1 | Caddy, ACME, per-site containers | (operator's own business) | any |
| `email` | C0 | Stalwart; DKIM keys via identity agent | (operator's own business) | static IP + rDNS strongly advised (wizard checks) |
| `agent-hub` | C0 endpoints; skills in WASI sandbox (+C2 for native tools) | MCP/A2A servers, tenzro-wasm, payment adapters | agent service fees; x402/AP2 flows | any |

**Tier gating.** Only `tee-provider` *requires* a tier (T3 hardware). Every other role runs at any tier: the tier changes routing weight, eligible job classes, and pricing — not admission. Confidential rentals route exclusively to T3 capacity; hardware-class-priced open jobs prefer T1+; T2 adds boot-chain proof for compliance-sensitive counterparties.

**Per-role notes.**
- *ai.serve*: default engine is the protocol-metered native path; `profile = "throughput"` swaps in the vLLM/SGLang module (ADR-007) where VRAM ≥48 GB, exposing the same OpenAI-compatible surface via the node. Model artifacts verify against catalog digests before load; license tier enforced by the registry. Multi-GPU boxes use tensor-parallel llama.cpp or the throughput engine; multi-box LANs use `tenzro-cluster` HRW placement.
- *ai.train / compute*: every third-party payload runs in a per-job microVM with a virtio-fs read-only model/data mount, jailed vsock control channel, egress limited to the job's declared endpoints, and GPU access via VFIO passthrough (whole-GPU or vGPU where licensed). tc-based shaping guarantees consensus and proof traffic priority over gradient sync.
- *tee-provider*: CVM launch produces the SNP/TDX report; GPU CC evidence (via NVIDIA attestation flow) is bundled; sovoxd submits both through the node to `TEE_VERIFY`. Attestation freshness is a health metric — a stale/failed report withdraws the capability advertisement before the network can slash it.
- *email*: the wizard refuses to enable the role without confirming outbound-25 viability and PTR alignment, offering a documented relay fallback — deliverability honesty over checkbox features.

## 8. Isolation model (summary)

| Class | Mechanism | TCB shared with keys/consensus | Used for |
|---|---|---|---|
| C0 | systemd-hardened native units | yes (minimized: seccomp, namespaces, caps) | tenzro-node, sovoxd, Caddy, Stalwart, exporters |
| C1 | rootless Podman, userns, seccomp/AppArmor profile | kernel only | operator's own web apps/tools |
| C2 | cloud-hypervisor microVM, virtio-only device model, no shared filesystem writes | no | rentals, training payloads, native agent tools |
| C3 | C2 + SEV-SNP/TDX memory encryption + measured launch (+ GPU CC) | no, incl. host operator (for data-in-use) | confidential jobs, TEE-provider, optional key vault |
| WASI | tenzro-wasm component host, capability-scoped, fuel-metered | in-process with node but deterministic & fuel-bounded | agent skills / MCP tools |

Rule of thumb enforced by the intent compiler: *anything that executes bytes chosen by a counterparty runs in ≥C2.*

Isolation classes and trust tiers are orthogonal by design: **classes (C0–C3) are what this machine protects itself from its workloads; tiers (T0–T3) are what this machine can prove about itself to others.** A T0 homelab box still runs rentals in C2 microVMs; a T3 datacenter host still runs its own web apps in C1.

## 9. Networking

nftables policy compiled from roles (default-deny inbound; established/related; per-role allows; rate-limited SYN; optional geo/ASN blocklists as data). Egress: unrestricted by default for the node's protocol traffic; per-microVM egress allowlists for jobs; optional full-egress-proxy mode for compliance profiles. WireGuard admin mesh (`sovox mesh`) carries SSH, Cockpit, Dashboard, and Fleet — Server hardened profile has **no** WAN-listening admin surface. IPv6 dual-stack throughout; DNS via local resolver with DNSSEC validation; split-horizon aware for home NAT hairpinning.

## 10. Storage & backup

ZFS layout as in §2/§6; `zrepl`-style scheduled snapshots on `rpool/safe/*` with pruning; `sovox snapshot`/`sovox backup send` to any SSH/ZFS target — or, dogfooded, to the Tenzro storage network as an encrypted client. Restore drill is a documented, wizard-assisted flow: new hardware + recovery key + latest `safe` replica → same node identity after deliberate re-attestation (PCR policy re-seal). Scrub schedule + SMART/DCGM health feed alerts.

## 11. Observability

Prometheus scrape targets: node exporter, ZFS, NVIDIA DCGM, Caddy, Stalwart, sovoxd (gates, update states, attestation freshness), tenzro-node (peers, consensus participation, router earnings, proof outcomes). Baseline alert pack: consensus stall, peer-count floor, missed availability proof, PoR failure, attestation stale, disk/pool degradation, thermal/power anomalies, cert expiry, mail-queue backlog. Grafana bundle optional; Dashboard is the operator-grade view; logs stay in journald with optional Loki shipping to an operator-chosen endpoint. Nothing leaves the node unless configured to (ADR-011).

## 12. Fleet & provisioning

Paths: (a) **USB/ISO wizard** for hands-on installs; (b) **`nixos-anywhere` + disko** for anything reachable over SSH (takes over an existing Linux — including a stock Tenzro validator VM per upstream's guide — and converges it to Sovox); (c) **netboot/PXE profile** for rack fleets. Fleet management: the same flake describes N hosts; push deploys for small fleets; the pull channel with per-ring pinning for large ones. **Sovox Fleet** (commercial) adds a multi-node control plane — inventory, ring orchestration, aggregate earnings/alerts — implemented strictly over the sovoxd API so self-hosters lose nothing but convenience.

## 13. Supply chain & CI

Every release: flake inputs pinned by hash → built on Sovox CI (Hydra-class) → **reproducibility check** (independent second builder must match closure hashes; mismatches block release) → sign narinfo (Ed25519) + channel manifest (threshold TUF-style) → publish images (ISO, raw, qcow2) with detached signatures, SPDX SBOM, and provenance attestation → staged through `edge`/`beta` rings with cohort telemetry *from opted-in canaries only*. The binary cache is mirrorable via one documented rsync/atticd procedure; "sovereign mode" = mirror cache + git mirror + local manifest signing key ceremony, giving an institution a fully internal update chain. NixOS-test-driven integration suite boots every role in VMs per commit, including an SNP-emulated attestation path and a 4-validator local testnet smoke.

## 14. Threat model (condensed)

| Adversary | Vector | Primary controls |
|---|---|---|
| Remote network attacker | Exposed services, protocol DoS | Default-deny + single structural port; loopback RPC; Caddy auth; rate limits; kernel LTS + fast channel |
| Malicious workload (renter/trainer/agent) | Escape, exfiltration, resource abuse | C2/C3 VM boundary; VFIO-scoped GPU; egress allowlists; fuel metering; cgroup guarantees |
| Malicious counterparty (economic) | Fake demand, proof gaming | Protocol-side: stake, availability/PoR proofs, robust aggregation, slashing — surfaced, not reimplemented |
| Supply-chain attacker | Poisoned deps/cache/channel | Pinning, reproducibility gate, threshold-signed manifests, SBOM diffing, mirrorable channel |
| Physical/evil-maid | Disk theft, boot tamper | FDE bound to measured boot; sealed identity; impermanent root |
| Dishonest operator (vs. counterparties) | Spec misdeclaration, sybil identities, result fabrication | Tiered attestation (T1 challenge proofs, T2 quotes, T3 reports); fingerprint-bound stake & reputation; redundant sampling, signed receipts, robust aggregation, PoR/availability proofs |
| Host operator (vs. confidential clients) | Memory inspection | C3: SNP/TDX + GPU CC; attestation verified on-chain by the counterparty, not by trusting Sovox |
| Sovox project itself | Coercion, disappearance | Apache-2.0; reproducible builds; sovereign mode; no kill-switch, no mandatory account |

**Residual risks, stated plainly:** TEE vendor-root trust and published side-channel classes; consumer GPUs lack CC; below T2, fingerprints and challenge responses are produced by operator-controlled software and are emulable at cost — they raise the bar, they are not attestation; economic attacks bounded only by bond sizes; DiLoCo-class training assumes robust aggregation holds at the chosen trust tier.

## 15. Failure & recovery matrix

| Failure | Behavior |
|---|---|
| Bad update | Boot counting → previous generation, automatic; incident record with gate that failed |
| Power loss mid-anything | ZFS + atomic generation switch → clean boot; RocksDB fsync durability honored by dataset config |
| Disk death (mirrored) | Degraded-pool alert; hot-replace runbook |
| Disk death (single) | Restore drill (§10): identity survives via recovery-key ceremony |
| GPU driver wedge | Role degrades (advertisement withdrawn) without touching consensus; `sovox doctor` remediation |
| Network partition | Node follows protocol behavior; sovoxd suppresses updates during partition; alerts locally |
| Compromise suspected | `sovox lockdown`: withdraw advertisements, close ingress, freeze wallet ops pending operator |

## 16. Capacity planning heuristics (v0.1)

Validator: upstream floor (4 vCPU/16 GB/100 GB) + 25% headroom. Inference: VRAM ≥ model-quant footprint + KV budget for target concurrency (Dashboard shows the catalog's fit calculator — same logic `tenzro join --provider` uses to pick the largest fitting model). Storage: declared capacity ≤ 80% of dataset quota; IOPS floor for PoR latency. Training: outer-step cadence tuned so sync fits the shaped bandwidth share (Streaming-DiLoCo-style overlap is upstream roadmap; Sovox exposes the knobs). Mixed roles: the compiler warns when declared obligations exceed measured hardware minus consensus reserves.

## 17. Repository layout (monorepo `sovox/sovox`)

```
flake.nix                  # entrypoint: packages, modules, images, checks
modules/
  sovox/                   # platform plane: sovoxd, dashboard, wizard, mesh, updates
  tenzro/                  # node packaging, units, network contract, data layout
  roles/                   # one module per blueprint (§7)
  hardening/               # boot chain, impermanence, nftables, sysctls, profiles
  desktop/                 # KDE Plasma edition deltas
overlays/                  # CUDA SM matrix, pinned engine builds
packages/                  # sovoxd, sovox-cli, dashboard, wizard (Rust/TS)
images/                    # ISO / raw / qcow2 / netboot builders
fleet/                     # nixos-anywhere+disko profiles, ring channel tooling
tests/                     # NixOS VM tests: per-role, update+rollback, 4-validator net, attestation
docs/                      # this suite + operator docs
scripts/                   # release, cache-sign, mirror, SBOM
```

## 18. Open engineering items

Tracked with owners before v0.2: throughput-engine metering receipts (with Tenzro upstream); Blackwell TEE-I/O host bring-up validation; vGPU partitioning policy for multi-tenant rentals; Loki-optional log pipeline; SELinux/landlock investigation (ADR risk §9.6); Fleet control-plane threat model; email-role reputation warm-up automation; hardware-challenge calibration corpus per GPU SKU (performance envelopes the verifier checks against); fingerprint-attestation format proposed upstream as a TDIP metadata extension / OAN standard so tiers become protocol-legible, not just Sovox-legible.

*Powered by Tenzro Protocol.*
