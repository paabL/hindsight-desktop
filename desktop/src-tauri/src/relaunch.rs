use std::path::{Path, PathBuf};
use tauri::Manager;

pub fn bundle_for_executable(executable: &Path) -> Option<PathBuf> {
    let macos = executable.parent()?;
    let contents = macos.parent()?;
    let bundle = contents.parent()?;
    (macos.file_name()? == "MacOS" && contents.file_name()? == "Contents"
        && bundle.extension()? == "app").then(|| bundle.to_path_buf())
}

pub fn restart(app: &tauri::AppHandle) -> Result<(), String> {
    use std::os::unix::process::CommandExt;
    let executable = std::env::current_exe().map_err(|_| "UPDATE_RESTART_FAILED")?;
    let bundle = bundle_for_executable(&executable).ok_or("UPDATE_RESTART_FAILED")?;
    let helper = app.path().resource_dir().map_err(|_| "UPDATE_RESTART_FAILED")?.join("native/HindsightBridge");
    // Independent of the bridge process and event loop: wait for this GUI to exit,
    // then open the installed .app through LaunchServices without forcing -n.
    std::process::Command::new(helper)
        .arg("--relaunch-after").arg(std::process::id().to_string())
        .arg("--bundle").arg(&bundle)
        .stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null()).process_group(0)
        .spawn().map_err(|_| "UPDATE_RESTART_FAILED")?;
    // Quitting inside the command could drop its reply: the page would then report a failed
    // installation although the new version is in place. Answer first, then quit; the helper
    // reopens the app only once this process is gone, so a stalled exit is forced.
    let handle = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(500));
        handle.exit(0);
        std::thread::sleep(std::time::Duration::from_secs(5));
        std::process::exit(0);
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn restart_uses_the_bundle_root_not_a_binary_or_an_updater_staging_path() {
        assert_eq!(bundle_for_executable(Path::new("/Applications/Hindsight Desktop.app/Contents/MacOS/hindsight-desktop")),
            Some(PathBuf::from("/Applications/Hindsight Desktop.app")));
        for path in ["/tmp/hindsight-desktop", "/Applications/Hindsight Desktop.app/Contents/Resources/HindsightBridge", "/Applications/Fake/Contents/MacOS/app"] {
            assert_eq!(bundle_for_executable(Path::new(path)), None);
        }
    }
}
