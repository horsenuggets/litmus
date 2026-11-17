mod cloud;
mod config;
mod luau;
mod manifest;
mod plugin;
mod progress;
mod report;
mod results;
mod selection;
mod server;
mod standalone;

use config::Config;
use manifest::Manifest;
use report::Sources;
use results::{Run, Tally};
use selection::Selection;
use serde_json::Value;
use server::{Outcome, Server, Timeouts};
use std::env;
use std::io;
use std::path::Path;
use std::process::ExitCode;
use terminal_size::{Width, terminal_size_of};

const VERSION: &str = env!("CARGO_PKG_VERSION");

const HELP: &str = "\
Runs a project's tests, in Roblox Studio or wherever litmus.toml says

Usage: litmus <command>

Commands:
  test [paths]        Run the project's .spec files in an open Studio place; with paths, only the ones at or
                      under those files and folders
  plugin install      Install the Studio plugin, replacing any copy installed before
  plugin uninstall    Remove the Studio plugin

Options for test:
  --plugin            Run in an open Studio place, through the plugin, as without any of these three
  --cloud             Run in Roblox's cloud, in the place litmus.toml names, which the project is built into as a
                      new unpublished version
  --standalone        Run in a runtime on this machine, started by the command litmus.toml gives
  --<flag>            A flag of the project's own for its adapter, with --standalone

litmus.toml:
  [rojo]              The Rojo project a plugin or cloud run reads the place from, as `project`, when it isn't
                      the default one
  [cloud]             The experience and its place, as `universe` and `place`; and as `build`, a .rbxl to use as
                      the new version, when Rojo alone doesn't build the whole place
  [standalone]        The command that runs a Luau file, as `run`; the folder of litmus's lib, as `lib`; where to
                      look for .spec files, as `specs`; and for a project with an adapter of its own, that file
                      as `adapter` and the flags it takes as `flags`

A cloud run also needs:
  LITMUS_API_KEY      The Open Cloud API key to run under, read from the environment, or else from the project's .env

Options:
  -h, --help          Print this help
  -V, --version       Print the version
";

#[derive(Debug, PartialEq)]
enum Backend {
    Plugin,
    Cloud,
    Standalone,
}

impl Backend {
    fn named(name: &str) -> Option<Backend> {
        match name {
            "plugin" => Some(Backend::Plugin),
            "cloud" => Some(Backend::Cloud),
            "standalone" => Some(Backend::Standalone),
            _ => None,
        }
    }
}

#[derive(Debug, PartialEq)]
struct Test {
    backend: Backend,
    flags: Vec<String>,
    paths: Vec<String>,
}

impl Test {
    /// None when the options don't add up to one place to run in
    fn parse(options: &[&str]) -> Option<Test> {
        let mut backend = None;
        let mut flags = Vec::new();
        let mut paths = Vec::new();

        for option in options {
            let Some(name) = option.strip_prefix("--") else {
                if option.starts_with('-') {
                    return None;
                }

                paths.push((*option).to_owned());
                continue;
            };

            match Backend::named(name) {
                Some(named) if backend.is_none() => backend = Some(named),
                Some(_) => return None,
                None if name.is_empty() => return None,
                None => flags.push(name.to_owned()),
            }
        }

        Some(Test {
            backend: backend.unwrap_or(Backend::Plugin),
            flags,
            paths,
        })
    }
}

struct Ran {
    results: Value,
    sources: Sources,
}

#[derive(Debug, PartialEq)]
enum Command {
    Test(Test),
    PluginInstall,
    PluginUninstall,
    Help,
    Version,
}

impl Command {
    /// None when the arguments ask for nothing litmus knows
    fn parse(arguments: &[impl AsRef<str>]) -> Option<Command> {
        let words: Vec<&str> = arguments.iter().map(AsRef::as_ref).collect();

        match words.as_slice() {
            ["test", options @ ..] => Test::parse(options).map(Command::Test),
            ["plugin", "install"] => Some(Command::PluginInstall),
            ["plugin", "uninstall"] => Some(Command::PluginUninstall),
            ["--help" | "-h"] => Some(Command::Help),
            ["--version" | "-V"] => Some(Command::Version),
            _ => None,
        }
    }

    /// False only when tests ran and didn't all pass
    fn run(self) -> Result<bool, String> {
        match self {
            Command::Test(asked) => test(&asked),
            Command::PluginInstall => plugin::install().and(Ok(true)),
            Command::PluginUninstall => plugin::uninstall().and(Ok(true)),
            Command::Help => {
                print!("{HELP}");
                Ok(true)
            }
            Command::Version => {
                println!("litmus {VERSION}");
                Ok(true)
            }
        }
    }
}

fn main() -> ExitCode {
    let arguments: Vec<String> = env::args().skip(1).collect();

    let Some(command) = Command::parse(&arguments) else {
        eprint!("{HELP}");
        return ExitCode::from(2);
    };

    // Failing tests exit with 1 and a command that couldn't be carried out with 2, so a script can tell the two apart
    match command.run() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::from(1),
        Err(message) => {
            eprintln!("litmus: {message}");
            ExitCode::from(2)
        }
    }
}

