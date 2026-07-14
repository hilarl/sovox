# Fleet install profile (Operator Docs §1.2). Exposed as `nix run .#install`.
#
# `--intent` hands the flake an operator intent file via the SOVOX_INTENT
# environment variable, which requires impure evaluation — the script
# passes `--option pure-eval false` through nixos-anywhere to every nix
# invocation it makes. Stated here and in fleet/README.md rather than
# hidden, because impure eval is a real trade: the build reads a file
# outside the flake.
{ writeShellApplication, inputs, system ? "x86_64-linux" }:

writeShellApplication {
  name = "sovox-fleet-install";
  runtimeInputs = [ inputs.nixos-anywhere.packages.${system}.default ];
  text = ''
    usage() {
      cat >&2 <<EOF
    usage: sovox-fleet-install --target root@host --plan single-zfs|mirror-zfs [--intent ./sovox.toml]
    (run from the repo root; --migrate-tenzro lands with the sovoxd migration path in v0.1)
    EOF
      exit 1
    }

    target=""
    plan="single-zfs"
    intent=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --target) target=$2; shift 2 ;;
        --plan) plan=$2; shift 2 ;;
        --intent) intent=$2; shift 2 ;;
        --migrate-tenzro)
          echo "error: --migrate-tenzro needs the sovoxd migration path (v0.1); reserved" >&2
          exit 2
          ;;
        *) usage ;;
      esac
    done
    [ -n "$target" ] || usage

    case "$plan" in
      single-zfs) attr="server-example" intentAttr="intent" ;;
      mirror-zfs) attr="server-mirror-example" intentAttr="intent-mirror" ;;
      *) usage ;;
    esac

    if [ -n "$intent" ]; then
      if [ ! -f "$intent" ]; then
        echo "error: intent file not found: $intent" >&2
        exit 2
      fi
      SOVOX_INTENT="$(realpath "$intent")"
      export SOVOX_INTENT
      # builtins.getEnv needs impure evaluation; see the header comment.
      exec nixos-anywhere --flake ".#$intentAttr" \
        --option pure-eval false \
        --target-host "$target"
    fi

    exec nixos-anywhere --flake ".#$attr" --target-host "$target"
  '';
}
