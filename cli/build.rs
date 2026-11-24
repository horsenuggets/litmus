use std::env;
use std::path::Path;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=../plugin");
    println!("cargo:rerun-if-changed=../plugin.project.json");

    let out_dir = env::var_os("OUT_DIR").expect("cargo sets OUT_DIR for build scripts");
    let plugin = Path::new(&out_dir).join("plugin.rbxm");

    let status = Command::new("rojo")
        .args(["build", "../plugin.project.json", "--output"])
        .arg(&plugin)
        .status()
        .expect("couldn't run rojo, which builds the plugin; is it installed? Try `rokit install`");

    assert!(status.success(), "rojo couldn't build the plugin");
}
