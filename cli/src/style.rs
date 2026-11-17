use anstyle::{AnsiColor, Color, RgbColor, Style};

/// The sixteen named colours have no orange, so this one is given as an exact colour: #FFB042
pub const ORANGE_COLOR: Color = Color::Rgb(RgbColor(255, 176, 66));

pub const GREEN: Style = AnsiColor::Green.on_default();
pub const RED: Style = AnsiColor::Red.on_default();
pub const ORANGE: Style = Style::new().fg_color(Some(ORANGE_COLOR));
pub const BOLD: Style = Style::new().bold();
pub const DIM: Style = Style::new().dimmed();

pub const fn badge(text: AnsiColor, background: Color) -> Style {
    Style::new()
        .fg_color(Some(Color::Ansi(text)))
        .bg_color(Some(background))
        .bold()
}

pub fn paint(style: Style, text: &str) -> String {
    format!("{style}{text}{style:#}")
}
