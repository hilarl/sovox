# Sovox — Operator Documentation

**Version 1.0 · July 2026 · Covers Sovox v0.1 surface (v0.2 items marked)**
Documentation follows the Diátaxis model: §1 tutorial · §2–4 reference · §5 how-to guides · §6–8 operations · §9 explanation lives in the whitepaper/architecture docs.

---

## 1. Quickstart (tutorial)

### 1.1 Path A — USB installer (hands-on)

1. Flash `sovox-<ver>-x86_64.iso` (verify: `minisign -Vm sovox-*.iso -P <release key>`), boot UEFI.
2. Wizard steps: language/keymap → **disk plan** (disko presets: `single-zfs`, `mirror-zfs`, `keep-data`) → **Secure Boot** (guided key enrollment; skippable with a warning) → network (DHCP/static/Wi-Fi on Desktop) → **edition & roles** (live hardware-feasibility hints: detected GPUs, VRAM, TEE type, TPM presence) → passphrase + **recovery-key ceremony** (print/QR; stored nowhere else).
3. First boot: wizard resumes → `tenzro join --provider` handoff (creates TDIP identity + threshold wallet, detects hardware, posts the provider bond — 100 TNZO on the current network spec — registers pricing defaults, pulls the largest catalog model that fits).
4. Verify: `sovox status` → expect `HEALTHY`, peers ≥ 8, roles active, and your **trust tier** (T0 Declared / T1 Fingerprinted / T2 Measured / T3 Confidential — computed from your hardware; any tier earns). Dashboard: `https://sovox.local` (mesh/LAN).
5. First earnings appear under `sovox earnings` once routed demand settles — typically within the first hours on an `ai` role node serving a popular catalog model.

### 1.2 Path B — remote takeover (any SSH-reachable Linux)

```
$ sovox install --target root@203.0.113.7 --plan mirror-zfs --intent ./sovox.toml
```
Wraps `nixos-anywhere` + disko: partitions per plan, installs the pinned closure, applies your intent, reboots into Sovox. Ideal for converting an existing stock Ubuntu/Debian Tenzro validator: state under `--migrate-tenzro <path>` is imported into the proper datasets and the identity re-sealed on the new trust chain.

### 1.3 Three commands you'll actually use

```
sovox status      # health, roles, peers, attestation, staged updates
sovox update      # fetch+verify+stage+health-gated activate (epoch-aware)
sovox rollback    # previous generation, one reboot
```

## 2. Hardware reference

| Role | Minimum | Recommended | Notes |
|---|---|---|---|
| Base system | x86-64-v3 or ARM64, 8 GB RAM, 60 GB SSD | 16 GB, NVMe, TPM 2.0 | **Any machine joins and earns.** No TPM/TEE → T0/T1 (encrypted software keystore + fingerprint identity); TPM 2.0 → T2 (sealed identity, measured boot); SNP/TDX host → T3. Tier changes what you can *prove*, never whether you can participate |
| `validator` | 4 vCPU / 16 GB / 100 GB SSD | 8 vCPU / 32 GB / 200 GB NVMe | Per upstream fleet guide; ≥4 validators for BFT, 10+ production, multi-zone |
| `ai.serve` (LLM) | NVIDIA ≥12 GB VRAM (SM ≥75) or Apple/AMD via upstream Vulkan/ROCm variants | 24–96 GB VRAM | CUDA 12.6 userspace pinned; catalog fit-calculator in Dashboard |
| `ai.serve` (ONNX modalities) | CPU-only viable | any CUDA GPU | forecast/vision/embedding/ASR etc. |
| `ai.train` | 24 GB VRAM, 100 Mbps up | 48–80 GB, 1 Gbps | Int8/Int4 outer-gradient sync keeps WAN feasible |
| `compute` rental | declared ≤ measured capacity | — | Rides `ai` role/stake |
| `storage` | 1 TB dedicated, fsync-honest disk | ECC RAM, mirrored pool | Quota enforced = declared + proof margin |
| `tee-provider` | AMD EPYC (SEV-SNP) or Intel Xeon (TDX) host | + H100/H200/B200-class GPU for GPU CC | Consumer GPUs lack CC — role won't offer GPU confidentiality without capable hardware |
| `email` | static IP, rDNS/PTR set, outbound 25 | — | Wizard verifies; relay fallback documented |
| Network (all) | 9000/tcp+udp reachable (direct, UPnP, or relay) | direct inbound | RPC surfaces never need WAN exposure |

## 3. `sovox.toml` reference (intent schema v1)

