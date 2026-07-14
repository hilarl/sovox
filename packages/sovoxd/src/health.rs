//! The boot health verdict. Three states, strict precedence:
//!
//!   poisoned      — the poison file exists (the lever the rollback test pulls)
//!   config-error  — /etc/sovox/sovox.toml exists but does not parse; a staged
//!                   generation that ships a broken intent file must fail the
//!                   gate and be rolled back
//!   ok            — everything else, including "no intent file at all"
//!
//! The `ok` and `poisoned` response bodies are shape-locked: the health gate
//! (modules/sovox/updates.nix) and the VM tests were built against them in
//! v0.0.1 and must keep passing unchanged.
//!
//! Deliberate omission: no systemd unit probe from inside the daemon —
//! sovox-health-check.service already asserts zero failed units, and calling
//! systemctl from this DynamicUser/ProtectSystem=strict sandbox would add
//! D-Bus surface for a redundant check.

use crate::json;
use crate::state::{LoadedConfig, State};

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

pub enum Verdict {
    Ok,
    Poisoned,
    ConfigError(String),
}

pub fn verdict(state: &State) -> Verdict {
    if state.poison.exists() {
        return Verdict::Poisoned;
    }
    match state.load_config() {
        LoadedConfig::Invalid(e) => Verdict::ConfigError(e),
        LoadedConfig::Absent | LoadedConfig::Parsed(_) => Verdict::Ok,
    }
}

impl Verdict {
    pub fn status_str(&self) -> &'static str {
        match self {
            Verdict::Ok => "ok",
            Verdict::Poisoned => "poisoned",
            Verdict::ConfigError(_) => "config-error",
        }
    }

    pub fn is_healthy(&self) -> bool {
        matches!(self, Verdict::Ok)
    }

    /// The `/health` body. `ok`/`poisoned` are the v0.0.1 shapes, verbatim.
    pub fn health_body(&self) -> String {
        match self {
            Verdict::Ok => format!(r#"{{"status":"ok","version":"{VERSION}"}}"#),
            Verdict::Poisoned => format!(r#"{{"status":"poisoned","version":"{VERSION}"}}"#),
            Verdict::ConfigError(e) => format!(
                r#"{{"status":"config-error","version":"{VERSION}","error":{}}}"#,
                json::string(e)
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::time::Instant;

    fn tmp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("sovoxd-health-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn state(dir: &PathBuf) -> State {
        State {
            started: Instant::now(),
            poison: dir.join("poison"),
            config: dir.join("sovox.toml"),
        }
    }

    #[test]
    fn verdict_matrix() {
        let dir = tmp("matrix");
        let s = state(&dir);

        // no poison, no config → ok
        assert!(matches!(verdict(&s), Verdict::Ok));

        // valid config → still ok
        std::fs::write(&s.config, "[node]\nname = \"x\"\n").unwrap();
        assert!(matches!(verdict(&s), Verdict::Ok));

        // malformed config → config-error
        std::fs::write(&s.config, "not toml at all").unwrap();
        assert!(matches!(verdict(&s), Verdict::ConfigError(_)));

        // poison wins over everything, including malformed config
        std::fs::write(&s.poison, "x").unwrap();
        assert!(matches!(verdict(&s), Verdict::Poisoned));

        std::fs::remove_file(&s.poison).unwrap();
        std::fs::remove_file(&s.config).unwrap();
        assert!(matches!(verdict(&s), Verdict::Ok));
    }

    /// Shape lock: these exact bodies are what the v0.0.1 health gate and VM
    /// tests were built against. Only the version number may drift.
    #[test]
    fn health_bodies_are_shape_locked() {
        assert_eq!(
            Verdict::Ok.health_body(),
            format!(r#"{{"status":"ok","version":"{VERSION}"}}"#)
        );
        assert_eq!(
            Verdict::Poisoned.health_body(),
            format!(r#"{{"status":"poisoned","version":"{VERSION}"}}"#)
        );
        let body = Verdict::ConfigError("line 3: duplicate key \"x\"".into()).health_body();
        assert_eq!(
            body,
            format!(
                r#"{{"status":"config-error","version":"{VERSION}","error":"line 3: duplicate key \"x\""}}"#
            )
        );
    }
}
