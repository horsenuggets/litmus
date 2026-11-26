use super::{FOLDER, MARKER, PROGRESS_MARKER, SCRIPT};
use crate::progress::{Display, Event};
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

const TICK: Duration = Duration::from_millis(100);

#[derive(Debug, PartialEq)]
enum Message {
    Printed(String),
    Event(Event),
    Results(String),
}

pub(super) fn deadline(started: Instant, timeout: u64) -> Result<Option<Instant>, String> {
    if timeout == 0 {
        return Ok(None);
    }

    started
        .checked_add(Duration::from_secs(timeout))
        .map(Some)
        .ok_or_else(|| format!("The standalone timeout of {timeout} seconds is too large for this platform."))
}

fn poll_interval(deadline: Option<Instant>, now: Instant) -> Duration {
    match deadline {
        Some(deadline) => deadline.saturating_duration_since(now).min(TICK),
        None => TICK,
    }
}

pub fn run(project_dir: &Path, run: &[String], specs: &[String], timeout: u64) -> Result<String, String> {
    let script = format!("{FOLDER}/{SCRIPT}");
    let shown = format!("{} {script}", run.join(" "));
    let deadline = deadline(Instant::now(), timeout)?;

    let mut child = Command::new(&run[0])
        .args(&run[1..])
        .arg(&script)
        .current_dir(project_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|error| {
            format!("couldn't start `{shown}`, which begins with what litmus.toml gives as `run` under [standalone]: {error}")
        })?;

    let Some(output) = child.stdout.take() else {
        return Err(format!("couldn't read what `{shown}` prints"));
    };

    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || relay(BufReader::new(output), |message| sender.send(message).is_ok()));

    let mut display = Display::new(specs.to_vec());
    let mut output_closed = false;

    let reported = loop {
        let wait = poll_interval(deadline, Instant::now());
        if wait.is_zero() {
            display.finish();

            let _ = child.kill();
            let _ = child.wait();

            let unit = if timeout == 1 { "second" } else { "seconds" };
            return Err(format!("`{shown}` was stopped, still running after {timeout} {unit}"));
        }

        let message = if output_closed {
            thread::sleep(wait);
            None
        } else {
            Some(receiver.recv_timeout(wait))
        };
        if poll_interval(deadline, Instant::now()).is_zero() {
            continue;
        }
        match message {
            Some(Ok(Message::Printed(line))) => display.print(&line),
            Some(Ok(Message::Event(event))) => display.take(event),
            Some(Ok(Message::Results(results))) => break Some(results),
            Some(Err(RecvTimeoutError::Disconnected)) => output_closed = true,
            Some(Err(RecvTimeoutError::Timeout)) | None => {}
        }
        if output_closed && child.try_wait().map_err(|error| format!("couldn't tell how `{shown}` ended: {error}"))?.is_some() {
            break None;
        }

        display.refresh();
    };

    display.finish();

    let Some(reported) = reported else {
        let status = child.wait().map_err(|error| format!("couldn't tell how `{shown}` ended: {error}"))?;

        return Err(format!("`{shown}` ended without reporting any results ({status})"));
    };

    let _ = child.kill();
    let _ = child.wait();

    Ok(reported)
}

fn relay(mut output: impl BufRead, mut pass: impl FnMut(Message) -> bool) {
    let mut line = Vec::new();

    while output.read_until(b'\n', &mut line).is_ok_and(|read| read > 0) {
        let text = String::from_utf8_lossy(&line);
        let message = read(text.trim_end_matches(['\n', '\r']));
        let last = matches!(message, Some(Message::Results(_)));

        if message.is_some_and(|message| !pass(message)) || last {
            return;
        }

        line.clear();
    }
}

