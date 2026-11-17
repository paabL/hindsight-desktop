//! Volet de la barre des menus : l’essentiel de Hindsight (connexion, banque, activité, consommation) et la
//! pause d’un clic. La page du volet lit elle-même le moteur (commande `menu.status`) ; ce module place le
//! panneau sous l’icône, le ferme comme un menu natif et relaie à la fenêtre principale ce qui la concerne.
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, PoisonError};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, Rect, State, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

pub const WINDOW: &str = "menubar";
pub const TRAY: &str = "hindsight";

/// Largeur fixe, hauteur ajustée au contenu comme les volets natifs.
const PANEL_WIDTH: f64 = 340.0;
const DEFAULT_HEIGHT: f64 = 460.0;
const MIN_HEIGHT: f64 = 160.0;
const MAX_HEIGHT: f64 = 760.0;

#[derive(Default)]
pub struct MenuState {
    /// Le volet est montré. Tenu ici plutôt que lu sur la fenêtre : sur macOS le volet est un panneau
    /// natif, pas la fenêtre Tauri de la page.
    open: AtomicBool,
    hidden_at: Mutex<Option<Instant>>,
    shown_at: Mutex<Option<Instant>>,
    /// Dernière hauteur de contenu mesurée par la page, réutilisée à l’ouverture.
    height: Mutex<Option<f64>>,
    /// Icône affichée (au repos, au travail, en retrait), pour ne la changer qu’à bon escient.
    icon: Mutex<Option<TrayLook>>,
}

/// Pendant l’ouverture, AppKit peut retirer le focus au volet ou livrer un clic de la sélection qui l’a
/// ouvert : ce ne sont pas des clics en dehors.
const OPENING: Duration = Duration::from_millis(400);

impl MenuState {
    fn height(&self) -> f64 {
        self.height.lock().unwrap_or_else(PoisonError::into_inner).unwrap_or(DEFAULT_HEIGHT)
    }
}

/// Ce que le volet demande à la fenêtre principale. Les vues et les banques sont des identifiants que la
/// fenêtre vérifie elle-même ; aucune commande du moteur ne passe par ici.
#[derive(Clone, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Action {
    /// Montre la fenêtre, sur une vue si elle est donnée.
    Open { section: Option<String> },
    /// Choisit une autre banque, sans montrer la fenêtre.
    Bank { id: String },
    /// Le volet a changé l’état de l’app (pause, service) : la fenêtre relit le sien.
    Changed,
    Quit,
}