```toml
[node]
name       = "atlas-01"
edition    = "server"            # server | desktop
ring       = "stable"            # edge | beta | stable
timezone   = "UTC"

[network]
mesh       = true                # WireGuard admin mesh
ipv6       = true
upnp       = true                # home-NAT convenience
[network.expose]                 # everything defaults to false/loopback
rpc  = false                     # if true: Caddy-published w/ TLS+auth
mcp  = false
a2a  = false

[roles]
enabled = ["validator", "ai", "storage"]

[roles.ai]
profile          = "native"      # native | throughput (v0.2, VRAM≥48G)
serve            = true
train            = true
rental           = true
models           = ["auto"]      # or explicit catalog IDs; digests verified
max_vram_percent = 90
train_bandwidth  = "40%"         # tc share; consensus always priority

[roles.storage]
capacity   = "2TB"
dataset    = "rpool/safe/state/shards"

[roles.validator]
stake_warn_below = "true"        # surface protocol stake sufficiency via RPC

[roles.tee]                      # v0.2
enabled    = false
gpu_cc     = "auto"

[roles.web]                      # v0.2
sites      = [{ domain = "example.org", root = "/srv/www/example" }]

[roles.email]                    # v0.2
domains    = ["example.org"]

[roles.agent-hub]                # v0.2
skills_dir     = "/var/lib/sovox/skills"
fuel_budget    = "default"
spend_budget   = { per_tx = "1 TNZO", per_day = "20 TNZO" }

[updates]
auto        = true
window      = "02:00-05:00"      # local; epoch-aware scheduler still applies
download_only = false

[identity]
key_backend = "tpm2"             # tpm2 | tee | software(warned)

[observability]
prometheus  = "mesh"             # mesh | local | off
loki_endpoint = ""               # optional, operator-chosen

[backup]
snapshots   = "hourly=24,daily=14,weekly=8"
send_target = ""                 # ssh/zfs target, or tenzro-storage client (v0.2)
```

Validation: `sovox check` (schema + semantic: role↔hardware feasibility, port collisions, quota vs. pool, stake warnings). Apply: `sovox up` (compiles → builds/fetches closure → health-gated switch, no reboot unless kernel/boot chain changed).

## 4. CLI reference (synopsis)

```
sovox
├─ status | doctor | check | up | diff        # state, diagnosis, intent lifecycle
├─ update [--download-only|--ring R] | rollback | generations
├─ role   list|add|rm|tune <role> [k=v]
├─ models list|pull|rm|price <id>             # wraps tenzro model, digest-verified
├─ earnings [--range] | bonds | reputation    # node RPC views
├─ attest  status|refresh                     # PCRs, TEE reports, TEE_VERIFY anchors
├─ mesh    init|join|peers                    # WireGuard admin mesh
├─ snapshot create|list | backup send|restore
├─ keys    status|reseal|recovery-drill
├─ expose  rpc|mcp|a2a on|off                 # Caddy-published surfaces
├─ lockdown | logs [unit] | metrics
├─ fleet   ...                                # (Fleet-enabled) inventory, rings, rollout
└─ tenzro  <passthrough>                      # full upstream CLI (63 modules)
```

Exit codes are stable and documented for automation; every mutating verb is an intent transaction (audit-logged with input/output hashes).

## 5. Role guides (how-to, condensed)

**AI serving.** `sovox role add ai && sovox up`. Verify: `sovox models list` shows the pulled model `serving`; `curl :8545` router probe via `sovox doctor ai`. Tune pricing: `sovox models price <id> --per-1k <TNZO>`. Multi-box LAN: enable on each node; `tenzro-cluster` converges placement without a coordinator.

**Training participant.** Enable `train=true`; the worker only accepts runs at your configured trust tier and isolation (C2 default; C3 for sealed-data runs on TEE hosts). Earnings accrue per accepted outer gradient; rejected gradients simply don't pay — persistent rejection triggers a `doctor` hint (clock, bandwidth, or GPU instability). Outlier exclusion via Byzantine-robust aggregation is a Phase 2 protocol capability; at Phase 1 the tier relies on stake bonding and mean aggregation.

**Compute rental.** `rental=true` advertises declared capacity. Each booking = one microVM; you'll see `rental-<id>.scope` units. Missed availability proofs make the consumer whole from your stake — the Dashboard shows proof-margin status; keep the node's update window honest and power stable.

**Storage.** Quota'd dataset + PoR responder. `sovox doctor storage` runs a self-challenge. Scrub monthly (scheduled by default); never thin-provision beneath a storage commitment.

**Validator.** Confirm stake via `sovox bonds`; multi-zone fleets should stagger rings so no quorum-relevant set updates simultaneously (Fleet enforces this; manual fleets: `--ring` discipline).

**TEE provider (v0.2).** `sovox attest status` must show green host attestation before the role will advertise. Each confidential job: CVM launch report (+ GPU CC evidence when applicable) auto-anchored; stale attestation withdraws the advertisement *before* the protocol penalizes.

