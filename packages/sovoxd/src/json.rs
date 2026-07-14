//! Minimal JSON serialization for the parsed config tree. Output only —
//! the daemon never parses JSON.

use crate::toml::{Table, Value};

pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

pub fn string(s: &str) -> String {
    format!("\"{}\"", escape(s))
}

pub fn value(v: &Value) -> String {
    match v {
        Value::Str(s) => string(s),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::Array(items) => {
            let inner: Vec<String> = items.iter().map(value).collect();
            format!("[{}]", inner.join(","))
        }
        Value::Table(t) => table(t),
    }
}

pub fn table(t: &Table) -> String {
    let inner: Vec<String> = t
        .iter()
        .map(|(k, v)| format!("{}:{}", string(k), value(v)))
        .collect();
    format!("{{{}}}", inner.join(","))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_control_and_quote_characters() {
        assert_eq!(escape("a\"b\\c\nd\te"), "a\\\"b\\\\c\\nd\\te");
        assert_eq!(escape("\u{01}"), "\\u0001");
    }

    #[test]
    fn serializes_nested_values() {
        let mut inner = Table::new();
        inner.insert("b".into(), Value::Bool(true));
        let mut t = Table::new();
        t.insert("a".into(), Value::Array(vec![Value::Int(1), Value::Str("x".into())]));
        t.insert("t".into(), Value::Table(inner));
        assert_eq!(table(&t), r#"{"a":[1,"x"],"t":{"b":true}}"#);
    }
}
