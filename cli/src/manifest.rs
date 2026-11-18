use crate::rojo;
use crate::selection::Selection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

const SPEC_SUFFIX: &str = ".spec";

pub type InstancePath = Vec<String>;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Node {
    name: String,
    class_name: String,
    #[serde(default)]
    file_paths: Vec<PathBuf>,
    #[serde(default)]
    children: Vec<Node>,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Script {
    pub path: InstancePath,
    pub hash: String,

    #[serde(skip)]
    pub file: PathBuf,
}

#[derive(Debug)]
pub struct Manifest {
    pub project: String,
    pub scripts: Vec<Script>,
}

impl Manifest {
    pub fn read(project_dir: &Path, rojo_project: Option<&Path>) -> Result<Manifest, String> {
        let sourcemap = rojo::run(project_dir, "sourcemap", rojo_project, &[])?;

        Manifest::from_sourcemap(&sourcemap, project_dir)
    }

    fn from_sourcemap(sourcemap: &[u8], project_dir: &Path) -> Result<Manifest, String> {
        let root: Node = serde_json::from_slice(sourcemap)
            .map_err(|error| format!("couldn't read rojo's sourcemap: {error}"))?;

        if root.class_name != "DataModel" {
            return Err(format!(
                "the Rojo project must describe a whole place, but its root is a {}",
                root.class_name
            ));
        }

        let mut scripts = Vec::new();
        collect(&root, &mut Vec::new(), project_dir, &mut scripts)?;

        Ok(Manifest {
            project: root.name,
            scripts,
        })
    }

    pub fn specs(&self) -> Vec<&InstancePath> {
        self.scripts
            .iter()
            .filter(|script| script.is_spec())
            .map(|script| &script.path)
            .collect()
    }

    pub fn narrow(&mut self, selection: &Selection) -> Result<(), String> {
        let specs: Vec<String> = self
            .scripts
            .iter()
            .filter(|script| script.is_spec())
            .map(Script::file_from_project)
            .collect();

        let kept = selection.narrow(specs)?;

        self.scripts
            .retain(|script| !script.is_spec() || kept.contains(&script.file_from_project()));

        Ok(())
    }
}

impl Script {
    fn is_spec(&self) -> bool {
        self.path.last().is_some_and(|name| name.ends_with(SPEC_SUFFIX))
    }

    fn file_from_project(&self) -> String {
        self.file.to_string_lossy().replace('\\', "/")
    }
}

fn collect(
    node: &Node,
    path: &mut InstancePath,
    project_dir: &Path,
    scripts: &mut Vec<Script>,
) -> Result<(), String> {
    for child in &node.children {
        path.push(child.name.clone());

        if let Some(file) = child.file_paths.iter().find(|file| is_luau(file)) {
            let source = fs::read(project_dir.join(file))
                .map_err(|error| format!("couldn't read {}: {error}", file.display()))?;

            scripts.push(Script {
                path: path.clone(),
                hash: hash_without_carriage_returns(&source),
                file: file.clone(),
            });
        }

        collect(child, path, project_dir, scripts)?;
        path.pop();
    }

    Ok(())
}

fn is_luau(file: &Path) -> bool {
    file.extension()
        .is_some_and(|extension| extension == "luau" || extension == "lua")
}

fn hash_without_carriage_returns(source: &[u8]) -> String {
    let normalized: Vec<u8> = source.iter().copied().filter(|byte| *byte != b'\r').collect();

    Sha256::digest(&normalized)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SOURCEMAP: &str = r#"{
        "name": "demo",
        "className": "DataModel",
        "filePaths": ["default.project.json"],
        "children": [{
            "name": "ReplicatedStorage",
            "className": "ReplicatedStorage",
            "children": [
                { "name": "Thing", "className": "ModuleScript", "filePaths": ["Thing.luau"] },
                { "name": "Thing.spec", "className": "ModuleScript", "filePaths": ["Thing.spec.luau"] },
                { "name": "Data", "className": "ModuleScript", "filePaths": ["Data.json"] }
            ]
        }]
    }"#;

    fn project(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("litmus-{}-{name}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("Thing.luau"), "return 1\r\n").unwrap();
        fs::write(dir.join("Thing.spec.luau"), "return 1\n").unwrap();
        fs::write(dir.join("Data.json"), "{}").unwrap();
        dir
    }

    #[test]
    fn hashes_as_sha256_in_hex() {
        assert_eq!(
            hash_without_carriage_returns(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn lists_luau_files_by_instance_path() {
        let dir = project("lists");
        let manifest = Manifest::from_sourcemap(SOURCEMAP.as_bytes(), &dir).unwrap();
        fs::remove_dir_all(&dir).unwrap();

        let paths: Vec<String> = manifest.scripts.iter().map(|script| script.path.join("/")).collect();

        assert_eq!(manifest.project, "demo");
        assert_eq!(paths, ["ReplicatedStorage/Thing", "ReplicatedStorage/Thing.spec"]);
        assert_eq!(manifest.specs(), [&manifest.scripts[1].path]);
    }

    #[test]
    fn narrows_to_the_specs_a_selection_names_and_keeps_every_other_script() {
        let dir = project("narrows");
        let mut manifest = Manifest::from_sourcemap(SOURCEMAP.as_bytes(), &dir).unwrap();
        fs::remove_dir_all(&dir).unwrap();

        let nowhere = Selection::of(&["Other.spec.luau".to_owned()]).unwrap();
        assert!(manifest.narrow(&nowhere).is_err());
        assert_eq!(manifest.scripts.len(), 2);

        let helper = Selection::of(&["Thing.luau".to_owned()]).unwrap();
        assert!(manifest.narrow(&helper).is_err());

        manifest.narrow(&Selection::of(&["Thing.spec.luau".to_owned()]).unwrap()).unwrap();
        assert_eq!(manifest.scripts.len(), 2);
        assert_eq!(manifest.specs().len(), 1);
    }

    #[test]
    fn ignores_line_endings() {
        let dir = project("endings");
        let manifest = Manifest::from_sourcemap(SOURCEMAP.as_bytes(), &dir).unwrap();
        fs::remove_dir_all(&dir).unwrap();

        assert_eq!(manifest.scripts[0].hash, manifest.scripts[1].hash);
    }

    #[test]
    fn refuses_a_project_that_is_not_a_place() {
        let sourcemap = r#"{ "name": "demo", "className": "Folder" }"#;
        let problem = Manifest::from_sourcemap(sourcemap.as_bytes(), Path::new(".")).unwrap_err();

        assert!(problem.contains("whole place"), "{problem}");
    }
}
