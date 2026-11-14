mod cloud;
mod manifest;
mod plugin;
mod report;
mod results;
mod server;

use manifest::Manifest;
use results::{SpecResult, Tally};
use serde_json::Value;
use server::{Outcome, Server, Timeouts};
use std::env;
use std::io;
use std::path::Path;
use std::process::ExitCode;
use terminal_size::{Width, terminal_size_of};

const VERSION: &str = env!("CARGO_PKG_VERSION");

const HELP: &str = "\
Runs a project's tests in Roblox Studio

Usage: litmus <command>

Commands:
  test                Run the project's .spec files in an open Studio place
  plugin install      Install the Studio plugin, replacing any copy installed before
  plugin uninstall    Remove the Studio plugin

Options for test:
  --cloud             Run in Roblox's cloud instead of Studio, under the API key in LITMUS_API_KEY
  --universe <id>     The experience to run in, with --cloud
  --place <id>        Its place to build the project into, as a new unpublished version, with --cloud

Options:
  -h, --help          Print this help
  -V, --version       Print the version
";

#[derive(Debug, PartialEq)]
enum Target {
    Studio,
    Cloud(cloud::Place),
}

impl Target {
    /// None when the options don't add up to one place to run in
    fn parse(options: &[&str]) -> Option<Target> {
        let mut in_cloud = false;
        let mut universe = None;
        let mut place = None;

        let mut options = options.iter();
        while let Some(option) = options.next() {
            match *option {
                "--cloud" => in_cloud = true,
                "--universe" => universe = Some(options.next()?.parse().ok()?),
                "--place" => place = Some(options.next()?.parse().ok()?),
                _ => return None,
            }
        }

        match (in_cloud, universe, place) {
            (false, None, None) => Some(Target::Studio),
            (true, Some(universe), Some(place)) => Some(Target::Cloud(cloud::Place { universe, place })),
            _ => None,
        }
    }
}

#[derive(Debug, PartialEq)]
enum Command {
    Test(Target),
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
            ["test", options @ ..] => Target::parse(options).map(Command::Test),
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
            Command::Test(target) => test(&target),
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
fn test(target: &Target) -> Result<bool, String> {
    let project_dir = Path::new(".");

    let manifest = Manifest::read(project_dir)?;
    if manifest.specs().is_empty() {
        return Err("the project has no .spec files".to_owned());
    }

    let results = match target {
        Target::Studio => run_in_studio(&manifest)?,
        Target::Cloud(place) => cloud::run(project_dir, &manifest, place)?,
    };

    let results: Vec<SpecResult> = serde_json::from_value(results)
        .map_err(|error| format!("couldn't read the results, so the place's lib may not match this CLI: {error}"))?;

    // Asked of stdout alone, so output sent to a file or another program is never wrapped
    let columns = terminal_size_of(io::stdout()).map(|(Width(columns), _)| usize::from(columns));

    anstream::print!("{}", report::render(&results, &manifest, columns));

    Ok(Tally::of(&results).passed())
}

/// The results as the lib wrote them, from whichever open place holds the project
fn run_in_studio(manifest: &Manifest) -> Result<Value, String> {
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

    #[test]
    fn reads_each_command() {
        assert_eq!(Command::parse(&["test"]), Some(Command::Test(Target::Studio)));
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
        assert_eq!(Command::parse(&["test", "extra"]), None);
    }

    #[test]
    fn reads_where_a_cloud_run_happens() {
        let cloud = Some(Command::Test(Target::Cloud(cloud::Place {
            universe: 11,
            place: 22,
        })));

        assert_eq!(Command::parse(&["test", "--cloud", "--universe", "11", "--place", "22"]), cloud);
        assert_eq!(Command::parse(&["test", "--place", "22", "--universe", "11", "--cloud"]), cloud);
    }

    #[test]
    fn refuses_a_cloud_run_it_could_not_place() {
        assert_eq!(Command::parse(&["test", "--cloud"]), None);
        assert_eq!(Command::parse(&["test", "--cloud", "--universe", "11"]), None);
        assert_eq!(Command::parse(&["test", "--cloud", "--universe", "11", "--place"]), None);
        assert_eq!(Command::parse(&["test", "--cloud", "--universe", "eleven", "--place", "22"]), None);
        assert_eq!(Command::parse(&["test", "--universe", "11", "--place", "22"]), None);
    }
}
