//! Install into a disposable bundle, then replace only `Contents` so Dock bookmarks
//! keep referring to the original application directory. No application is launched.
#![cfg(target_os = "macos")]

use std::{
    ffi::CString,
    fs, io,
    os::unix::{ffi::OsStrExt, fs::MetadataExt},
    path::{Path, PathBuf},
    process::{Command, Output},
};

use tauri_plugin_updater::{Update, UpdaterExt};
use tempfile::TempDir;

const BUNDLE_ID: &str = "local.hindsight.desktop.tauri";
const BACKUP: &str = "previous-Contents";

/// Verify before any filesystem work; the official updater still verifies and
/// extracts the archive, but can replace only our disposable copy of the bundle.
/// Only `UPDATE_ADMIN_REQUIRED` permits the caller to use the original offer's
/// administrator-capable installer. It means staging passed validation and a
/// permission failure occurred before any move, with the original still intact.
pub fn install<R: tauri::Runtime>(
    app: &tauri::AppHandle<R>,
    offer: &Update,
    bytes: &[u8],
    executable: &Path,
) -> Result<(), String> {
    offer.verify(bytes).map_err(updater_error)?;

    let bundle_path = installed_bundle(executable).map_err(|e| io_error("bundle layout", e))?;
    let original = Bundle::read(&bundle_path).map_err(|e| io_error("installed bundle", e))?;
    let staging = staging_dir(&original).map_err(|e| io_error("create staging", e))?;
    let staged_path = staging.path().join(bundle_path.file_name().unwrap());
    checked_command(
        Command::new("/usr/bin/ditto")
            .arg(&bundle_path)
            .arg(&staged_path),
        "copy installed bundle",
    )
    .map_err(|e| io_error("stage bundle", e))?;

    let filename = executable.file_name().unwrap();
    let staged_executable = staged_path.join("Contents/MacOS").join(filename);
    let staged_offer = app
        .updater_builder()
        .target(offer.target.clone())
        .executable_path(&staged_executable)
        .build()
        .map_err(updater_error)?
        .restore_update(offer.raw_json.clone())
        .map_err(updater_error)?
        .ok_or("UPDATE_NOT_AVAILABLE")?;
    if staged_offer.version != offer.version
        || staged_offer.signature != offer.signature
        || staged_offer.download_url != offer.download_url
    {
        return Err("UPDATE_UNTRUSTED_SOURCE".into());
    }
    staged_offer.install(bytes).map_err(updater_error)?;

    let staged = validate_staged(&staged_path, &offer.version, filename)
        .map_err(|e| io_error("validate staged bundle", e))?;
    let result = commit_contents_with(
        &original,
        &staged,
        &staging.path().join(BACKUP),
        swap_contents,
        |from, to| fs::rename(from, to),
    );
    finish_commit(staging, result)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Identity {
    device: u64,
    inode: u64,
}

impl Identity {
    fn directory(path: &Path) -> io::Result<Self> {
        let metadata = fs::symlink_metadata(path)?;
        if !metadata.is_dir() {
            return Err(invalid("expected a real directory, not a symlink"));
        }
        Ok(Self {
            device: metadata.dev(),
            inode: metadata.ino(),
        })
    }
}

struct Bundle {
    path: PathBuf,
    root: Identity,
    contents: Identity,
}

impl Bundle {
    fn read(path: &Path) -> io::Result<Self> {
        let root = Identity::directory(path)?;
        let contents = Identity::directory(&path.join("Contents"))?;
        if root.device != contents.device {
            return Err(invalid("Contents must be on the application's volume"));
        }
        Ok(Self {
            path: path.to_path_buf(),
            root,
            contents,
        })
    }

    fn unchanged(&self) -> io::Result<()> {
        let now = Self::read(&self.path)?;
        if now.root != self.root || now.contents != self.contents {
            return Err(invalid("bundle identity changed during installation"));
        }
        Ok(())
    }
}

fn installed_bundle(executable: &Path) -> io::Result<PathBuf> {
    let macos = executable
        .parent()
        .ok_or_else(|| invalid("missing MacOS"))?;
    let contents = macos.parent().ok_or_else(|| invalid("missing Contents"))?;
    let bundle = contents.parent().ok_or_else(|| invalid("missing .app"))?;
    if !executable.is_absolute()
        || executable.file_name().is_none()
        || macos.file_name().is_none_or(|name| name != "MacOS")
        || contents.file_name().is_none_or(|name| name != "Contents")
        || bundle
            .extension()
            .is_none_or(|extension| extension != "app")
    {
        return Err(invalid(
            "expected an absolute .app/Contents/MacOS executable",
        ));
    }
    Bundle::read(bundle)?;
    Identity::directory(macos)?;
    if !fs::symlink_metadata(executable)?.is_file() {
        return Err(invalid("expected a regular application executable"));
    }
    bundle.canonicalize()
}

fn staging_dir(original: &Bundle) -> io::Result<TempDir> {
    let mut failure = invalid("no writable staging directory on the application's volume");
    for candidate in [
        Some(std::env::temp_dir()),
        original.path.parent().map(Path::to_path_buf),
    ]
    .into_iter()
    .flatten()
    {
        let attempt = (|| {
            let candidate = candidate.canonicalize()?;
            if Identity::directory(&candidate)?.device != original.root.device {
                return Err(invalid("staging is on a different volume"));
            }
            let staging = tempfile::Builder::new()
                .prefix("hindsight-update-")
                .tempdir_in(candidate)?;
            if Identity::directory(staging.path())?.device != original.root.device {
                return Err(invalid("staging is on a different volume"));
            }
            Ok(staging)
        })();
        match attempt {
            Ok(staging) => return Ok(staging),
            Err(error) => failure = error,
        }
    }
    Err(failure)
}

fn validate_staged(path: &Path, version: &str, executable: &std::ffi::OsStr) -> io::Result<Bundle> {
    let bundle = Bundle::read(path)?;
    Identity::directory(&path.join("Contents/MacOS"))?;
    for file in [
        path.join("Contents/Info.plist"),
        path.join("Contents/MacOS").join(executable),
    ] {
        if !fs::symlink_metadata(file)?.is_file() {
            return Err(invalid(
                "staged metadata and executable must be regular files",
            ));
        }
    }
    let plist = path.join("Contents/Info.plist");
    let executable = executable
        .to_str()
        .ok_or_else(|| invalid("non-UTF-8 executable name"))?;
    for (key, expected) in [
        ("CFBundleIdentifier", BUNDLE_ID),
        ("CFBundleShortVersionString", version),
        ("CFBundleExecutable", executable),
    ] {
        let value = checked_command(
            Command::new("/usr/libexec/PlistBuddy")
                .args(["-c", &format!("Print :{key}")])
                .arg(&plist),
            "read staged Info.plist",
        )?;
        if String::from_utf8(value.stdout)
            .map_err(|_| invalid("invalid plist string"))?
            .trim()
            != expected
        {
            return Err(invalid(&format!("unexpected {key}")));
        }
    }
    checked_command(
        Command::new("/usr/bin/codesign")
            .args(["--verify", "--deep", "--strict"])
            .arg(path),
        "verify staged code signature",
    )?;
    bundle.unchanged()?;
    Ok(bundle)
}

#[derive(Debug)]
enum CommitError {
    Io(io::Error),
    AdminRequired,
    Rollback {
        install: io::Error,
        restore: io::Error,
    },
}

impl From<io::Error> for CommitError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

// Injection is confined to filesystem operations, so inline tests can exercise
// unsupported filesystems and both rollback outcomes without an installed app.
fn commit_contents_with(
    original: &Bundle,
    staged: &Bundle,
    backup: &Path,
    swap: impl FnOnce(&Path, &Path) -> io::Result<()>,
    mut rename: impl FnMut(&Path, &Path) -> io::Result<()>,
) -> Result<(), CommitError> {
    original.unchanged()?;
    staged.unchanged()?;
    if original.root.device != staged.root.device {
        return Err(invalid("staged bundle is on a different volume").into());
    }
    let target = original.path.join("Contents");
    let replacement = staged.path.join("Contents");
    match swap(&target, &replacement) {
        Ok(()) => return Ok(()),
        Err(error) if swap_unsupported(&error) => (),
        Err(error) => return Err(before_move_error(original, error)),
    }
    // Never overwrite a backup, even an empty directory.
    match fs::symlink_metadata(backup) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => (),
        Err(error) => return Err(error.into()),
        Ok(_) => return Err(invalid("rollback path already exists").into()),
    }
    if let Err(error) = rename(&target, backup) {
        return Err(before_move_error(original, error));
    }
    if let Err(install) = rename(&replacement, &target) {
        return match rename(backup, &target) {
            Ok(()) => Err(CommitError::Io(install)),
            Err(restore) => Err(CommitError::Rollback { install, restore }),
        };
    }
    Ok(())
}

