use anstyle::{AnsiColor, Color, RgbColor, Style};

pub const ORANGE_COLOR: Color = Color::Rgb(RgbColor(255, 176, 66));

pub const GREEN: Style = AnsiColor::Green.on_default();
pub const RED: Style = AnsiColor::Red.on_default();
pub const ORANGE: Style = Style::new().fg_color(Some(ORANGE_COLOR));
pub const BOLD: Style = Style::new().bold();
pub const DIM: Style = Style::new().dimmed();

const WIDEST_BADGE_LABEL: usize = "ERROR".len();

pub struct Labelled<'a> {
    pub label: &'a str,
    pub value: String,
}

pub const fn badge(text: AnsiColor, background: Color) -> Style {
    Style::new()
        .fg_color(Some(Color::Ansi(text)))
        .bg_color(Some(background))
        .bold()
}

pub fn paint(style: Style, text: &str) -> String {
    format!("{style}{text}{style:#}")
}

pub fn headline(style: Style, label: &str, name: &str, width: usize, note: &str) -> String {
    let badge = paint(style, &format!(" {label} "));
    let gap = " ".repeat(WIDEST_BADGE_LABEL - label.len());

    if note.is_empty() {
        return format!(" {badge}{gap}  {name}");
    }

    format!(" {badge}{gap}  {name:<width$}  {}", paint(DIM, note))
}

pub fn labelled(rows: &[Labelled]) -> Vec<String> {
    let width = rows.iter().map(|row| row.label.chars().count()).max().unwrap_or(0);
    let margin = " ".repeat(width + 3);

    rows.iter()
        .flat_map(|row| {
            let gap = " ".repeat(width - row.label.chars().count());
            let mut value = row.value.lines();

            let mut lines = vec![format!(" {}{gap}  {}", paint(BOLD, row.label), value.next().unwrap_or_default())];
            lines.extend(value.map(|line| format!("{margin}{line}")));

            lines
        })
        .collect()
}

pub fn counts(parts: &[(usize, &str, Style)]) -> String {
    let shown: Vec<String> = parts
        .iter()
        .filter(|(count, _, _)| *count > 0)
        .map(|(count, label, style)| paint(*style, &format!("{count} {label}")))
        .collect();

    if shown.is_empty() {
        return paint(DIM, "none");
    }

    shown.join(", ")
}
