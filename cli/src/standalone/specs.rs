use crate::selection::relative;
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

const SPEC_ENDINGS: [&str; 2] = [".spec.luau", ".spec.lua"];

pub fn find(project_dir: &Path, roots: &[String]) -> Result<Vec<String>, String> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::standalone::tests::project;

    fn specs_in(name: &str, files: &[&str], roots: &[&str]) -> Result<Vec<String>, String> {
        let dir = project(name, files);
        let roots: Vec<String> = roots.iter().map(|root| (*root).to_owned()).collect();

        find(&dir, &roots)
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
}
