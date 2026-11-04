#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde_json::Value;
use tauri::{Manager, State};
use tauri_plugin_dialog::DialogExt;
use base64::Engine;
use tokio::{io::{AsyncBufReadExt, AsyncWriteExt, BufReader}, process::{Child, ChildStdin, ChildStdout, Command}, sync::Mutex};

mod release_update;

struct NativeBridge { _child: Child, stdin: ChildStdin, stdout: BufReader<ChildStdout>, next: u64 }
struct BridgeState(Mutex<Option<NativeBridge>>);

#[tauri::command]
async fn bridge(app: tauri::AppHandle, request: Value, state: State<'_, BridgeState>) -> Result<Value, String> {
    let mut guard = state.0.lock().await;
    let result = bridge_call(&app, request, &mut guard).await?;
    if result["relaunch"] == true { app.restart(); }
    Ok(result)
}

async fn bridge_call(app: &tauri::AppHandle, request: Value, guard: &mut Option<NativeBridge>) -> Result<Value, String> {
    let command = request.get("command").and_then(Value::as_str).ok_or("Action invalide")?;
    if command.len() > 80 || !command.chars().all(|c| c.is_ascii_alphabetic() || c == '.') { return Err("Action invalide".into()); }
    let args = match request.get("args") {
        None => "{}".to_string(),
        Some(args) if args.is_object() => args.to_string(),
        Some(_) => return Err("Paramètres invalides".into()),
    };
    if args.len() > 16_000_000 { return Err("Paramètres invalides".into()); }
    if guard.is_none() {
        let executable = if cfg!(debug_assertions) {
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../native/HindsightBridge")
        } else { app.path().resource_dir().map_err(|e| e.to_string())?.join("native/HindsightBridge") };
        let bundle = if cfg!(debug_assertions) { String::new() } else {
            app.path().resource_dir().map_err(|e| e.to_string())?.parent().and_then(|p| p.parent()).ok_or("Bundle invalide")?.to_string_lossy().to_string()
        };
        let mut child = Command::new(executable)
            .env("HINDSIGHT_DESKTOP_SOURCE", env!("HINDSIGHT_BUILD_SOURCE"))
            .env("HINDSIGHT_DESKTOP_COMMIT", env!("HINDSIGHT_BUILD_COMMIT"))
            .env("HINDSIGHT_DESKTOP_VERSION", env!("CARGO_PKG_VERSION"))
            .env("HINDSIGHT_DESKTOP_BUNDLE", bundle)
            .stdin(std::process::Stdio::piped()).stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null()).kill_on_drop(true).spawn().map_err(|e| e.to_string())?;
        let stdin = child.stdin.take().ok_or("Entrée du moteur indisponible")?;
        let stdout = BufReader::new(child.stdout.take().ok_or("Sortie du moteur indisponible")?);
        *guard = Some(NativeBridge { _child: child, stdin, stdout, next: 0 });
    }
    let native = guard.as_mut().ok_or("Moteur indisponible")?;
    native.next += 1;
    let id = native.next;
    // Paramètres sérialisés une seule fois, pour la limite de taille comme pour la ligne envoyée.
    let line = format!("{{\"args\":{args},\"command\":{},\"id\":{id}}}\n", Value::from(command));
    native.stdin.write_all(line.as_bytes()).await.map_err(|e| e.to_string())?;
    native.stdin.flush().await.map_err(|e| e.to_string())?;
    let mut line = String::new();
    if native.stdout.read_line(&mut line).await.map_err(|e| e.to_string())? == 0 { return Err("Le moteur Hindsight s'est arrêté. Rouvrez l'application.".into()); }
    let mut reply: Value = serde_json::from_str(&line).map_err(|e| e.to_string())?;
    if reply["id"] != id { return Err("Réponse du moteur désynchronisée".into()); }
    if let Some(error) = reply.get("error").and_then(Value::as_str) { return Err(error.into()); }
    // Le résultat est rendu sans copie profonde (plusieurs mégaoctets pour certaines sections). Il reste
    // décodé puis réencodé : les clés repartent triées vers la vue, quel que soit l'ordre du moteur.
    Ok(reply.get_mut("result").map(Value::take).unwrap_or(Value::Null))
}

#[tauri::command]
async fn save_export(app: tauri::AppHandle, state: State<'_, BridgeState>, filename: String, base64: String) -> Result<bool, String> {
    // A file save is also a foreground operation that an update must not interrupt.
    let _guard = state.0.lock().await;
    if base64.len() > 160_000_000 { return Err("L'archive dépasse la limite d'export.".into()); }
    let name = std::path::Path::new(&filename).file_name().and_then(|v| v.to_str()).unwrap_or("hindsight-export.zip");
    let selected = app.dialog().file().set_file_name(name).blocking_save_file();
    let Some(selected) = selected else { return Ok(false) };
    let path = selected.into_path().map_err(|e| e.to_string())?;
    let bytes = base64::engine::general_purpose::STANDARD.decode(base64).map_err(|e| e.to_string())?;
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)] { use std::os::unix::fs::OpenOptionsExt; options.mode(0o600); }
    let mut file = options.open(path).map_err(|e| e.to_string())?;
    std::io::Write::write_all(&mut file, &bytes).map_err(|e| e.to_string())?;
    Ok(true)
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(BridgeState(Mutex::new(None)))
        .manage(release_update::ReleaseUpdateState::default())
        .invoke_handler(tauri::generate_handler![bridge, save_export, release_update::release_update_check, release_update::release_update_install])
        .run(tauri::generate_context!())
        .expect("Impossible de démarrer Hindsight Desktop");
}
