use crate::luau;
use crate::progress::{Display, Event};
use crate::selection::Selection;
use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeSet;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

const HARNESS: &str = include_str!("standalone/harness.luau");

const FOLDER: &str = ".litmus";
const SCRIPT: &str = "run.luau";
const MARKER: &str = "@@litmus-run@@";
const PROGRESS_MARKER: &str = "@@litmus-progress@@";
const BUDGET: Duration = Duration::from_secs(300);
const TICK: Duration = Duration::from_millis(100);

const SPEC_ENDINGS: [&str; 2] = [".spec.luau", ".spec.lua"];
const MODULE_ENDINGS: [&str; 2] = [".luau", ".lua"];
const SHIPPED_ADAPTER: &str = "Adapter/Lune";
const OWN_OPTIONS: [&str; 5] = ["plugin", "cloud", "standalone", "help", "version"];

#[derive(Debug, PartialEq)]
enum Message {
    Printed(String),
    Event(Event),
    Reported(String),
}

#[derive(Deserialize, Debug, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Runtime {
    pub run: Vec<String>,
    pub lib: String,
    pub specs: Vec<String>,
    pub adapter: Option<String>,
    #[serde(default)]
    pub flags: Vec<String>,
}

impl Runtime {
    pub fn check(&self) -> Result<(), String> {
        if self.run.first().is_none_or(String::is_empty) {
            return Err("`run` has to start with the command that runs a Luau file, as in [\"lune\", \"run\"]".to_owned());
        }

        for path in self.specs.iter() {
            relative(path)?;
        }

        for path in [&self.lib].into_iter().chain(&self.adapter) {
            if relative(path)?.is_empty() {
                return Err(format!("\"{path}\" has to name something inside the project's folder"));
            }
        }

        match self.flags.iter().find(|flag| !is_flag(flag)) {
            Some(flag) => Err(format!(
                "`flags` can't hold \"{flag}\"; a flag is lowercase letters, digits and dashes, \
                 and none of litmus's own options"
            )),
            None => Ok(()),
        }
    }
}

pub fn run(project_dir: &Path, runtime: &Runtime, flags: &[String], selection: &Selection) -> Result<Value, String> {
    if let Some(flag) = flags.iter().find(|flag| !runtime.flags.contains(flag)) {
        return Err(format!("--{flag} isn't a flag litmus.toml lists under [standalone]"));
    }

    let found = find_specs(project_dir, &runtime.specs)?;
    if found.is_empty() {
        return Err("the project has no .spec files where litmus.toml says to look".to_owned());
    }

    let specs = selection.narrow(found)?;

    let folder = project_dir.join(FOLDER);
    let script = harness(runtime, &specs, flags)?;

    fs::create_dir_all(&folder)
        .and_then(|()| fs::write(folder.join(SCRIPT), script))
        .map_err(|error| format!("couldn't write {FOLDER}/{SCRIPT}: {error}"))?;

    let reported = execute(project_dir, &runtime.run, &specs)?;

    serde_json::from_str(&reported).map_err(|error| format!("couldn't read what the run reported: {error}"))
}

fn is_flag(flag: &str) -> bool {
    let spelled = flag
        .bytes()
        .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-');

    spelled && !flag.is_empty() && !flag.starts_with('-') && !OWN_OPTIONS.contains(&flag)
}

pub fn relative(path: &str) -> Result<String, String> {
    if path.starts_with(['/', '\\']) || path.contains(':') {
        return Err(format!("\"{path}\" has to be a path from the project's folder"));
    }

    let names: Vec<&str> = path
        .split(['/', '\\'])
        .filter(|name| !name.is_empty() && *name != ".")
        .collect();

    Ok(names.join("/"))
}

fn find_specs(project_dir: &Path, roots: &[String]) -> Result<Vec<String>, String> {
    let mut specs = BTreeSet::new();

    for listed in roots {
        let root = relative(listed)?;
        let found = project_dir.join(&root);

        if found.is_dir() {
            collect(&found, &root, &mut specs)?;
        } else if found.is_file() {
            specs.insert(root);
        } else {
            return Err(format!("litmus.toml lists \"{listed}\" under specs, and nothing is there"));
        }
    }

    Ok(specs.into_iter().collect())
}