**Web/Email/Agent Hub (v0.2).** Web: drop content in `sites[].root` or point at a C1 container; Caddy handles TLS. Email: complete the deliverability checklist the wizard prints (SPF/DKIM/DMARC records shown ready-to-paste; warm-up guidance). Agent Hub: skills are WASI components with per-skill fuel + TNZO spend budgets; native tools require explicit `isolation="microvm"`.

## 6. Operations runbook

**Updates.** Default unattended within window; epoch-aware scheduler defers around proof deadlines/leader slots. Change-controlled fleets: `updates.download_only=true` + `sovox update --apply` in your window. Failed gates → automatic rollback + `sovox incidents show` (which gate, journal slice).

**Backup/restore.** Snapshots on `safe/*` per policy; `backup send` to any ZFS/SSH target. Restore drill (practice quarterly): fresh install → `sovox keys recovery-drill` walkthrough → import replica → deliberate re-attestation reseals identity to the new trust chain.

**Incident: attestation failure.** Symptom: `attest status` red / unseal failed at boot. Causes: firmware update changed PCRs (expected — run `sovox keys reseal` after verifying the update was yours), or tampering (treat as compromise → `sovox lockdown`, investigate offline).

**Incident: earnings stopped.** `sovox doctor` decision tree: peers low (NAT/ISP) → port 9000 reachability probe + relay fallback check; model unlisted (license tier / catalog change) → `models list --explain`; pricing uncompetitive → router stats; proofs missing → clock/disk latency.

**Incident: slashing-risk warning.** Dashboard surfaces protocol-side warnings (equivocation impossible under single-instance systemd lock; primary real risks are downtime vs. obligations). Response: reduce declared obligations before hardware maintenance (`sovox role tune compute capacity=0` drains gracefully at epoch boundary).

**Scaling out.** Second node in 10 minutes: `sovox install --target ... --intent same.toml --node-name atlas-02` — identities are per-node; intent is shared.

## 7. Security hardening checklist (Server, hardened profile)

- [x] Secure Boot enrolled (Lanzaboote), setup-mode exited — *wizard-enforced unless skipped*
- [x] TPM2-sealed identity; recovery key ceremony completed and stored offline
- [x] Impermanent root active (`sovox status` shows `root: ephemeral`)
- [x] Ingress = 9000 only (+role ports you chose); `sovox expose` all off unless required
- [x] SSH/Cockpit/Dashboard on mesh only; no WAN admin surface
- [x] `updates.auto=true` on `stable` ring (or documented change process)
- [x] Backups tested via recovery drill within last quarter
- [ ] Optional: egress-proxy compliance mode; geo/ASN ingress policy; Loki off-node logs
- [ ] Optional (P3): sovereign mode — local cache mirror + manifest key ceremony (Assurance guide)

## 8. Troubleshooting quick table

| Symptom | Likely cause → fix |
|---|---|
| Peers < 4, earnings zero | 9000/tcp+udp blocked → router/ISP; confirm relay path with `sovox doctor net`; open both protocols |
| GPU role won't enable | Driver/CUDA mismatch after manual overlay edits → `sovox up` from clean intent; check `nvidia-smi` inside `doctor ai` |
| Update loops back | Read `incidents show` gate; commonly role probe on a model that no longer fits after VRAM change |
| RPC publicly reachable warning | You set `expose.rpc=true` or bypassed Caddy — revert; upstream default bind is why Sovox forces loopback |
| Mail deliverability poor | PTR/SPF/DKIM/DMARC mismatch → wizard checklist; warm-up schedule; consider relay |
| Clock-skew alerts | NTS pool unreachable (air-gapped) → configure internal NTP; consensus and proofs need sane time |
| Disk latency PoR failures | SMR/USB disks or thin-provisioned storage → move dataset to honest NVMe/HDD CMR |

## 9. Glossary (selection)

**TDIP** Tenzro Decentralized Identity Protocol (`did:tenzro`; human / delegated-agent / autonomous-agent / institution classes). **TNZO** fixed-supply protocol token: gas, bonds, commission denominator, governance. **Availability proof** per-epoch liveness proof gating streaming rental escrow. **PoR** proof-of-retrievability challenge for storage. **Outer gradient** DiLoCo-class synchronization unit; the thing training participants are paid per. **Closure** the complete, content-addressed set of a NixOS system's dependencies — Sovox's unit of update, rollback, and audit. **Generation** a bootable system state; rollback target. **Impermanence** root filesystem reset to a blank snapshot each boot; state persists only in declared datasets. **CVM** confidential VM (SEV-SNP/TDX). **GPU CC** NVIDIA GPU Confidential Computing (Hopper/Blackwell-class). **Ring** update channel stage (edge/beta/stable). **Sovereign mode** fully self-hosted mirror of every Sovox artifact channel.

---

*Support: community forum & Matrix (free) · Sovox Assurance (SLA). Upstream protocol docs: `github.com/tenzro/tenzro-network/docs`.*

*Powered by Tenzro Protocol.*
