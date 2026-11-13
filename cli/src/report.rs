use crate::manifest::Manifest;
use crate::results::{Failure, SpecResult, Tally};
use crate::server::Mismatch;
use anstyle::{AnsiColor, Color, RgbColor, Style};
use std::collections::HashMap;
use std::path::Path;

/// The sixteen named colours have no orange, so this one is given as an exact colour: #FFB042
const ORANGE_COLOR: Color = Color::Rgb(RgbColor(255, 176, 66));

const PASS_BADGE: Style = badge(AnsiColor::Black, Color::Ansi(AnsiColor::Green));
const FAIL_BADGE: Style = badge(AnsiColor::BrightWhite, Color::Ansi(AnsiColor::Red));
const ERROR_BADGE: Style = badge(AnsiColor::Black, ORANGE_COLOR);
const GREEN: Style = AnsiColor::Green.on_default();
const RED: Style = AnsiColor::Red.on_default();
const ORANGE: Style = Style::new().fg_color(Some(ORANGE_COLOR));
const BOLD: Style = Style::new().bold();
const DIM: Style = Style::new().dimmed();

/// The longest label a badge holds, so that spec names start in one column whatever the badge says
const LABEL_WIDTH: usize = "ERROR".len();

const DETAIL_INDENT: &str = "     ";

/// The lib tags its own errors with this, which says nothing once the CLI is the one printing them
const LIB_TAG: &str = "[Litmus]: ";

/// How many of a stale place's files get named before the rest are only counted
const MAX_LISTED: usize = 10;

/// Files by the dotted name the lib reports them under
type Files<'a> = HashMap<String, &'a Path>;

pub fn render(results: &[SpecResult], manifest: &Manifest) -> String {
    let files: Files = manifest
        .scripts
        .iter()
        .map(|script| (script.path.join("."), script.file.as_path()))
        .collect();

    let width = results
        .iter()
        .map(|spec| name_of(&spec.path, &files).chars().count())
        .max()
        .unwrap_or(0);

    let mut lines: Vec<String> = vec![String::new()];
    for spec in results {
        lines.extend(spec_lines(spec, &files, width));
    }

    if lines.last().is_some_and(|line| !line.is_empty()) {
        lines.push(String::new());
    }

    lines.extend(summary(&Tally::of(results)));
    lines.push(String::new());

    lines.join("\n")
}

/// A passing spec takes one line; any other is followed by what went wrong and a blank line
fn spec_lines(spec: &SpecResult, files: &Files, width: usize) -> Vec<String> {
    let name = name_of(&spec.path, files);

    if let Some(failure) = &spec.failure {
        return vec![
            headline(ERROR_BADGE, "ERROR", &name, width, ""),
            describe(failure, files),
            String::new(),
        ];
    }

    let total = spec.tests.len();
    let failed = spec.failed_tests().count();
    if failed == 0 {
        return vec![headline(PASS_BADGE, "PASS", &name, width, &plural(total, "test"))];
    }

    let note = format!("{} of {total} passed", total - failed);
    let mut lines = vec![headline(FAIL_BADGE, "FAIL", &name, width, &note)];

    for (test, failure) in spec.failed_tests() {
        let title: Vec<&str> = test.groups.iter().chain([&test.name]).map(String::as_str).collect();

        lines.push(format!("   {} {}", paint(RED, "✗"), title.join(" > ")));
        lines.push(describe(failure, files));
    }

    lines.push(String::new());
    lines
}

fn headline(style: Style, label: &str, name: &str, width: usize, note: &str) -> String {
    let badge = paint(style, &format!(" {label} "));
    let gap = " ".repeat(LABEL_WIDTH - label.len());

    if note.is_empty() {
        return format!(" {badge}{gap}  {name}");
    }

    format!(" {badge}{gap}  {name:<width$}  {}", paint(DIM, note))
}

fn summary(tally: &Tally) -> [String; 2] {
    let specs = counts(&[
        (tally.failed_specs, "failed", RED),
        (tally.errored_specs, "errored", ORANGE),
        (tally.passed_specs, "passed", GREEN),
    ]);
    let tests = counts(&[
        (tally.failed_tests, "failed", RED),
        (tally.passed_tests, "passed", GREEN),
    ]);

    [
        format!(" {}  {specs}", paint(BOLD, "Specs")),
        format!(" {}  {tests}", paint(BOLD, "Tests")),
    ]
}

/// Why no place took the run: either none holds the project, or the ones that do are behind the disk
pub fn unclaimed(mismatches: &[Mismatch]) -> String {
    if mismatches.is_empty() {
        return "no open place holds this project; open it in Studio and switch the Litmus plugin on".to_owned();
    }

    let mut lines = vec!["no open place matches the code on disk; is rojo serving?".to_owned()];

    for mismatch in mismatches {
        lines.push(format!(
            "  {}: {} differ, {} missing",
            mismatch.place,
            mismatch.differing.len(),
            mismatch.missing.len()
        ));

        let paths = mismatch.differing.iter().chain(&mismatch.missing);
        for path in paths.clone().take(MAX_LISTED) {
            lines.push(format!("    {}", path.join(".")));
        }

        let unlisted = paths.count().saturating_sub(MAX_LISTED);
        if unlisted > 0 {
            lines.push(format!("    and {unlisted} more"));
        }
    }

    lines.join("\n")
}

