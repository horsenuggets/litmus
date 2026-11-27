use super::{FOLDER, MARKER, PROGRESS_MARKER, SCRIPT};
use crate::interrupt::Interrupt;
use crate::progress::{Display, Event};
#[cfg(windows)]
use process_wrap::std::JobObject;
#[cfg(unix)]
use process_wrap::std::ProcessGroup;
use process_wrap::std::{CommandWrap, KillOnDrop};
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{ExitStatus, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

#[cfg(all(test, windows))]
mod windows_tests;

#[cfg(target_os = "macos")]
#[link(name = "proc")]
unsafe extern "C" {
    fn proc_listpgrppids(group: libc::pid_t, buffer: *mut std::ffi::c_void, size: libc::c_int) -> libc::c_int;
}

const CLEANUP_BUDGET: Duration = Duration::from_secs(1);
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

fn collection_deadline(execution: Option<Instant>, now: Instant) -> Instant {
    let limit = now + Duration::from_secs(1);
    execution.map_or(limit, |execution| execution.min(limit))
}

struct OwnedChild {
    child: Option<Box<dyn process_wrap::std::ChildWrapper>>,
    stopped: Option<Result<ExitStatus, String>>,
}

impl OwnedChild {
    fn stop(&mut self, shown: &str) -> Result<ExitStatus, String> {
        if let Some(stopped) = &self.stopped {
            return stopped.clone();
        }
        let stopped = stop_owned(self.child.take().expect("The run still owns its child."), shown);
        self.stopped = Some(stopped.clone());
        stopped
    }
}

impl Drop for OwnedChild {
    fn drop(&mut self) {
        if let Some(child) = self.child.take() {
            let _ = stop_owned(child, "the standalone runtime");
        }
    }
}

struct Watchdog {
    finished: mpsc::Sender<()>,
    worker: Option<thread::JoinHandle<()>>,
}

impl Drop for Watchdog {
    fn drop(&mut self) {
        let _ = self.finished.send(());
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

pub fn run(project_dir: &Path, run: &[String], specs: &[String], timeout: u64, interrupt: &Interrupt) -> Result<String, String> {
    let script = format!("{FOLDER}/{SCRIPT}");
    let shown = format!("{} {script}", run.join(" "));
    let deadline = deadline(Instant::now(), timeout)?;
    let budget = Duration::from_secs(timeout);

    let mut command = CommandWrap::with_new(&run[0], |command| {
        command.args(&run[1..]).arg(&script).current_dir(project_dir).stdin(Stdio::null()).stdout(Stdio::piped());
    });
    #[cfg(unix)]
    command.wrap(ProcessGroup::leader());
    #[cfg(windows)]
    command.wrap(JobObject);
    command.wrap(KillOnDrop);

    let _active = interrupt.arm();
    let mut child = command.spawn().map_err(|error| {
        format!("couldn't start `{shown}`, which begins with what litmus.toml gives as `run` under [standalone]: {error}")
    })?;
    let output = child.stdout().take().expect("The runtime stdout was piped.");
    let child = Arc::new(Mutex::new(OwnedChild { child: Some(child), stopped: None }));
    let owned = Arc::downgrade(&child);
    let interrupted_command = shown.clone();
    interrupt.on_signal(move |signal| {
        if let Some(owned) = owned.upgrade() {
            let mut owned = owned.lock().unwrap();
            let _ = owned.stop(&interrupted_command);
            // Hold ownership until termination so the output thread cannot race cleanup.
            crate::interrupt::terminate(signal);
        }
        crate::interrupt::terminate(signal);
    });

    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || relay(BufReader::new(output), |message| sender.send(message).is_ok()));

    let _watchdog = deadline.map(|deadline| {
        let (finished, completion) = mpsc::channel();
        let timed_child = Arc::downgrade(&child);
        let timed_command = shown.clone();
        let worker = thread::spawn(move || {
            if matches!(completion.recv_timeout(deadline.saturating_duration_since(Instant::now())), Err(RecvTimeoutError::Timeout))
                && let Some(child) = timed_child.upgrade()
            {
                // Cleanup cannot depend on the output consumer continuing to read stdout.
                let _ = child.lock().unwrap().stop(&timed_command);
            }
        });
        Watchdog { finished, worker: Some(worker) }
    });
    let mut display = Display::new(specs.to_vec());
    let mut output_closed = false;

    let mut reported = loop {
        if interrupt.cancelled() {
            break Ok(None);
        }
        let wait = poll_interval(deadline, Instant::now());
        if wait.is_zero() {
            break Err(format!("`{shown}` was stopped, still running after {}", in_words(budget)));
        }
        let message = if output_closed {
            thread::sleep(wait);
            None
        } else {
            Some(receiver.recv_timeout(wait))
        };
        if interrupt.cancelled() {
            break Ok(None);
        }
        if poll_interval(deadline, Instant::now()).is_zero() {
            break Err(format!("`{shown}` was stopped, still running after {}", in_words(budget)));
        }
        match message {
            Some(Ok(Message::Printed(line))) => display.print(&line),
            Some(Ok(Message::Event(event))) => display.take(event),
            Some(Ok(Message::Results(results))) => break Ok(Some(results)),
            Some(Err(RecvTimeoutError::Disconnected)) => output_closed = true,
            Some(Err(RecvTimeoutError::Timeout)) | None => {}
        }

        if poll_interval(deadline, Instant::now()).is_zero() {
            break Err(format!("`{shown}` was stopped, still running after {}", in_words(budget)));
        }

        // Poll the launcher, not the group or job. Descendants can keep stdout open.
        let launcher_status = {
            let mut owned = child.lock().unwrap();
            match owned.child.as_mut() {
                Some(child) => {
                    // SAFETY: Polling preserves the native child and ownership handles.
                    let launcher = unsafe { child.try_inner_child_mut() }.expect("The command has a native child.");
                    launcher_exited(launcher)
                }
                None => Ok(true),
            }
        };
        match launcher_status {
            Ok(true) => break Ok(None),
            Ok(false) => {}
            Err(error) => break Err(format!("couldn't tell how `{shown}` ended: {error}")),
        }

        display.refresh();
    };

    display.finish();

    let stopped = {
        let mut owned = child.lock().unwrap();
        owned.stop(&shown)
    };
    if reported.is_ok() {
        let drain_deadline = collection_deadline(deadline, Instant::now());
        // Collect before replaying logs so output backpressure cannot hide queued results.
        let mut pending = Vec::new();
        while !interrupt.cancelled() {
            let wait = poll_interval(Some(drain_deadline), Instant::now());
            if wait.is_zero() {
                break;
            }
            let message = receiver.recv_timeout(wait);
            if poll_interval(Some(drain_deadline), Instant::now()).is_zero() {
                break;
            }
            match message {
                Ok(message) => {
                    let last = matches!(message, Message::Results(_));
                    pending.push(message);
                    if last {
                        break;
                    }
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }
        }
        let mut final_report = None;
        for message in pending {
            match message {
                Message::Printed(line) => display.print(&line),
                Message::Event(event) => display.take(event),
                Message::Results(results) => final_report = Some(results),
            }
        }
        display.finish();
        reported = reported.map(|report| report.or(final_report));
    }
    if interrupt.cancelled() {
        reported = Err("the standalone run was interrupted".to_owned());
    }
    let (outcome, warning) = outcome(&shown, reported, stopped);
    if let Some(warning) = warning {
        eprintln!("litmus: {warning}");
    }

    outcome
}

fn launcher_exited(child: &mut std::process::Child) -> std::io::Result<bool> {
    #[cfg(unix)]
    {
        // Keep an exited group leader unreaped so its numeric PGID cannot be reused.
        let mut info = unsafe { std::mem::zeroed::<libc::siginfo_t>() };
        let result = unsafe { libc::waitid(libc::P_PID, child.id(), &mut info, libc::WEXITED | libc::WNOHANG | libc::WNOWAIT) };
        if result == -1 {
            Err(std::io::Error::last_os_error())
        } else {
            Ok(unsafe { info.si_pid() } != 0)
        }
    }
    #[cfg(windows)]
    child.try_wait().map(|status| status.is_some())
}

#[cfg(target_os = "macos")]
fn only_zombie_launcher(launcher: &mut std::process::Child) -> bool {
    if !matches!(launcher_exited(launcher), Ok(true)) {
        return false;
    }
    // Two slots distinguish the reserved leader from any other group member. Unknown
    // or truncated observations must not suppress a genuine permission failure.
    let mut members: [libc::pid_t; 2] = [0; 2];
    // SAFETY: The buffer is writable and sized in bytes; the leader remains unreaped.
    let count = unsafe {
        proc_listpgrppids(launcher.id() as libc::pid_t, members.as_mut_ptr().cast(), std::mem::size_of_val(&members) as libc::c_int)
    };
    count == 1 && members[0] == launcher.id() as libc::pid_t
}

fn stop_owned(mut child: Box<dyn process_wrap::std::ChildWrapper>, shown: &str) -> Result<ExitStatus, String> {
    let stopped = stop(&mut child, shown);
    // The bounded cleanup already attempted both owners. Never enter the wrapper's
    // unbounded kill-and-wait again, or signal a PGID after reaping its launcher.
    drop(child.into_inner());
    stopped
}

// Stops the owned process group or job, then reaps the launcher.
fn stop(child: &mut Box<dyn process_wrap::std::ChildWrapper>, shown: &str) -> Result<ExitStatus, String> {
    #[cfg(unix)]
    let stop_deadline = Instant::now() + CLEANUP_BUDGET;
    #[cfg(unix)]
    let stopped = loop {
        match child.start_kill() {
            #[cfg(target_os = "macos")]
            Err(error) if error.raw_os_error() == Some(libc::EPERM) && {
                // macOS rejects signals to a zombie-only group. Its reserved leader
                // and an authoritative membership query distinguish that from denial.
                let launcher = unsafe { child.try_inner_child_mut() }.expect("The command has a native child.");
                only_zombie_launcher(launcher)
            } => break Ok(()),
            Err(error) if error.raw_os_error() == Some(libc::EPERM) && Instant::now() < stop_deadline => {
                // Keep the leader reserved through retries, even if macOS rejects the
                // signal while it exits. Persistent permission errors remain visible.
                thread::sleep(TICK);
            }
            result => break result,
        }
    };
    #[cfg(windows)]
    let stopped = child.start_kill();
    let tree_problem = match stopped {
        Ok(()) => None,
        #[cfg(unix)]
        Err(error) if error.raw_os_error() == Some(libc::ESRCH) => None,
        Err(error) => Some(format!("couldn't stop the process tree for `{shown}`, so it may still be running: {error}")),
    };

    // A launcher can leave its original group. Its native child remains ours, so
    // terminate it independently before any wait can release its numeric identity.
    let native_error = {
        // SAFETY: The wrapper keeps this native child and all ownership handles alive.
        let launcher = unsafe { child.try_inner_child_mut() }.expect("The command has a native child.");
        launcher.kill().err()
    };
    let status = wait_for_exit(
        || {
            #[cfg(unix)]
            {
                // Group polling can miss a launcher that moved groups. No more group
                // signals follow this native reap, so PID reuse is harmless here.
                let launcher = unsafe { child.try_inner_child_mut() }.expect("The command has a native child.");
                launcher.try_wait()
            }
            #[cfg(windows)]
            child.try_wait()
        },
        Instant::now() + CLEANUP_BUDGET,
    )
    .map_err(|error| match native_error {
        Some(kill) => format!("couldn't stop or reap the launcher for `{shown}`, so it may still be running ({kill}; {error})"),
        None => format!("couldn't reap the launcher for `{shown}` before cleanup ended, so it may still be running: {error}"),
    });
    match (tree_problem, status) {
        (Some(problem), Err(wait)) => Err(format!("{problem}, and {wait}")),
        (Some(problem), Ok(_)) => Err(problem),
        (None, status) => status,
    }
}

fn wait_for_exit(
    mut poll: impl FnMut() -> std::io::Result<Option<ExitStatus>>,
    deadline: Instant,
) -> std::io::Result<ExitStatus> {
    loop {
        if let Some(status) = poll()? {
            return Ok(status);
        }
        let wait = deadline.saturating_duration_since(Instant::now()).min(TICK);
        if wait.is_zero() {
            return Err(std::io::Error::new(std::io::ErrorKind::TimedOut, "Cleanup could not confirm process termination."));
        }
        thread::sleep(wait);
    }
}

// What the run comes to. Results the runtime reported still count when stopping it then
// failed, with a warning, since the tests themselves finished.
fn outcome(
    shown: &str,
    reported: Result<Option<String>, String>,
    stopped: Result<ExitStatus, String>,
) -> (Result<String, String>, Option<String>) {
    match (reported, stopped) {
        (Ok(Some(results)), Ok(_)) => (Ok(results), None),
        (Ok(Some(results)), Err(problem)) => (Ok(results), Some(problem)),
        (Ok(None), Ok(status)) => (Err(format!("`{shown}` ended without reporting any results ({status})")), None),
        (Ok(None), Err(problem)) => (Err(format!("`{shown}` ended without reporting any results, and {problem}")), None),
        (Err(timeout), Ok(_)) => (Err(timeout), None),
        (Err(timeout), Err(problem)) => (Err(format!("{timeout}, and {problem}")), None),
    }
}

fn in_words(duration: Duration) -> String {
    let seconds = duration.as_secs();
    let (count, unit) = if seconds >= 60 && seconds.is_multiple_of(60) { (seconds / 60, "minute") } else { (seconds, "second") };

    format!("{count} {unit}{}", if count == 1 { "" } else { "s" })
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
    use crate::testing::TempProject;
    use std::fs;
    use std::io::{Cursor, Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::process::Command;

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

    fn fixture_command(name: &str) -> Command {
        let mut command = Command::new(std::env::current_exe().unwrap());
        command.args(["--exact", name, "--ignored", "--nocapture"]);
        #[cfg(unix)]
        unsafe {
            use std::os::unix::process::CommandExt;
            // Signal and broken-pipe regressions must not leave core files behind.
            command.pre_exec(|| {
                let limit = libc::rlimit { rlim_cur: 0, rlim_max: 0 };
                if libc::setrlimit(libc::RLIMIT_CORE, &limit) == 0 { Ok(()) } else { Err(std::io::Error::last_os_error()) }
            });
        }
        command
    }

    #[test]
    #[ignore = "invoked as a subprocess by process cleanup tests"]
    #[allow(clippy::zombie_processes, reason = "This launcher must exit before its descendant to exercise cleanup.")]
    fn wrapper_fixture() {
        #[cfg(windows)]
        super::windows_tests::ignore_ctrl_c(true);
        let mode = fs::read_to_string("mode").unwrap();
        if mode == "natural-backlog-results" {
            descendant_fixture();
            return;
        }
        #[cfg(unix)]
        if matches!(mode.as_str(), "moved-launcher" | "moved-launcher-broken-pipe") {
            let group = fs::read_to_string("parent-group").unwrap().parse::<libc::pid_t>().unwrap();
            assert_eq!(unsafe { libc::setpgid(0, group) }, 0);
            descendant_fixture();
            return;
        }
        let mut child = fixture_command("standalone::process::tests::descendant_fixture").spawn().unwrap();
        if matches!(mode.as_str(), "backlog-results" | "escaped" | "missing" | "exited-results") {
            let deadline = Instant::now() + Duration::from_secs(5);
            let ready = if mode == "backlog-results" { "reported" } else { "ready" };
            while !Path::new(ready).exists() && Instant::now() < deadline {
                thread::sleep(Duration::from_millis(10));
            }
            if mode == "exited-results" {
                println!("\n{MARKER}{{\"specs\":[]}}");
                std::io::stdout().flush().unwrap();
            }
        } else {
            child.wait().unwrap();
        }
    }

    #[test]
    #[ignore = "invoked as a subprocess by process cleanup tests"]
    fn descendant_fixture() {
        let address = fs::read_to_string("address").unwrap();
        let mode = fs::read_to_string("mode").unwrap();
        #[cfg(unix)]
        if mode == "escaped" {
            assert_ne!(unsafe { libc::setsid() }, -1);
        }
        let mut connection = TcpStream::connect(address).unwrap();
        connection.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
        connection.write_all(&[1]).unwrap();
        let mut acknowledged = [0];
        connection.read_exact(&mut acknowledged).unwrap();
        assert_eq!(acknowledged, [1]);
        fs::write("ready", "").unwrap();
        if mode == "interrupt-results" {
            let deadline = Instant::now() + Duration::from_secs(5);
            while !Path::new("report").exists() && Instant::now() < deadline {
                thread::sleep(Duration::from_millis(10));
            }
        }
        if matches!(mode.as_str(), "results" | "inactive" | "interrupt-results") {
            println!("\n{MARKER}{{\"specs\":[]}}");
            std::io::stdout().flush().unwrap();
        }
        let prints = match mode.as_str() {
            "backlog-results" | "interrupt-output" | "natural-backlog-results" => 10_000,
            "blocked-output" | "timeout-output" => 1_000_000,
            "broken-pipe" | "moved-launcher-broken-pipe" => 1,
            _ => 0,
        };
        for _ in 0..prints {
            println!("The runtime is still running.");
        }
        if matches!(mode.as_str(), "backlog-results" | "natural-backlog-results") {
            println!("\n{MARKER}{{\"specs\":[]}}");
            std::io::stdout().flush().unwrap();
            fs::write("reported", "").unwrap();
        }
        if mode != "natural-backlog-results" {
            let _ = connection.read(&mut [0]);
        }
    }

    fn wrapper_run() -> Vec<String> {
        vec![
            std::env::current_exe().unwrap().to_str().unwrap().to_owned(),
            "--exact".to_owned(),
            "standalone::process::tests::wrapper_fixture".to_owned(),
            "--ignored".to_owned(),
            "--nocapture".to_owned(),
            "--skip".to_owned(),
        ]
    }

    fn cleaned_up(mode: &str) -> Result<String, String> {
        let project = TempProject::new(&format!("process-cleanup-{mode}"));
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        listener.set_nonblocking(true).unwrap();
        project.write("address", &listener.local_addr().unwrap().to_string());
        project.write("mode", mode);
        #[cfg(unix)]
        if mode == "moved-launcher" {
            project.write("parent-group", &unsafe { libc::getpgrp() }.to_string());
        }
        let command = wrapper_run();
        thread::scope(|scope| {
            let (finished, completion) = mpsc::sync_channel(1);
            let project = &project;
            let command = &command;
            let runner = scope.spawn(move || {
                let result = run(project, command, &[], 5, &Interrupt::default());
                let _ = finished.send(result);
            });
            let deadline = Instant::now() + Duration::from_secs(3);
            let mut connection = loop {
                match listener.accept() {
                    Ok((connection, _)) => break connection,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < deadline => {
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(error) => {
                        let result = completion.recv_timeout(Duration::from_secs(8));
                        panic!("The descendant did not connect ({error}). Runner returned {result:?}.");
                    }
                }
            };
            connection.set_nonblocking(false).unwrap();
            connection.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
            let mut ready = [0];
            connection.read_exact(&mut ready).unwrap();
            assert_eq!(ready, [1]);
            connection.write_all(&[1]).unwrap();
            let result = completion.recv_timeout(Duration::from_secs(8));
            if result.is_err() {
                let _ = connection.write_all(&[0]);
            }
            runner.join().unwrap();
            let result = result.expect("The runner did not finish before the fixture could expire.");
            let read = connection.read(&mut [0]);
            let closed = match &read {
                Ok(0) => true,
                Err(error) => matches!(error.kind(), std::io::ErrorKind::ConnectionAborted | std::io::ErrorKind::ConnectionReset),
                _ => false,
            };
            // Release a surviving fixture before asserting, so a regression does not leak it.
            if !closed {
                let _ = connection.write_all(&[0]);
            }
            if mode == "escaped" {
                assert!(!closed, "The escaped fixture must retain the inherited output pipe.");
            } else {
                assert!(closed, "The runtime descendant survived the {mode} exit ({read:?}). Runner returned {result:?}.");
            }
            result
        })
    }

    #[test]
    fn cleanup_waits_return_a_status_or_a_bounded_error() {
        let deadline = Instant::now();
        assert!(wait_for_exit(|| Ok(Some(exited())), deadline).unwrap().success());
        let pending = wait_for_exit(|| Ok(None), deadline).unwrap_err();
        assert_eq!(pending.kind(), std::io::ErrorKind::TimedOut);
        let refused = wait_for_exit(|| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)), deadline).unwrap_err();
        assert_eq!(refused.kind(), std::io::ErrorKind::PermissionDenied);
    }

    #[cfg(unix)]
    #[test]
    fn launcher_polling_keeps_its_process_group_identifier_reserved_until_cleanup() {
        use std::os::unix::process::CommandExt;

        let mut child = Command::new("sh").args(["-c", "exit 0"]).process_group(0).spawn().unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while !launcher_exited(&mut child).unwrap() {
            assert!(Instant::now() < deadline, "The launcher did not exit.");
            thread::sleep(Duration::from_millis(10));
        }
        #[cfg(target_os = "macos")]
        let only_zombie = only_zombie_launcher(&mut child);
        // A second native wait must still find the zombie, rather than ECHILD.
        let mut status = 0;
        let reaped = unsafe { libc::waitpid(child.id() as libc::pid_t, &mut status, libc::WNOHANG) };
        assert_eq!(reaped, child.id() as libc::pid_t, "Polling reaped the process-group leader early.");
        #[cfg(target_os = "macos")]
        assert!(only_zombie, "The reserved zombie must not be mistaken for a live process tree.");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn a_live_launcher_is_not_a_zombie_only_group() {
        use std::os::unix::process::CommandExt;
        let mut child = Command::new("sh").args(["-c", "exec sleep 60"]).process_group(0).spawn().unwrap();
        let observed = only_zombie_launcher(&mut child);
        child.kill().unwrap();
        child.wait().unwrap();
        assert!(!observed);
    }

    #[test]
    fn reported_results_stop_the_wrapper_and_runtime() {
        assert_eq!(cleaned_up("results").unwrap(), "{\"specs\":[]}");
    }

    #[test]
    fn keeps_results_printed_just_before_the_wrapper_exits() {
        assert_eq!(cleaned_up("exited-results").unwrap(), "{\"specs\":[]}");
    }

    #[cfg(unix)]
    #[test]
    fn escaped_output_writer_does_not_hold_the_runner_open() {
        let problem = cleaned_up("escaped").unwrap_err();
        assert!(problem.contains("ended without reporting any results"), "{problem}");
    }

    #[test]
    fn timeout_stops_the_wrapper_and_runtime() {
        assert!(cleaned_up("timeout").unwrap_err().contains("was stopped, still running"));
    }

    #[cfg(unix)]
    #[test]
    fn a_launcher_that_changes_groups_is_still_stopped_and_reaped() {
        assert!(cleaned_up("moved-launcher").unwrap_err().contains("was stopped, still running"));
    }

    #[test]
    fn missing_results_stop_a_runtime_after_its_wrapper_exits() {
        let problem = cleaned_up("missing").unwrap_err();

        assert!(problem.contains("ended without reporting any results"), "{problem}");
    }

    #[test]
    #[ignore = "invoked as a subprocess by termination tests"]
    fn interrupt_fixture() -> std::process::ExitCode {
        let mode = fs::read_to_string("mode").unwrap();
        #[cfg(windows)]
        if matches!(mode.as_str(), "interrupt" | "interrupt-output" | "interrupt-results" | "inactive" | "blocked-output") {
            super::windows_tests::ignore_ctrl_c(false);
        }
        if mode == "timeout-output" {
            let outcome = run(Path::new("."), &wrapper_run(), &[], 1, &Interrupt::default());
            std::process::exit(if outcome.is_err() { 2 } else { 0 });
        }
        let command = crate::Command::parse(&["test", "--standalone"]).unwrap();
        let outcome = crate::dispatch(command);
        if mode == "inactive" {
            fs::write("finished", "").unwrap();
            thread::sleep(Duration::from_secs(10));
        }
        outcome
    }

    pub(super) fn termination_case(signal: Option<i32>, mode: &str) {
        #[cfg(unix)]
        use std::os::unix::process::{CommandExt, ExitStatusExt};
        use std::panic::{AssertUnwindSafe, catch_unwind, resume_unwind};

        let project = TempProject::new(&format!("process-{signal:?}-{mode}"));
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        listener.set_nonblocking(true).unwrap();
        project.write("address", &listener.local_addr().unwrap().to_string());
        project.write("mode", mode);
        #[cfg(unix)]
        if mode == "moved-launcher-broken-pipe" {
            project.write("parent-group", &unsafe { libc::getpgrp() }.to_string());
        }
        project.write("tests/a.spec.luau", "");
        project.write(
            "litmus.toml",
            &format!("[standalone]\nrun = {}\ntimeout = 300\nlib = \"lib\"\nspecs = [\"tests\"]\n", serde_json::to_string(&wrapper_run()).unwrap()),
        );
        let mut command = fixture_command("standalone::process::tests::interrupt_fixture");
        #[cfg(unix)]
        command.process_group(0);
        #[cfg(windows)]
        if signal.is_some() {
            super::windows_tests::new_console(&mut command);
        }
        let mut child = command
            .current_dir(&project)
            .stdin(Stdio::null())
            .stdout(if signal.is_some() && mode != "blocked-output" { Stdio::null() } else { Stdio::piped() })
            .spawn()
            .unwrap();
        let mut connection = None;
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            let deadline = Instant::now() + Duration::from_secs(5);
            connection = Some(loop {
                match listener.accept() {
                    Ok((connection, _)) => break connection,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < deadline => {
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(error) => {
                        panic!("The termination fixture did not connect ({mode}, {error}).")
                    }
                }
            });
            let connection = connection.as_mut().unwrap();
            connection.set_nonblocking(false).unwrap();
            connection.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
            connection.read_exact(&mut [0]).unwrap();
            if signal.is_none() && !matches!(mode, "backlog-results" | "natural-backlog-results" | "timeout-output") {
                drop(child.stdout.take());
            }
            connection.write_all(&[1]).unwrap();
            let ready = project.join(if mode == "inactive" { "finished" } else { "ready" });
            while !ready.exists() && Instant::now() < deadline {
                thread::sleep(Duration::from_millis(10));
            }
            assert!(ready.exists(), "The termination fixture was not ready ({mode}).");
            if matches!(mode, "blocked-output" | "timeout-output") {
                #[cfg(unix)]
                use std::os::fd::AsRawFd;
                let output = child.stdout.as_ref().unwrap();
                let mut previous = 0;
                loop {
                    #[cfg(unix)]
                    let available = {
                        let mut available = 0;
                        assert_eq!(unsafe { libc::ioctl(output.as_raw_fd(), libc::FIONREAD, &mut available) }, 0);
                        available
                    };
                    #[cfg(windows)]
                    let available = super::windows_tests::available(output) as i32;
                    if available >= 4096 && available == previous {
                        break;
                    }
                    assert!(Instant::now() < deadline, "The downstream output pipe did not fill.");
                    previous = available;
                    thread::sleep(Duration::from_millis(100));
                }
            }
            #[cfg(unix)]
            if let Some(signal) = signal {
                assert_eq!(unsafe { libc::kill(-(child.id() as libc::pid_t), signal) }, 0);
            }
            #[cfg(windows)]
            if signal.is_some() {
                super::windows_tests::send_ctrl_c(child.id());
            }
            if mode == "interrupt-results" {
                project.write("report", "");
            }
            let output = if mode == "timeout-output" {
                connection.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
                let read = connection.read(&mut [0]);
                assert!(
                    matches!(read, Ok(0)) || read.as_ref().is_err_and(|error| matches!(
                        error.kind(), std::io::ErrorKind::ConnectionAborted | std::io::ErrorKind::ConnectionReset
                    )),
                    "The runtime survived its deadline while stdout was blocked ({read:?})."
                );
                let mut output = child.stdout.take().unwrap();
                Some(thread::spawn(move || {
                    let mut printed = Vec::new();
                    output.read_to_end(&mut printed).unwrap();
                    printed
                }))
            } else if matches!(mode, "backlog-results" | "natural-backlog-results") {
                let reported = project.join("reported");
                while !reported.exists() && Instant::now() < deadline {
                    thread::sleep(Duration::from_millis(10));
                }
                assert!(reported.exists(), "The runtime did not queue its results.");
                let mut output = child.stdout.take().unwrap();
                let mut prefix = Vec::new();
                connection.set_nonblocking(true).unwrap();
                let cleanup_deadline = Instant::now() + Duration::from_secs(3);
                loop {
                    match connection.read(&mut [0]) {
                        Ok(0) => break,
                        Err(error)
                            if matches!(error.kind(), std::io::ErrorKind::ConnectionAborted | std::io::ErrorKind::ConnectionReset) =>
                        {
                            break;
                        }
                        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {}
                        result => panic!("The runtime lifetime socket was not idle ({result:?})."),
                    }
                    assert!(Instant::now() < cleanup_deadline, "Cleanup did not precede output replay.");
                    let mut chunk = [0; 4096];
                    let read = output.read(&mut chunk).unwrap();
                    prefix.extend_from_slice(&chunk[..read]);
                    thread::sleep(Duration::from_millis(10));
                }
                connection.set_nonblocking(false).unwrap();
                assert!(prefix.len() < 100_000, "The queued logs must still exceed the downstream pipe capacity.");
                // Keep the downstream pipe stalled beyond the result-collection window.
                thread::sleep(Duration::from_millis(1200));
                Some(thread::spawn(move || {
                    output.read_to_end(&mut prefix).unwrap();
                    prefix
                }))
            } else {
                None
            };
            let deadline = Instant::now() + Duration::from_secs(5);
            let status = loop {
                match child.try_wait().unwrap() {
                    Some(status) => break Some(status),
                    None if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
                    None => break None,
                }
            };
            let read = connection.read(&mut [0]);
            assert!(
                matches!(read, Ok(0))
                    || read.as_ref().is_err_and(|error| matches!(
                        error.kind(),
                        std::io::ErrorKind::ConnectionAborted | std::io::ErrorKind::ConnectionReset
                    )),
                "The terminated runtime survived ({mode}, {read:?})."
            );
            let status = status.expect("The terminated CLI did not exit.");
            #[cfg(unix)]
            if let Some(signal) = signal {
                assert_eq!(status.signal(), Some(signal), "{mode}, {status:?}");
            }
            #[cfg(windows)]
            if let Some(signal) = signal {
                assert_eq!(status.code(), Some(signal), "{mode}, {status:?}");
            }
            if let Some(output) = output {
                let output = output.join().unwrap();
                let tail = &output[output.len().saturating_sub(2048)..];
                if mode == "timeout-output" {
                    assert_eq!(status.code(), Some(2), "The blocked-output timeout did not fail the run.");
                } else {
                    assert!(status.success(), "Queued results were lost ({status:?}). Output tail follows. {}", String::from_utf8_lossy(tail));
                }
            } else if signal.is_none() {
                assert!(!status.success(), "The broken stdout did not interrupt the fixture.");
            }
        }));
        if let Some(mut connection) = connection {
            let _ = connection.write_all(&[0]);
        }
        let _ = child.kill();
        let _ = child.wait();
        if let Err(problem) = outcome {
            resume_unwind(problem);
        }
    }

    #[cfg(unix)]
    #[test]
    fn group_termination_cleans_up_the_runtime_and_keeps_the_original_signal() {
        for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP, libc::SIGQUIT] {
            for mode in ["interrupt", "interrupt-output", "interrupt-results", "inactive"] {
                termination_case(Some(signal), mode);
            }
        }
    }

    #[cfg(unix)]
    #[test]
    fn termination_cleans_up_even_when_the_output_consumer_stops_reading() {
        for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP, libc::SIGQUIT] {
            termination_case(Some(signal), "blocked-output");
        }
    }

    #[test]
    fn timeout_stops_the_runtime_even_when_the_output_consumer_stops_reading() {
        termination_case(None, "timeout-output");
    }

    #[test]
    fn queued_results_survive_a_natural_exit_without_any_descendants() {
        termination_case(None, "natural-backlog-results");
    }

    #[test]
    fn queued_results_survive_slow_output_replay_after_launcher_exit() {
        termination_case(None, "backlog-results");
    }

    #[cfg(unix)]
    #[test]
    fn broken_stdout_stops_a_launcher_that_moved_to_another_group() {
        termination_case(None, "moved-launcher-broken-pipe");
    }

    #[test]
    fn broken_stdout_unwinds_without_leaving_the_runtime_running() {
        termination_case(None, "broken-pipe");
    }

    fn exited() -> ExitStatus {
        #[cfg(unix)]
        use std::os::unix::process::ExitStatusExt;
        #[cfg(windows)]
        use std::os::windows::process::ExitStatusExt;

        ExitStatus::from_raw(0)
    }

    #[test]
    fn keeps_reported_results_with_a_warning_when_the_runtime_cannot_be_stopped() {
        let (outcome, warning) = outcome("lune run", Ok(Some("{}".to_owned())), Err("couldn't stop it".to_owned()));

        assert_eq!(outcome, Ok("{}".to_owned()));
        assert_eq!(warning.as_deref(), Some("couldn't stop it"));
    }

    #[test]
    fn reports_results_without_a_warning_when_the_runtime_stopped() {
        assert_eq!(outcome("lune run", Ok(Some("{}".to_owned())), Ok(exited())), (Ok("{}".to_owned()), None));
    }

    #[test]
    fn names_both_problems_when_a_run_timed_out_and_could_not_be_stopped() {
        let (outcome, warning) = outcome("lune run", Err("it timed out".to_owned()), Err("couldn't stop it".to_owned()));

        assert_eq!(outcome, Err("it timed out, and couldn't stop it".to_owned()));
        assert_eq!(warning, None);
    }

    #[test]
    fn says_a_run_reported_nothing_even_when_it_could_not_be_stopped() {
        let (outcome, _) = outcome("lune run", Ok(None), Err("couldn't stop it".to_owned()));

        assert_eq!(outcome, Err("`lune run` ended without reporting any results, and couldn't stop it".to_owned()));
    }

    #[test]
    fn gives_the_budget_in_minutes_when_it_is_whole_minutes() {
        assert_eq!(in_words(Duration::from_secs(300)), "5 minutes");
        assert_eq!(in_words(Duration::from_secs(60)), "1 minute");
        assert_eq!(in_words(Duration::from_secs(2)), "2 seconds");
        assert_eq!(in_words(Duration::from_secs(90)), "90 seconds");
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
    fn final_collection_cannot_extend_the_execution_deadline() {
        let now = Instant::now();
        assert_eq!(collection_deadline(None, now), now + Duration::from_secs(1));
        assert_eq!(collection_deadline(Some(now + Duration::from_secs(5)), now), now + Duration::from_secs(1));
        assert_eq!(collection_deadline(Some(now + Duration::from_millis(25)), now), now + Duration::from_millis(25));
        assert_eq!(collection_deadline(Some(now), now), now);
        assert_eq!(collection_deadline(Some(now - Duration::from_millis(1)), now), now - Duration::from_millis(1));
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
        let problem = run(&dir, &command, &[], 1, &Interrupt::default()).unwrap_err();

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
        let problem = run(&dir, &command, &[], 1, &Interrupt::default()).unwrap_err();

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
        let problem = run(&dir, &command, &[], 1, &Interrupt::default()).unwrap_err();

        assert!(problem.contains("after 1 second"), "{problem}");
    }

    #[cfg(unix)]
    #[test]
    fn closing_stdout_does_not_escape_the_deadline() {
        let dir = crate::testing::TempProject::new("closed-output-deadline");
        let command = ["sh".to_owned(), "-c".to_owned(), "exec 1>&-; exec sleep 60".to_owned()];
        let problem = run(&dir, &command, &[], 1, &Interrupt::default()).unwrap_err();

        assert!(problem.contains("after 1 second"), "{problem}");
    }

    #[cfg(unix)]
    #[test]
    fn a_disabled_timeout_accepts_a_result_after_a_short_deadline_would_expire() {
        let dir = crate::testing::TempProject::new("disabled-deadline");
        let command = ["sh".to_owned(), "-c".to_owned(), "sleep 2; printf '%s\\n' '@@litmus-run@@{\"specs\":[]}'".to_owned()];

        assert_eq!(run(&dir, &command, &[], 0, &Interrupt::default()), Ok("{\"specs\":[]}".to_owned()));
    }

    #[test]
    fn a_command_that_cannot_start_is_named() {
        let command = ["litmus-no-such-command".to_owned(), "run".to_owned()];
        let problem = run(Path::new("."), &command, &[], 300, &Interrupt::default()).unwrap_err();

        assert!(problem.contains("`litmus-no-such-command run .litmus/run.luau`"), "{problem}");
    }
}
