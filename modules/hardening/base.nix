# Base hardening profile: nftables default-deny compiled from
# sovox.internal.baselinePorts, kernel sysctls, appliance posture.
{ config, lib, pkgs, ... }:
let
  ports = lib.unique config.sovox.internal.baselinePorts;
  portSet = "{ ${lib.concatMapStringsSep ", " toString ports} }";
in
{
  # checkRuleset (default true) syntax-checks the ruleset at *build* time —
  # the only pre-CI validation available on a nix-less dev host.
  networking.nftables.enable = true;

  networking.nftables.tables.sovox = {
    family = "inet";
    # Default-deny inbound; established/related; baseline ports tcp+udp with
    # rate-limited SYN. Roles append to sovox.internal.baselinePorts.
    content = ''
      chain input {
        type filter hook input priority filter; policy drop;

        ct state established,related accept
        ct state invalid drop
        iifname "lo" accept

        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } accept
        meta l4proto ipv6-icmp accept

        ${lib.optionalString (ports != [ ]) ''
        # rate-limited SYN: excess connection attempts are dropped before accept
        tcp flags syn / fin,syn,rst,ack tcp dport ${portSet} limit rate over 60/second burst 120 packets drop
        tcp dport ${portSet} accept
        udp dport ${portSet} accept
        ''}

        ${lib.optionalString (config.sovox.profile == "standard") ''
        # PROTOTYPE ONLY: SSH reachable on all interfaces in the
        # "standard" profile. Tracked issue: move behind the WireGuard admin
        # mesh (`sovox mesh`, v0.1); "hardened" already excludes this rule.
        tcp dport 22 accept
        ''}
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
      }
    '';
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = false;
    };
  };

  boot.kernel.sysctl = {
    # network
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    # kernel
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.yama.ptrace_scope" = 1;
  };

  # systemd-wide defaults; per-unit hardening lives with each unit
  # (tenzro-node: docs/03-ARCHITECTURE.md §6; sovoxd: modules/sovox/updates.nix).
  systemd.coredump.enable = false;

  security.sudo.execWheelOnly = true;

  # TDIP PAM insertion point (v0.2): lands here —
  #   security.pam.services.{login,sshd}.rules — pam_tdip resolves against the
  #   node's TDIP identity graph; the mandatory local-root/recovery fallback
  #   must always work air-gapped. Deliberately not stubbed with logic.
}