impl Action {
    fn valid(&self) -> bool {
        let short = |value: &str| !value.is_empty() && value.len() <= 200;
        match self {
            Action::Open { section } => section.as_deref().is_none_or(|id| {
                short(id) && id.chars().all(|c| c.is_ascii_lowercase() || c == '-')
            }),
            Action::Bank { id } => short(id),
            Action::Changed | Action::Quit => true,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TrayLook {
    /// Connecté, rien en cours.
    Idle,
    /// Des opérations tournent sur le serveur.
    Working,
    /// En pause ou déconnecté : l’icône pâlit.
    Dim,
}

#[tauri::command]
pub fn menu_action(window: WebviewWindow, action: Action) -> Result<(), String> {
    if window.label() != WINDOW || !action.valid() {
        return Err("Action du volet refusée.".into());
    }
    dispatch(window.app_handle(), action)
}

pub fn dispatch(app: &AppHandle, action: Action) -> Result<(), String> {
    match action {
        Action::Quit => {
            app.exit(0);
            Ok(())
        }
        Action::Open { .. } => {
            hide(app);
            super::show_main(app);
            app.emit_to("main", "menu-action", action).map_err(|error| error.to_string())
        }
        Action::Bank { .. } | Action::Changed => {
            app.emit_to("main", "menu-action", action).map_err(|error| error.to_string())
        }
    }
}

#[tauri::command]
pub fn menu_hide(app: AppHandle) {
    hide(&app);
}

/// La page annonce la hauteur de son contenu ; le haut du volet reste sous l’icône.
#[tauri::command]
pub fn menu_resize(window: WebviewWindow, state: State<'_, MenuState>, height: f64) -> Result<(), String> {
    if window.label() != WINDOW || !height.is_finite() {
        return Err("Taille du volet refusée.".into());
    }
    let height = height.clamp(MIN_HEIGHT, MAX_HEIGHT);
    {
        let mut stored = state.height.lock().unwrap_or_else(PoisonError::into_inner);
        if stored.is_some_and(|current| (current - height).abs() < 1.0) {
            return Ok(());
        }
        *stored = Some(height);
    }
    resize(&window, height).map_err(|error| error.to_string())
}

#[cfg(target_os = "macos")]
fn resize(window: &WebviewWindow, height: f64) -> tauri::Result<()> {
    window.run_on_main_thread(move || crate::panel::resize(height, MIN_HEIGHT))
}

#[cfg(not(target_os = "macos"))]
fn resize(window: &WebviewWindow, height: f64) -> tauri::Result<()> {
    window.set_size(tauri::LogicalSize::new(PANEL_WIDTH, height))
}

/// Le verre suit le thème de l’app (réglage de Hindsight), pas celui du système.
#[tauri::command]
pub fn menu_theme(window: WebviewWindow, dark: bool) -> Result<(), String> {
    if window.label() != WINDOW {
        return Err("Thème du volet refusé.".into());
    }
    #[cfg(target_os = "macos")]
    window.run_on_main_thread(move || crate::panel::set_theme(dark)).map_err(|error| error.to_string())?;
    #[cfg(not(target_os = "macos"))]
    let _ = dark;
    Ok(())
}

/// Icône et bulle d’aide de la barre des menus, décidées par la page d’après l’état lu.
#[tauri::command]
pub fn tray_state(app: AppHandle, state: State<'_, MenuState>, look: TrayLook, tooltip: String) -> Result<(), String> {
    let Some(tray) = app.tray_by_id(TRAY) else {
        return Ok(());
    };
    let failed = |error: tauri::Error| format!("Barre des menus non actualisée : {error}");
    let tooltip: String = tooltip.chars().take(240).collect();
    tray.set_tooltip(Some(tooltip).filter(|text| !text.is_empty())).map_err(failed)?;
    let mut current = state.icon.lock().unwrap_or_else(PoisonError::into_inner);
    if *current != Some(look) {
        tray.set_icon(Some(icon(look))).map_err(failed)?;
        tray.set_icon_as_template(true).map_err(failed)?;
        *current = Some(look);
    }
    Ok(())
}

/// Image gabarit (noire sur transparent) : macOS la teinte selon la barre des menus.
pub fn icon(look: TrayLook) -> tauri::image::Image<'static> {
    match look {
        TrayLook::Idle => tauri::include_image!("icons/tray.png"),
        TrayLook::Working => tauri::include_image!("icons/tray-working.png"),
        TrayLook::Dim => tauri::include_image!("icons/tray-dim.png"),
    }
}

/// Fermeture implicite (changement d’app, clic en dehors), ignorée juste après l’ouverture : sans ce délai
/// le volet ouvert sans activer l’app se refermait aussitôt.
pub fn hide_outside(app: &AppHandle, reason: &str) {
    if !is_open(app) {
        return;
    }
    let opening = app
        .state::<MenuState>()
        .shown_at
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .is_some_and(|at| at.elapsed() < OPENING);
    if opening {
        return;
    }
    super::log(&format!("Volet de la barre des menus : fermé ({reason})"));
    hide(app);
}

pub fn hide(app: &AppHandle) {
    let state = app.state::<MenuState>();
    if !state.open.swap(false, Ordering::SeqCst) {
        return;
    }
    *state.hidden_at.lock().unwrap_or_else(PoisonError::into_inner) = Some(Instant::now());
    let _ = app.emit_to(WINDOW, "menu-visibility", false);
    #[cfg(target_os = "macos")]
    {
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            crate::panel::dismiss();
            highlight_icon(&handle, false);
            stop_outside_clicks(&handle);
        });
    }
    #[cfg(not(target_os = "macos"))]
    if let Some(window) = app.get_webview_window(WINDOW) {
        let _ = window.hide();
    }
}