fn read(text: &str) -> Option<Message> {
    if let Some(results) = text.strip_prefix(MARKER) {
        return Some(Message::Results(results.to_owned()));
    }

    match text.strip_prefix(PROGRESS_MARKER) {
        Some(event) => serde_json::from_str(event).ok().map(Message::Event),
        None => Some(Message::Printed(text.to_owned())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn relayed(output: &str) -> Vec<Message> {
        let mut passed = Vec::new();

        relay(Cursor::new(output), |message| {
            passed.push(message);
            true
        });

        passed
    }

    fn printed(line: &str) -> Message {
        Message::Printed(line.to_owned())
    }

    #[test]
    fn passes_lines_on_until_the_results_and_reads_no_further() {
        let passed = relayed("first\r\nsecond\n@@litmus-run@@{\"specs\":[]}\nlast");

        assert_eq!(passed, [printed("first"), printed("second"), Message::Results("{\"specs\":[]}".to_owned())]);
    }

    #[test]
    fn tells_a_line_of_progress_from_one_a_spec_printed() {
        let passed = relayed("@@litmus-progress@@{\"kind\":\"settled\"}\nprinted\n");

        assert_eq!(passed, [Message::Event(Event::Settled), printed("printed")]);
    }

    #[test]
    fn drops_a_line_of_progress_it_cannot_read() {
        assert_eq!(relayed("@@litmus-progress@@{\"kind\":\"unheard-of\"}\nprinted\n"), [printed("printed")]);
    }

    #[test]
    fn a_run_that_printed_no_marked_line_reported_nothing() {
        assert_eq!(relayed("only a print\n"), [printed("only a print")]);
        assert_eq!(relayed(""), []);
    }

    #[test]
    fn stops_reading_once_nobody_takes_what_it_passes_on() {
        let mut passed = 0;

        relay(Cursor::new("first\nsecond\n"), |_| {
            passed += 1;
            false
        });

        assert_eq!(passed, 1);
    }

    #[test]
    fn a_disabled_deadline_has_no_expiry() {
        let started = Instant::now();

        assert_eq!(deadline(started, 0), Ok(None));
    }

    #[test]
    fn a_configured_deadline_uses_exact_seconds() {
        let started = Instant::now();

        for timeout in [1, 300, 900] {
            let expires = deadline(started, timeout).unwrap().unwrap();

            assert_eq!(expires.duration_since(started), Duration::from_secs(timeout));
            assert!(started < expires);
            assert!(started + Duration::from_secs(timeout) >= expires);
        }
    }

    #[test]
    fn polling_never_waits_past_expiry_or_accepts_the_exact_boundary() {
        let now = Instant::now();

        assert_eq!(poll_interval(None, now), TICK);
        assert_eq!(poll_interval(Some(now + Duration::from_secs(1)), now), TICK);
        assert_eq!(poll_interval(Some(now + Duration::from_millis(25)), now), Duration::from_millis(25));
        assert_eq!(poll_interval(Some(now), now), Duration::ZERO);
        assert_eq!(poll_interval(Some(now), now + Duration::from_millis(1)), Duration::ZERO);
    }

    #[test]
    fn a_deadline_that_does_not_fit_is_an_error_instead_of_a_panic() {
        let started = Instant::now();
        let timeout = u64::MAX;

        assert!(started.checked_add(Duration::from_secs(timeout)).is_none());
        let problem = deadline(started, timeout).unwrap_err();
        assert!(problem.contains("timeout") && problem.contains(&timeout.to_string()), "{problem}");
    }

    #[cfg(unix)]
    #[test]
    fn a_silent_command_stops_at_the_configured_deadline() {
        let dir = crate::testing::TempProject::new("silent-deadline");
        let command = ["sh".to_owned(), "-c".to_owned(), "exec sleep 60".to_owned()];
        let problem = run(&dir, &command, &[], 1).unwrap_err();

        assert!(problem.contains("after 1 second"), "{problem}");
        assert!(!problem.contains("after 1 seconds"), "{problem}");
    }

    #[cfg(unix)]
    #[test]
    fn progress_does_not_replace_the_configured_deadline() {
        let dir = crate::testing::TempProject::new("progress-deadline");
        let command = [
            "sh".to_owned(),
            "-c".to_owned(),
            "for tick in 1 2 3 4 5 6 7 8; do printf '%s\\n' '@@litmus-progress@@{\"kind\":\"settled\"}'; sleep 0.25; done; printf '%s\\n' '@@litmus-run@@{\"specs\":[]}'".to_owned(),
        ];
        let started = Instant::now();
        let problem = run(&dir, &command, &[], 1).unwrap_err();

        assert!(problem.contains("after 1 second"), "{problem}");
        assert!(started.elapsed() < Duration::from_secs(3), "{:?}", started.elapsed());
    }

    #[cfg(unix)]
    #[test]
    fn a_result_after_expiry_is_not_accepted_during_a_receive_tick() {
        let dir = crate::testing::TempProject::new("late-result-deadline");
        let command = [
            "sh".to_owned(),
            "-c".to_owned(),
            "sleep 0.95; printf '%s\\n' '@@litmus-progress@@{\"kind\":\"settled\"}'; sleep 0.1; printf '%s\\n' '@@litmus-run@@{\"specs\":[]}'".to_owned(),
        ];
        let problem = run(&dir, &command, &[], 1).unwrap_err();

        assert!(problem.contains("after 1 second"), "{problem}");
    }

    #[cfg(unix)]
    #[test]
    fn closing_stdout_does_not_escape_the_deadline() {
        let dir = crate::testing::TempProject::new("closed-output-deadline");
        let command = ["sh".to_owned(), "-c".to_owned(), "exec 1>&-; exec sleep 60".to_owned()];
        let problem = run(&dir, &command, &[], 1).unwrap_err();

        assert!(problem.contains("after 1 second"), "{problem}");
    }

    #[cfg(unix)]
    #[test]
    fn a_disabled_timeout_accepts_a_result_after_a_short_deadline_would_expire() {
        let dir = crate::testing::TempProject::new("disabled-deadline");
        let command = ["sh".to_owned(), "-c".to_owned(), "sleep 2; printf '%s\\n' '@@litmus-run@@{\"specs\":[]}'".to_owned()];

        assert_eq!(run(&dir, &command, &[], 0), Ok("{\"specs\":[]}".to_owned()));
    }

    #[test]
    fn a_command_that_cannot_start_is_named() {
        let command = ["litmus-no-such-command".to_owned(), "run".to_owned()];
        let problem = run(Path::new("."), &command, &[], 300).unwrap_err();

        assert!(problem.contains("`litmus-no-such-command run .litmus/run.luau`"), "{problem}");
    }
}
