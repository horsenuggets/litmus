use crate::manifest::Manifest;
use anstyle::{AnsiColor, Color, Style};
use serde::Deserialize;
use std::collections::HashMap;
use std::path::Path;

const PASS_BADGE: Style = badge(AnsiColor::Black, AnsiColor::Green);
const FAIL_BADGE: Style = badge(AnsiColor::BrightWhite, AnsiColor::Red);
const GREEN: Style = AnsiColor::Green.on_default();
const RED: Style = AnsiColor::Red.on_default();
const BOLD: Style = Style::new().bold();
const DIM: Style = Style::new().dimmed();

/// The lib tags its own errors with this, which says nothing once the CLI is the one printing them
const LIB_TAG: &str = "[Litmus]: ";

#[derive(Deserialize)]
pub struct Failure {
    message: String,
    source: String,
    line: u32,
}

#[derive(Deserialize)]
pub struct TestResult {
    name: String,
    groups: Vec<String>,
    failure: Option<Failure>,
}

#[derive(Deserialize)]
pub struct SpecResult {
    path: String,
    tests: Vec<TestResult>,

    /// Set when the spec itself didn't load, in which case none of its tests ran
    failure: Option<Failure>,
}

pub struct Report {
    pub text: String,
    pub passed: bool,
}

/// Files by the dotted name the lib reports them under
type Files<'a> = HashMap<String, &'a Path>;

#[derive(Default)]
struct Tally {
    passed_specs: usize,
    failed_specs: usize,
    errored_specs: usize,
    passed_tests: usize,
    failed_tests: usize,
}

pub fn render(results: &[SpecResult], manifest: &Manifest) -> Report {
    let files: Files = manifest
        .files
        .iter()
        .map(|file| (file.path.join("."), file.file.as_path()))
        .collect();

    let width = results
        .iter()
        .map(|spec| name_of(&spec.path, &files).chars().count())
        .max()
        .unwrap_or(0);

    let mut lines: Vec<String> = vec![String::new()];
    let mut tally = Tally::default();

    for spec in results {
        let name = name_of(&spec.path, &files);

        if let Some(failure) = &spec.failure {
            tally.errored_specs += 1;

            lines.push(format!(" {}  {name}", paint(FAIL_BADGE, " ERROR ")));
            lines.push(describe(failure, &files, "     "));
            lines.push(String::new());
            continue;
        }

        let total = spec.tests.len();
        let failed = spec.tests.iter().filter(|test| test.failure.is_some()).count();
        tally.passed_tests += total - failed;
        tally.failed_tests += failed;

        if failed == 0 {
            tally.passed_specs += 1;

            let count = paint(DIM, &plural(total, "test"));
            lines.push(format!(" {}   {name:<width$}  {count}", paint(PASS_BADGE, " PASS ")));
            continue;
        }

        tally.failed_specs += 1;

        let count = paint(DIM, &format!("{} of {total} passed", total - failed));
        lines.push(format!(" {}   {name:<width$}  {count}", paint(FAIL_BADGE, " FAIL ")));

        for test in &spec.tests {
            if let Some(failure) = &test.failure {
                let title = test
                    .groups
                    .iter()
                    .chain([&test.name])
                    .map(String::as_str)
                    .collect::<Vec<_>>()
                    .join(" > ");

                lines.push(format!("   {} {title}", paint(RED, "✗")));
                lines.push(describe(failure, &files, "     "));
            }
        }

        lines.push(String::new());
    }

    if lines.last().is_some_and(|line| !line.is_empty()) {
        lines.push(String::new());
    }

    lines.push(format!(
        " {}  {}",
        paint(BOLD, "Specs"),
        counts(&[
            (tally.failed_specs, "failed", RED),
            (tally.errored_specs, "errored", RED),
            (tally.passed_specs, "passed", GREEN),
        ])
    ));
    lines.push(format!(
        " {}  {}",
        paint(BOLD, "Tests"),
        counts(&[
            (tally.failed_tests, "failed", RED),
            (tally.passed_tests, "passed", GREEN),
        ])
    ));
    lines.push(String::new());

    Report {
        text: lines.join("\n"),
        passed: tally.failed_specs == 0 && tally.errored_specs == 0,
    }
}

/// The file a name from the lib stands for, or the name itself when it isn't one of the project's
fn name_of(name: &str, files: &Files) -> String {
    files
        .get(name)
        .map_or_else(|| name.to_owned(), |file| file.display().to_string())
}

/// `path:line: message`, the form a terminal turns into a link
fn describe(failure: &Failure, files: &Files, indent: &str) -> String {
    let location = format!("{}:{}:", name_of(&failure.source, files), failure.line);
    let mut message = tidy(failure).lines();

    let mut lines = vec![format!(
        "{indent}{} {}",
        paint(DIM, &location),
        message.next().unwrap_or_default()
    )];
    lines.extend(message.map(|line| format!("{indent}{line}")));

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

const fn badge(text: AnsiColor, background: AnsiColor) -> Style {
    Style::new()
        .fg_color(Some(Color::Ansi(text)))
        .bg_color(Some(Color::Ansi(background)))
        .bold()
}

fn paint(style: Style, text: &str) -> String {
    format!("{style}{text}{style:#}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::File;

    fn manifest() -> Manifest {
        let file = |name: &str, file: &str| File {
            path: vec!["ReplicatedStorage".to_owned(), name.to_owned()],
            hash: String::new(),
            file: file.into(),
        };

        Manifest {
            project: "demo".to_owned(),
            files: vec![
                file("Good.spec", "tests/Good.spec.luau"),
                file("Bad.spec", "tests/Bad.spec.luau"),
                file("Broken.spec", "tests/Broken.spec.luau"),
                file("Helper", "src/Helper.luau"),
            ],
        }
    }

    fn plain(results: &str) -> Report {
        let results: Vec<SpecResult> = serde_json::from_str(results).unwrap();
        let report = render(&results, &manifest());

        Report {
            text: anstream::adapter::strip_str(&report.text).to_string(),
            passed: report.passed,
        }
    }

    #[test]
    fn shows_each_kind_of_spec() {
        let report = plain(
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

        assert_eq!(report.text, expected);
        assert!(!report.passed);
    }

    #[test]
    fn passes_when_nothing_failed() {
        let report = plain(
            r#"[{ "path": "ReplicatedStorage.Good.spec", "tests": [{ "name": "works", "groups": [] }] }]"#,
        );

        assert!(report.passed);
        assert!(report.text.contains(" Specs  1 passed\n Tests  1 passed\n"), "{}", report.text);
    }

    #[test]
    fn drops_the_position_luau_puts_in_front_of_a_message() {
        let report = plain(
            r#"[{ "path": "ReplicatedStorage.Bad.spec", "tests": [{ "name": "throws", "groups": [], "failure": {
                "message": "ReplicatedStorage.Helper:4: boom\nsecond line", "source": "ReplicatedStorage.Helper", "line": 4, "trace": "t"
            } }] }]"#,
        );

        assert!(
            report.text.contains("     src/Helper.luau:4: boom\n     second line\n"),
            "{}",
            report.text
        );
    }
}
