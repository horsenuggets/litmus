use crate::results::Run;
use crate::server::Server;
use serde::Serialize;
use serde_json::Value;
use std::fs;
use std::path::Path;
use std::time::Duration;

const WINDOW: Duration = Duration::from_secs(3);

const UNNAMED: &str = "a project";

#[derive(Serialize)]
struct Source<'a> {
    path: &'a [String],
    text: String,
}

#[derive(Serialize)]
struct Shown<'a> {
    results: &'a Value,
    sources: Vec<Source<'a>>,
}

pub fn offer(project_dir: &Path, results: &Value, run: &Run) {
    let Ok(server) = Server::open() else {
        return;
    };

    let Ok(shown) = serde_json::to_string(&shown(project_dir, results, run)) else {
        return;
    };

    let _ = server.offer_show(&name_of(project_dir), &shown, WINDOW, |place| {
        eprintln!("litmus: shown in {place}");
    });
}

fn shown<'a>(project_dir: &Path, results: &'a Value, run: &'a Run) -> Shown<'a> {
    let sources = run
        .failing_sources()
        .into_iter()
        .filter_map(|path| {
            let text = fs::read_to_string(project_dir.join(path.join("/"))).ok()?;
            Some(Source { path, text })
        })
        .collect();

    Shown { results, sources }
}

fn name_of(project_dir: &Path) -> String {
    project_dir
        .canonicalize()
        .ok()
        .and_then(|folder| Some(folder.file_name()?.to_string_lossy().into_owned()))
        .unwrap_or_else(|| UNNAMED.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use serde_json::json;
    use std::env;

    #[test]
    fn the_files_failures_name_go_along_with_the_results() {
        let project_dir = env::temp_dir().join(format!("litmus-show-{}", std::process::id()));
        fs::create_dir_all(project_dir.join("tests")).unwrap();
        fs::write(project_dir.join("tests/a.spec.luau"), "error()\n").unwrap();

        let failure = |file: &str| json!({ "message": "m", "source": ["tests", file], "line": 1 });
        let results = json!({ "specs": [
            { "path": ["tests", "a.spec.luau"], "tests": [], "failure": failure("a.spec.luau") },
            { "path": ["tests", "b.spec.luau"], "tests": [], "failure": failure("gone.luau") },
        ] });
        let run = Run::deserialize(&results).unwrap();

        let shown = serde_json::to_value(shown(&project_dir, &results, &run)).unwrap();
        fs::remove_dir_all(&project_dir).unwrap();

        assert_eq!(shown["results"], results);
        assert_eq!(
            shown["sources"],
            json!([{ "path": ["tests", "a.spec.luau"], "text": "error()\n" }])
        );
    }

    #[test]
    fn a_project_goes_by_the_name_of_its_folder() {
        let project_dir = env::temp_dir().join(format!("litmus-named-{}", std::process::id()));
        fs::create_dir_all(&project_dir).unwrap();

        let name = name_of(&project_dir);
        fs::remove_dir_all(&project_dir).unwrap();

        assert_eq!(name, format!("litmus-named-{}", std::process::id()));
        assert_eq!(name_of(Path::new("nowhere/at/all")), "a project");
    }
}
