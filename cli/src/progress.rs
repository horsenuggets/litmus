use crate::style::{GREEN, Labelled, RED, badge, counts, headline, labelled};
use anstyle::{AnsiColor, Color, Style};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::io::{self, IsTerminal, Write};
use std::time::{Duration, Instant};

const LOAD_BADGE: Style = badge(AnsiColor::Black, Color::Ansi(AnsiColor::White));
const RUN_BADGE: Style = badge(AnsiColor::Black, Color::Ansi(AnsiColor::Cyan));

const MAX_SPECS_LISTED: usize = 5;
const REDRAW_INTERVAL: Duration = Duration::from_millis(100);

const WRAP_OFF: &str = "\x1b[?7l";
const WRAP_ON: &str = "\x1b[?7h";
const CLEAR_BELOW: &str = "\x1b[J";

#[derive(Deserialize, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Event {
    Loading { spec: usize },
    Loaded { spec: usize, tests: usize },
    Tested { spec: usize, failed: bool },
    Finished { spec: usize },
    Settled,
}

struct Running {
    tests: usize,
    finished: usize,
}

pub struct Progress {
    specs: Vec<String>,
    loading: Option<usize>,
    running: BTreeMap<usize, Running>,
    done: usize,
    passed: usize,
    failed: usize,
    settled: bool,
}

impl Progress {
    pub fn new(specs: Vec<String>) -> Progress {
        Progress {
            specs,
            loading: None,
            running: BTreeMap::new(),
            done: 0,
            passed: 0,
            failed: 0,
            settled: false,
        }
    }

    pub fn take(&mut self, event: Event) {
        match event {
            Event::Loading { spec } => self.loading = Some(spec),

            Event::Loaded { spec, tests } => {
                self.loading = None;
                self.running.insert(spec, Running { tests, finished: 0 });
            }

            Event::Tested { spec, failed } => {
                if let Some(running) = self.running.get_mut(&spec) {
                    running.finished += 1;
                }

                if failed {
                    self.failed += 1;
                } else {
                    self.passed += 1;
                }
            }

            Event::Finished { spec } => {
                self.running.remove(&spec);
                self.done += 1;
            }

            Event::Settled => self.settled = true,
        }
    }

    pub fn lines(&self, elapsed: Duration) -> Vec<String> {
        let time = clock(elapsed);

        if self.settled {
            return vec![format!(" Adapter is preparing its results  {time}")];
        }

        let mut rows: Vec<(Style, &str, String, String)> = Vec::new();

        for (spec, running) in self.running.iter().take(MAX_SPECS_LISTED) {
            let note = format!("{} of {} tests", running.finished, running.tests);
            rows.push((RUN_BADGE, "RUN", self.name(*spec), note));
        }

        if let Some(spec) = self.loading {
            rows.push((LOAD_BADGE, "LOAD", self.name(spec), String::new()));
        }

        let width = rows.iter().map(|(_, _, name, _)| name.chars().count()).max().unwrap_or(0);

        let mut lines: Vec<String> = rows
            .iter()
            .map(|(style, label, name, note)| headline(*style, label, name, width, note))
            .collect();

        let unlisted = self.running.len().saturating_sub(MAX_SPECS_LISTED);
        if unlisted > 0 {
            lines.push(format!("          and {unlisted} more running"));
        }

        if !lines.is_empty() {
            lines.push(String::new());
        }

        lines.extend(labelled(&[
            Labelled { label: "Specs", value: format!("{} of {} done", self.done, self.specs.len()) },
            Labelled { label: "Tests", value: counts(&[(self.failed, "failed", RED), (self.passed, "passed", GREEN)]) },
            Labelled { label: "Time", value: time },
        ]));

        lines
    }

    fn name(&self, spec: usize) -> String {
        match spec.checked_sub(1).and_then(|index| self.specs.get(index)) {
            Some(name) => name.clone(),
            None => format!("spec {spec}"),
        }
    }
}

fn clock(elapsed: Duration) -> String {
    let seconds = elapsed.as_secs();

    if seconds < 60 {
        return format!("{seconds}s");
    }

    format!("{}m {:02}s", seconds / 60, seconds % 60)
}

pub struct Display {
    progress: Progress,
    live: bool,
    started: Instant,
    drawn: Instant,
    shown: Vec<String>,
}

impl Display {
    pub fn new(specs: Vec<String>) -> Display {
        Display {
            progress: Progress::new(specs),
            live: io::stdout().is_terminal(),
            started: Instant::now(),
            drawn: Instant::now(),
            shown: Vec::new(),
        }
    }

    pub fn take(&mut self, event: Event) {
        self.progress.take(event);
    }

    pub fn print(&mut self, line: &str) {
        self.erase();
        println!("{line}");
        self.draw();
    }

    pub fn refresh(&mut self) {
        if self.drawn.elapsed() >= REDRAW_INTERVAL {
            self.draw();
        }
    }

    pub fn finish(&mut self) {
        self.erase();
    }