fn before_move_error(original: &Bundle, error: io::Error) -> CommitError {
    if error.kind() == io::ErrorKind::PermissionDenied {
        match original.unchanged() {
            Ok(()) => CommitError::AdminRequired,
            Err(changed) => CommitError::Io(changed),
        }
    } else {
        CommitError::Io(error)
    }
}

fn finish_commit(staging: TempDir, result: Result<(), CommitError>) -> Result<(), String> {
    match result {
        // Only now may TempDir remove the original Contents left in staging.
        Ok(()) => Ok(()),
        Err(CommitError::AdminRequired) => Err("UPDATE_ADMIN_REQUIRED".into()),
        Err(CommitError::Io(error)) => Err(io_error("replace Contents", error)),
        Err(CommitError::Rollback { install, restore }) => {
            let recovery = staging.keep().join(BACKUP);
            Err(format!(
                "UPDATE_INSTALL_ROLLBACK_FAILED: {install}; rollback: {restore}; previous Contents preserved at {}",
                recovery.display()
            ))
        }
    }
}

fn swap_unsupported(error: &io::Error) -> bool {
    // Darwin sys/errno.h: ENOTSUP, EOPNOTSUPP, ENOSYS. EINVAL is deliberately
    // excluded: invalid arguments and unrelated I/O errors are not a bypass.
    matches!(error.raw_os_error(), Some(45 | 102 | 78))
}

