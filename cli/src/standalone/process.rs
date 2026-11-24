use super::{FOLDER, MARKER, PROGRESS_MARKER, SCRIPT};
use crate::progress::{Display, Event};
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

const BUDGET: Duration = Duration::from_secs(300);
const TICK: Duration = Duration::from_millis(100);

#[derive(Debug, PartialEq)]
enum Message {
    Printed(String),
    Event(Event),
    Results(String),
}

pub fn run(project_dir: &Path, run: &[String], specs: &[String]) -> Result<String, String> {
    let script = format!("{FOLDER}/{SCRIPT}");
    let shown = format!("{} {script}", run.join(" "));

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

    let deadline = Instant::now() + BUDGET;
    let mut display = Display::new(specs.to_vec());

    let reported = loop {
        match receiver.recv_timeout(TICK) {
            Ok(Message::Printed(line)) => display.print(&line),
            Ok(Message::Event(event)) => display.take(event),
            Ok(Message::Results(results)) => break Some(results),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break None,
        }

        if Instant::now() >= deadline {
            display.finish();

            let _ = child.kill();
            let _ = child.wait();

            return Err(format!("`{shown}` was stopped, still running after {} minutes", BUDGET.as_secs() / 60));
        }

        display.refresh();
    };

    display.finish();

    let Some(reported) = reported else {
        let status = child
            .wait()
            .map_err(|error| format!("couldn't tell how `{shown}` ended: {error}"))?;

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

        assert_eq!(
            passed,
            [printed("first"), printed("second"), Message::Results("{\"specs\":[]}".to_owned())]
        );
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
    fn a_command_that_cannot_start_is_named() {
        let command = ["litmus-no-such-command".to_owned(), "run".to_owned()];
        let problem = run(Path::new("."), &command, &[]).unwrap_err();

        assert!(problem.contains("`litmus-no-such-command run .litmus/run.luau`"), "{problem}");
    }
}