    fn draw(&mut self) {
        if !self.live {
            return;
        }

        self.drawn = Instant::now();

        let lines = self.progress.lines(self.started.elapsed());
        if lines == self.shown {
            return;
        }

        self.erase();

        let mut block = String::from(WRAP_OFF);
        for line in &lines {
            block.push_str(line);
            block.push('\n');
        }
        block.push_str(WRAP_ON);

        write(&block);
        self.shown = lines;
    }

    fn erase(&mut self) {
        if self.shown.is_empty() {
            return;
        }

        write(&format!("\x1b[{}A\r{CLEAR_BELOW}", self.shown.len()));
        self.shown.clear();
    }
}

fn write(text: &str) {
    let mut out = anstream::stdout().lock();
    let _ = out.write_all(text.as_bytes());
    let _ = out.flush();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn progress() -> Progress {
        Progress::new(vec!["tests/a.spec.luau".to_owned(), "tests/longer.spec.luau".to_owned()])
    }

    fn plain(progress: &Progress, seconds: u64) -> Vec<String> {
        progress
            .lines(Duration::from_secs(seconds))
            .iter()
            .map(|line| anstream::adapter::strip_str(line).to_string())
            .collect()
    }

    #[test]
    fn reads_each_event_the_lib_reports() {
        let read = |text: &str| serde_json::from_str::<Event>(text).unwrap();

        assert_eq!(read(r#"{"spec":2,"kind":"loading"}"#), Event::Loading { spec: 2 });
        assert_eq!(read(r#"{"kind":"loaded","spec":2,"tests":7}"#), Event::Loaded { spec: 2, tests: 7 });
        assert_eq!(read(r#"{"kind":"tested","spec":2,"failed":true}"#), Event::Tested { spec: 2, failed: true });
        assert_eq!(read(r#"{"kind":"finished","spec":2}"#), Event::Finished { spec: 2 });
        assert_eq!(read(r#"{"kind":"settled"}"#), Event::Settled);
        assert!(serde_json::from_str::<Event>(r#"{"kind":"unheard-of"}"#).is_err());
    }

    #[test]
    fn starts_with_nothing_running_and_nothing_done() {
        assert_eq!(plain(&progress(), 0), [" Specs  0 of 2 done", " Tests  none", " Time   0s"]);
    }

    #[test]
    fn shows_the_spec_that_is_loading() {
        let mut progress = progress();
        progress.take(Event::Loading { spec: 1 });

        assert_eq!(
            plain(&progress, 3),
            ["  LOAD    tests/a.spec.luau", "", " Specs  0 of 2 done", " Tests  none", " Time   3s"]
        );
    }

    #[test]
    fn shows_how_far_each_running_spec_is_above_the_one_loading() {
        let mut progress = progress();
        progress.take(Event::Loading { spec: 1 });
        progress.take(Event::Loaded { spec: 1, tests: 3 });
        progress.take(Event::Tested { spec: 1, failed: false });
        progress.take(Event::Tested { spec: 1, failed: true });
        progress.take(Event::Loading { spec: 2 });

        assert_eq!(
            plain(&progress, 75),
            [
                "  RUN     tests/a.spec.luau       2 of 3 tests",
                "  LOAD    tests/longer.spec.luau",
                "",
                " Specs  0 of 2 done",
                " Tests  1 failed, 1 passed",
                " Time   1m 15s",
            ]
        );
    }

    #[test]
    fn drops_a_spec_from_the_list_once_it_finishes() {
        let mut progress = progress();
        progress.take(Event::Loading { spec: 1 });
        progress.take(Event::Loaded { spec: 1, tests: 1 });
        progress.take(Event::Tested { spec: 1, failed: false });
        progress.take(Event::Finished { spec: 1 });

        assert_eq!(plain(&progress, 1), [" Specs  1 of 2 done", " Tests  1 passed", " Time   1s"]);
    }

    #[test]
    fn counts_the_running_specs_it_has_no_room_to_list() {
        let mut progress = Progress::new((1..=7).map(|number| format!("{number}.spec.luau")).collect());
        for spec in 1..=7 {
            progress.take(Event::Loaded { spec, tests: 1 });
        }

        let lines = plain(&progress, 0);

        assert_eq!(lines.iter().filter(|line| line.starts_with("  RUN ")).count(), 5);
        assert_eq!(lines[5], "          and 2 more running");
    }

    #[test]
    fn becomes_one_line_once_every_test_is_done() {
        let mut progress = progress();
        progress.take(Event::Loading { spec: 1 });
        progress.take(Event::Settled);

        assert_eq!(plain(&progress, 58), [" Adapter is preparing its results  58s"]);
    }

    #[test]
    fn names_a_spec_it_was_never_told_of_by_its_number() {
        let mut progress = progress();
        progress.take(Event::Loading { spec: 9 });

        assert_eq!(plain(&progress, 0)[0], "  LOAD    spec 9");
    }
}
