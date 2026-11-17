use crate::report::{BOLD, paint};
use serde::Deserialize;

#[derive(Deserialize, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Component {
    Heading { text: String },
    Text { text: String },
    Stats { items: Vec<Stat> },
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct Stat {
    label: String,
    text: String,
}

pub fn render(components: &[Component]) -> Vec<String> {
    let mut lines = Vec::new();
    let mut under_heading = false;

    for component in components {
        if !lines.is_empty() && !under_heading {
            lines.push(String::new());
        }

        lines.extend(draw(component));
        under_heading = matches!(component, Component::Heading { .. });
    }

    lines
}

fn draw(component: &Component) -> Vec<String> {
    match component {
        Component::Heading { text } => vec![format!(" {}", paint(BOLD, text))],
        Component::Text { text } => text.trim_end().lines().map(str::to_owned).collect(),
        Component::Stats { items } => stats(items),
    }
}

fn stats(items: &[Stat]) -> Vec<String> {
    let width = items.iter().map(|item| item.label.chars().count()).max().unwrap_or(0);

    items
        .iter()
        .map(|item| {
            let gap = " ".repeat(width - item.label.chars().count());

            format!(" {}{gap}  {}", paint(BOLD, &item.label), item.text)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plain(components: &str) -> Vec<String> {
        let components: Vec<Component> = serde_json::from_str(components).unwrap();

        render(&components)
            .iter()
            .map(|line| anstream::adapter::strip_str(line).to_string())
            .collect()
    }

    #[test]
    fn puts_a_heading_straight_over_what_it_heads_and_a_gap_between_the_rest() {
        let lines = plain(
            r#"[
                { "kind": "heading", "text": "Lines run" },
                { "kind": "text", "text": "one\ntwo\n" },
                { "kind": "text", "text": "three" }
            ]"#,
        );

        assert_eq!(lines, [" Lines run", "one", "two", "", "three"]);
    }

    #[test]
    fn lines_the_texts_of_stats_up_past_the_longest_label() {
        let lines = plain(
            r#"[{ "kind": "stats", "items": [
                { "label": "Coverage", "text": "5.8% of 100 lines ran" },
                { "label": "Loaded", "text": "2 of 3 modules" }
            ] }]"#,
        );

        assert_eq!(lines, [" Coverage  5.8% of 100 lines ran", " Loaded    2 of 3 modules"]);
    }

    #[test]
    fn draws_nothing_for_no_components() {
        assert_eq!(plain("[]"), [] as [&str; 0]);
    }

    #[test]
    fn refuses_a_kind_it_does_not_know() {
        assert!(serde_json::from_str::<Vec<Component>>(r#"[{ "kind": "chart" }]"#).is_err());
    }
}
