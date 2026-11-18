use crate::rojo;
use rbx_dom_weak::InstanceBuilder;
use rbx_dom_weak::types::Variant;
use std::env;
use std::ffi::OsStr;
use std::fs;
use std::path::Path;
use std::process;

const SCRIPT_SERVICE: &str = "ServerScriptService";
const LOADSTRING_SWITCH: &str = "LoadStringEnabled";

pub fn build(project_dir: &Path, rojo_project: Option<&Path>) -> Result<Vec<u8>, String> {
    let file = env::temp_dir().join(format!("litmus-{}.rbxl", process::id()));

    rojo::run(project_dir, "build", rojo_project, &[OsStr::new("--output"), file.as_os_str()])?;

    let built = fs::read(&file).map_err(|error| format!("couldn't read the place rojo built: {error}"));
    let _ = fs::remove_file(&file);

    allow_loadstring(&built?)
}

pub fn read(file: &Path) -> Result<Vec<u8>, String> {
    let binary = file
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("rbxl"));

    if !binary {
        return Err(format!("{} isn't a binary place file, which ends in .rbxl", file.display()));
    }

    let place = fs::read(file).map_err(|error| format!("couldn't read {}: {error}", file.display()))?;

    allow_loadstring(&place)
}

fn allow_loadstring(place: &[u8]) -> Result<Vec<u8>, String> {
    let mut dom = rbx_binary::from_reader(place).map_err(|error| format!("couldn't read the place file: {error}"))?;

    let service = dom.root().children().iter().copied().find(|child| {
        dom.get_by_ref(*child)
            .is_some_and(|instance| instance.class.as_str() == SCRIPT_SERVICE)
    });

    match service.and_then(|service| dom.get_by_ref_mut(service)) {
        Some(service) => {
            service.properties.insert(LOADSTRING_SWITCH.into(), Variant::Bool(true));
        }
        None => {
            let service = InstanceBuilder::new(SCRIPT_SERVICE).with_property(LOADSTRING_SWITCH, true);
            dom.insert(dom.root_ref(), service);
        }
    }

    let mut allowed = Vec::new();
    rbx_binary::to_writer(&mut allowed, &dom, dom.root().children())
        .map_err(|error| format!("couldn't write the place to upload: {error}"))?;

    Ok(allowed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rbx_dom_weak::{Instance, WeakDom};

    fn place(services: Vec<InstanceBuilder>) -> Vec<u8> {
        let dom = WeakDom::new(InstanceBuilder::new("DataModel").with_children(services));

        let mut file = Vec::new();
        rbx_binary::to_writer(&mut file, &dom, dom.root().children()).unwrap();
        file
    }

    fn module(name: &str, source: &str) -> InstanceBuilder {
        InstanceBuilder::new("ModuleScript")
            .with_name(name)
            .with_property("Source", source)
    }

    fn child<'a>(dom: &'a WeakDom, parent: &Instance, name: &str) -> &'a Instance {
        parent
            .children()
            .iter()
            .filter_map(|child| dom.get_by_ref(*child))
            .find(|child| child.name == name)
            .unwrap_or_else(|| panic!("nothing named {name}"))
    }

    fn switch(service: &Instance) -> Option<&Variant> {
        service.properties.get(&LOADSTRING_SWITCH.into())
    }

    #[test]
    fn switches_loadstring_on_and_keeps_the_scripts() {
        let storage = InstanceBuilder::new("ReplicatedStorage").with_child(module("Thing.spec", "return 1\n"));
        let scripts = InstanceBuilder::new(SCRIPT_SERVICE).with_child(module("Server", "return 2\n"));

        let allowed = allow_loadstring(&place(vec![storage, scripts])).unwrap();
        let dom = rbx_binary::from_reader(allowed.as_slice()).unwrap();

        let storage = child(&dom, dom.root(), "ReplicatedStorage");
        let scripts = child(&dom, dom.root(), SCRIPT_SERVICE);
        let source = |module: &Instance| module.properties.get(&"Source".into()).cloned();

        assert_eq!(dom.root().children().len(), 2);
        assert_eq!(switch(scripts), Some(&Variant::Bool(true)));
        assert_eq!(source(child(&dom, storage, "Thing.spec")), Some(Variant::String("return 1\n".to_owned())));
        assert_eq!(source(child(&dom, scripts, "Server")), Some(Variant::String("return 2\n".to_owned())));
    }

    #[test]
    fn reads_a_place_built_elsewhere() {
        let file = env::temp_dir().join(format!("litmus-{}-reads.rbxl", process::id()));
        fs::write(&file, place(vec![InstanceBuilder::new("ReplicatedStorage")])).unwrap();

        let allowed = read(&file);
        fs::remove_file(&file).unwrap();

        let dom = rbx_binary::from_reader(allowed.unwrap().as_slice()).unwrap();

        assert_eq!(switch(child(&dom, dom.root(), SCRIPT_SERVICE)), Some(&Variant::Bool(true)));
    }

    #[test]
    fn refuses_a_file_that_is_not_a_binary_place() {
        let problem = read(Path::new("build.rbxlx")).unwrap_err();

        assert!(problem.contains("build.rbxlx isn't a binary place file"), "{problem}");
    }

    #[test]
    fn adds_the_service_to_a_place_without_one() {
        let allowed = allow_loadstring(&place(vec![InstanceBuilder::new("ReplicatedStorage")])).unwrap();
        let dom = rbx_binary::from_reader(allowed.as_slice()).unwrap();

        assert_eq!(dom.root().children().len(), 2);
        assert_eq!(switch(child(&dom, dom.root(), SCRIPT_SERVICE)), Some(&Variant::Bool(true)));
    }
}
