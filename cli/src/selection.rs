#[derive(Default, Debug, PartialEq)]
pub struct Selection {
    paths: Vec<String>,
}

impl Selection {
    pub fn of(paths: &[String]) -> Result<Selection, String> {
        let paths: Result<Vec<String>, String> = paths.iter().map(|path| relative(path)).collect();

        Ok(Selection { paths: paths? })
    }

    pub fn narrow(&self, specs: Vec<String>) -> Result<Vec<String>, String> {
        if self.paths.is_empty() {
            return Ok(specs);
        }

        let empty = self
            .paths
            .iter()
            .find(|path| !specs.iter().any(|spec| holds(path, spec)));

        if let Some(path) = empty {
            return Err(format!("none of the project's .spec files is at or under \"{path}\""));
        }

        Ok(specs
            .into_iter()
            .filter(|spec| self.paths.iter().any(|path| holds(path, spec)))
            .collect())
    }
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

fn holds(path: &str, file: &str) -> bool {
    path.is_empty() || file == path || file.strip_prefix(path).is_some_and(|rest| rest.starts_with('/'))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn specs() -> Vec<String> {
        ["tests/a.spec.luau", "tests/deep/b.spec.luau", "tests/deeper/c.spec.luau", "src/d.spec.luau"]
            .map(str::to_owned)
            .to_vec()
    }

    fn narrowed(paths: &[&str]) -> Result<Vec<String>, String> {
        let paths: Vec<String> = paths.iter().map(|path| (*path).to_owned()).collect();

        Selection::of(&paths)?.narrow(specs())
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
    fn keeps_every_spec_when_no_path_is_named() {
        assert_eq!(narrowed(&[]), Ok(specs()));
        assert_eq!(Selection::default().narrow(specs()), Ok(specs()));
    }

    #[test]
    fn keeps_the_spec_a_path_names() {
        assert_eq!(narrowed(&["tests/a.spec.luau"]), Ok(vec!["tests/a.spec.luau".to_owned()]));
    }

    #[test]
    fn keeps_the_specs_under_a_folder_and_not_its_namesakes() {
        assert_eq!(narrowed(&["tests/deep"]), Ok(vec!["tests/deep/b.spec.luau".to_owned()]));
    }

    #[test]
    fn keeps_what_any_of_several_paths_names_in_the_order_it_came() {
        assert_eq!(
            narrowed(&["src", "tests/a.spec.luau"]),
            Ok(vec!["tests/a.spec.luau".to_owned(), "src/d.spec.luau".to_owned()])
        );
    }

    #[test]
    fn reads_a_path_however_it_was_typed() {
        assert_eq!(narrowed(&[".\\tests\\deep\\"]), Ok(vec!["tests/deep/b.spec.luau".to_owned()]));
        assert_eq!(narrowed(&["."]), Ok(specs()));
    }

    #[test]
    fn refuses_a_path_that_holds_no_spec() {
        let problem = narrowed(&["tests/a.spec.luau", "tests/missing"]).unwrap_err();

        assert!(problem.contains("\"tests/missing\""), "{problem}");
        assert!(narrowed(&["tests/a"]).is_err());
    }

    #[test]
    fn refuses_a_path_outside_the_project() {
        assert!(narrowed(&["/tests"]).is_err());
        assert!(narrowed(&["C:\\tests"]).is_err());
    }
}
