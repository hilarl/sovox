//! Daemon state: where things live on disk, when we started, and the node
//! summary derived from the rendered intent file. The config is re-read on
//! every request — a staged generation that swaps /etc/sovox/sovox.toml is
//! observed without a daemon restart, which is what the health gate needs.

use std::path::PathBuf;
use std::time::Instant;

use crate::toml::{self, Table, Value};

pub struct State {
    pub started: Instant,
    pub poison: PathBuf,
    pub config: PathBuf,
}

pub enum LoadedConfig {
    /// No intent file on disk — valid (bare bootstrap), health is unaffected.
    Absent,
    Parsed(Table),
    Invalid(String),
}

impl State {
    pub fn load_config(&self) -> LoadedConfig {
        match std::fs::read_to_string(&self.config) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => LoadedConfig::Absent,
            Err(e) => LoadedConfig::Invalid(format!("read {}: {e}", self.config.display())),
            Ok(text) => match toml::parse(&text) {
                Ok(table) => LoadedConfig::Parsed(table),
                Err(e) => LoadedConfig::Invalid(e.to_string()),
            },
        }
    }

    pub fn uptime_seconds(&self) -> u64 {
        self.started.elapsed().as_secs()
    }
}

fn str_at<'t>(table: &'t Table, section: &str, key: &str) -> Option<&'t str> {
    match table.get(section) {
        Some(Value::Table(t)) => match t.get(key) {
            Some(Value::Str(s)) => Some(s),
            _ => None,
        },
        _ => None,
    }
}

/// `[roles].enabled` as strings; empty when absent or mistyped.
pub fn enabled_roles(table: &Table) -> Vec<String> {
    match table.get("roles") {
        Some(Value::Table(roles)) => match roles.get("enabled") {
            Some(Value::Array(items)) => items
                .iter()
                .filter_map(|v| match v {
                    Value::Str(s) => Some(s.clone()),
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        },
        _ => Vec::new(),
    }
}

pub struct Summary {
    pub node: Option<String>,
    pub edition: Option<String>,
    pub ring: Option<String>,
    pub roles: Vec<String>,
}

pub fn summarize(table: &Table) -> Summary {
    Summary {
        node: str_at(table, "node", "name").map(str::to_owned),
        edition: str_at(table, "node", "edition").map(str::to_owned),
        ring: str_at(table, "node", "ring").map(str::to_owned),
        roles: enabled_roles(table),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summarizes_node_and_roles() {
        let t = toml::parse(
            "[node]\nname = \"atlas-01\"\nedition = \"server\"\nring = \"stable\"\n\
             [roles]\nenabled = [\"ai\", \"storage\"]\n",
        )
        .unwrap();
        let s = summarize(&t);
        assert_eq!(s.node.as_deref(), Some("atlas-01"));
        assert_eq!(s.edition.as_deref(), Some("server"));
        assert_eq!(s.ring.as_deref(), Some("stable"));
        assert_eq!(s.roles, vec!["ai".to_string(), "storage".to_string()]);
    }

    #[test]
    fn missing_sections_summarize_to_nothing() {
        let t = toml::parse("").unwrap();
        let s = summarize(&t);
        assert!(s.node.is_none() && s.edition.is_none() && s.ring.is_none());
        assert!(s.roles.is_empty());
    }
}
