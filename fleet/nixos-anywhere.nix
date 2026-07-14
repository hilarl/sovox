# Fleet install profile (Operator Docs §1.2, minus --intent/--migrate-tenzro,
# which need sovoxd). Exposed as `nix run .#install`.
{ writeShellApplication, inputs, system ? "x86_64-linux" }:

writeShellApplication {
  name = "sovox-fleet-install";
  runtimeInputs = [ inputs.nixos-anywhere.packages.${system}.default ];
  text = ''
    usage() {
      cat >&2 <<EOF
    usage: sovox-fleet-install --target root@host --plan single-zfs|mirror-zfs
    (run from the repo root; --intent/--migrate-tenzro land with sovoxd in v0.1)
    EOF
      exit 1
    }

    target=""
    plan="single-zfs"
    while [ $# -gt 0 ]; do
      case "$1" in
        --target) target=$2; shift 2 ;;
        --plan) plan=$2; shift 2 ;;
        --intent|--migrate-tenzro)
          echo "error: $1 requires sovoxd (v0.1); not available in the prototype" >&2
          exit 2
          ;;
        *) usage ;;
      esac
    done
    [ -n "$target" ] || usage

    case "$plan" in
      single-zfs) attr="server-example" ;;
      mirror-zfs) attr="server-mirror-example" ;;
      *) usage ;;
    esac

    exec nixos-anywhere --flake ".#$attr" --target-host "$target"
  '';
}
