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

const USAGE: &str = "usage: litmus run";

fn main() -> ExitCode {
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments != ["run"] {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    }

    match run() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::from(1),
        Err(message) => {
            eprintln!("litmus: {message}");
            ExitCode::from(2)
        }
    }
}

/// Whether every spec loaded and every test passed
fn run() -> Result<bool, String> {
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
