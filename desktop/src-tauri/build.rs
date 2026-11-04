use std::process::Command;
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize().unwrap();
    let commit = std::env::var("HINDSIGHT_RELEASE_COMMIT").ok().unwrap_or_else(|| Command::new("/usr/bin/git").args(["rev-parse", "HEAD"]).current_dir(&root).output()
        .ok().filter(|o| o.status.success()).map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned()).unwrap_or_default()
    );
    // Une distribution publique ne pointe jamais sur le dossier privé de sa construction.
    let source = if std::env::var_os("HINDSIGHT_DISTRIBUTION_BUILD").is_some() { String::new() } else { root.display().to_string() };
    println!("cargo:rustc-env=HINDSIGHT_BUILD_SOURCE={}", source);
    println!("cargo:rustc-env=HINDSIGHT_BUILD_COMMIT={}", commit);
    println!("cargo:rerun-if-changed={}", root.join(".git/HEAD").display());
    println!("cargo:rerun-if-changed={}", root.join(".git/refs").display());
    println!("cargo:rerun-if-changed={}", root.join(".git/packed-refs").display());
    println!("cargo:rerun-if-env-changed=HINDSIGHT_DISTRIBUTION_BUILD");
    println!("cargo:rerun-if-env-changed=HINDSIGHT_RELEASE_COMMIT");
    tauri_build::build()
}
