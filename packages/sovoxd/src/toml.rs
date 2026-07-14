//! Hand-written parser for the TOML subset that `modules/sovox/render.nix`
//! actually emits: comments, `[a.b]` table headers, basic strings, booleans,
//! integers, and (possibly multi-line) arrays. Inline tables and arrays of
//! tables are deliberately unsupported — the rendered file never contains
//! them, and rejecting them loudly beats half-parsing them.

use std::collections::BTreeMap;
use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Str(String),
    Bool(bool),
    Int(i64),
    Array(Vec<Value>),
    Table(Table),
}

pub type Table = BTreeMap<String, Value>;

#[derive(Debug, Clone, PartialEq)]
pub struct Error {
    pub line: usize,
    pub msg: String,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.msg)
    }
}

fn err<T>(line: usize, msg: impl Into<String>) -> Result<T, Error> {
    Err(Error { line, msg: msg.into() })
}

/// Cut a `#` comment, respecting basic strings.
fn strip_comment(line: &str) -> &str {
    let mut in_string = false;
    let mut escaped = false;
    for (i, c) in line.char_indices() {
        if in_string {
            if escaped {
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '"' {
                in_string = false;
            }
        } else if c == '"' {
            in_string = true;
        } else if c == '#' {
            return &line[..i];
        }
    }
    line
}

/// Net bracket depth of `[`/`]` outside strings — drives multi-line arrays.
fn bracket_depth(s: &str) -> i64 {
    let mut depth = 0;
    let mut in_string = false;
    let mut escaped = false;
    for c in s.chars() {
        if in_string {
            if escaped {
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '"' {
                in_string = false;
            }
        } else {
            match c {
                '"' => in_string = true,
                '[' => depth += 1,
                ']' => depth -= 1,
                _ => {}
            }
        }
    }
    depth
}

struct Cursor<'a> {
    chars: std::iter::Peekable<std::str::Chars<'a>>,
    line: usize,
}

impl<'a> Cursor<'a> {
    fn new(s: &'a str, line: usize) -> Self {
        Cursor { chars: s.chars().peekable(), line }
    }

    fn skip_ws(&mut self) {
        while let Some(&c) = self.chars.peek() {
            if c == '\n' {
                self.line += 1;
                self.chars.next();
            } else if c.is_whitespace() {
                self.chars.next();
            } else {
                break;
            }
        }
    }

    fn parse_value(&mut self) -> Result<Value, Error> {
        self.skip_ws();
        match self.chars.peek() {
            Some('"') => self.parse_string().map(Value::Str),
            Some('[') => self.parse_array(),
            Some('{') => err(self.line, "inline tables are not supported"),
            Some('t') | Some('f') => self.parse_bool(),
            Some(c) if *c == '-' || c.is_ascii_digit() => self.parse_int(),
            Some(c) => err(self.line, format!("unexpected character {c:?} in value")),
            None => err(self.line, "expected a value"),
        }
    }

    fn parse_string(&mut self) -> Result<String, Error> {
        self.chars.next(); // opening quote
        let mut out = String::new();
        loop {
            match self.chars.next() {
                None => return err(self.line, "unterminated string"),
                Some('\n') => return err(self.line, "unterminated string"),
                Some('"') => return Ok(out),
                Some('\\') => match self.chars.next() {
                    Some('"') => out.push('"'),
                    Some('\\') => out.push('\\'),
                    Some('n') => out.push('\n'),
                    Some('t') => out.push('\t'),
                    Some('r') => out.push('\r'),
                    Some(c) => return err(self.line, format!("unsupported escape \\{c}")),
                    None => return err(self.line, "unterminated string"),
                },
                Some(c) => out.push(c),
            }
        }
    }

    fn parse_bool(&mut self) -> Result<Value, Error> {
        let word: String = std::iter::from_fn(|| {
            self.chars.next_if(|c| c.is_ascii_alphabetic())
        })
        .collect();
        match word.as_str() {
            "true" => Ok(Value::Bool(true)),
            "false" => Ok(Value::Bool(false)),
            other => err(self.line, format!("expected true/false, got {other:?}")),
        }
    }

    fn parse_int(&mut self) -> Result<Value, Error> {
        let mut raw = String::new();
        if self.chars.peek() == Some(&'-') {
            raw.push(self.chars.next().unwrap());
        }
        while let Some(c) = self.chars.next_if(|c| c.is_ascii_digit() || *c == '_') {
            if c != '_' {
                raw.push(c);
            }
        }
        raw.parse::<i64>()
            .map(Value::Int)
            .map_err(|_| Error { line: self.line, msg: format!("invalid integer {raw:?}") })
    }

    fn parse_array(&mut self) -> Result<Value, Error> {
        self.chars.next(); // opening bracket
        let mut items = Vec::new();
        loop {
            self.skip_ws();
            if self.chars.peek() == Some(&']') {
                self.chars.next();
                return Ok(Value::Array(items));
            }
            items.push(self.parse_value()?);
            self.skip_ws();
            match self.chars.peek() {
                Some(',') => {
                    self.chars.next();
                }
                Some(']') => {}
                _ => return err(self.line, "expected ',' or ']' in array"),
            }
        }
    }

    fn rest_is_blank(&mut self) -> bool {
        self.skip_ws();
        self.chars.peek().is_none()
    }
}

/// Split a header/key path like `roles.agent-hub` or `a."b.c"` into segments.
fn parse_path(s: &str, line: usize) -> Result<Vec<String>, Error> {
    let mut segments = Vec::new();
    let mut chars = s.chars().peekable();
    loop {
        while chars.next_if(|c| *c == ' ' || *c == '\t').is_some() {}
        let seg = match chars.peek() {
            Some('"') => {
                chars.next();
                let mut out = String::new();
                loop {
                    match chars.next() {
                        None => return err(line, "unterminated quoted key"),
                        Some('"') => break,
                        Some(c) => out.push(c),
                    }
                }
                out
            }
            _ => {
                let bare: String = std::iter::from_fn(|| {
                    chars.next_if(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
                })
                .collect();
                bare
            }
        };
        if seg.is_empty() {
            return err(line, format!("empty key segment in {s:?}"));
        }
        segments.push(seg);
        while chars.next_if(|c| *c == ' ' || *c == '\t').is_some() {}
        match chars.next() {
            None => return Ok(segments),
            Some('.') => continue,
            Some(c) => return err(line, format!("unexpected character {c:?} in key {s:?}")),
        }
    }
}

/// Walk/create nested tables along `path`, returning the innermost table.
fn descend<'t>(root: &'t mut Table, path: &[String], line: usize) -> Result<&'t mut Table, Error> {
    let mut current = root;
    for seg in path {
        let entry = current
            .entry(seg.clone())
            .or_insert_with(|| Value::Table(Table::new()));
        current = match entry {
            Value::Table(t) => t,
            _ => return err(line, format!("key {seg:?} is not a table")),
        };
    }
    Ok(current)
}

