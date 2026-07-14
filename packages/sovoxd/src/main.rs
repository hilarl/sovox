//! sovoxd: the Sovox node daemon, answering over a local Unix socket.
//!
//! `GET /health`  → 200 {"status":"ok",...} — 503 on poison file or a broken
//!                  intent file (the boot health gate curls this)
//! `GET /version` → 200 {"version":...}
//! `GET /status`  → node summary: uptime, edition, ring, enabled roles
//! `GET /config`  → the parsed /etc/sovox/sovox.toml as JSON
//! `GET /roles`   → [roles].enabled plus per-role tables
//!
//! This socket API is the local surface of sovoxd (Arch §4.5): the health
//! gate and tests built against it are not rewritten as the daemon grows.
//! The poison file (/etc/sovox/poison) is the lever the rollback test pulls.

mod health;
mod http;
mod json;
mod state;
mod toml;

use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use health::VERSION;
use state::State;

const DEFAULT_SOCKET: &str = "/run/sovoxd/sovoxd.sock";
const DEFAULT_POISON: &str = "/etc/sovox/poison";
const DEFAULT_CONFIG: &str = "/etc/sovox/sovox.toml";

struct Args {
    socket: PathBuf,
    poison: PathBuf,
    config: PathBuf,
}

fn parse_args(args: &[String]) -> Result<Args, String> {
    let mut socket = std::env::var("SOVOXD_SOCKET").unwrap_or_else(|_| DEFAULT_SOCKET.into());
    let mut poison = std::env::var("SOVOXD_POISON_FILE").unwrap_or_else(|_| DEFAULT_POISON.into());
    let mut config = std::env::var("SOVOXD_CONFIG").unwrap_or_else(|_| DEFAULT_CONFIG.into());

    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--socket" => {
                socket = it.next().ok_or("--socket requires a path")?.clone();
            }
            "--poison-file" => {
                poison = it.next().ok_or("--poison-file requires a path")?.clone();
            }
            "--config" => {
                config = it.next().ok_or("--config requires a path")?.clone();
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(Args {
        socket: PathBuf::from(socket),
        poison: PathBuf::from(poison),
        config: PathBuf::from(config),
    })
}

fn serve_connection(mut stream: UnixStream, state: &State) {
    let mut buf = [0u8; 4096];
    let n = match stream.read(&mut buf) {
        Ok(0) | Err(_) => return,
        Ok(n) => n,
    };
    let request = String::from_utf8_lossy(&buf[..n]);
    let reply = http::route(&request, state);
    let _ = stream.write_all(reply.as_bytes());
    let _ = stream.flush();
}

