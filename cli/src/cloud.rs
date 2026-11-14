mod client;
mod place;

use crate::manifest::Manifest;
use client::{Client, Progress};
use serde_json::Value;
use std::env;
use std::path::Path;
use std::thread;
use std::time::{Duration, Instant};

const KEY_VARIABLE: &str = "LITMUS_API_KEY";

const TASK: &str = include_str!("cloud/task.luau");

const POLL: Duration = Duration::from_secs(1);

/// Open Cloud stops a task five minutes in, so one unfinished after this long never left the queue
const PATIENCE: Duration = Duration::from_secs(360);

/// Where a cloud run happens: each run saves a new version of the place, so it should be one kept for testing
#[derive(Debug, PartialEq)]
pub struct Place {
    pub universe: u64,
    pub place: u64,
}

/// Runs the project's specs in a copy of it built for this run, and returns the results as the lib wrote them
pub fn run(project_dir: &Path, manifest: &Manifest, place: &Place) -> Result<Value, String> {
    let key = env::var(KEY_VARIABLE)
        .map_err(|_| format!("{KEY_VARIABLE} isn't set; --cloud runs under the Open Cloud API key it holds"))?;
    let client = Client::new(key);

    let file = place::build(project_dir)?;
    let version = client.upload(place, &file)?;
    eprintln!("litmus: running in version {version} of place {}", place.place);

    let task = client.start(place, version, &script(manifest)?)?;
    results(&wait(&client, &task)?)
}

/// The task's script: `task.luau`, called with the specs to run
fn script(manifest: &Manifest) -> Result<String, String> {
    let specs = serde_json::to_string(&manifest.specs())
        .map_err(|error| format!("couldn't write the list of specs: {error}"))?;

    // The file starts on the first line, so a line number in an error is a line of the file
    Ok(format!("return (function(...) {TASK}\nend)({})", luau_string(&specs)))
}

/// Every byte that could end the string or mean something else in it is written as its number
fn luau_string(text: &str) -> String {
    let mut literal = String::from("\"");

    for byte in text.bytes() {
        let plain = byte == b' ' || (byte.is_ascii_graphic() && byte != b'"' && byte != b'\\');

        if plain {
            literal.push(char::from(byte));
        } else {
            literal.push_str(&format!("\\{byte:03}"));
        }
    }

    literal.push('"');
    literal
}

/// What the task's script returned, once it has
fn wait(client: &Client, task: &str) -> Result<Vec<Value>, String> {
    let deadline = Instant::now() + PATIENCE;

    loop {
        match client.progress(task)? {
            Progress::Complete(returned) => return Ok(returned),
            Progress::Failed(reason) => return Err(format!("the task failed: {reason}")),
            Progress::Running if Instant::now() >= deadline => {
                return Err("the task never finished".to_owned());
            }
            Progress::Running => thread::sleep(POLL),
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
    fn the_script_is_the_task_called_with_the_specs() {
        let script = script(&manifest(&["Thing", "Thing.spec"])).unwrap();

        assert!(script.starts_with("return (function(...) local httpService"), "{script}");
        assert!(
            script.ends_with("\nend)(\"[[\\034ReplicatedStorage\\034,\\034Thing.spec\\034]]\")"),
            "{script}"
        );
    }

    #[test]
    fn a_luau_string_spells_out_whatever_is_not_plain() {
        assert_eq!(luau_string("a b"), "\"a b\"");
        assert_eq!(luau_string("\"\\\n"), "\"\\034\\092\\010\"");
        assert_eq!(luau_string("é"), "\"\\195\\169\"");
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