/// Whether every spec loaded and every test passed
fn test(asked: &Test) -> Result<bool, String> {
    let project_dir = Path::new(".");

    if asked.backend != Backend::Standalone
        && let Some(flag) = asked.flags.first()
    {
        return Err(format!(
            "--{flag} isn't an option of litmus; a flag of the project's own goes with --standalone"
        ));
    }

    let selection = Selection::of(&asked.paths)?;

    let ran = match asked.backend {
        Backend::Standalone => run_standalone(project_dir, &asked.flags, &selection)?,
        Backend::Plugin | Backend::Cloud => run_in_place(project_dir, &asked.backend, &selection)?,
    };

    let run: Run = serde_json::from_value(ran.results)
        .map_err(|error| format!("couldn't read the results, so the project's lib may not match this CLI: {error}"))?;

    // Asked of stdout alone, so output sent to a file or another program is never wrapped
    let columns = terminal_size_of(io::stdout()).map(|(Width(columns), _)| usize::from(columns));

    anstream::print!("{}", report::render(&run, &ran.sources, columns));

    Ok(Tally::of(&run.specs).passed())
}

fn run_standalone(project_dir: &Path, flags: &[String], selection: &Selection) -> Result<Ran, String> {
    let runtime = Config::read(project_dir)?.standalone()?;

    Ok(Ran {
        results: standalone::run(project_dir, &runtime, flags, selection)?,
        sources: Sources::Disk,
    })
}

fn run_in_place(project_dir: &Path, backend: &Backend, selection: &Selection) -> Result<Ran, String> {
    let config = Config::read(project_dir)?;
    let rojo_project = config.rojo_project();

    let mut manifest = Manifest::read(project_dir, rojo_project.as_deref())?;
    if manifest.specs().is_empty() {
        return Err("the project has no .spec files".to_owned());
    }

    manifest.narrow(selection)?;

    let results = match backend {
        Backend::Cloud => {
            let place = config.cloud()?;
            cloud::run(project_dir, &manifest, &place, rojo_project.as_deref())?
        }
        _ => run_with_plugin(&manifest)?,
    };

    Ok(Ran {
        results,
        sources: Sources::of(&manifest),
    })
}

/// The results as the lib wrote them, from whichever open place holds the project
fn run_with_plugin(manifest: &Manifest) -> Result<Value, String> {
    let server = Server::open()?;
    eprintln!("litmus: waiting for Studio on port {}", server.port());

    let outcome = server.serve(manifest, Timeouts::default(), |place| {
        eprintln!("litmus: running in {place}");
    })?;

    match outcome {
        Outcome::Results(results) => Ok(results),
        Outcome::Failed { place, message } => Err(format!("{place} couldn't run the tests: {message}")),
        Outcome::Abandoned { place } => Err(format!("{place} took the run and never reported back")),
        Outcome::Unclaimed(mismatches) => Err(report::unclaimed(&mismatches)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_on(backend: Backend, flags: &[&str]) -> Option<Command> {
        test_of(backend, flags, &[])
    }

    fn test_of(backend: Backend, flags: &[&str], paths: &[&str]) -> Option<Command> {
        Some(Command::Test(Test {
            backend,
            flags: flags.iter().map(|flag| (*flag).to_owned()).collect(),
            paths: paths.iter().map(|path| (*path).to_owned()).collect(),
        }))
    }

    #[test]
    fn reads_each_command() {
        assert_eq!(Command::parse(&["test"]), test_on(Backend::Plugin, &[]));
        assert_eq!(Command::parse(&["plugin", "install"]), Some(Command::PluginInstall));
        assert_eq!(Command::parse(&["plugin", "uninstall"]), Some(Command::PluginUninstall));
        assert_eq!(Command::parse(&["--help"]), Some(Command::Help));
        assert_eq!(Command::parse(&["-h"]), Some(Command::Help));
        assert_eq!(Command::parse(&["--version"]), Some(Command::Version));
        assert_eq!(Command::parse(&["-V"]), Some(Command::Version));
    }

    #[test]
    fn refuses_anything_else() {
        assert_eq!(Command::parse(&[] as &[&str]), None);
        assert_eq!(Command::parse(&["run"]), None);
        assert_eq!(Command::parse(&["plugin"]), None);
    }

    #[test]
    fn reads_the_paths_a_test_run_names() {
        assert_eq!(Command::parse(&["test", "tests/deep"]), test_of(Backend::Plugin, &[], &["tests/deep"]));
        assert_eq!(
            Command::parse(&["test", "a.spec.luau", "--standalone", "--coverage", "tests"]),
            test_of(Backend::Standalone, &["coverage"], &["a.spec.luau", "tests"])
        );
    }

    #[test]
    fn reads_the_backend_a_test_run_names() {
        assert_eq!(Command::parse(&["test", "--plugin"]), test_on(Backend::Plugin, &[]));
        assert_eq!(Command::parse(&["test", "--cloud"]), test_on(Backend::Cloud, &[]));
        assert_eq!(Command::parse(&["test", "--standalone"]), test_on(Backend::Standalone, &[]));
    }

    #[test]
    fn keeps_any_other_flag_for_the_project() {
        assert_eq!(
            Command::parse(&["test", "--coverage", "--standalone", "--full-trace"]),
            test_on(Backend::Standalone, &["coverage", "full-trace"])
        );
        assert_eq!(Command::parse(&["test", "--backend"]), test_on(Backend::Plugin, &["backend"]));
    }

    #[test]
    fn refuses_options_that_do_not_add_up() {
        assert_eq!(Command::parse(&["test", "--cloud", "--standalone"]), None);
        assert_eq!(Command::parse(&["test", "--plugin", "--plugin"]), None);
        assert_eq!(Command::parse(&["test", "-c"]), None);
        assert_eq!(Command::parse(&["test", "--"]), None);
    }

    #[test]
    fn a_flag_of_the_project_only_goes_with_a_standalone_run() {
        let asked = Test {
            backend: Backend::Cloud,
            flags: vec!["coverage".to_owned()],
            paths: vec![],
        };

        let problem = test(&asked).unwrap_err();

        assert!(problem.contains("--coverage") && problem.contains("--standalone"), "{problem}");
    }
}