fn is_open(app: &AppHandle) -> bool {
    app.state::<MenuState>().open.load(Ordering::SeqCst)
}

/// La page du volet, créée une fois. Sur macOS sa fenêtre Tauri n’est jamais montrée : la vue web vit dans
/// le panneau natif (voir panel.rs).
fn page(app: &AppHandle) -> tauri::Result<WebviewWindow> {
    let window = match app.get_webview_window(WINDOW) {
        Some(window) => window,
        None => {
            let builder = WebviewWindowBuilder::new(app, WINDOW, WebviewUrl::App("index.html?view=menu".into()))
                .title("Hindsight — barre des menus")
                .inner_size(PANEL_WIDTH, app.state::<MenuState>().height())
                .resizable(false)
                .decorations(false)
                .transparent(true)
                .skip_taskbar(true)
                .focused(false)
                .visible(false);
            #[cfg(not(target_os = "macos"))]
            let builder = builder.shadow(true).always_on_top(true).visible_on_all_workspaces(true);
            builder.build()?
        }
    };
    #[cfg(target_os = "macos")]
    crate::panel::attach(app, &window, PANEL_WIDTH, app.state::<MenuState>().height())
        .map_err(std::io::Error::other)?;
    Ok(window)
}

/// Prépare le volet au lancement : le premier clic l’ouvre sans attente, avec l’icône déjà à jour.
pub fn prepare(app: &AppHandle) {
    if let Err(error) = page(app) {
        super::log(&format!("Volet de la barre des menus : {error}"));
    }
}

/// Clic sur l’icône : ouvre ou referme le volet, sous l’icône et sur le bon écran.
pub fn toggle(app: &AppHandle, _rect: Rect) -> tauri::Result<()> {
    if is_open(app) {
        hide(app);
        return Ok(());
    }
    let state = app.state::<MenuState>();
    // Le clic sur l’icône ferme d’abord le volet (clic en dehors) : ne pas le rouvrir.
    let recently_hidden = state
        .hidden_at
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .is_some_and(|at| at.elapsed() < Duration::from_millis(250));
    if recently_hidden {
        return Ok(());
    }
    let window = page(app)?;
    #[cfg(target_os = "macos")]
    {
        let _ = &window;
        let (x, y, width, height) = native_frame(app, state.height())?;
        crate::panel::present(x, y, width, height).map_err(std::io::Error::other)?;
        highlight_icon(app, true);
        watch_outside_clicks(app);
    }
    #[cfg(not(target_os = "macos"))]
    {
        let scale = window.scale_factor()?;
        let anchor = _rect.position.to_logical::<f64>(scale);
        let icon = _rect.size.to_logical::<f64>(scale);
        if let Some(monitor) = window.current_monitor()? {
            let area = monitor.work_area();
            let (x, y, width, height) = placement(
                [anchor.x, anchor.y + icon.height, icon.width],
                [
                    area.position.x as f64 / scale,
                    area.position.y as f64 / scale,
                    area.size.width as f64 / scale,
                    area.size.height as f64 / scale,
                ],
                state.height(),
            );
            window.set_size(tauri::LogicalSize::new(width, height))?;
            window.set_position(tauri::LogicalPosition::new(x, y))?;
        }
        window.show()?;
        window.set_focus()?;
    }
    *state.shown_at.lock().unwrap_or_else(PoisonError::into_inner) = Some(Instant::now());
    state.open.store(true, Ordering::SeqCst);
    app.emit_to(WINDOW, "menu-visibility", true)?;
    Ok(())
}

