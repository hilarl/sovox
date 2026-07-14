//! HTTP/1.x over the Unix socket: request-line parsing, response framing,
//! and the route table. Everything answers JSON and closes the connection.

use crate::health::{self, VERSION};
use crate::json;
use crate::state::{enabled_roles, summarize, LoadedConfig, State};
use crate::toml::Value;

/// Parse the method and target out of an HTTP/1.x request line
/// ("GET /health HTTP/1.1").
pub fn request_target(request: &str) -> Option<(&str, &str)> {
    let line = request.lines().next()?;
    let mut parts = line.split_whitespace();
    let method = parts.next()?;
    let target = parts.next()?;
    Some((method, target))
}

pub fn response(status: u16, reason: &str, body: &str) -> String {
    format!(
        "HTTP/1.1 {status} {reason}\r\n\
         Content-Type: application/json\r\n\
         Content-Length: {len}\r\n\
         Connection: close\r\n\
         \r\n\
         {body}",
        len = body.len()
    )
}

fn ok(body: &str) -> String {
    response(200, "OK", body)
}

fn opt_json(v: &Option<String>) -> String {
    match v {
        Some(s) => json::string(s),
        None => "null".into(),
    }
}

fn handle_health(state: &State) -> String {
    let verdict = health::verdict(state);
    let body = verdict.health_body();
    if verdict.is_healthy() {
        ok(&body)
    } else {
        response(503, "Service Unavailable", &body)
    }
}

fn handle_status(state: &State) -> String {
    let verdict = health::verdict(state);
    let (loaded, summary) = match state.load_config() {
        LoadedConfig::Parsed(t) => (true, Some(summarize(&t))),
        _ => (false, None),
    };
    let (node, edition, ring, roles) = match &summary {
        Some(s) => (
            opt_json(&s.node),
            opt_json(&s.edition),
            opt_json(&s.ring),
            format!(
                "[{}]",
                s.roles.iter().map(|r| json::string(r)).collect::<Vec<_>>().join(",")
            ),
        ),
        None => ("null".into(), "null".into(), "null".into(), "[]".into()),
    };
    ok(&format!(
        r#"{{"status":{status},"version":"{VERSION}","uptime_seconds":{uptime},"config_loaded":{loaded},"node":{node},"edition":{edition},"ring":{ring},"roles":{roles}}}"#,
        status = json::string(verdict.status_str()),
        uptime = state.uptime_seconds(),
    ))
}

fn handle_config(state: &State) -> String {
    match state.load_config() {
        LoadedConfig::Parsed(t) => ok(&format!(
            r#"{{"loaded":true,"config":{}}}"#,
            json::table(&t)
        )),
        LoadedConfig::Absent => ok(r#"{"loaded":false,"config":null}"#),
        LoadedConfig::Invalid(e) => ok(&format!(
            r#"{{"loaded":false,"config":null,"error":{}}}"#,
            json::string(&e)
        )),
    }
}

fn handle_roles(state: &State) -> String {
    match state.load_config() {
        LoadedConfig::Parsed(t) => {
            let enabled = enabled_roles(&t);
            let enabled_json = format!(
                "[{}]",
                enabled.iter().map(|r| json::string(r)).collect::<Vec<_>>().join(",")
            );
            // The per-role tables under [roles], minus the `enabled` list.
            let detail = match t.get("roles") {
                Some(Value::Table(roles)) => {
                    let inner: Vec<String> = roles
                        .iter()
                        .filter(|(k, _)| k.as_str() != "enabled")
                        .map(|(k, v)| format!("{}:{}", json::string(k), json::value(v)))
                        .collect();
                    format!("{{{}}}", inner.join(","))
                }
                _ => "{}".into(),
            };
            ok(&format!(
                r#"{{"enabled":{enabled_json},"roles":{detail}}}"#
            ))
        }
        _ => ok(r#"{"enabled":[],"roles":{}}"#),
    }
}

pub fn route(request: &str, state: &State) -> String {
    match request_target(request) {
        Some(("GET", "/health")) => handle_health(state),
        Some(("GET", "/version")) => ok(&format!(r#"{{"version":"{VERSION}"}}"#)),
        Some(("GET", "/status")) => handle_status(state),
        Some(("GET", "/config")) => handle_config(state),
        Some(("GET", "/roles")) => handle_roles(state),
        Some(("GET", _)) => response(404, "Not Found", r#"{"error":"not found"}"#),
        _ => response(405, "Method Not Allowed", r#"{"error":"method not allowed"}"#),
    }
}
