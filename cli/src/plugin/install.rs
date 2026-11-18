use std::env;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

const PLUGIN: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/plugin.rbxm"));

const FILE_NAME: &str = "LitmusManagedPlugin.rbxm";

pub fn install() -> Result<(), String> {
    let file = install_into(&plugins_folder()?)?;
    println!("litmus: installed the plugin at {}", file.display());

    Ok(())
}

pub fn uninstall() -> Result<(), String> {
    let folder = plugins_folder()?;

    if uninstall_from(&folder)? {
        println!("litmus: removed the plugin from {}", folder.display());
    } else {
        println!("litmus: the plugin isn't installed in {}", folder.display());
    }

    Ok(())
}

fn install_into(folder: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(folder).map_err(|error| format!("couldn't create {}: {error}", folder.display()))?;

    let file = folder.join(FILE_NAME);
    fs::write(&file, PLUGIN).map_err(|error| format!("couldn't write {}: {error}", file.display()))?;

    Ok(file)
}

fn uninstall_from(folder: &Path) -> Result<bool, String> {
    let file = folder.join(FILE_NAME);

    match fs::remove_file(&file) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
        Err(error) => Err(format!("couldn't remove {}: {error}", file.display())),
    }
}

#[cfg(target_os = "windows")]
fn plugins_folder() -> Result<PathBuf, String> {
    let local = env::var_os("LOCALAPPDATA")
        .ok_or("couldn't find Studio's plugins folder, since LOCALAPPDATA isn't set")?;

    Ok(PathBuf::from(local).join("Roblox").join("Plugins"))
}

#[cfg(target_os = "macos")]
fn plugins_folder() -> Result<PathBuf, String> {
    let home = env::var_os("HOME").ok_or("couldn't find Studio's plugins folder, since HOME isn't set")?;

    Ok(PathBuf::from(home).join("Documents").join("Roblox").join("Plugins"))
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
fn plugins_folder() -> Result<PathBuf, String> {
    Err("Roblox Studio only runs on Windows and macOS, so there is nowhere to put its plugin".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(name: &str) -> PathBuf {
        env::temp_dir().join(format!("litmus-{}-{name}", std::process::id())).join("Plugins")
    }

    #[test]
    fn carries_a_binary_model() {
        assert!(PLUGIN.starts_with(b"<roblox!"));
    }

    #[test]
    fn installs_into_a_folder_that_is_not_there_yet() {
        let folder = folder("installs");
        let file = install_into(&folder).unwrap();
        let written = fs::read(&file).unwrap();
        fs::remove_dir_all(folder.parent().unwrap()).unwrap();

        assert_eq!(file, folder.join(FILE_NAME));
        assert!(written == PLUGIN);
    }

    #[test]
    fn uninstalls_only_what_is_installed() {
        let folder = folder("uninstalls");
        install_into(&folder).unwrap();

        let first = uninstall_from(&folder);
        let second = uninstall_from(&folder);
        let left = folder.join(FILE_NAME).exists();
        fs::remove_dir_all(folder.parent().unwrap()).unwrap();

        assert_eq!(first, Ok(true));
        assert_eq!(second, Ok(false));
        assert!(!left);
    }
}
