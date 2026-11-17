pub fn string(text: &str) -> String {
    let mut literal = String::from("\"");

    for byte in text.bytes() {
        let plain = byte == b' ' || (byte.is_ascii_graphic() && byte != b'"' && byte != b'\\');

        if plain {
            literal.push(char::from(byte));
        } else {
            literal.push_str(&format!("\\{byte:03}"));
        }
    }

    literal.push('"');
    literal
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_string_spells_out_whatever_is_not_plain() {
        assert_eq!(string("a b"), "\"a b\"");
        assert_eq!(string("\"\\\n"), "\"\\034\\092\\010\"");
        assert_eq!(string("é"), "\"\\195\\169\"");
    }
}
