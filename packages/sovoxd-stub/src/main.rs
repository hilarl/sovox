//! sovoxd-stub: minimal health/version daemon over a Unix socket.
//!
//! `GET /health`  → 200 {"status":"ok",...} — or 503 if the poison file exists
//! `GET /version` → 200 {"version":...}
//!
//! This socket API is designed as a subset of the eventual sovoxd local API
//! (Arch §4.5): the health gate built against it is not rewritten in v0.1.
//! The poison file (/etc/sovox/poison) is the lever the rollback test pulls.

use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const DEFAULT_SOCKET: &str = "/run/sovoxd/sovoxd.sock";
const DEFAULT_POISON: &str = "/etc/sovox/poison";

struct Config {
    socket: PathBuf,
    poison: PathBuf,
}

fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut socket = std::env::var("SOVOXD_SOCKET").unwrap_or_else(|_| DEFAULT_SOCKET.into());
    let mut poison = std::env::var("SOVOXD_POISON_FILE").unwrap_or_else(|_| DEFAULT_POISON.into());

    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--socket" => {
                socket = it.next().ok_or("--socket requires a path")?.clone();
            }
            "--poison-file" => {
                poison = it.next().ok_or("--poison-file requires a path")?.clone();
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(Config {
        socket: PathBuf::from(socket),
        poison: PathBuf::from(poison),
    })
}

/// Parse the request target out of an HTTP/1.x request line ("GET /health HTTP/1.1").
fn request_target(request: &str) -> Option<(&str, &str)> {
    let line = request.lines().next()?;
    let mut parts = line.split_whitespace();
    let method = parts.next()?;
    let target = parts.next()?;
    Some((method, target))
}

fn response(status: u16, reason: &str, body: &str) -> String {
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

fn handle(request: &str, poison: &Path) -> String {
    match request_target(request) {
        Some(("GET", "/health")) => {
            if poison.exists() {
                response(
                    503,
                    "Service Unavailable",
                    &format!(r#"{{"status":"poisoned","version":"{VERSION}"}}"#),
                )
            } else {
                response(
                    200,
                    "OK",
                    &format!(r#"{{"status":"ok","version":"{VERSION}"}}"#),
                )
            }
        }
        Some(("GET", "/version")) => {
            response(200, "OK", &format!(r#"{{"version":"{VERSION}"}}"#))
        }
        Some(("GET", _)) => response(404, "Not Found", r#"{"error":"not found"}"#),
        _ => response(405, "Method Not Allowed", r#"{"error":"method not allowed"}"#),
    }
}

fn serve_connection(mut stream: UnixStream, poison: &Path) {
    let mut buf = [0u8; 4096];
    let n = match stream.read(&mut buf) {
        Ok(0) | Err(_) => return,
        Ok(n) => n,
    };
    let request = String::from_utf8_lossy(&buf[..n]);
    let reply = handle(&request, poison);
    let _ = stream.write_all(reply.as_bytes());
    let _ = stream.flush();
}

fn run(config: Config) -> std::io::Result<()> {
    // Stale socket from an unclean shutdown; RuntimeDirectory is fresh per
    // service start, but be robust when run by hand.
    let _ = std::fs::remove_file(&config.socket);
    let listener = UnixListener::bind(&config.socket)?;
    eprintln!(
        "sovoxd-stub {VERSION} listening on {} (poison file: {})",
        config.socket.display(),
        config.poison.display()
    );

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let poison = config.poison.clone();
                std::thread::spawn(move || serve_connection(stream, &poison));
            }
            Err(err) => eprintln!("sovoxd-stub: accept error: {err}"),
        }
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let config = match parse_args(&args) {
        Ok(config) => config,
        Err(err) => {
            eprintln!("sovoxd-stub: {err}");
            eprintln!("usage: sovoxd-stub [--socket PATH] [--poison-file PATH]");
            std::process::exit(2);
        }
    };
    if let Err(err) = run(config) {
        eprintln!("sovoxd-stub: {err}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("sovoxd-stub-test-{name}-{}", std::process::id()));
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

    fn spawn_server(dir: &Path) -> (PathBuf, PathBuf) {
        let socket = dir.join("sovoxd.sock");
        let poison = dir.join("poison");
        let config = Config {
            socket: socket.clone(),
            poison: poison.clone(),
        };
        std::thread::spawn(move || run(config).unwrap());
        for _ in 0..100 {
            if socket.exists() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        (socket, poison)
    }

    #[test]
    fn health_ok_then_poisoned() {
        let dir = tmp_dir("health");
        let (socket, poison) = spawn_server(&dir);

        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
        assert!(reply.contains(r#""status":"ok""#));

        std::fs::write(&poison, "poisoned").unwrap();
        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 503"), "got: {reply}");
        assert!(reply.contains(r#""status":"poisoned""#));

        std::fs::remove_file(&poison).unwrap();
        let reply = request(&socket, "/health");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
    }

    #[test]
    fn version_reports_crate_version() {
        let dir = tmp_dir("version");
        let (socket, _poison) = spawn_server(&dir);
        let reply = request(&socket, "/version");
        assert!(reply.starts_with("HTTP/1.1 200"), "got: {reply}");
        assert!(reply.contains(&format!(r#""version":"{VERSION}""#)));
    }

    #[test]
    fn unknown_paths_and_methods() {
        assert!(handle("GET /nope HTTP/1.1\r\n\r\n", Path::new("/nonexistent")).starts_with("HTTP/1.1 404"));
        assert!(handle("POST /health HTTP/1.1\r\n\r\n", Path::new("/nonexistent")).starts_with("HTTP/1.1 405"));
        assert!(handle("", Path::new("/nonexistent")).starts_with("HTTP/1.1 405"));
    }
}
