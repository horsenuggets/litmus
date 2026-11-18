use crate::style::{BOLD, DIM, GREEN, Labelled, labelled, paint};
use serde::Deserialize;

const METER_WIDTH: usize = 24;
const ROW_INDENT: &str = "   ";
const LEVEL_INDENT: &str = "  ";
const COLUMN_GAP: &str = "  ";
const KEY_GAP: &str = "   ";

#[derive(Deserialize, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Piece {
    Heading { text: String },
    Text { text: String },
    Stats { items: Vec<Stat> },
    Legend { items: Vec<Key> },
    Tree { rows: Vec<Row> },
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct Stat {
    label: String,
    text: String,
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct Key {
    label: String,
    tone: Tone,
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct Row {
    cells: Vec<Cell>,
    open: bool,
    rows: Vec<Row>,
}

#[derive(Deserialize, Debug, PartialEq)]
#[serde(untagged)]
pub enum Cell {
    Plain(String),
    Made(Made),
}

#[derive(Deserialize, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Made {
    Cell { text: String, align: Align, tone: Tone },
    Meter { parts: Vec<Part> },
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct Part {
    value: f64,
    tone: Tone,
}

#[derive(Deserialize, Debug, PartialEq, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum Align {
    Left,
    Right,
}

#[derive(Deserialize, Debug, PartialEq, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum Tone {
    Good,
    Plain,
    Dim,
}

impl Tone {
    fn paint(self, text: &str) -> String {
        match self {
            Tone::Good => paint(GREEN, text),
            Tone::Plain => text.to_owned(),
            Tone::Dim => paint(DIM, text),
        }
    }

    fn glyph(self) -> &'static str {
        match self {
            Tone::Good => "━",
            Tone::Plain => "─",
            Tone::Dim => "·",
        }
    }
}

pub fn render(pieces: &[Piece]) -> Vec<String> {
    let mut lines = Vec::new();
    let mut under_heading = false;

    for piece in pieces {
        if !lines.is_empty() && !under_heading {
            lines.push(String::new());
        }

        lines.extend(draw(piece));
        under_heading = matches!(piece, Piece::Heading { .. });
    }

    lines
}

fn draw(piece: &Piece) -> Vec<String> {
    match piece {
        Piece::Heading { text } => vec![format!(" {}", paint(BOLD, text))],
        Piece::Text { text } => text.trim_end().lines().map(str::to_owned).collect(),
        Piece::Stats { items } => stats(items),
        Piece::Legend { items } => vec![legend(items)],
        Piece::Tree { rows } => tree(rows),
    }
}

fn stats(items: &[Stat]) -> Vec<String> {
    let rows: Vec<Labelled> = items
        .iter()
        .map(|item| Labelled { label: &item.label, value: item.text.clone() })
        .collect();

    labelled(&rows)
}

fn legend(items: &[Key]) -> String {
    let keys: Vec<String> = items
        .iter()
        .map(|key| format!("{} {}", key.tone.paint(key.tone.glyph()), key.label))
        .collect();

    format!("{ROW_INDENT}{}", keys.join(KEY_GAP))
}

struct VisibleRow<'a> {
    depth: usize,
    row: &'a Row,
}

fn flatten<'a>(rows: &'a [Row], depth: usize, list: &mut Vec<VisibleRow<'a>>) {
    for row in rows {
        list.push(VisibleRow { depth, row });

        if row.open {
            flatten(&row.rows, depth + 1, list);
        }
    }
}

fn tree(rows: &[Row]) -> Vec<String> {
    let mut list = Vec::new();
    flatten(rows, 0, &mut list);

    let columns = list.iter().map(|visible| visible.row.cells.len()).max().unwrap_or(0);

    let widths: Vec<usize> = (0..columns)
        .map(|column| list.iter().filter_map(|visible| visible.width(column)).max().unwrap_or(0))
        .collect();

    list.iter().map(|visible| visible.line(&widths)).collect()
}

impl VisibleRow<'_> {
    fn indent(&self, column: usize) -> String {
        if column == 0 { LEVEL_INDENT.repeat(self.depth) } else { String::new() }
    }

    fn width(&self, column: usize) -> Option<usize> {
        let cell = self.row.cells.get(column)?;

        Some(self.indent(column).len() + cell.width())
    }

    fn line(&self, widths: &[usize]) -> String {
        let last = self.row.cells.len().saturating_sub(1);

        let cells: Vec<String> = self
            .row
            .cells
            .iter()
            .enumerate()
            .map(|(column, cell)| cell.draw(&self.indent(column), widths[column], column == last))
            .collect();

        if cells.is_empty() {
            return String::new();
        }

        format!("{ROW_INDENT}{}", cells.join(COLUMN_GAP))
    }
}

impl Cell {
    fn width(&self) -> usize {
        match self {
            Cell::Plain(text) | Cell::Made(Made::Cell { text, .. }) => text.chars().count(),
            Cell::Made(Made::Meter { .. }) => METER_WIDTH,
        }
    }

    fn draw(&self, indent: &str, width: usize, last: bool) -> String {
        let room = width.saturating_sub(indent.len() + self.width());
        let after = if last { String::new() } else { " ".repeat(room) };

        match self {
            Cell::Plain(text) => format!("{indent}{text}{after}"),

            Cell::Made(Made::Cell { text, align: Align::Left, tone }) => tone.paint(&format!("{indent}{text}{after}")),
            Cell::Made(Made::Cell { text, align: Align::Right, tone }) => {
                tone.paint(&format!("{indent}{}{text}", " ".repeat(room)))
            }

            Cell::Made(Made::Meter { parts }) => format!("{indent}{}{after}", bar(parts)),
        }
    }
}