/// AppKit donne l’icône et son écran dans le même repère (points, origine en bas à gauche) : ne jamais
/// mélanger son rectangle en pixels Retina avec les écrans logiques. Quand macOS masque l’icône (trop
/// d’éléments d’état), le volet s’ouvre dans le coin en haut à droite de l’écran principal.
#[cfg(target_os = "macos")]
fn native_frame(app: &AppHandle, content: f64) -> tauri::Result<(f64, f64, f64, f64)> {
    let mtm = objc2::MainThreadMarker::new().ok_or_else(|| std::io::Error::other("Le volet s’ouvre sur le fil principal."))?;
    let rect = |frame: objc2_foundation::NSRect| [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height];
    let under_icon = app.tray_by_id(TRAY).and_then(|tray| {
        tray.with_inner_tray_icon(move |tray| {
            let mtm = objc2::MainThreadMarker::new()?;
            let native = tray.ns_status_item()?.button(mtm)?.window()?;
            let screen = native.screen()?;
            let (icon, area) = (native.frame(), screen.visibleFrame());
            (icon.size.width > 0.0 && area.size.width > 16.0 && area.size.height > 16.0).then(|| (rect(icon), rect(area)))
        })
        .ok()
        .flatten()
    });
    let (icon, area) = match under_icon {
        Some(geometry) => geometry,
        None => {
            let area = objc2_app_kit::NSScreen::mainScreen(mtm)
                .map(|screen| rect(screen.visibleFrame()))
                .ok_or_else(|| std::io::Error::other("Aucun écran pour le volet."))?;
            ([area[0] + area[2] - 44.0, area[1] + area[3], 28.0, 0.0], area)
        }
    };
    Ok(native_placement(icon, area, content))
}

#[cfg(target_os = "macos")]
fn native_placement(icon: [f64; 4], area: [f64; 4], height: f64) -> (f64, f64, f64, f64) {
    // Inverser Y garde un seul repère logique, y compris au-dessus de l’écran principal.
    let (x, y, w, h) = placement([icon[0], -icon[1], icon[2]], [area[0], -(area[1] + area[3]), area[2], area[3]], height);
    (x, -y - h, w, h)
}

/// Comme les éléments d’état natifs, l’icône reste en surbrillance tant que son volet est ouvert.
#[cfg(target_os = "macos")]
fn highlight_icon(app: &AppHandle, highlighted: bool) {
    if let Some(tray) = app.tray_by_id(TRAY) {
        let _ = tray.with_inner_tray_icon(move |tray| {
            let button = tray.ns_status_item()?.button(objc2::MainThreadMarker::new()?)?;
            button.highlight(highlighted);
            Some(())
        });
    }
}

#[cfg(target_os = "macos")]
thread_local! {
    /// Moniteurs des clics hors du volet, propres au fil principal d’AppKit.
    static OUTSIDE_CLICKS: std::cell::RefCell<Vec<objc2::rc::Retained<objc2::runtime::AnyObject>>> =
        const { std::cell::RefCell::new(Vec::new()) };
}

/// Tout clic hors du volet le ferme, comme un NSPopover transitoire : dans une autre app (moniteur global),
/// même quand le volet n’est jamais devenu la fenêtre active, et dans les fenêtres ou la barre des menus de
/// Hindsight (moniteur local).
#[cfg(target_os = "macos")]
fn watch_outside_clicks(app: &AppHandle) {
    use objc2_app_kit::{NSEvent, NSEventMask as M};
    use std::ptr::NonNull;
    let mask = M::LeftMouseDown | M::RightMouseDown | M::OtherMouseDown;
    OUTSIDE_CLICKS.with(|slot| {
        if !slot.borrow().is_empty() {
            return;
        }
        let handle = app.clone();
        let elsewhere =
            block2::RcBlock::new(move |_: NonNull<NSEvent>| hide_outside(&handle, "clic dans une autre app"));
        let handle = app.clone();
        let here = block2::RcBlock::new(move |event: NonNull<NSEvent>| -> *mut NSEvent {
            let inside = objc2::MainThreadMarker::new()
                .and_then(|mtm| unsafe { event.as_ref() }.window(mtm))
                .is_some_and(|window| crate::panel::owns(&window));
            if !inside {
                hide_outside(&handle, "clic dans Hindsight");
            }
            event.as_ptr()
        });
        let mut monitors = slot.borrow_mut();
        monitors.extend(NSEvent::addGlobalMonitorForEventsMatchingMask_handler(mask, &elsewhere));
        // Le gestionnaire rend l’événement tel quel : AppKit le livre quand même.
        monitors.extend(unsafe { NSEvent::addLocalMonitorForEventsMatchingMask_handler(mask, &here) });
    });
}

