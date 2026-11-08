use std::{path::Path, time::Duration};

use serde_json::{json, Value};
use tauri::State;
use tauri_plugin_updater::{Update, UpdaterExt};
use tokio::sync::Mutex;

use crate::{bridge_call, BridgeState, NativeBridge};

#[derive(Default)]
pub struct ReleaseUpdateState(Mutex<Option<Update>>);

// The webview can select a checked version, never its source or verification key.
#[tauri::command]
pub async fn release_update_check(
    app: tauri::AppHandle,
    state: State<'_, ReleaseUpdateState>,
) -> Result<Option<Value>, String> {
    let mut pending = state.0.try_lock().map_err(|_| "UPDATE_BUSY")?;
    // A failed or empty check must not leave a previous offer installable.
    *pending = None;
    let updater = app
        .updater_builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|_| "UPDATE_CHECK_FAILED")?;
    let update = updater.check().await.map_err(|_| "UPDATE_CHECK_FAILED")?;
    if let Some(mut update) = update {
        if !trusted_download(&update.download_url, &update.version) {
            return Err("UPDATE_UNTRUSTED_SOURCE".into());
        }
        // The short feed-check deadline must not also limit the archive download.
        update.timeout = Some(Duration::from_secs(5 * 60));
        let metadata = json!({ "version": update.version, "body": update.body });
        *pending = Some(update);
        Ok(Some(metadata))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn release_update_install(
    app: tauri::AppHandle,
    state: State<'_, ReleaseUpdateState>,
    bridge: State<'_, BridgeState>,
    version: String,
) -> Result<(), String> {
    let result = install_release(&app, &state, &bridge, &version).await;
    if let Err(error) = &result {
        record_failure(&app, &version, error);
    }
    result
}

async fn install_release(
    app: &tauri::AppHandle,
    state: &ReleaseUpdateState,
    bridge: &BridgeState,
    version: &str,
) -> Result<(), String> {
    let mut pending = state.0.try_lock().map_err(|_| "UPDATE_BUSY")?;
    // Do not interrupt a native request. Holding this guard also prevents a new
    // bridge operation from beginning between replacement and restart.
    let mut bridge_guard = bridge.0.try_lock().map_err(|_| "UPDATE_BUSY")?;
    let executable = std::env::current_exe()
        .and_then(|path| path.canonicalize())
        .map_err(|_| "UPDATE_MOVE_TO_APPLICATIONS")?;
    if !install_location_allowed(&executable) {
        return Err("UPDATE_MOVE_TO_APPLICATIONS".into());
    }
    if let Err(error) = selected_version(pending.as_ref().map(|u| u.version.as_str()), version) {
        *pending = None;
        return Err(error.into());
    }
    require_idle_bridge(app, &mut bridge_guard).await?;
    let update = pending.take().ok_or("UPDATE_NOT_AVAILABLE")?;
    if !trusted_download(&update.download_url, version) {
        return Err("UPDATE_UNTRUSTED_SOURCE".into());
    }
    // The plugin verifies the package signature and its signed version before
    // modifying the application. A failed installation never triggers restart.
    let bytes = update
        .download(|_, _| {}, || {})
        .await
        .map_err(|error| download_error(&error))?;
    // Detached native work may have started during the download. Refuse to
    // replace/restart until it finishes; a readiness failure is never a bypass.
    require_idle_bridge(app, &mut bridge_guard).await?;
    match crate::macos_install::install(app, &update, &bytes, &executable) {
        Ok(()) => {}
        // Keep the existing OS authorization flow for administrator-owned apps.
        // Its whole-bundle swap is followed by the same waited relaunch and legacy
        // shortcut repair; other failures never bypass the preserving installer.
        Err(code) if code == "UPDATE_ADMIN_REQUIRED" => update.install(&bytes).map_err(|error| install_error(&error))?,
        Err(error) => return Err(error),
    }
    crate::relaunch::restart(app)?;
    Ok(())
}

async fn require_idle_bridge(
    app: &tauri::AppHandle,
    bridge: &mut Option<NativeBridge>,
) -> Result<(), String> {
    let ready = bridge_call(app, json!({ "command": "updates.releaseReady" }), bridge)
        .await
        .map_err(|_| "UPDATE_BUSY")?;
    if ready.get("releaseUpdateReady").and_then(Value::as_bool) != Some(true) {
        return Err("UPDATE_BUSY".into());
    }
    Ok(())
}

fn selected_version(offered: Option<&str>, selected: &str) -> Result<(), &'static str> {
    match offered {
        Some(version) if version == selected => Ok(()),
        Some(_) => Err("UPDATE_VERSION_CHANGED"),
        None => Err("UPDATE_NOT_AVAILABLE"),
    }
}

