mod manifest;
mod server;

use manifest::Manifest;
use server::{Mismatch, Outcome, Server, Timeouts};
use std::env;
use std::path::Path;
use std::process::ExitCode;

const USAGE: &str = "usage: litmus run";

/// How many of a stale place's files get named before the rest are only counted
const MAX_LISTED: usize = 10;

fn main() -> ExitCode {
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments != ["run"] {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    }

    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("litmus: {message}");
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<(), String> {
    let manifest = Manifest::read(Path::new("."))?;
    if manifest.specs().is_empty() {
        return Err("the project has no .spec files".to_owned());
    }

    let server = Server::open()?;
    eprintln!("litmus: waiting for Studio on port {}", server.port());

    match server.serve(&manifest, Timeouts::default())? {
        Outcome::Results(results) => {
            let text = serde_json::to_string_pretty(&results)
                .map_err(|error| format!("couldn't print the results: {error}"))?;
            println!("{text}");
            Ok(())
        }
        Outcome::Failed { place, message } => {
            Err(format!("{place} couldn't run the tests: {message}"))
        }
        Outcome::Abandoned { place } => Err(format!("{place} took the run and never reported back")),
        Outcome::Unclaimed(mismatches) => Err(describe_unclaimed(&mismatches)),
    }
}

fn describe_unclaimed(mismatches: &[Mismatch]) -> String {
    if mismatches.is_empty() {
        return "no open place holds this project; open it in Studio and switch the Litmus plugin on".to_owned();
    }

    let mut lines = vec!["no open place matches the code on disk; is rojo serving?".to_owned()];

    for mismatch in mismatches {
        lines.push(format!(
            "  {}: {} differ, {} missing",
            mismatch.place,
            mismatch.differing.len(),
            mismatch.missing.len()
        ));

        let paths = mismatch.differing.iter().chain(&mismatch.missing);
        for path in paths.clone().take(MAX_LISTED) {
            lines.push(format!("    {}", path.join(".")));
        }

        let unlisted = paths.count().saturating_sub(MAX_LISTED);
        if unlisted > 0 {
            lines.push(format!("    and {unlisted} more"));
        }
    }

    lines.join("\n")
}