fn swap_contents(target: &Path, staged: &Path) -> io::Result<()> {
    unsafe extern "C" {
        fn renamex_np(
            from: *const std::ffi::c_char,
            to: *const std::ffi::c_char,
            flags: u32,
        ) -> i32;
    }
    let from = CString::new(staged.as_os_str().as_bytes())?;
    let to = CString::new(target.as_os_str().as_bytes())?;
    // SDK sys/stdio.h: RENAME_SWAP = 0x00000002. Both strings outlive the call;
    // renamex_np only reads them and exchanges the two directory entries.
    if unsafe { renamex_np(from.as_ptr(), to.as_ptr(), 0x00000002) } == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

fn checked_command(command: &mut Command, operation: &str) -> io::Result<Output> {
    let output = command.output()?;
    if !output.status.success() {
        return Err(io::Error::other(format!(
            "{operation}: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    Ok(output)
}

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

/// The failure class the app names in plain words; the full error follows the code.
/// Copies made by commands report their errno only in their message.
pub(crate) fn io_code(error: &io::Error) -> &'static str {
    let message = error.to_string();
    if error.kind() == io::ErrorKind::PermissionDenied
        || message.contains("Operation not permitted")
        || message.contains("Permission denied")
    {
        "UPDATE_PERMISSION_DENIED"
    } else if error.raw_os_error() == Some(28) || message.contains("No space left on device") {
        // Darwin sys/errno.h: ENOSPC.
        "UPDATE_DISK_FULL"
    } else {
        "UPDATE_INSTALL_FAILED"
    }
}

fn io_error(operation: &str, error: io::Error) -> String {
    format!("{}: {operation}: {error}", io_code(&error))
}

fn updater_error(error: tauri_plugin_updater::Error) -> String {
    use tauri_plugin_updater::Error;
    match error {
        Error::Minisign(_)
        | Error::Base64(_)
        | Error::SignatureUtf8(_)
        | Error::MissingSignedVersion
        | Error::SignedVersionMismatch { .. }
        | Error::InsecureTransportProtocol => "UPDATE_UNTRUSTED_SOURCE".into(),
        Error::Io(error) => io_error("official staged installer", error),
        error => format!("UPDATE_INSTALL_FAILED: official staged installer: {error}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;
    use std::{
        ffi::c_void,
        os::unix::fs::{symlink, PermissionsExt},
        ptr,
    };

    fn write_bundle(path: &Path, identifier: &str, version: &str) {
        fs::create_dir_all(path.join("Contents/MacOS")).unwrap();
        let executable = path.join("Contents/MacOS/test");
        fs::write(&executable, format!("synthetic executable {version}")).unwrap();
        fs::set_permissions(executable, fs::Permissions::from_mode(0o755)).unwrap();
        fs::write(
            path.join("Contents/Info.plist"),
            format!(
                r#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>{identifier}</string>
            <key>CFBundleShortVersionString</key><string>{version}</string>
            <key>CFBundleExecutable</key><string>test</string></dict></plist>"#
            ),
        )
        .unwrap();
    }

    struct Fixture {
        _sandbox: TempDir,
        staging: TempDir,
        original: Bundle,
        staged: Bundle,
    }

    impl Fixture {
        fn new() -> Self {
            let sandbox = tempfile::tempdir().unwrap();
            let original = sandbox.path().join("Original.app");
            write_bundle(&original, BUNDLE_ID, "1.0.0");
            let staging = tempfile::tempdir_in(sandbox.path()).unwrap();
            let staged = staging.path().join("Staged.app");
            write_bundle(&staged, BUNDLE_ID, "2.0.0");
            Self {
                original: Bundle::read(&original.canonicalize().unwrap()).unwrap(),
                staged: Bundle::read(&staged.canonicalize().unwrap()).unwrap(),
                staging,
                _sandbox: sandbox,
            }
        }

        fn old_contents(&self) {
            assert_eq!(
                Identity::directory(&self.original.path).unwrap(),
                self.original.root
            );
            assert_eq!(
                Identity::directory(&self.original.path.join("Contents")).unwrap(),
                self.original.contents
            );
            assert_eq!(
                fs::read_to_string(self.original.path.join("Contents/MacOS/test")).unwrap(),
                "synthetic executable 1.0.0"
            );
        }
    }

    // CoreFoundation's CFURL bookmarks are toll-free bridged to Foundation's
    // NSURL bookmarks. Call the real bookmark implementation without Swift,
    // a GUI, a Dock preference write, or a security-scope/access prompt.
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFURLCreateFromFileSystemRepresentation(
            allocator: *const c_void,
            bytes: *const u8,
            length: isize,
            directory: u8,
        ) -> *const c_void;
        fn CFURLCreateBookmarkData(
            allocator: *const c_void,
            url: *const c_void,
            options: usize,
            properties: *const c_void,
            relative: *const c_void,
            error: *mut *const c_void,
        ) -> *const c_void;
        fn CFURLCreateByResolvingBookmarkData(
            allocator: *const c_void,
            data: *const c_void,
            options: usize,
            relative: *const c_void,
            properties: *const c_void,
            stale: *mut u8,
            error: *mut *const c_void,
        ) -> *const c_void;
        fn CFURLGetFileSystemRepresentation(
            url: *const c_void,
            resolve: u8,
            buffer: *mut u8,
            length: isize,
        ) -> u8;
        fn CFRelease(value: *const c_void);
    }

    struct Bookmark(*const c_void);

    impl Bookmark {
        fn new(path: &Path) -> Self {
            let bytes = path.as_os_str().as_bytes();
            // SAFETY: buffers and CF objects live across each call; optional
            // arguments are null, and every Create result is released once.
            unsafe {
                let url = CFURLCreateFromFileSystemRepresentation(
                    ptr::null(),
                    bytes.as_ptr(),
                    bytes.len() as isize,
                    1,
                );
                assert!(!url.is_null());
                let data = CFURLCreateBookmarkData(
                    ptr::null(),
                    url,
                    0,
                    ptr::null(),
                    ptr::null(),
                    ptr::null_mut(),
                );
                CFRelease(url);
                assert!(!data.is_null());
                Self(data)
            }
        }

        fn assert_unchanged(&self, bundle: &Bundle) {
            let mut stale = 1;
            let mut buffer = [0u8; 4096];
            // SAFETY: self owns live bookmark data; output pointers have the
            // SDK's Boolean/CFIndex types. Flags suppress UI and mounting.
            unsafe {
                let url = CFURLCreateByResolvingBookmarkData(
                    ptr::null(),
                    self.0,
                    (1 << 8) | (1 << 9),
                    ptr::null(),
                    ptr::null(),
                    &mut stale,
                    ptr::null_mut(),
                );
                assert!(!url.is_null());
                let success = CFURLGetFileSystemRepresentation(
                    url,
                    1,
                    buffer.as_mut_ptr(),
                    buffer.len() as isize,
                );
                CFRelease(url);
                assert_ne!(success, 0);
            }
            let length = buffer.iter().position(|&byte| byte == 0).unwrap();
            let resolved = Path::new(std::ffi::OsStr::from_bytes(&buffer[..length]));
            assert_eq!(stale, 0, "original Foundation bookmark became stale");
            assert_eq!(resolved.canonicalize().unwrap(), bundle.path);
            assert_eq!(Identity::directory(resolved).unwrap(), bundle.root);
        }
    }

    impl Drop for Bookmark {
        fn drop(&mut self) {
            // SAFETY: this is the one owned Create result, released once.
            unsafe { CFRelease(self.0) };
        }
    }

    #[test]
    fn two_atomic_contents_updates_preserve_app_inode_metadata_and_foundation_bookmark() {
        let fixture = Fixture::new();
        let bookmark = Bookmark::new(&fixture.original.path);
        let outer_metadata = fixture.original.path.join("user-metadata");
        fs::write(&outer_metadata, b"keep outside Contents").unwrap();
        fs::write(
            fixture
                .original
                .path
                .join("Contents/previous-version-marker"),
            b"old",
        )
        .unwrap();
        let result = commit_contents_with(
            &fixture.original,
            &fixture.staged,
            &fixture.staging.path().join(BACKUP),
            swap_contents,
            |a, b| fs::rename(a, b),
        );
        assert!(result.is_ok(), "{result:?}");
        assert_eq!(
            Identity::directory(&fixture.original.path.join("Contents")).unwrap(),
            fixture.staged.contents
        );
        assert_eq!(
            Identity::directory(&fixture.staged.path.join("Contents")).unwrap(),
            fixture.original.contents
        );
        bookmark.assert_unchanged(&fixture.original);
        let staging_path = fixture.staging.path().to_path_buf();
        finish_commit(fixture.staging, result).unwrap();
        assert!(!staging_path.exists());
        assert!(fixture.original.path.join("Contents/MacOS/test").is_file());
        assert!(!fixture
            .original
            .path
            .join("Contents/previous-version-marker")
            .exists());

        let second_staging = tempfile::tempdir_in(fixture._sandbox.path()).unwrap();
        let second_path = second_staging.path().join("Staged.app");
        write_bundle(&second_path, BUNDLE_ID, "3.0.0");
        let current = Bundle::read(&fixture.original.path).unwrap();
        let second = Bundle::read(&second_path).unwrap();
        let result = commit_contents_with(
            &current,
            &second,
            &second_staging.path().join(BACKUP),
            swap_contents,
            |a, b| fs::rename(a, b),
        );
        assert!(result.is_ok(), "{result:?}");
        assert_eq!(
            Identity::directory(&current.path.join("Contents")).unwrap(),
            second.contents
        );
        bookmark.assert_unchanged(&fixture.original);
        finish_commit(second_staging, result).unwrap();
        assert_eq!(
            fs::read_to_string(current.path.join("Contents/MacOS/test")).unwrap(),
            "synthetic executable 3.0.0"
        );
        assert_eq!(fs::read(outer_metadata).unwrap(), b"keep outside Contents");
    }

    #[test]
    fn unsupported_swap_falls_back_without_changing_root_or_bookmark() {
        for code in [45, 102, 78] {
            let fixture = Fixture::new();
            let bookmark = Bookmark::new(&fixture.original.path);
            let backup = fixture.staging.path().join(BACKUP);
            let result = commit_contents_with(
                &fixture.original,
                &fixture.staged,
                &backup,
                |_, _| Err(io::Error::from_raw_os_error(code)),
                |a, b| fs::rename(a, b),
            );
            assert!(result.is_ok(), "{result:?}");
            assert_eq!(
                Identity::directory(&backup).unwrap(),
                fixture.original.contents
            );
            bookmark.assert_unchanged(&fixture.original);
            finish_commit(fixture.staging, result).unwrap();
            assert!(!backup.exists());
        }
    }

    #[test]
    fn only_unchanged_precommit_permission_errors_allow_admin_installation() {
        for code in [1, 13, 5, 18, 2, 22] {
            let fixture = Fixture::new();
            let result = commit_contents_with(
                &fixture.original,
                &fixture.staged,
                &fixture.staging.path().join(BACKUP),
                |_, _| Err(io::Error::from_raw_os_error(code)),
                |_, _| panic!("unexpected rename fallback for errno {code}"),
            );
            fixture.old_contents();
            if [1, 13].contains(&code) {
                assert!(matches!(result, Err(CommitError::AdminRequired)));
                assert_eq!(
                    finish_commit(fixture.staging, result),
                    Err("UPDATE_ADMIN_REQUIRED".into())
                );
            } else {
                assert!(matches!(result, Err(CommitError::Io(_))));
                assert!(finish_commit(fixture.staging, result)
                    .unwrap_err()
                    .starts_with("UPDATE_INSTALL_FAILED:"));
            }
        }

        let fixture = Fixture::new();
        let result = commit_contents_with(
            &fixture.original,
            &fixture.staged,
            &fixture.staging.path().join(BACKUP),
            |_, _| Err(io::Error::from_raw_os_error(45)),
            |_, _| Err(io::Error::from_raw_os_error(13)),
        );
        fixture.old_contents();
        assert_eq!(
            finish_commit(fixture.staging, result),
            Err("UPDATE_ADMIN_REQUIRED".into())
        );

        // Even a permission error cannot authorize a legacy install if another
        // actor replaced Contents between the initial check and the failed swap.
        for change_root in [false, true] {
            let fixture = Fixture::new();
            let result = commit_contents_with(
                &fixture.original,
                &fixture.staged,
                &fixture.staging.path().join(BACKUP),
                |target, _| {
                    if change_root {
                        fs::rename(
                            &fixture.original.path,
                            fixture._sandbox.path().join("Saved.app"),
                        )?;
                        fs::create_dir_all(target)?;
                    } else {
                        fs::rename(target, fixture.original.path.join("saved-Contents"))?;
                        fs::create_dir(target)?;
                    }
                    Err(io::Error::from_raw_os_error(13))
                },
                |_, _| panic!("unexpected rename"),
            );
            assert!(matches!(result, Err(CommitError::Io(_))));
            assert!(finish_commit(fixture.staging, result)
                .unwrap_err()
                .starts_with("UPDATE_INSTALL_FAILED:"));
        }

        // Permission failures from staging/validation/the plugin are not the
        // precommit hook and must never authorize bypassing staged validation.
        // They are reported as refused permissions, never as UPDATE_ADMIN_REQUIRED.
        assert!(io_error("validation", io::Error::from_raw_os_error(13))
            .starts_with("UPDATE_PERMISSION_DENIED:"));
        assert!(updater_error(tauri_plugin_updater::Error::Io(
            io::Error::from_raw_os_error(13)
        ))
        .starts_with("UPDATE_PERMISSION_DENIED:"));
    }

    #[test]
    fn failed_replacement_rolls_back_original_contents() {
        for error_code in [5, 13] {
            let fixture = Fixture::new();
            let bookmark = Bookmark::new(&fixture.original.path);
            let mut calls = 0;
            let result = commit_contents_with(
                &fixture.original,
                &fixture.staged,
                &fixture.staging.path().join(BACKUP),
                |_, _| Err(io::Error::from_raw_os_error(45)),
                |a, b| {
                    calls += 1;
                    if calls == 2 {
                        Err(io::Error::from_raw_os_error(error_code))
                    } else {
                        fs::rename(a, b)
                    }
                },
            );
            assert_eq!(calls, 3);
            assert!(matches!(result, Err(CommitError::Io(_))));
            fixture.old_contents();
            bookmark.assert_unchanged(&fixture.original);
            let expected = if error_code == 13 {
                "UPDATE_PERMISSION_DENIED:"
            } else {
                "UPDATE_INSTALL_FAILED:"
            };
            assert!(finish_commit(fixture.staging, result)
                .unwrap_err()
                .starts_with(expected));
            fixture.original.unchanged().unwrap();
        }
    }

    #[test]
    fn failed_rollback_keeps_the_only_original_contents_for_recovery() {
        let fixture = Fixture::new();
        let backup = fixture.staging.path().join(BACKUP);
        let mut calls = 0;
        let result = commit_contents_with(
            &fixture.original,
            &fixture.staged,
            &backup,
            |_, _| Err(io::Error::from_raw_os_error(45)),
            |a, b| {
                calls += 1;
                if calls == 1 {
                    fs::rename(a, b)
                } else {
                    Err(io::Error::from_raw_os_error(13))
                }
            },
        );
        assert!(matches!(result, Err(CommitError::Rollback { .. })));
        let error = finish_commit(fixture.staging, result).unwrap_err();
        assert!(error.starts_with("UPDATE_INSTALL_ROLLBACK_FAILED:"));
        assert!(error.contains(&backup.display().to_string()));
        assert_eq!(
            Identity::directory(&backup).unwrap(),
            fixture.original.contents
        );
        assert_eq!(
            Identity::directory(&fixture.original.path).unwrap(),
            fixture.original.root
        );
        assert_eq!(
            fs::read_to_string(backup.join("MacOS/test")).unwrap(),
            "synthetic executable 1.0.0"
        );
    }

    #[test]
    fn changed_directory_identity_and_existing_backup_abort_before_renames() {
        for change_staged in [false, true] {
            let fixture = Fixture::new();
            let changed = if change_staged {
                &fixture.staged
            } else {
                &fixture.original
            };
            fs::rename(
                changed.path.join("Contents"),
                changed.path.join("saved-Contents"),
            )
            .unwrap();
            fs::create_dir(changed.path.join("Contents")).unwrap();
            let result = commit_contents_with(
                &fixture.original,
                &fixture.staged,
                &fixture.staging.path().join(BACKUP),
                |_, _| panic!("identity changed"),
                |_, _| panic!("identity changed"),
            );
            assert!(matches!(result, Err(CommitError::Io(_))));
        }
        let fixture = Fixture::new();
        let backup = fixture.staging.path().join(BACKUP);
        fs::create_dir(&backup).unwrap();
        let result = commit_contents_with(
            &fixture.original,
            &fixture.staged,
            &backup,
            |_, _| Err(io::Error::from_raw_os_error(45)),
            |_, _| panic!("existing backup"),
        );
        assert!(matches!(result, Err(CommitError::Io(_))));
        fixture.old_contents();
    }

    #[test]
    fn staged_identifier_version_executable_and_signature_are_checked() {
        let fixture = Fixture::new();
        for (identifier, version, expected_error) in [
            ("another.application", "2.0.0", "CFBundleIdentifier"),
            (BUNDLE_ID, "9.0.0", "CFBundleShortVersionString"),
            (BUNDLE_ID, "2.0.0", "verify staged code signature"),
        ] {
            write_bundle(&fixture.staged.path, identifier, version);
            let error =
                validate_staged(&fixture.staged.path, "2.0.0", std::ffi::OsStr::new("test"))
                    .err()
                    .unwrap();
            assert!(error.to_string().contains(expected_error), "{error}");
            fixture.old_contents();
        }
        let error = validate_staged(
            &fixture.staged.path,
            "2.0.0",
            std::ffi::OsStr::new("missing"),
        )
        .err()
        .unwrap();
        assert_eq!(error.kind(), io::ErrorKind::NotFound);
    }

    #[test]
    fn symlinked_bundle_components_cannot_redirect_installation() {
        let fixture = Fixture::new();
        let alias = fixture._sandbox.path().join("Alias.app");
        symlink(&fixture.original.path, &alias).unwrap();
        assert!(installed_bundle(&alias.join("Contents/MacOS/test")).is_err());
        let contents = fixture.staged.path.join("Contents");
        fs::rename(&contents, fixture.staged.path.join("saved-Contents")).unwrap();
        symlink(fixture.original.path.join("Contents"), &contents).unwrap();
        assert!(
            validate_staged(&fixture.staged.path, "2.0.0", std::ffi::OsStr::new("test")).is_err()
        );
        fixture.old_contents();
    }

    // Public signed b"test" vector from the exact local updater 2.14.1 source
    // (MIT OR Apache-2.0); no private key or signing implementation is included.
    const TEST_PUBLIC_KEY: &str = "untrusted comment: minisign public key: A49EF4746FA6E6D7\nRWTX5qZvdPSepDGWg2bz8n6ArQnBMwgQK1geVosorcbLzcunD+KJ+cYe";
    const TEST_SIGNATURE: &str = "untrusted comment: signature from tauri secret key\nRUTX5qZvdPSepPF2zsjvP/L/TQtBLRnWRvaq+4omK1UEugtQp/USrGiI1v762sDy3id3aor7bRC9ETyeot6lMHHrWoZ5hjUM1Qc=\ntrusted comment: timestamp:1791649051\tfile:payload\tversion:2.0.0\nDDq2CLOEl5cQmC2eJRHlnZPVViOZsu1CjpPKQoei4A/XBfkDqGO0B+QMrcrHgEQ5qV3mne75tdFWhJpqUXh9AA==";

    #[test]
    fn tamper_relabel_and_invalid_archive_never_change_original_bundle() {
        let fixture = Fixture::new();
        let encode = |value: &str| base64::engine::general_purpose::STANDARD.encode(value);
        let mut context = tauri::test::mock_context(tauri::test::noop_assets());
        context.config_mut().plugins.0.insert(
            "updater".into(),
            serde_json::json!({
                "pubkey": encode(TEST_PUBLIC_KEY), "requireSignedVersion": true,
                "endpoints": ["https://example.invalid/update"]
            }),
        );
        let app = tauri::test::mock_builder()
            .plugin(tauri_plugin_updater::Builder::new().build())
            .build(context)
            .unwrap();
        let executable = fixture.original.path.join("Contents/MacOS/test");
        let offer = app
            .updater_builder()
            .executable_path(&executable)
            .build()
            .unwrap()
            .restore_update(serde_json::json!({
                "version": "2.0.0", "url": "https://example.invalid/package.app.tar.gz",
                "signature": encode(TEST_SIGNATURE)
            }))
            .unwrap()
            .unwrap();
        assert!(offer.verify(b"test").is_ok());
        // An invalid path would fail first if verification were not first.
        assert_eq!(
            install(app.handle(), &offer, b"tampered", Path::new("missing")),
            Err("UPDATE_UNTRUSTED_SOURCE".into())
        );
        let mut relabelled = offer.clone();
        relabelled.version = "9.0.0".into();
        assert_eq!(
            install(app.handle(), &relabelled, b"test", &executable),
            Err("UPDATE_UNTRUSTED_SOURCE".into())
        );
        let mut changed_metadata = offer.clone();
        changed_metadata.raw_json["version"] = serde_json::json!("3.0.0");
        assert_eq!(
            install(app.handle(), &changed_metadata, b"test", &executable),
            Err("UPDATE_UNTRUSTED_SOURCE".into())
        );
        assert!(install(app.handle(), &offer, b"test", &executable)
            .unwrap_err()
            .starts_with("UPDATE_INSTALL_FAILED:"));
        fixture.old_contents();
    }
}