fn bar(parts: &[Part]) -> String {
    let total: f64 = parts.iter().map(|part| part.value.max(0.0)).sum();

    let mut cells: Vec<usize> = parts
        .iter()
        .map(|part| {
            let share = if total > 0.0 { part.value.max(0.0) * METER_WIDTH as f64 / total } else { 0.0 };
            let cell = (share + 0.5).floor() as usize;

            if part.value > 0.0 { cell.max(1) } else { cell }
        })
        .collect();

    if total <= 0.0
        && let Some(last) = cells.last_mut()
    {
        *last = METER_WIDTH;
    }

    let used: usize = cells.iter().sum();
    let widest = (0..cells.len()).rev().max_by_key(|index| cells[*index]);

    if let Some(widest) = widest {
        cells[widest] = (cells[widest] + METER_WIDTH).saturating_sub(used);
    }

    parts
        .iter()
        .zip(cells)
        .filter(|(_, cell)| *cell > 0)
        .map(|(part, cell)| part.tone.paint(&part.tone.glyph().repeat(cell)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::without_colour;

    fn plain(pieces: &str) -> Vec<String> {
        let pieces: Vec<Piece> = serde_json::from_str(pieces).unwrap();

        render(&pieces)
            .iter()
            .map(|line| without_colour(line))
            .collect()
    }

    fn meter(parts: &[(u32, &str)]) -> String {
        let parts: Vec<String> = parts
            .iter()
            .map(|(value, tone)| format!(r#"{{ "value": {value}, "tone": "{tone}" }}"#))
            .collect();

        format!(r#"{{ "kind": "meter", "parts": [{}] }}"#, parts.join(","))
    }

    fn right(text: &str, tone: &str) -> String {
        format!(r#"{{ "kind": "cell", "text": "{text}", "align": "right", "tone": "{tone}" }}"#)
    }

    fn row(cells: &[String], open: bool, rows: &[String]) -> String {
        format!(r#"{{ "cells": [{}], "open": {open}, "rows": [{}] }}"#, cells.join(","), rows.join(","))
    }

    fn tree_of(rows: &[String]) -> Vec<String> {
        plain(&format!(r#"[{{ "kind": "tree", "rows": [{}] }}]"#, rows.join(",")))
    }

    fn name(text: &str) -> String {
        format!(r#""{text}""#)
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
    fn gives_each_tone_of_a_legend_the_glyph_a_meter_draws_it_with() {
        let lines = plain(
            r#"[{ "kind": "legend", "items": [
                { "label": "ran", "tone": "good" },
                { "label": "loaded but not run", "tone": "plain" },
                { "label": "never loaded", "tone": "dim" }
            ] }]"#,
        );

        assert_eq!(lines, ["   ━ ran   ─ loaded but not run   · never loaded"]);
    }

    #[test]
    fn draws_a_tree_in_columns_with_the_rows_under_an_open_row_set_in() {
        let game = row(
            &[name("Game"), meter(&[(250, "good"), (750, "plain"), (1000, "dim")]), right("12.5%", "plain"), right("250 of 2,000", "dim")],
            false,
            &[row(&[name("Hidden")], false, &[])],
        );
        let tool = row(&[name("Tool"), meter(&[(9, "good")]), right("100.0%", "plain"), right("9 of 9", "dim")], false, &[]);
        let source = row(
            &[name("Source"), meter(&[(259, "good"), (750, "plain"), (1000, "dim")]), right("12.8%", "plain"), right("259 of 2,009", "dim")],
            true,
            &[game, tool],
        );

        assert_eq!(
            tree_of(&[source]),
            [
                "   Source  ━━━─────────············   12.8%  259 of 2,009",
                "     Game  ━━━─────────············   12.5%  250 of 2,000",
                "     Tool  ━━━━━━━━━━━━━━━━━━━━━━━━  100.0%        9 of 9",
            ]
        );
    }

    #[test]
    fn leaves_no_spaces_trailing_a_row_that_ends_to_the_left_or_early() {
        let lines = tree_of(&[row(&[name("a"), name("wide")], false, &[]), row(&[name("longer")], false, &[])]);

        assert_eq!(lines, ["   a       wide", "   longer"]);
    }

    #[test]
    fn gives_a_share_too_small_for_a_cell_one_anyway_and_keeps_the_width() {
        let lines = tree_of(&[row(&[meter(&[(1, "good"), (1, "plain"), (100_000, "dim")])], false, &[])]);

        assert_eq!(lines, ["   ━─······················"]);
    }

    #[test]
    fn draws_a_meter_of_nothing_in_its_last_tone() {
        let lines = tree_of(&[row(&[meter(&[(0, "good"), (0, "dim")])], false, &[])]);

        assert_eq!(lines, ["   ························"]);
    }

    #[test]
    fn paints_a_cell_and_each_part_of_a_meter_in_its_tone() {
        let pieces: Vec<Piece> = serde_json::from_str(&format!(
            r#"[{{ "kind": "tree", "rows": [{}] }}]"#,
            row(&[meter(&[(1, "good"), (1, "plain"), (1, "dim")]), right("9", "dim")], false, &[])
        ))
        .unwrap();

        let line = &render(&pieces)[0];
        let good = paint(GREEN, &"━".repeat(8));
        let dim = paint(DIM, &"·".repeat(8));

        assert_eq!(*line, format!("   {good}{}{dim}  {}", "─".repeat(8), paint(DIM, "9")));
    }

    #[test]
    fn draws_nothing_for_no_components() {
        assert_eq!(plain("[]"), [] as [&str; 0]);
    }

    #[test]
    fn refuses_a_kind_it_does_not_know() {
        assert!(serde_json::from_str::<Vec<Piece>>(r#"[{ "kind": "chart" }]"#).is_err());
    }
}
