mod client;
mod place;

use crate::luau;
use crate::manifest::Manifest;
use client::{Client, TaskState};
use serde::Deserialize;
use serde_json::Value;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

const KEY_VARIABLE: &str = "LITMUS_API_KEY";
const DOTENV: &str = ".env";

const TASK: &str = include_str!("cloud/task.luau");

const POLL: Duration = Duration::from_secs(1);

const PATIENCE: Duration = Duration::from_secs(360);

#[derive(Deserialize, Debug, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Target {
    pub universe: u64,
    pub place: u64,
    pub build: Option<PathBuf>,
}

pub fn run(project_dir: &Path, manifest: &Manifest, target: &Target, rojo_project: Option<&Path>) -> Result<Value, String> {
    let client = Client::new(key(project_dir)?);

    let file = match &target.build {
        Some(build) => place::read(&project_dir.join(build))?,
        None => place::build(project_dir, rojo_project)?,
    };

    let version = client.upload(target, &file)?;
    eprintln!("litmus: running in version {version} of place {}", target.place);

    let task = client.start(target, version, &script(manifest)?)?;
    results(&wait(&client, &task)?)
}

fn key(project_dir: &Path) -> Result<String, String> {
    let set = env::var(KEY_VARIABLE).ok().filter(|key| !key.is_empty());

    set.or_else(|| key_in(&fs::read_to_string(project_dir.join(DOTENV)).ok()?))
        .ok_or_else(|| {
            format!(
                "{KEY_VARIABLE} isn't set, in the environment or in the project's {DOTENV}; \
                 a cloud run goes under the Open Cloud API key it holds"
            )
        })
}

fn key_in(dotenv: &str) -> Option<String> {
    dotenv
        .lines()
        .filter_map(|line| line.split_once('='))
        .find(|(name, _)| name.trim() == KEY_VARIABLE)
        .map(|(_, value)| value.trim().trim_matches(['"', '\'']).to_owned())
        .filter(|key| !key.is_empty())
}

fn script(manifest: &Manifest) -> Result<String, String> {
    let specs = serde_json::to_string(&manifest.specs())
        .map_err(|error| format!("couldn't write the list of specs: {error}"))?;

    Ok(format!("return (function(...) {TASK}\nend)({})", luau::string(&specs)))
}

fn wait(client: &Client, task: &str) -> Result<Vec<Value>, String> {
    let deadline = Instant::now() + PATIENCE;

    loop {
        match client.progress(task)? {
            TaskState::Complete(returned) => return Ok(returned),
            TaskState::Failed(reason) => return Err(format!("the task failed: {reason}")),
            TaskState::Running if Instant::now() >= deadline => {
                return Err("the task never finished".to_owned());
            }
            TaskState::Running => thread::sleep(POLL),
        }
    }
}

fn results(returned: &[Value]) -> Result<Value, String> {
    let Some(Value::String(encoded)) = returned.first() else {
        return Err("the task finished without returning any results".to_owned());
    };

    serde_json::from_str(encoded).map_err(|error| format!("couldn't read what the task returned: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::Script;
    use serde_json::json;

    fn manifest(names: &[&str]) -> Manifest {
        Manifest {
            project: "demo".to_owned(),
            scripts: names
                .iter()
                .map(|name| Script {
                    path: vec!["ReplicatedStorage".to_owned(), (*name).to_owned()],
                    hash: String::new(),
                    file: format!("{name}.luau").into(),
                })
                .collect(),
        }
    }

    #[test]
    fn finds_the_key_among_the_lines_of_a_dotenv() {
        let dotenv = "# keys\nOTHER=1\nLITMUS_API_KEY = \"abc=def\" \nLITMUS_API_KEY=later\n";

        assert_eq!(key_in(dotenv), Some("abc=def".to_owned()));
        assert_eq!(key_in("LITMUS_API_KEY='abc'\r\n"), Some("abc".to_owned()));
    }

    #[test]
    fn a_dotenv_without_a_key_has_none() {
        assert_eq!(key_in(""), None);
        assert_eq!(key_in("OTHER_LITMUS_API_KEY=abc\n"), None);
        assert_eq!(key_in("LITMUS_API_KEY=\n"), None);
    }

    #[test]
    fn the_script_is_the_task_called_with_the_specs() {
        let script = script(&manifest(&["Thing", "Thing.spec"])).unwrap();

        assert!(script.starts_with("return (function(...) local httpService"), "{script}");
        assert!(
            script.ends_with("\nend)(\"[[\\034ReplicatedStorage\\034,\\034Thing.spec\\034]]\")"),
            "{script}"
        );
    }

    #[test]
    fn results_are_the_json_the_task_returned() {
        assert_eq!(results(&[json!("[{ \"path\": [\"a\"] }]")]), Ok(json!([{ "path": ["a"] }])));
    }

    #[test]
    fn a_task_that_returned_something_else_is_an_error() {
        assert!(results(&[]).is_err());
        assert!(results(&[json!(5)]).is_err());
        assert!(results(&[json!("not json")]).is_err());
    }
}