fn collect(folder: &Path, path: &str, specs: &mut BTreeSet<String>) -> Result<(), String> {
    let unreadable = |error| format!("couldn't read {}: {error}", folder.display());

    for entry in fs::read_dir(folder).map_err(unreadable)? {
        let entry = entry.map_err(unreadable)?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let below = if path.is_empty() { name.clone() } else { format!("{path}/{name}") };

        if entry.path().is_dir() {
            if !name.starts_with('.') {
                collect(&entry.path(), &below, specs)?;
            }
        } else if SPEC_ENDINGS.iter().any(|ending| name.ends_with(ending)) {
            specs.insert(below);
        }
    }

    Ok(())
}

fn harness(runtime: &Runtime, specs: &[String], flags: &[String]) -> Result<String, String> {
    let lib = relative(&runtime.lib)?;

    let adapter = match &runtime.adapter {
        Some(adapter) => module(&relative(adapter)?).to_owned(),
        None => format!("{lib}/{SHIPPED_ADAPTER}"),
    };

    let specs: Vec<String> = specs.iter().map(|spec| luau::string(spec)).collect();
    let flags: Vec<String> = flags
        .iter()
        .map(|flag| format!("[{}] = true", luau::string(flag)))
        .collect();

    let header = [
        format!("local litmus = require({})", luau::string(&from_folder(&lib))),
        format!("local adapter = require({})", luau::string(&from_folder(&adapter))),
        String::new(),
        format!("local marker = {}", luau::string(MARKER)),
        format!("local progressMarker = {}", luau::string(PROGRESS_MARKER)),
        String::new(),
        "local options = {".to_owned(),
        format!("    lib = {},", luau::string(&lib)),
        String::new(),
        format!("    specs = {},", table(&specs)),
        String::new(),
        format!("    flags = {},", table(&flags)),
        "}".to_owned(),
    ];

    Ok(format!("{}\n\n{HARNESS}", header.join("\n")))
}

fn table(entries: &[String]) -> String {
    if entries.is_empty() {
        return "{}".to_owned();
    }

    let lines: Vec<String> = entries.iter().map(|entry| format!("        {entry},\n")).collect();

    format!("{{\n{}    }}", lines.concat())
}

fn module(file: &str) -> &str {
    MODULE_ENDINGS
        .iter()
        .find_map(|ending| file.strip_suffix(ending))
        .unwrap_or(file)
}

fn from_folder(path: &str) -> String {
    format!("../{path}")
}

fn execute(project_dir: &Path, run: &[String], specs: &[String]) -> Result<String, String> {
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
            Ok(Message::Reported(results)) => break Some(results),
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
        let last = matches!(message, Some(Message::Reported(_)));

        if message.is_some_and(|message| !pass(message)) || last {
            return;
        }

        line.clear();
    }
}