pub fn parse(input: &str) -> Result<Table, Error> {
    let mut root = Table::new();
    let mut current_path: Vec<String> = Vec::new();
    let mut defined_headers: Vec<Vec<String>> = Vec::new();

    let mut lines = input.lines().enumerate().peekable();
    while let Some((idx, raw)) = lines.next() {
        let lineno = idx + 1;
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            continue;
        }

        if let Some(rest) = line.strip_prefix('[') {
            if rest.starts_with('[') {
                return err(lineno, "arrays of tables ([[…]]) are not supported");
            }
            let Some(inner) = rest.strip_suffix(']') else {
                return err(lineno, "unterminated table header");
            };
            let path = parse_path(inner, lineno)?;
            if defined_headers.contains(&path) {
                return err(lineno, format!("duplicate table header [{}]", inner.trim()));
            }
            // Creating the table validates that no segment is a non-table value.
            descend(&mut root, &path, lineno)?;
            defined_headers.push(path.clone());
            current_path = path;
            continue;
        }

        // Assignment. Find '=' outside strings.
        let eq = {
            let mut in_string = false;
            let mut escaped = false;
            let mut found = None;
            for (i, c) in line.char_indices() {
                if in_string {
                    if escaped {
                        escaped = false;
                    } else if c == '\\' {
                        escaped = true;
                    } else if c == '"' {
                        in_string = false;
                    }
                } else if c == '"' {
                    in_string = true;
                } else if c == '=' {
                    found = Some(i);
                    break;
                }
            }
            found
        };
        let Some(eq) = eq else {
            return err(lineno, format!("expected `key = value`, got {line:?}"));
        };

        let key_path = parse_path(&line[..eq], lineno)?;

        // Multi-line arrays: keep consuming physical lines until brackets close.
        let mut value_src = line[eq + 1..].to_string();
        let mut end_line = lineno;
        while bracket_depth(&value_src) > 0 {
            let Some((idx, raw)) = lines.next() else {
                return err(end_line, "unterminated array");
            };
            end_line = idx + 1;
            value_src.push('\n');
            value_src.push_str(strip_comment(raw));
        }

        let mut cursor = Cursor::new(&value_src, lineno);
        let value = cursor.parse_value()?;
        if !cursor.rest_is_blank() {
            return err(cursor.line, "trailing characters after value");
        }

        let full_path: Vec<String> = current_path
            .iter()
            .chain(key_path.iter())
            .cloned()
            .collect();
        let (last, parents) = full_path.split_last().unwrap();
        let table = descend(&mut root, parents, lineno)?;
        if table.contains_key(last) {
            return err(lineno, format!("duplicate key {last:?}"));
        }
        table.insert(last.clone(), value);
    }

    Ok(root)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn get<'t>(table: &'t Table, path: &str) -> &'t Value {
        let mut current = table;
        let segs: Vec<&str> = path.split('.').collect();
        for (i, seg) in segs.iter().enumerate() {
            if i == segs.len() - 1 {
                return current.get(*seg).unwrap_or_else(|| panic!("missing {path}"));
            }
            current = match current.get(*seg) {
                Some(Value::Table(t)) => t,
                other => panic!("{seg} is {other:?}"),
            };
        }
        unreachable!()
    }

    /// The Operator Docs §3 example, rewritten in the supported subset
    /// (no inline tables; spend_budget rendered as a string).
    const DOCS_EXAMPLE: &str = r#"
