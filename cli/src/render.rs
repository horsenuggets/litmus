use crate::manifest::Manifest;
use crate::piece;
use crate::results::{Failure, Run, SpecResult, Tally};
use crate::style::{BOLD, DIM, GREEN, ORANGE, ORANGE_COLOR, RED, badge, paint};
use anstyle::{AnsiColor, Color, Style};
use std::collections::HashMap;
use std::path::PathBuf;

const PASS_BADGE: Style = badge(AnsiColor::Black, Color::Ansi(AnsiColor::Green));
const FAIL_BADGE: Style = badge(AnsiColor::BrightWhite, Color::Ansi(AnsiColor::Red));
const ERROR_BADGE: Style = badge(AnsiColor::Black, ORANGE_COLOR);

const LABEL_WIDTH: usize = "ERROR".len();

const DETAIL_INDENT: &str = "     ";

const REASON_INDENT: &str = "                ";

const MIN_MESSAGE_WIDTH: usize = 30;

const LIB_TAG: &str = "[Litmus]: ";

pub enum Sources {
    Place(HashMap<Vec<String>, PathBuf>),
    Disk,
}

impl Sources {
    pub fn of(manifest: &Manifest) -> Sources {
        Sources::Place(
            manifest
                .scripts
                .iter()
                .map(|script| (script.path.clone(), script.file.clone()))
                .collect(),
        )
    }

    fn file(&self, path: &[String]) -> String {
        match self {
            Sources::Place(files) => files
                .get(path)
                .map_or_else(|| path.join("."), |file| file.display().to_string()),
            Sources::Disk => path.join("/"),
        }
    }

    fn chunk(&self, path: &[String]) -> String {
        match self {
            Sources::Place(_) => path.join("."),
            Sources::Disk => path.join("/"),
        }
    }
}

pub fn run(run: &Run, sources: &Sources, columns: Option<usize>) -> String {
    let results = &run.specs;

    let name_width = results
        .iter()
        .map(|spec| sources.file(&spec.path).chars().count())
        .max()
        .unwrap_or(0);

    let mut lines: Vec<String> = vec![String::new()];
    let mut after_details = false;

    for (index, spec) in results.iter().enumerate() {
        let block = spec_lines(spec, sources, name_width, columns);
        let has_details = block.len() > 1;

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
        lines.extend(piece::render(appendix));
        lines.push(String::new());
    }

    lines.extend(summary(&Tally::of(results)));
    lines.extend(run.failure.as_deref().map(run_failure).unwrap_or_default());
    lines.push(String::new());

    lines.join("\n")
}

fn spec_lines(spec: &SpecResult, sources: &Sources, name_width: usize, columns: Option<usize>) -> Vec<String> {
    let name = sources.file(&spec.path);

    if let Some(failure) = &spec.failure {
        let mut lines = vec![headline(ERROR_BADGE, "ERROR", &name, name_width, "")];
        lines.extend(describe(failure, sources, columns));

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
        lines.extend(describe(failure, sources, columns));
    }

    lines
}

pub fn headline(style: Style, label: &str, name: &str, width: usize, note: &str) -> String {
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

fn run_failure(reason: &str) -> Vec<String> {
    let mut reason = reason.trim_end().lines();
    let first = reason.next().unwrap_or_default();

    let mut lines = vec![format!(" {}    {}: {first}", paint(BOLD, "Run"), paint(RED, "failed"))];
    lines.extend(reason.map(|line| format!("{REASON_INDENT}{line}")));

    lines
}

fn describe(failure: &Failure, sources: &Sources, columns: Option<usize>) -> Vec<String> {
    let location = format!("{}:{}:", sources.file(&failure.source), failure.line);
    let margin = " ".repeat(DETAIL_INDENT.len() + location.chars().count() + 1);

    let room = columns
        .map(|columns| columns.saturating_sub(margin.len()))
        .filter(|room| *room >= MIN_MESSAGE_WIDTH);

    let mut message = wrap(tidy(failure, sources), room).into_iter();
    let first = message.next().unwrap_or_default();

    let mut lines = vec![format!("{DETAIL_INDENT}{} {first}", paint(DIM, &location))];
    lines.extend(message.map(|line| format!("{margin}{line}")));

    lines
}

fn wrap(text: &str, width: Option<usize>) -> Vec<String> {
    let Some(width) = width else {
        return text.lines().map(str::to_owned).collect();
    };

    let mut lines = Vec::new();

    for line in text.lines() {
        let mut current = String::new();
        let mut length = 0;

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

fn tidy<'a>(failure: &'a Failure, sources: &Sources) -> &'a str {
    let position = format!("{}:{}: ", sources.chunk(&failure.source), failure.line);
    let message = failure.message.strip_prefix(&position).unwrap_or(&failure.message);

    message.strip_prefix(LIB_TAG).unwrap_or(message)
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

fn plural(count: usize, noun: &str) -> String {
    format!("{count} {noun}{}", if count == 1 { "" } else { "s" })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::Script;
    use crate::piece::Piece;

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
            appendix: appendix.map(|text| vec![Piece::Text { text: text.to_owned() }]),
            failure: None,
        }
    }

    fn plain_run(run: &Run, columns: Option<usize>) -> String {
        anstream::adapter::strip_str(&super::run(run, &Sources::of(&manifest()), columns)).to_string()
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
        let text = anstream::adapter::strip_str(&super::run(&run, &Sources::of(&manifest), None)).to_string();

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
        let text = plain_run(&run(results, Some("Coverage\n  src/Helper.luau  87%\n")), None);

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
    fn says_why_the_adapter_failed_the_run_under_the_counts() {
        let results = r#"[{ "path": ["ReplicatedStorage", "Good.spec"], "tests": [{ "name": "works", "groups": [] }] }]"#;
        let mut run = run(results, Some("Coverage 4%"));
        run.failure = Some("coverage is under the floor
of 5%
".to_owned());

        let expected = "
  PASS    tests/Good.spec.luau  1 test

Coverage 4%

 Specs  1 passed
 Tests  1 passed
 Run    failed: coverage is under the floor
                of 5%
";

        assert_eq!(plain_run(&run, None), expected);
    }

    #[test]
    fn draws_the_pieces_an_adapter_added_above_the_counts() {
        let mut run = run("[]", None);
        run.appendix = serde_json::from_str(r#"[{ "kind": "heading", "text": "Lines run" }]"#).unwrap();

        assert_eq!(plain_run(&run, None), "\n Lines run\n\n Specs  none\n Tests  none\n");
    }

    #[test]
    fn shows_what_the_adapter_added_when_no_spec_ran() {
        let text = plain_run(&run("[]", Some("nothing to cover")), None);

        assert_eq!(text, "\nnothing to cover\n\n Specs  none\n Tests  none\n");
    }

    #[test]
    fn shows_a_run_on_disk_by_the_files_its_adapter_named() {
        let run = run(
            r#"[{ "path": ["tests", "Bad.spec.luau"], "tests": [{ "name": "throws", "groups": [], "failure": {
                "message": "src/Helper.luau:4: boom", "source": ["src", "Helper.luau"], "line": 4, "trace": "t"
            } }] }]"#,
            None,
        );
        let text = anstream::adapter::strip_str(&super::run(&run, &Sources::Disk, None)).to_string();

        let expected = "
  FAIL    tests/Bad.spec.luau  0 of 1 passed
   ✗ throws
     src/Helper.luau:4: boom
";

        assert!(text.starts_with(expected), "{text}");
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
}