fn install_location_allowed(executable: &Path) -> bool {
    let is_bundle = executable.parent().is_some_and(|macos| {
        macos.file_name().is_some_and(|name| name == "MacOS")
            && macos.parent().is_some_and(|contents| {
                contents.file_name().is_some_and(|name| name == "Contents")
                    && contents.parent().is_some_and(|bundle| {
                        bundle
                            .extension()
                            .is_some_and(|extension| extension == "app")
                    })
            })
    });
    is_bundle
        && !executable.starts_with("/Volumes")
        && !executable
            .components()
            .any(|part| part.as_os_str() == "AppTranslocation")
}

fn trusted_download(url: &tauri::Url, version: &str) -> bool {
    if url.scheme() != "https"
        || url.host_str() != Some("github.com")
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port_or_known_default() != Some(443)
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return false;
    }
    let prefix = format!("/paabL/hindsight-desktop/releases/download/v{version}/");
    let Some(filename) = url.path().strip_prefix(&prefix) else {
        return false;
    };
    !filename.contains('/') && filename.ends_with(".app.tar.gz")
}

// Each code names a cause the app explains in plain words; the detail after it is
// only recorded in the update log, never shown.
fn install_error(error: &tauri_plugin_updater::Error) -> String {
    use tauri_plugin_updater::Error;
    match error {
        Error::Minisign(_)
        | Error::Base64(_)
        | Error::SignatureUtf8(_)
        | Error::MissingSignedVersion
        | Error::SignedVersionMismatch { .. }
        | Error::InsecureTransportProtocol => "UPDATE_UNTRUSTED_SOURCE".into(),
        Error::Io(io) => format!("{}: {error}", crate::macos_install::io_code(io)),
        _ => format!("UPDATE_INSTALL_FAILED: {error}"),
    }
}

fn download_error(error: &tauri_plugin_updater::Error) -> String {
    use tauri_plugin_updater::Error;
    match error {
        Error::Reqwest(_) | Error::Network(_) => format!("UPDATE_DOWNLOAD_FAILED: {error}"),
        _ => install_error(error),
    }
}

/// The app shows a plain message; the full cause stays on this Mac, in
/// ~/Library/Logs/local.hindsight.desktop.tauri/updates.log.
fn record_failure(app: &tauri::AppHandle, version: &str, error: &str) {
    use std::io::Write;
    use tauri::Manager;
    let Ok(folder) = app.path().app_log_dir() else {
        return;
    };
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or_default();
    let line = format!(
        "{} {} -> {version}: {error}\n",
        utc_timestamp(seconds),
        app.package_info().version
    );
    let _ = std::fs::create_dir_all(&folder).and_then(|()| {
        std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(folder.join("updates.log"))?
            .write_all(line.as_bytes())
    });
}

