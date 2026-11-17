mod harness;
mod process;
mod specs;

use crate::selection::Selection;
use serde::Deserialize;
use serde_json::Value;
use std::fs;
use std::path::Path;

const FOLDER: &str = ".litmus";
const SCRIPT: &str = "run.luau";
const MARKER: &str = "@@litmus-run@@";
const PROGRESS_MARKER: &str = "@@litmus-progress@@";

const OWN_OPTIONS: [&str; 5] = ["plugin", "cloud", "standalone", "help", "version"];

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

    let found = specs::find(project_dir, &runtime.specs)?;
    if found.is_empty() {
        return Err("the project has no .spec files where litmus.toml says to look".to_owned());
    }

    let specs = selection.narrow(found)?;

    let folder = project_dir.join(FOLDER);
    let script = harness::script(runtime, &specs, flags)?;

    fs::create_dir_all(&folder)
        .and_then(|()| fs::write(folder.join(SCRIPT), script))
        .map_err(|error| format!("couldn't write {FOLDER}/{SCRIPT}: {error}"))?;

    let reported = process::run(project_dir, &runtime.run, &specs)?;

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

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    pub(super) fn runtime() -> Runtime {
        Runtime {
            run: vec!["lune".to_owned(), "run".to_owned()],
            lib: "submodules/litmus/lib".to_owned(),
            specs: vec!["tests".to_owned()],
            adapter: None,
            flags: vec!["coverage".to_owned()],
        }
    }

    pub(super) fn project(name: &str, files: &[&str]) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("litmus-{}-standalone-{name}", std::process::id()));

        for file in files {
            let file = dir.join(file);
            fs::create_dir_all(file.parent().unwrap()).unwrap();
            fs::write(file, "").unwrap();
        }

        dir
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
        assert!(started.elapsed() < std::time::Duration::from_secs(30), "{:?}", started.elapsed());
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
