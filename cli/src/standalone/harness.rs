use super::{MARKER, PROGRESS_MARKER, Runtime};
use crate::luau;
use crate::selection::relative;

const HARNESS: &str = include_str!("harness.luau");

const MODULE_ENDINGS: [&str; 2] = [".luau", ".lua"];
const SHIPPED_ADAPTER: &str = "Adapter/Lune";

pub fn script(runtime: &Runtime, specs: &[String], flags: &[String]) -> Result<String, String> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::standalone::tests::runtime;

    #[test]
    fn the_harness_starts_by_requiring_the_lib_and_its_lune_adapter() {
        let specs = ["tests/a.spec.luau".to_owned(), "tests/b \"c\".spec.luau".to_owned()];
        let script = script(&runtime(), &specs, &["coverage".to_owned()]).unwrap();

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

        let script = script(&runtime, &[], &[]).unwrap();

        let requires = "local litmus = require(\"../../shared/lib\")\nlocal adapter = require(\"../tools/adapter\")\n";
        let options = "local options = {\n    lib = \"../shared/lib\",\n\n    specs = {},\n\n    flags = {},\n}\n";

        assert!(script.starts_with(requires), "{script}");
        assert!(script.contains(options), "{script}");
    }
}