/// The file a name from the lib stands for, or the name itself when it isn't one of the project's
fn name_of(name: &str, files: &Files) -> String {
    files
        .get(name)
        .map_or_else(|| name.to_owned(), |file| file.display().to_string())
}

/// `path:line: message`, the form a terminal turns into a link
fn describe(failure: &Failure, files: &Files) -> String {
    let location = format!("{}:{}:", name_of(&failure.source, files), failure.line);
    let mut message = tidy(failure).lines();

    let mut lines = vec![format!(
        "{DETAIL_INDENT}{} {}",
        paint(DIM, &location),
        message.next().unwrap_or_default()
    )];
    lines.extend(message.map(|line| format!("{DETAIL_INDENT}{line}")));

    lines.join("\n")
}

/// Luau starts a thrown message with where it was thrown, which the location beside it already says
fn tidy(failure: &Failure) -> &str {
    let position = format!("{}:{}: ", failure.source, failure.line);
    let message = failure.message.strip_prefix(&position).unwrap_or(&failure.message);

    message.strip_prefix(LIB_TAG).unwrap_or(message)
}

/// Leaves out whatever there is none of, but always says something
fn counts(parts: &[(usize, &str, Style)]) -> String {
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

fn plural(count: usize, noun: &str) -> String {
    format!("{count} {noun}{}", if count == 1 { "" } else { "s" })
}

const fn badge(text: AnsiColor, background: Color) -> Style {
    Style::new()
        .fg_color(Some(Color::Ansi(text)))
        .bg_color(Some(background))
        .bold()
}

fn paint(style: Style, text: &str) -> String {
    format!("{style}{text}{style:#}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::Script;

    fn manifest() -> Manifest {
        let script = |name: &str, file: &str| Script {
            path: vec!["ReplicatedStorage".to_owned(), name.to_owned()],
            hash: String::new(),
            file: file.into(),
        };

        Manifest {
            project: "demo".to_owned(),
            scripts: vec![
                script("Good.spec", "tests/Good.spec.luau"),
                script("Bad.spec", "tests/Bad.spec.luau"),
                script("Broken.spec", "tests/Broken.spec.luau"),
                script("Helper", "src/Helper.luau"),
            ],
        }
    }

    fn plain(results: &str) -> String {
        let results: Vec<SpecResult> = serde_json::from_str(results).unwrap();
        anstream::adapter::strip_str(&render(&results, &manifest())).to_string()
    }

    #[test]
    fn shows_each_kind_of_spec() {
        let text = plain(
            r#"[
                { "path": "ReplicatedStorage.Bad.spec", "tests": [
                    { "name": "adds", "groups": [] },
                    { "name": "subtracts", "groups": ["math", "minus"], "failure": {
                        "message": "expected 2, got 1", "source": "ReplicatedStorage.Bad.spec", "line": 9, "trace": "t"
                    } }
                ] },
                { "path": "ReplicatedStorage.Broken.spec", "tests": [], "failure": {
                    "message": "[Litmus]: ReplicatedStorage.Helper returned 2 values; a module must return exactly one",
                    "source": "ReplicatedStorage.Broken.spec", "line": 1, "trace": "t"
                } },
                { "path": "ReplicatedStorage.Good.spec", "tests": [{ "name": "works", "groups": [] }] }
            ]"#,
        );

        let expected = "
  FAIL    tests/Bad.spec.luau     1 of 2 passed
   ✗ math > minus > subtracts
     tests/Bad.spec.luau:9: expected 2, got 1

  ERROR   tests/Broken.spec.luau
     tests/Broken.spec.luau:1: ReplicatedStorage.Helper returned 2 values; a module must return exactly one

  PASS    tests/Good.spec.luau    1 test

 Specs  1 failed, 1 errored, 1 passed
 Tests  1 failed, 2 passed
";

        assert_eq!(text, expected);
    }

    #[test]
    fn leaves_out_counts_of_nothing() {
        let text = plain(
            r#"[{ "path": "ReplicatedStorage.Good.spec", "tests": [{ "name": "works", "groups": [] }] }]"#,
        );

        assert!(text.contains(" Specs  1 passed\n Tests  1 passed\n"), "{text}");
    }

    #[test]
    fn drops_the_position_luau_puts_in_front_of_a_message() {
        let text = plain(
            r#"[{ "path": "ReplicatedStorage.Bad.spec", "tests": [{ "name": "throws", "groups": [], "failure": {
                "message": "ReplicatedStorage.Helper:4: boom\nsecond line", "source": "ReplicatedStorage.Helper", "line": 4, "trace": "t"
            } }] }]"#,
        );

        assert!(text.contains("     src/Helper.luau:4: boom\n     second line\n"), "{text}");
    }

    #[test]
    fn names_the_files_a_stale_place_is_behind_on() {
        let mismatches: Vec<Mismatch> = serde_json::from_str(
            r#"[{ "place": "Stale", "missing": [["ReplicatedStorage", "Gone"]], "differing": [["ReplicatedStorage", "Thing.spec"]] }]"#,
        )
        .unwrap();

        let text = unclaimed(&mismatches);

        assert!(text.contains("  Stale: 1 differ, 1 missing\n"), "{text}");
        assert!(text.contains("    ReplicatedStorage.Thing.spec\n    ReplicatedStorage.Gone"), "{text}");
        assert!(unclaimed(&[]).contains("no open place holds this project"));
    }
}