/// RFC 3339 UTC time without a date library (civil-from-days, H. Hinnant).
fn utc_timestamp(seconds: u64) -> String {
    let days = (seconds / 86_400) as i64;
    let time = seconds % 86_400;
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        time / 3_600,
        time % 3_600 / 60,
        time % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;

    #[test]
    fn installation_requires_the_offer_selected_by_the_user() {
        assert_eq!(selected_version(None, "0.1.3"), Err("UPDATE_NOT_AVAILABLE"));
        assert_eq!(
            selected_version(Some("0.1.4"), "0.1.3"),
            Err("UPDATE_VERSION_CHANGED")
        );
        assert!(selected_version(Some("0.1.3"), "0.1.3").is_ok());
    }

    #[test]
    fn disk_image_and_translocated_copies_cannot_replace_themselves() {
        for path in [
            "/Volumes/Hindsight Desktop/Hindsight Desktop.app/Contents/MacOS/hindsight-desktop",
            "/private/var/folders/test/AppTranslocation/ABC/d/Hindsight Desktop.app/Contents/MacOS/hindsight-desktop",
            "/Users/example/hindsight-mac/desktop/src-tauri/target/debug/hindsight-desktop",
            "/Applications/Hindsight Desktop.app/Contents/Resources/hindsight-desktop",
        ] {
            assert!(!install_location_allowed(Path::new(path)));
        }
        assert!(install_location_allowed(Path::new(
            "/Applications/Hindsight Desktop.app/Contents/MacOS/hindsight-desktop"
        )));
        assert!(install_location_allowed(Path::new(
            "/Users/example/Applications/Hindsight Desktop.app/Contents/MacOS/hindsight-desktop"
        )));
    }

    #[test]
    fn download_is_confined_to_the_official_versioned_github_asset() {
        let good = "https://github.com/paabL/hindsight-desktop/releases/download/v0.1.3/Hindsight-Desktop_0.1.3_macOS-Apple-Silicon.app.tar.gz";
        assert!(trusted_download(&good.parse().unwrap(), "0.1.3"));
        for bad in [
            good.replace("https://", "http://"),
            good.replace("github.com", "github.com.example.org"),
            good.replace("github.com/", "github.com:8443/"),
            good.replace("github.com/", "user@github.com/"),
            good.replace("paabL", "another-owner"),
            good.replace("v0.1.3/", "v0.1.2/"),
            good.replace(".app.tar.gz", ".dmg"),
            format!("{good}?download=1"),
            format!("{good}#fragment"),
        ] {
            assert!(!trusted_download(&bad.parse().unwrap(), "0.1.3"), "{bad}");
        }
    }

    // Public test vector from tauri-plugin-updater 2.14.1 (MIT OR Apache-2.0).
    // The private throwaway key is not included. The signed payload is b"test".
    const TEST_PUBLIC_KEY: &str = "untrusted comment: minisign public key: A49EF4746FA6E6D7\nRWTX5qZvdPSepDGWg2bz8n6ArQnBMwgQK1geVosorcbLzcunD+KJ+cYe";
    const TEST_SIGNATURE: &str = "untrusted comment: signature from tauri secret key\nRUTX5qZvdPSepPF2zsjvP/L/TQtBLRnWRvaq+4omK1UEugtQp/USrGiI1v762sDy3id3aor7bRC9ETyeot6lMHHrWoZ5hjUM1Qc=\ntrusted comment: timestamp:1791649051\tfile:payload\tversion:2.0.0\nDDq2CLOEl5cQmC2eJRHlnZPVViOZsu1CjpPKQoei4A/XBfkDqGO0B+QMrcrHgEQ5qV3mne75tdFWhJpqUXh9AA==";

    fn signed_offer(version: &str) -> Update {
        let encode = |text: &str| base64::engine::general_purpose::STANDARD.encode(text);
        let mut context = tauri::test::mock_context(tauri::test::noop_assets());
        context.config_mut().plugins.0.insert(
            "updater".into(),
            json!({ "pubkey": encode(TEST_PUBLIC_KEY), "requireSignedVersion": true }),
        );
        let app = tauri::test::mock_builder()
            .plugin(tauri_plugin_updater::Builder::new().build())
            .build(context)
            .unwrap();
        app.updater_builder()
            .pubkey(encode(TEST_PUBLIC_KEY))
            .target("test-target")
            .executable_path("/private/tmp/Hindsight Updater Test.app/Contents/MacOS/test")
            .endpoints(vec!["https://example.invalid/update".parse().unwrap()])
            .unwrap()
            .build()
            .unwrap()
            .restore_update(json!({
                "version": version,
                "platforms": { "test-target": {
                    "url": "https://example.invalid/package.app.tar.gz",
                    "signature": encode(TEST_SIGNATURE)
                }}
            }))
            .unwrap()
            .unwrap()
    }

    #[test]
    fn signed_payload_passes_and_corruption_is_rejected_before_install() {
        let update = signed_offer("2.0.0");
        assert!(update.verify(b"test").is_ok());
        let error = update.install(b"tampered payload").unwrap_err();
        assert_eq!(install_error(&error), "UPDATE_UNTRUSTED_SOURCE");
    }

    #[test]
    fn failures_name_their_cause_and_keep_the_detail_for_the_log() {
        use tauri_plugin_updater::Error;
        let offline = download_error(&Error::Network("Download request failed with status: 503".into()));
        assert!(offline.starts_with("UPDATE_DOWNLOAD_FAILED: "), "{offline}");
        assert!(offline.ends_with("503`"), "{offline}");
        let denied = install_error(&Error::Io(std::io::ErrorKind::PermissionDenied.into()));
        assert!(denied.starts_with("UPDATE_PERMISSION_DENIED: "), "{denied}");
        let full = install_error(&Error::Io(std::io::Error::from_raw_os_error(28)));
        assert!(full.starts_with("UPDATE_DISK_FULL: "), "{full}");
        let other = install_error(&Error::Io(std::io::Error::other("unexpected archive layout")));
        assert_eq!(other, "UPDATE_INSTALL_FAILED: unexpected archive layout");
        // Copies run as commands report the errno only in their message.
        for (message, code) in [
            ("stage bundle: ditto: No space left on device", "UPDATE_DISK_FULL"),
            ("stage bundle: ditto: Operation not permitted", "UPDATE_PERMISSION_DENIED"),
        ] {
            assert_eq!(crate::macos_install::io_code(&std::io::Error::other(message)), code);
        }
    }

    #[test]
    fn update_log_times_are_readable_utc() {
        assert_eq!(utc_timestamp(0), "1970-01-01T00:00:00Z");
        assert_eq!(utc_timestamp(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(utc_timestamp(1_794_095_892), "2026-11-07T23:58:12Z");
    }

    #[test]
    fn validly_signed_package_cannot_be_relabelled_as_another_version() {
        let update = signed_offer("9.0.0");
        let error = update.install(b"test").unwrap_err();
        assert!(matches!(
            error,
            tauri_plugin_updater::Error::SignedVersionMismatch { .. }
        ));
    }

    #[test]
    #[ignore = "Requires the final signed release archive and feed through HINDSIGHT_VERIFY_ARCHIVE/HINDSIGHT_VERIFY_FEED"]
    fn final_release_archive_verifies_and_installs_in_an_isolated_bundle() {
        let archive = std::env::var("HINDSIGHT_VERIFY_ARCHIVE").expect("set archive path");
        let feed = std::env::var("HINDSIGHT_VERIFY_FEED").expect("set feed path");
        let bytes = std::fs::read(archive).unwrap();
        let manifest: Value = serde_json::from_slice(&std::fs::read(feed).unwrap()).unwrap();
        let embedded: Value = serde_json::from_str(include_str!("../tauri.conf.json")).unwrap();
        assert_eq!(embedded["plugins"]["updater"]["requireSignedVersion"], true);

        struct IsolatedFolder(std::path::PathBuf);
        impl Drop for IsolatedFolder {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let folder = IsolatedFolder(std::env::temp_dir().join(format!(
            "hindsight-release-qualification-{}-{unique}",
            std::process::id()
        )));
        let bundle = folder.0.join("Qualification.app");
        let executable = bundle.join("Contents/MacOS/hindsight-desktop");
        std::fs::create_dir_all(executable.parent().unwrap()).unwrap();
        std::fs::write(&executable, b"old executable").unwrap();
        let old_marker = bundle.join("Contents/previous-version-marker");
        std::fs::write(&old_marker, b"previous version").unwrap();
        use std::os::unix::fs::MetadataExt;
        let original_identity = std::fs::metadata(&bundle).unwrap().ino();

        let mut context = tauri::test::mock_context(tauri::test::noop_assets());
        context
            .config_mut()
            .plugins
            .0
            .insert("updater".into(), embedded["plugins"]["updater"].clone());
        let app = tauri::test::mock_builder()
            .plugin(tauri_plugin_updater::Builder::new().build())
            .build(context)
            .unwrap();
        let update = app
            .updater_builder()
            .target("darwin-aarch64")
            .executable_path(&executable)
            .build()
            .unwrap()
            .restore_update(manifest)
            .unwrap()
            .unwrap();
        assert!(trusted_download(&update.download_url, &update.version));
        update.verify(&bytes).unwrap();
        let mut tampered = bytes.clone();
        assert!(!tampered.is_empty());
        tampered[0] ^= 1;
        assert!(crate::macos_install::install(app.handle(), &update, &tampered, &executable).is_err());
        assert_eq!(std::fs::read(&old_marker).unwrap(), b"previous version");
        assert!(!bundle.join("Contents/Info.plist").exists());

        crate::macos_install::install(app.handle(), &update, &bytes, &executable).unwrap();
        assert_eq!(std::fs::metadata(&bundle).unwrap().ino(), original_identity, "The pinned app directory must retain its file identity");
        assert!(!old_marker.exists());
        let version = std::process::Command::new("/usr/libexec/PlistBuddy")
            .args(["-c", "Print :CFBundleShortVersionString"])
            .arg(bundle.join("Contents/Info.plist"))
            .output()
            .unwrap();
        assert!(version.status.success());
        assert_eq!(
            String::from_utf8(version.stdout).unwrap().trim(),
            update.version
        );
        let signature = std::process::Command::new("/usr/bin/codesign")
            .args(["--verify", "--deep", "--strict"])
            .arg(&bundle)
            .output()
            .unwrap();
        assert!(
            signature.status.success(),
            "{}",
            String::from_utf8_lossy(&signature.stderr)
        );
    }
}
