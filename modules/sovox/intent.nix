# The inverse of render.nix: turn a sovox.toml intent file into sovox.*
# option settings. This is what makes `nix run .#install -- --intent …` a
# real path (fleet/nixos-anywhere.nix) and what the edition test round-trips
# (render → fromTOML → fromTable must reproduce the option values).
#
# Not a NixOS module — a pure attrset of functions, importable anywhere.
# Only keys present in the file are set; everything else keeps its option
# default, so a minimal intent file stays minimal.
let
  opt = set: name: if set ? ${name} then { ${name} = set.${name}; } else { };
  opts = set: names: builtins.foldl' (acc: n: acc // opt set n) { } names;
in
rec {
  # attrset (as from builtins.fromTOML) → { sovox = …; } module config
  fromTable = intent:
    let
      node = intent.node or { };
      network = intent.network or { };
      expose = network.expose or { };
      roles = intent.roles or { };
      role = name: keys:
        if roles ? ${name} then { ${name} = opts roles.${name} keys; } else { };
    in
    {
      sovox =
        (opt node "edition")
        // {
          node = opts node [ "name" "ring" "timezone" ];

          network = opts network [ "mesh" "ipv6" "upnp" ] // {
            expose = opts expose [ "rpc" "mcp" "a2a" ];
          };

          roles =
            (opts roles [ "enabled" ])
            // role "ai" [ "profile" "serve" "train" "rental" "models" "max_vram_percent" "train_bandwidth" ]
            // role "storage" [ "capacity" "dataset" ]
            // role "validator" [ "stake_warn_below" ]
            // role "web" [ "sites" ]
            // role "email" [ "domains" ]
            // role "agent-hub" [ "skills_dir" "fuel_budget" "spend_budget" ]
            # docs key [roles.tee].enabled ↔ option sovox.roles.tee.enable
            // (if roles ? tee then {
              tee = opts roles.tee [ "gpu_cc" ]
                // (if roles.tee ? enabled then { enable = roles.tee.enabled; } else { });
            } else { });

          updates = opts (intent.updates or { }) [ "auto" "window" "download_only" ];

          identity = opts (intent.identity or { }) [ "key_backend" ];

          observability = opts (intent.observability or { }) [ "prometheus" "loki_endpoint" ];

          backup = opts (intent.backup or { }) [ "snapshots" "send_target" ];
        };
    };

  # PATH → { sovox = …; } module config
  fromIntent = path: fromTable (builtins.fromTOML (builtins.readFile path));
}
