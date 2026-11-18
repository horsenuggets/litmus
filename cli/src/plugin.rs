mod install;

pub use install::{install, uninstall};

use crate::manifest::Manifest;
use crate::server::{Mismatch, Outcome, Server, Timeouts};
use serde_json::Value;

const MAX_FILES_LISTED: usize = 10;

pub fn run(manifest: &Manifest) -> Result<Value, String> {
    let server = Server::open()?;
    eprintln!("litmus: waiting for Studio on port {}", server.port());

    let outcome = server.offer_run(manifest, Timeouts::default(), |place| {
        eprintln!("litmus: running in {place}");
    })?;

    match outcome {
        Outcome::Results(results) => Ok(results),
        Outcome::Failed { place, message } => Err(format!("{place} couldn't run the tests: {message}")),
        Outcome::Abandoned { place } => Err(format!("{place} took the run and never reported back")),
        Outcome::Unclaimed(mismatches) => Err(unclaimed(&mismatches)),
    }
}

fn unclaimed(mismatches: &[Mismatch]) -> String {
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
        for path in paths.clone().take(MAX_FILES_LISTED) {
            lines.push(format!("    {}", path.join(".")));
        }

        let unlisted = paths.count().saturating_sub(MAX_FILES_LISTED);
        if unlisted > 0 {
            lines.push(format!("    and {unlisted} more"));
        }
    }

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_the_files_a_stale_place_is_behind_on() {
        let mismatches: Vec<Mismatch> = serde_json::from_str(
            r#"[{ "place": "Stale", "missing": [["ReplicatedStorage", "Gone"]], "differing": [["ReplicatedStorage", "Thing.spec"]] }]"#,
        )
        .unwrap();

        let text = unclaimed(&mismatches);

        assert!(text.contains("  Stale: 1 differ, 1 missing\n"), "{text}");
        assert!(text.contains("    ReplicatedStorage.Thing.spec\n    ReplicatedStorage.Gone"), "{text}");
        assert!(unclaimed(&[]).contains("no open place holds this project"));
    }
}