# rendered by modules/sovox/render.nix
[node]
name       = "atlas-01"
edition    = "server"            # server | desktop
ring       = "stable"
timezone   = "UTC"

[network]
mesh       = true
ipv6       = true
upnp       = false

[network.expose]
rpc  = false
mcp  = false
a2a  = false

[roles]
enabled = ["validator", "ai", "storage"]

[roles.ai]
profile          = "native"
serve            = true
train            = true
rental           = true
models           = ["auto"]
max_vram_percent = 90
train_bandwidth  = "40%"

[roles.storage]
capacity   = "2TB"
dataset    = "rpool/safe/state/shards"

[roles.agent-hub]
skills_dir   = "/var/lib/sovox/skills"
spend_budget = "per_tx=1,per_day=20"

[updates]
auto          = true
window        = "02:00-05:00"
download_only = false

[identity]
key_backend = "software"

[observability]
prometheus    = "local"
loki_endpoint = ""

[backup]
snapshots   = "hourly=24,daily=14,weekly=8"
send_target = ""
"#;

    #[test]
    fn parses_the_docs_example() {
        let t = parse(DOCS_EXAMPLE).unwrap();
        assert_eq!(get(&t, "node.name"), &Value::Str("atlas-01".into()));
        assert_eq!(get(&t, "node.edition"), &Value::Str("server".into()));
        assert_eq!(get(&t, "network.mesh"), &Value::Bool(true));
        assert_eq!(get(&t, "network.expose.rpc"), &Value::Bool(false));
        assert_eq!(
            get(&t, "roles.enabled"),
            &Value::Array(vec![
                Value::Str("validator".into()),
                Value::Str("ai".into()),
                Value::Str("storage".into()),
            ])
        );
        assert_eq!(get(&t, "roles.ai.max_vram_percent"), &Value::Int(90));
        assert_eq!(
            get(&t, "roles.agent-hub.skills_dir"),
            &Value::Str("/var/lib/sovox/skills".into())
        );
        assert_eq!(
            get(&t, "backup.snapshots"),
            &Value::Str("hourly=24,daily=14,weekly=8".into())
        );
    }

    #[test]
    fn empty_and_comment_only_input() {
        assert_eq!(parse("").unwrap(), Table::new());
        assert_eq!(parse("# nothing\n   \n# here\n").unwrap(), Table::new());
    }

    #[test]
    fn multiline_arrays() {
        let t = parse("[roles]\nenabled = [\n  \"ai\", # serving\n  \"storage\",\n]\n").unwrap();
        assert_eq!(
            get(&t, "roles.enabled"),
            &Value::Array(vec![Value::Str("ai".into()), Value::Str("storage".into())])
        );
    }

    #[test]
    fn string_escapes_and_hash_inside_string() {
        let t = parse(r#"a = "x # not a comment \"quoted\" \n""#).unwrap();
        assert_eq!(
            get(&t, "a"),
            &Value::Str("x # not a comment \"quoted\" \n".into())
        );
    }

    #[test]
    fn negative_and_separated_integers() {
        let t = parse("a = -42\nb = 1_000\n").unwrap();
        assert_eq!(get(&t, "a"), &Value::Int(-42));
        assert_eq!(get(&t, "b"), &Value::Int(1000));
    }

    #[test]
    fn duplicate_table_header_is_an_error() {
        let e = parse("[a]\nx = 1\n[a]\ny = 2\n").unwrap_err();
        assert_eq!(e.line, 3);
        assert!(e.msg.contains("duplicate table header"));
    }

    #[test]
    fn duplicate_key_is_an_error() {
        let e = parse("x = 1\nx = 2\n").unwrap_err();
        assert_eq!(e.line, 2);
        assert!(e.msg.contains("duplicate key"));
    }

    #[test]
    fn unterminated_string_is_an_error() {
        let e = parse("a = \"oops\n").unwrap_err();
        assert_eq!(e.line, 1);
        assert!(e.msg.contains("unterminated string"));
    }

    #[test]
    fn bad_bool_is_an_error() {
        let e = parse("a = tru\n").unwrap_err();
        assert!(e.msg.contains("expected true/false"));
    }

    #[test]
    fn inline_tables_are_rejected() {
        let e = parse("a = { b = 1 }\n").unwrap_err();
        assert!(e.msg.contains("inline tables"));
    }

    #[test]
    fn arrays_of_tables_are_rejected() {
        let e = parse("[[a]]\n").unwrap_err();
        assert!(e.msg.contains("arrays of tables"));
    }

    #[test]
    fn missing_equals_is_an_error() {
        let e = parse("just some words\n").unwrap_err();
        assert!(e.msg.contains("key = value"));
    }

    #[test]
    fn trailing_garbage_is_an_error() {
        let e = parse("a = 1 2\n").unwrap_err();
        assert!(e.msg.contains("trailing characters"));
    }
}
