use crate::manifest::Manifest;
use crate::results::{Failure, Run, SpecResult, Tally};
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

/// The narrowest column worth wrapping a message into; with less room, the terminal is left to wrap it
const MIN_MESSAGE_WIDTH: usize = 30;

/// The lib tags its own errors with this, which says nothing once the CLI is the one printing them
const LIB_TAG: &str = "[Litmus]: ";

/// How many of a stale place's files get named before the rest are only counted
const MAX_LISTED: usize = 10;

/// Files by the path the lib reports them under
type Files<'a> = HashMap<&'a [String], &'a Path>;

/// `columns` is how wide the terminal is, or nothing when the text isn't going to one
pub fn render(run: &Run, manifest: &Manifest, columns: Option<usize>) -> String {
    let results = &run.specs;

    let files: Files = manifest
        .scripts
        .iter()
        .map(|script| (script.path.as_slice(), script.file.as_path()))
        .collect();

    let name_width = results
        .iter()
        .map(|spec| name_of(&spec.path, &files).chars().count())
        .max()
        .unwrap_or(0);

    let mut lines: Vec<String> = vec![String::new()];
    let mut after_details = false;

    for (index, spec) in results.iter().enumerate() {
        let block = spec_lines(spec, &files, name_width, columns);
        let has_details = block.len() > 1;

        // Passing specs sit together as a list, while a spec with details stands apart on both sides
        if index > 0 && (has_details || after_details) {
            lines.push(String::new());
        }

        lines.extend(block);
        after_details = has_details;
    }

    if !results.is_empty() {
        lines.push(String::new());
    }

    if let Some(appendix) = &run.appendix {
        lines.extend(appendix.trim_end().lines().map(str::to_owned));
        lines.push(String::new());
    }

    lines.extend(summary(&Tally::of(results)));
    lines.push(String::new());

    lines.join("\n")
}

/// A passing spec takes one line; any other is followed by what went wrong
fn spec_lines(spec: &SpecResult, files: &Files, name_width: usize, columns: Option<usize>) -> Vec<String> {
    let name = name_of(&spec.path, files);

    if let Some(failure) = &spec.failure {
        let mut lines = vec![headline(ERROR_BADGE, "ERROR", &name, name_width, "")];
        lines.extend(describe(failure, files, columns));

        return lines;
    }

    let total = spec.tests.len();
    let failed = spec.failed_tests().count();
    if failed == 0 {
        return vec![headline(PASS_BADGE, "PASS", &name, name_width, &plural(total, "test"))];
    }

    let note = format!("{} of {total} passed", total - failed);
    let mut lines = vec![headline(FAIL_BADGE, "FAIL", &name, name_width, &note)];

    for (test, failure) in spec.failed_tests() {
        let title: Vec<&str> = test.groups.iter().chain([&test.name]).map(String::as_str).collect();

        lines.push(format!("   {} {}", paint(RED, "✗"), title.join(" > ")));
        lines.extend(describe(failure, files, columns));
    }

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

/// The file a path from the lib stands for, or the path as Studio writes it when it isn't one of the project's
fn name_of(path: &[String], files: &Files) -> String {
    files
        .get(path)
        .map_or_else(|| path.join("."), |file| file.display().to_string())
}

/// `path:line: message`, the form a terminal turns into a link, with the message's further lines kept under its first
fn describe(failure: &Failure, files: &Files, columns: Option<usize>) -> Vec<String> {
    let location = format!("{}:{}:", name_of(&failure.source, files), failure.line);
    let margin = " ".repeat(DETAIL_INDENT.len() + location.chars().count() + 1);

    let room = columns
        .map(|columns| columns.saturating_sub(margin.len()))
        .filter(|room| *room >= MIN_MESSAGE_WIDTH);

    let mut message = wrap(tidy(failure), room).into_iter();
    let first = message.next().unwrap_or_default();

    let mut lines = vec![format!("{DETAIL_INDENT}{} {first}", paint(DIM, &location))];
    lines.extend(message.map(|line| format!("{margin}{line}")));

    lines
}

/// Breaks each line longer than `width` between words; a word longer than that is left to overflow
fn wrap(text: &str, width: Option<usize>) -> Vec<String> {
    let Some(width) = width else {
        return text.lines().map(str::to_owned).collect();
    };

    let mut lines = Vec::new();

    for line in text.lines() {
        let mut current = String::new();
        let mut length = 0;

        // Splitting on single spaces keeps runs of them, so indentation inside a message survives
        for (index, word) in line.split(' ').enumerate() {
            let word_length = word.chars().count();

            if index == 0 {
                current.push_str(word);
                length = word_length;
            } else if length + 1 + word_length <= width {
                current.push(' ');
                current.push_str(word);
                length += 1 + word_length;
            } else {
                lines.push(std::mem::replace(&mut current, word.to_owned()));
                length = word_length;
            }
        }

        lines.push(current);
    }

    lines
}

/// Luau starts a thrown message with where it was thrown, which the location beside it already says
fn tidy(failure: &Failure) -> &str {
    // The position names the script the way Studio does, with dots between the names
    let position = format!("{}:{}: ", failure.source.join("."), failure.line);
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
        plain_at(results, None)
    }

    fn plain_at(results: &str, columns: Option<usize>) -> String {
        plain_run(&run(results, None), columns)
    }

    fn run(results: &str, appendix: Option<&str>) -> Run {
        Run {
            specs: serde_json::from_str(results).unwrap(),
            appendix: appendix.map(str::to_owned),
        }
    }

    fn plain_run(run: &Run, columns: Option<usize>) -> String {
        anstream::adapter::strip_str(&render(run, &manifest(), columns)).to_string()
    }

    #[test]
    fn shows_each_kind_of_spec() {
        let text = plain(
            r#"[
                { "path": ["ReplicatedStorage", "Bad.spec"], "tests": [
                    { "name": "adds", "groups": [] },
                    { "name": "subtracts", "groups": ["math", "minus"], "failure": {
                        "message": "expected 2, got 1", "source": ["ReplicatedStorage", "Bad.spec"], "line": 9, "trace": "t"
                    } }
                ] },
                { "path": ["ReplicatedStorage", "Broken.spec"], "tests": [], "failure": {
                    "message": "[Litmus]: ReplicatedStorage.Helper returned 2 values; a module must return exactly one",
                    "source": ["ReplicatedStorage", "Broken.spec"], "line": 1, "trace": "t"
                } },
                { "path": ["ReplicatedStorage", "Good.spec"], "tests": [{ "name": "works", "groups": [] }] }
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
            r#"[{ "path": ["ReplicatedStorage", "Good.spec"], "tests": [{ "name": "works", "groups": [] }] }]"#,
        );

        assert!(text.contains(" Specs  1 passed\n Tests  1 passed\n"), "{text}");
    }

    #[test]
    fn drops_the_position_luau_puts_in_front_of_a_message() {
        let text = plain(
            r#"[{ "path": ["ReplicatedStorage", "Bad.spec"], "tests": [{ "name": "throws", "groups": [], "failure": {
                "message": "ReplicatedStorage.Helper:4: boom\nsecond line", "source": ["ReplicatedStorage", "Helper"], "line": 4, "trace": "t"
            } }] }]"#,
        );

        let expected = "
     src/Helper.luau:4: boom
                        second line
