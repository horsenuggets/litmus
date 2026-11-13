mod manifest;
mod report;
mod results;
mod server;

use manifest::Manifest;
use results::{SpecResult, Tally};
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

Options:
  -h, --help          Print this help
  -V, --version       Print the version
";

#[derive(Debug, PartialEq)]
enum Command {
    Test,
    Help,
    Version,
}

impl Command {
    /// None when the arguments ask for nothing litmus knows
    fn parse(arguments: &[impl AsRef<str>]) -> Option<Command> {
        let words: Vec<&str> = arguments.iter().map(AsRef::as_ref).collect();

        match words.as_slice() {
            ["test"] => Some(Command::Test),
            ["--help" | "-h"] => Some(Command::Help),
            ["--version" | "-V"] => Some(Command::Version),
            _ => None,
        }
    }

    /// False only when tests ran and didn't all pass
    fn run(self) -> Result<bool, String> {
        match self {
            Command::Test => test(),
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
fn test() -> Result<bool, String> {
    let manifest = Manifest::read(Path::new("."))?;
    if manifest.specs().is_empty() {
        return Err("the project has no .spec files".to_owned());
    }

    let server = Server::open()?;
    eprintln!("litmus: waiting for Studio on port {}", server.port());

    let outcome = server.serve(&manifest, Timeouts::default(), |place| {
        eprintln!("litmus: running in {place}");
    })?;

    match outcome {
        Outcome::Results(results) => {
            let results: Vec<SpecResult> = serde_json::from_value(results).map_err(|error| {
                format!("couldn't read the results, so the place's lib may not match this CLI: {error}")
            })?;

            // Asked of stdout alone, so output sent to a file or another program is never wrapped
            let columns = terminal_size_of(io::stdout()).map(|(Width(columns), _)| usize::from(columns));

            anstream::print!("{}", report::render(&results, &manifest, columns));

            Ok(Tally::of(&results).passed())
        }
        Outcome::Failed { place, message } => {
            Err(format!("{place} couldn't run the tests: {message}"))
        }
        Outcome::Abandoned { place } => Err(format!("{place} took the run and never reported back")),
        Outcome::Unclaimed(mismatches) => Err(report::unclaimed(&mismatches)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_each_command() {
        assert_eq!(Command::parse(&["test"]), Some(Command::Test));
        assert_eq!(Command::parse(&["--help"]), Some(Command::Help));
        assert_eq!(Command::parse(&["-h"]), Some(Command::Help));
        assert_eq!(Command::parse(&["--version"]), Some(Command::Version));
        assert_eq!(Command::parse(&["-V"]), Some(Command::Version));
    }

    #[test]
    fn refuses_anything_else() {
        assert_eq!(Command::parse(&[] as &[&str]), None);
        assert_eq!(Command::parse(&["run"]), None);
        assert_eq!(Command::parse(&["test", "extra"]), None);
    }
}
