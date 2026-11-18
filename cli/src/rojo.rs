use std::ffi::OsStr;
use std::path::Path;
use std::process::Command;

pub fn run(project_dir: &Path, subcommand: &str, rojo_project: Option<&Path>, options: &[&OsStr]) -> Result<Vec<u8>, String> {
    let output = Command::new("rojo")
        .arg(subcommand)
        .args(rojo_project)
        .args(options)
        .current_dir(project_dir)
        .output()
        .map_err(|error| format!("couldn't run rojo: {error}"))?;

    if !output.status.success() {
        let reason = String::from_utf8_lossy(&output.stderr);
        return Err(format!("rojo {subcommand} failed: {}", reason.trim()));
    }

    Ok(output.stdout)
}