";

        assert!(text.contains(expected), "{text}");
    }

    #[test]
    fn tells_a_name_with_a_dot_from_two_names() {
        let script = |path: &[&str], file: &str| Script {
            path: path.iter().map(|name| (*name).to_owned()).collect(),
            hash: String::new(),
            file: file.into(),
        };

        let manifest = Manifest {
            project: "demo".to_owned(),
            scripts: vec![
                script(&["Shared", "Util.spec"], "src/Util.spec.luau"),
                script(&["Shared", "Util", "spec"], "src/Util/spec.luau"),
            ],
        };

        let run = run(r#"[{ "path": ["Shared", "Util", "spec"], "tests": [] }]"#, None);
        let text = anstream::adapter::strip_str(&render(&run, &manifest, None)).to_string();

        assert!(text.contains("src/Util/spec.luau"), "{text}");
    }

    #[test]
    fn keeps_passing_specs_together_and_others_apart() {
        let text = plain(
            r#"[
                { "path": ["ReplicatedStorage", "Good.spec"], "tests": [] },
                { "path": ["ReplicatedStorage", "Good.spec"], "tests": [] },
                { "path": ["ReplicatedStorage", "Broken.spec"], "tests": [], "failure": {
                    "message": "boom", "source": ["ReplicatedStorage", "Broken.spec"], "line": 1, "trace": "t"
                } },
                { "path": ["ReplicatedStorage", "Good.spec"], "tests": [] }
            ]"#,
        );

        let expected = "
  PASS    tests/Good.spec.luau    0 tests
  PASS    tests/Good.spec.luau    0 tests

  ERROR   tests/Broken.spec.luau
     tests/Broken.spec.luau:1: boom

  PASS    tests/Good.spec.luau    0 tests

 Specs  1 errored, 3 passed
 Tests  none
";

        assert_eq!(text, expected);
    }

    #[test]
    fn shows_what_the_adapter_added_between_the_specs_and_the_counts() {
        let results = r#"[{ "path": ["ReplicatedStorage", "Good.spec"], "tests": [{ "name": "works", "groups": [] }] }]"#;
        let text = plain_run(&run(results, Some("Coverage
  src/Helper.luau  87%
")), None);

        let expected = "
  PASS    tests/Good.spec.luau  1 test

Coverage
  src/Helper.luau  87%

 Specs  1 passed
 Tests  1 passed
";

        assert_eq!(text, expected);
    }

    #[test]
    fn shows_what_the_adapter_added_when_no_spec_ran() {
        let text = plain_run(&run("[]", Some("nothing to cover")), None);

        assert_eq!(text, "
nothing to cover

 Specs  none
 Tests  none
");
    }

    #[test]
    fn wraps_a_long_message_between_words_in_its_own_column() {
        let results = r#"[{ "path": ["ReplicatedStorage", "Bad.spec"], "tests": [{ "name": "wraps", "groups": [], "failure": {
            "message": "one two three four five six seven eight nine ten\n  indented stays", "source": ["ReplicatedStorage", "Helper"], "line": 4, "trace": "t"
        } }] }]"#;

        let expected = "
     src/Helper.luau:4: one two three four five six
                        seven eight nine ten
                          indented stays
";

        let text = plain_at(results, Some(24 + 30));

        assert!(text.contains(expected), "{text}");
    }

    #[test]
    fn leaves_wrapping_to_a_terminal_too_narrow_for_a_column() {
        let results = r#"[{ "path": ["ReplicatedStorage", "Bad.spec"], "tests": [{ "name": "wraps", "groups": [], "failure": {
            "message": "one two three four five six seven eight nine ten", "source": ["ReplicatedStorage", "Helper"], "line": 4, "trace": "t"
        } }] }]"#;

        let text = plain_at(results, Some(24 + 29));

        assert!(text.contains("src/Helper.luau:4: one two three four five six seven eight nine ten\n"), "{text}");
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