#[cfg(target_os = "macos")]
fn stop_outside_clicks(app: &AppHandle) {
    if is_open(app) {
        return; // Rouvert entre-temps : les moniteurs servent encore.
    }
    OUTSIDE_CLICKS.with(|slot| {
        for monitor in slot.borrow_mut().drain(..) {
            unsafe { objc2_app_kit::NSEvent::removeMonitor(&monitor) };
        }
    });
}

/// Coordonnées logiques : respecte aussi les écrans Retina et les origines négatives.
fn placement(anchor: [f64; 3], area: [f64; 4], content: f64) -> (f64, f64, f64, f64) {
    let [left, top, width, height] = area;
    let w = PANEL_WIDTH.min((width - 16.0).max(1.0));
    let h = content.clamp(MIN_HEIGHT, MAX_HEIGHT).min((height - 16.0).max(1.0));
    let x = (anchor[0] + anchor[2] / 2.0 - w / 2.0).clamp(left + 8.0, left + width - w - 8.0);
    let y = (anchor[1] + 6.0).clamp(top + 8.0, top + height - h - 8.0);
    (x, y, w, h)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(target_os = "macos")]
    #[test]
    fn native_anchor_uses_points_and_bottom_left_without_retina_lookup() {
        assert_eq!(
            native_placement([1200.0, 1058.0, 70.0, 22.0], [0.0, 0.0, 1280.0, 1055.0], 480.0),
            (932.0, 567.0, 340.0, 480.0)
        );
        assert_eq!(
            native_placement([-1390.0, 828.0, 60.0, 22.0], [-1440.0, 0.0, 1440.0, 825.0], 480.0),
            (-1432.0, 337.0, 340.0, 480.0)
        );
        assert_eq!(
            native_placement([1000.0, 2498.0, 70.0, 22.0], [0.0, 1440.0, 1920.0, 1055.0], 480.0),
            (865.0, 2007.0, 340.0, 480.0)
        );
    }

    #[test]
    fn panel_stays_on_its_screen_and_above_the_dock() {
        assert_eq!(placement([1200.0, 25.0, 70.0], [0.0, 25.0, 1280.0, 735.0], 900.0), (932.0, 33.0, 340.0, 719.0));
        assert_eq!(placement([600.0, 25.0, 40.0], [0.0, 25.0, 1280.0, 300.0], 480.0), (450.0, 33.0, 340.0, 284.0));
        assert_eq!(placement([600.0, 25.0, 40.0], [0.0, 25.0, 1280.0, 800.0], 40.0).3, 160.0);
    }

    #[test]
    fn actions_carry_only_views_and_bank_ids() {
        let parse = |value: serde_json::Value| serde_json::from_value::<Action>(value);
        assert!(parse(serde_json::json!({"kind":"bridge","command":"admin.deleteBank"})).is_err());
        assert!(parse(serde_json::json!({"kind":"bank"})).is_err());
        assert!(parse(serde_json::json!({"kind":"open","section":"operations"})).unwrap().valid());
        assert!(parse(serde_json::json!({"kind":"open"})).unwrap().valid());
        assert!(!parse(serde_json::json!({"kind":"open","section":"../x"})).unwrap().valid());
        assert!(!parse(serde_json::json!({"kind":"bank","id":""})).unwrap().valid());
    }
}