fn run(args: Args) -> std::io::Result<()> {
    // Stale socket from an unclean shutdown; RuntimeDirectory is fresh per
    // service start, but be robust when run by hand.
    let _ = std::fs::remove_file(&args.socket);
    let listener = UnixListener::bind(&args.socket)?;
    eprintln!(
        "sovoxd {VERSION} listening on {} (poison: {}, config: {})",
        args.socket.display(),
        args.poison.display(),
        args.config.display()
    );

    let state = Arc::new(State {
        started: Instant::now(),
        poison: args.poison,
        config: args.config,
    });

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let state = Arc::clone(&state);
                std::thread::spawn(move || serve_connection(stream, &state));
            }
            Err(err) => eprintln!("sovoxd: accept error: {err}"),
        }
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args = match parse_args(&args) {
        Ok(args) => args,
        Err(err) => {
            eprintln!("sovoxd: {err}");
            eprintln!("usage: sovoxd [--socket PATH] [--poison-file PATH] [--config PATH]");
            std::process::exit(2);
        }
    };
    if let Err(err) = run(args) {
        eprintln!("sovoxd: {err}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn tmp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("sovoxd-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn request(socket: &Path, target: &str) -> String {
        let mut stream = UnixStream::connect(socket).unwrap();
        stream
            .write_all(format!("GET {target} HTTP/1.1\r\nHost: localhost\r\n\r\n").as_bytes())
            .unwrap();
        let mut reply = String::new();
        stream.read_to_string(&mut reply).unwrap();
        reply
    }

    fn body(reply: &str) -> &str {
        reply.split("\r\n\r\n").nth(1).unwrap()
    }

    fn spawn_server(dir: &Path) -> (PathBuf, PathBuf, PathBuf) {
        let socket = dir.join("sovoxd.sock");
        let poison = dir.join("poison");
        let config = dir.join("sovox.toml");
        let args = Args {
            socket: socket.clone(),
            poison: poison.clone(),
            config: config.clone(),
        };
        std::thread::spawn(move || run(args).unwrap());
        for _ in 0..100 {
            if socket.exists() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        (socket, poison, config)
    }

    const SAMPLE: &str = "[node]\nname = \"atlas-01\"\nedition = \"server\"\nring = \"stable\"\n\
                          [roles]\nenabled = [\"ai\"]\n[roles.ai]\nserve = true\n";

    #[test]
    fn health_ok_then_poisoned() {
        let dir = tmp_dir("health");
        let (socket, poison, _config) = spawn_server(&dir);

        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
        // Shape lock: the exact v0.0.1 body, only the version drifting.
        assert_eq!(body(&reply), format!(r#"{{"status":"ok","version":"{VERSION}"}}"#));

        std::fs::write(&poison, "poisoned").unwrap();
        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 503"), "got: {reply}");
        assert_eq!(
            body(&reply),
            format!(r#"{{"status":"poisoned","version":"{VERSION}"}}"#)
        );

        std::fs::remove_file(&poison).unwrap();
        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
    }

    #[test]
    fn health_gates_on_broken_config() {
        let dir = tmp_dir("config-error");
        let (socket, _poison, config) = spawn_server(&dir);

        std::fs::write(&config, "definitely not toml").unwrap();
        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 503"), "got: {reply}");
        assert!(body(&reply).contains(r#""status":"config-error""#));

        // Fixing the file heals the verdict without a restart.
        std::fs::write(&config, SAMPLE).unwrap();
        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
    }

    #[test]
    fn version_reports_crate_version() {
        let dir = tmp_dir("version");
        let (socket, _poison, _config) = spawn_server(&dir);
        let reply = request(&socket, "/version");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
        assert_eq!(body(&reply), format!(r#"{{"version":"{VERSION}"}}"#));
    }

    #[test]
    fn status_reflects_config() {
        let dir = tmp_dir("status");
        let (socket, _poison, config) = spawn_server(&dir);

        // Without a config file: healthy, nothing loaded.
        let reply = request(&socket, "/status");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
        let b = body(&reply).to_string();
        assert!(b.contains(r#""status":"ok""#), "got: {b}");
        assert!(b.contains(r#""config_loaded":false"#), "got: {b}");
        assert!(b.contains(r#""node":null"#), "got: {b}");
        assert!(b.contains(r#""uptime_seconds":"#), "got: {b}");

        std::fs::write(&config, SAMPLE).unwrap();
        let b = request(&socket, "/status");
        assert!(b.contains(r#""config_loaded":true"#), "got: {b}");
        assert!(b.contains(r#""node":"atlas-01""#), "got: {b}");
        assert!(b.contains(r#""edition":"server""#), "got: {b}");
        assert!(b.contains(r#""ring":"stable""#), "got: {b}");
        assert!(b.contains(r#""roles":["ai"]"#), "got: {b}");
    }

    #[test]
    fn config_endpoint_round_trips() {
        let dir = tmp_dir("config");
        let (socket, _poison, config) = spawn_server(&dir);

        let reply = request(&socket, "/config");
        assert_eq!(body(&reply), r#"{"loaded":false,"config":null}"#);

        std::fs::write(&config, SAMPLE).unwrap();
        let b = request(&socket, "/config");
        assert!(b.contains(r#""loaded":true"#), "got: {b}");
        assert!(b.contains(r#""name":"atlas-01""#), "got: {b}");
        assert!(b.contains(r#""serve":true"#), "got: {b}");

        std::fs::write(&config, "broken =").unwrap();
        let b = request(&socket, "/config");
        assert!(b.contains(r#""loaded":false"#), "got: {b}");
        assert!(b.contains(r#""error":"line 1"#), "got: {b}");
    }

    #[test]
    fn roles_endpoint_lists_enabled_and_detail() {
        let dir = tmp_dir("roles");
        let (socket, _poison, config) = spawn_server(&dir);

        let reply = request(&socket, "/roles");
        assert_eq!(body(&reply), r#"{"enabled":[],"roles":{}}"#);

        std::fs::write(&config, SAMPLE).unwrap();
        let b = request(&socket, "/roles");
        assert!(b.contains(r#""enabled":["ai"]"#), "got: {b}");
        assert!(b.contains(r#""ai":{"serve":true}"#), "got: {b}");
    }

    #[test]
    fn unknown_paths_and_methods() {
        let dir = tmp_dir("routing");
        let state = State {
            started: Instant::now(),
            poison: dir.join("poison"),
            config: dir.join("sovox.toml"),
        };
        assert!(http::route("GET /nope HTTP/1.1\r\n\r\n", &state).starts_with("HTTP/1.1 404"));
        assert!(http::route("POST /health HTTP/1.1\r\n\r\n", &state).starts_with("HTTP/1.1 405"));
        assert!(http::route("", &state).starts_with("HTTP/1.1 405"));
    }
}