fn read(text: &str) -> Option<Message> {
    if let Some(results) = text.strip_prefix(MARKER) {
        return Some(Message::Reported(results.to_owned()));
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
    use std::path::PathBuf;

    fn runtime() -> Runtime {
        Runtime {
            run: vec!["lune".to_owned(), "run".to_owned()],
            lib: "submodules/litmus/lib".to_owned(),
            specs: vec!["tests".to_owned()],
            adapter: None,
            flags: vec!["coverage".to_owned()],
        }
    }

    fn project(name: &str, files: &[&str]) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("litmus-{}-standalone-{name}", std::process::id()));

        for file in files {
            let file = dir.join(file);
            fs::create_dir_all(file.parent().unwrap()).unwrap();
            fs::write(file, "").unwrap();
        }

        dir
    }

    fn specs_in(name: &str, files: &[&str], roots: &[&str]) -> Result<Vec<String>, String> {
        let dir = project(name, files);
        let roots: Vec<String> = roots.iter().map(|root| (*root).to_owned()).collect();

        let specs = find_specs(&dir, &roots);
        fs::remove_dir_all(&dir).unwrap();

        specs
    }

    #[test]
    fn finds_the_spec_files_under_each_root_in_order() {
        let files = [
            "tests/b.spec.luau",
            "tests/deep/er/a.spec.lua",
            "tests/helper.luau",
            "tests/spec.luau",
            "src/c.spec.luau",
            "other/d.spec.luau",
        ];

        assert_eq!(
            specs_in("finds", &files, &["tests", "./src/"]),
            Ok(vec![
                "src/c.spec.luau".to_owned(),
                "tests/b.spec.luau".to_owned(),
                "tests/deep/er/a.spec.lua".to_owned(),
            ])
        );
    }

    #[test]
    fn takes_a_spec_once_when_two_roots_hold_it() {
        let files = ["tests/a.spec.luau", "tests/deep/b.spec.luau"];

        assert_eq!(
            specs_in("once", &files, &["tests", "tests/deep", "tests/a.spec.luau"]),
            Ok(vec!["tests/a.spec.luau".to_owned(), "tests/deep/b.spec.luau".to_owned()])
        );
    }

    #[test]
    fn looks_through_the_whole_project_but_not_its_hidden_folders() {
        let files = ["a.spec.luau", "tests/b.spec.luau", ".litmus/c.spec.luau", "tests/.cache/d.spec.luau"];

        assert_eq!(
            specs_in("hidden", &files, &["."]),
            Ok(vec!["a.spec.luau".to_owned(), "tests/b.spec.luau".to_owned()])
        );
    }

    #[test]
    fn refuses_a_root_that_is_not_there() {
        let problem = specs_in("missing", &["tests/a.spec.luau"], &["specs"]).unwrap_err();

        assert!(problem.contains("\"specs\""), "{problem}");
    }

    #[test]
    fn the_harness_starts_by_requiring_the_lib_and_its_lune_adapter() {
        let specs = ["tests/a.spec.luau".to_owned(), "tests/b \"c\".spec.luau".to_owned()];
        let script = harness(&runtime(), &specs, &["coverage".to_owned()]).unwrap();

        let header = r#"local litmus = require("../submodules/litmus/lib")
local adapter = require("../submodules/litmus/lib/Adapter/Lune")

local marker = "@@litmus-run@@"
local progressMarker = "@@litmus-progress@@"

local options = {
    lib = "submodules/litmus/lib",

    specs = {
        "tests/a.spec.luau",
        "tests/b \034c\034.spec.luau",
    },

    flags = {
        ["coverage"] = true,
    },
}

"#;

        assert!(script.starts_with(header), "{script}");
        assert!(script.ends_with("print(marker .. encode(litmus.run(adapter(options), report)))\n"), "{script}");
    }

    #[test]
    fn the_harness_requires_the_adapter_the_project_names() {
        let runtime = Runtime {
            lib: "..\\shared\\lib".to_owned(),
            adapter: Some("./tools/adapter.luau".to_owned()),
            ..runtime()
        };

        let script = harness(&runtime, &[], &[]).unwrap();

        let requires = "local litmus = require(\"../../shared/lib\")\nlocal adapter = require(\"../tools/adapter\")\n";
        let options = "local options = {\n    lib = \"../shared/lib\",\n\n    specs = {},\n\n    flags = {},\n}\n";

        assert!(script.starts_with(requires), "{script}");
        assert!(script.contains(options), "{script}");
    }

    #[test]
    fn a_path_is_written_from_the_project_with_forward_slashes() {
        assert_eq!(relative("tests"), Ok("tests".to_owned()));
        assert_eq!(relative("./a\\b//c/"), Ok("a/b/c".to_owned()));
        assert_eq!(relative("../lib"), Ok("../lib".to_owned()));
        assert_eq!(relative("."), Ok(String::new()));

        assert!(relative("/usr/lib").is_err());
        assert!(relative("C:\\lib").is_err());
    }

    #[test]
    fn accepts_a_runtime_that_adds_up() {
        assert_eq!(runtime().check(), Ok(()));
    }

    #[test]
    fn refuses_a_runtime_without_a_command() {
        assert!(Runtime { run: vec![], ..runtime() }.check().is_err());
        assert!(Runtime { run: vec![String::new()], ..runtime() }.check().is_err());
    }

    #[test]
    fn refuses_paths_that_do_not_sit_in_the_project() {
        let lib = |lib: &str| Runtime { lib: lib.to_owned(), ..runtime() };

        assert!(lib("/opt/litmus").check().is_err());
        assert!(lib(".").check().is_err());
        assert!(Runtime { specs: vec!["D:\\tests".to_owned()], ..runtime() }.check().is_err());
        assert!(Runtime { adapter: Some("/adapter.luau".to_owned()), ..runtime() }.check().is_err());
        assert_eq!(Runtime { specs: vec![".".to_owned()], ..runtime() }.check(), Ok(()));
    }

    #[test]
    fn refuses_flags_it_could_not_tell_from_its_own_options() {
        let flags = |flag: &str| Runtime { flags: vec![flag.to_owned()], ..runtime() };

        assert_eq!(flags("with-dashes-2").check(), Ok(()));

        for flag in ["plugin", "cloud", "standalone", "help", "version", "", "Coverage", "--coverage", "-c", "two words"] {
            assert!(flags(flag).check().is_err(), "{flag}");
        }
    }

    #[test]
    fn refuses_a_flag_the_project_never_listed() {
        let problem = run(Path::new("a folder that doesn't exist"), &runtime(), &["verbose".to_owned()], &Selection::default())
            .unwrap_err();

        assert!(problem.contains("--verbose"), "{problem}");
    }

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
            [printed("first"), printed("second"), Message::Reported("{\"specs\":[]}".to_owned())]
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
        let run = ["litmus-no-such-command".to_owned(), "run".to_owned()];
        let problem = execute(Path::new("."), &run, &[]).unwrap_err();

        assert!(problem.contains("`litmus-no-such-command run .litmus/run.luau`"), "{problem}");
    }

    #[cfg(unix)]
    #[test]
    fn a_run_is_what_the_command_printed_on_its_marked_line() {
        let dir = project("runs", &["tests/a.spec.luau"]);
        let runtime = Runtime {
            run: vec!["sh".to_owned(), "-c".to_owned(), "echo '@@litmus-run@@{\"specs\":[]}'".to_owned()],
            ..runtime()
        };

        let reported = run(&dir, &runtime, &[], &Selection::default());
        let written = fs::read_to_string(dir.join(".litmus/run.luau"));
        fs::remove_dir_all(&dir).unwrap();

        assert_eq!(reported, Ok(serde_json::json!({ "specs": [] })));
        assert!(written.unwrap().contains("\"tests/a.spec.luau\""));
    }

    #[cfg(unix)]
    #[test]
    fn a_run_is_over_once_it_reported_even_if_the_command_goes_on() {
        let dir = project("lingers", &["tests/a.spec.luau"]);
        let runtime = Runtime {
            run: vec![
                "sh".to_owned(),
                "-c".to_owned(),
                "echo '@@litmus-run@@{\"specs\":[]}'; exec sleep 60".to_owned(),
            ],
            ..runtime()
        };

        let started = std::time::Instant::now();
        let reported = run(&dir, &runtime, &[], &Selection::default());
        fs::remove_dir_all(&dir).unwrap();

        assert_eq!(reported, Ok(serde_json::json!({ "specs": [] })));
        assert!(started.elapsed() < Duration::from_secs(30), "{:?}", started.elapsed());
    }

    #[cfg(unix)]
    #[test]
    fn a_command_that_reports_nothing_is_an_error() {
        let dir = project("silent", &["tests/a.spec.luau"]);
        let runtime = Runtime {
            run: vec!["sh".to_owned(), "-c".to_owned(), "exit 3".to_owned()],
            ..runtime()
        };

        let problem = run(&dir, &runtime, &[], &Selection::default()).unwrap_err();
        fs::remove_dir_all(&dir).unwrap();

        assert!(problem.contains("without reporting any results"), "{problem}");
    }
}
