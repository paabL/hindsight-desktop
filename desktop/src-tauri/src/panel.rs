//! Volet natif macOS : un `NSPanel` non activant qui héberge la page du volet.
//!
//! macOS n’affiche au-dessus de l’espace plein écran d’une autre application que
//! les panneaux créés avec le style « non activant ». Une fenêtre ordinaire n’y
//! apparaît pas, quels que soient son niveau et ses comportements d’espace, sauf
//! à retirer l’app du Dock. Tauri crée donc la page dans une fenêtre qui n’est
//! jamais montrée, et sa vue web est déplacée dans ce panneau (ce que wry prévoit
//! avec `reparent`). Le panneau prend le clavier sans activer Hindsight : l’app au
//! premier plan y reste et aucun bureau ne change.
use std::cell::RefCell;
use std::ffi::c_void;
use std::ptr::NonNull;
use std::time::Duration;

use objc2::rc::Retained;
use objc2::{define_class, msg_send, MainThreadMarker, MainThreadOnly};
use objc2_app_kit::{
    NSApplication, NSAutoresizingMaskOptions, NSBackingStoreType, NSColor, NSEvent, NSPanel,
    NSPopUpMenuWindowLevel, NSResponder, NSView, NSWindow, NSWindowAnimationBehavior,
    NSWindowCollectionBehavior, NSWindowStyleMask,
};
use objc2_foundation::{NSObject, NSPoint, NSRect, NSSize};
use raw_window_handle::{
    AppKitWindowHandle, HandleError, HasWindowHandle, RawWindowHandle, WindowHandle,
};
use tauri::{AppHandle, WebviewWindow};
use window_vibrancy::{
    LiquidGlassOptions, NSGlassEffectViewStyle, NSVisualEffectMaterial, NSVisualEffectState,
};

/// Rayon des coins, identique à `--menu-radius` dans menubar.css.
const RADIUS: f64 = 18.0;
const ESCAPE: u16 = 53;

struct Native {
    panel: Retained<MenuPanel>,
    /// La vue web de la page, retenue pour lui rendre le clavier à chaque ouverture.
    page: Retained<NSView>,
}

thread_local! {
    // AppKit n’est utilisable que sur le fil principal : l’état y reste.
    static NATIVE: RefCell<Option<Native>> = const { RefCell::new(None) };
    static APP: RefCell<Option<AppHandle>> = const { RefCell::new(None) };
}

define_class!(
    // SAFETY: NSPanel se sous-classe librement ; la classe n’ajoute aucune variable
    // d’instance et ses redéfinitions gardent le contrat des méthodes d’origine.
    #[unsafe(super(NSPanel, NSWindow, NSResponder, NSObject))]
    #[thread_kind = MainThreadOnly]
    #[name = "HindsightMenuPanel"]
    struct MenuPanel;

    impl MenuPanel {
        /// Une fenêtre sans bordure refuse le clavier par défaut.
        #[unsafe(method(canBecomeKeyWindow))]
        fn can_become_key(&self) -> bool {
            true
        }

        #[unsafe(method(canBecomeMainWindow))]
        fn can_become_main(&self) -> bool {
            false
        }

        /// Perdre le clavier ne ferme pas le volet : l’app au premier plan, surtout
        /// en plein écran, le reprend parfois d’elle-même et le volet à peine
        /// ouvert disparaissait. Seuls un clic ailleurs, un changement d’app ou de
        /// bureau et Échap le ferment (voir `watch_workspace` et menubar.rs).
        #[unsafe(method(resignKeyWindow))]
        fn resign_key(&self) {
            let _: () = unsafe { msg_send![super(self), resignKeyWindow] };
            crate::log("Volet de barre des menus : clavier repris par une autre fenêtre");
        }

        /// Les touches que la page n’a pas traitées finissent ici. NSWindow
        /// émettrait un bip : Échap ferme, le reste est proposé aux menus (⌘Q).
        #[unsafe(method(keyDown:))]
        fn key_down(&self, event: &NSEvent) {
            if event.keyCode() == ESCAPE {
                with_app(crate::menubar::hide);
            } else if let Some(menu) = NSApplication::sharedApplication(self.mtm()).mainMenu() {
                menu.performKeyEquivalent(event);
            }
        }
    }
);

fn with_app(action: impl FnOnce(&AppHandle)) {
    if let Some(app) = APP.with(|slot| slot.borrow().clone()) {
        action(&app);
    }
}

/// Copie retenue du panneau : aucun emprunt ne reste ouvert pendant un appel
/// AppKit, qui peut rappeler ce module (perte du focus pendant `orderOut`).
fn panel() -> Option<Retained<MenuPanel>> {
    NATIVE.with(|slot| slot.borrow().as_ref().map(|native| native.panel.clone()))
}

/// Vue AppKit présentée à window-vibrancy, qui n’attend qu’une `NSView`.
struct ViewHandle(NonNull<c_void>);

impl HasWindowHandle for ViewHandle {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let raw = RawWindowHandle::AppKit(AppKitWindowHandle::new(self.0));
        // SAFETY: la vue appartient au panneau, conservé pour toute la vie de l’app.
        Ok(unsafe { WindowHandle::borrow_raw(raw) })
    }
}

/// Liquid Glass sur macOS 26 et après, matériau Popover avant.
fn glass(view: &NSView) {
    let handle = ViewHandle(NonNull::from(view).cast());
    let options = LiquidGlassOptions::new(NSGlassEffectViewStyle::Regular).radius(RADIUS);
    if window_vibrancy::apply_liquid_glass(&handle, options).is_err() {
        if let Err(error) = window_vibrancy::apply_vibrancy(
            &handle,
            NSVisualEffectMaterial::Popover,
            Some(NSVisualEffectState::Active),
            Some(RADIUS),
        ) {
            crate::log(&format!("Volet de barre des menus : fond natif indisponible ({error})"));
        }
    }
}

/// Rien ne dépasse de l’arrondi. Le verre dessine sa propre ombre, à peine
/// visible, jusque dans les coins du panneau : macOS comptait alors ces coins
/// dans la forme de la fenêtre et traçait son contour et son ombre en carré.
fn clip(view: &NSView) {
    view.setWantsLayer(true);
    if let Some(layer) = view.layer() {
        layer.setCornerRadius(RADIUS);
        // SAFETY: constante QuartzCore, valide pendant toute la vie du processus.
        layer.setCornerCurve(unsafe { objc2_quartz_core::kCACornerCurveContinuous });
        layer.setMasksToBounds(true);
    }
}

/// Crée le panneau autour de la vue web de `page`. Sans effet s’il existe déjà.
pub fn attach(app: &AppHandle, page: &WebviewWindow, width: f64, height: f64) -> Result<(), String> {
    let mtm = MainThreadMarker::new().ok_or("Le volet se crée sur le fil principal.")?;
    if NATIVE.with(|slot| slot.borrow().is_some()) {
        return Ok(());
    }
    // Sur le fil principal, Tauri exécute cette fermeture avant de rendre la main.
    let (sender, receiver) = std::sync::mpsc::channel();
    page.with_webview(move |webview| {
        let _ = sender.send(webview.inner() as usize);
    })
    .map_err(|error| error.to_string())?;
    let pointer = receiver
        .try_recv()
        .map_err(|_| "Vue web du volet indisponible.".to_string())?;
    // SAFETY: wry garde la WKWebView (une NSView) vivante tant que la page existe.
    let web = unsafe { Retained::retain(pointer as *mut NSView) }
        .ok_or("Vue web du volet indisponible.")?;

    let frame = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(width, height));
    // Le style non activant doit être donné à la création : c’est lui qui autorise
    // le panneau au-dessus du plein écran des autres apps.
    let style = NSWindowStyleMask::Borderless | NSWindowStyleMask::NonactivatingPanel;
    let panel: Retained<MenuPanel> = unsafe {
        msg_send![
            super(MenuPanel::alloc(mtm).set_ivars(())),
            initWithContentRect: frame,
            styleMask: style,
            backing: NSBackingStoreType::Buffered,
            defer: false,
        ]
    };
    // SAFETY: le panneau est masqué, jamais fermé ; Rust en garde la référence.
    unsafe { panel.setReleasedWhenClosed(false) };
    panel.setFloatingPanel(true);
    panel.setBecomesKeyOnlyIfNeeded(false);
    panel.setWorksWhenModal(true);
    // Un NSPanel disparaît par défaut dès que son app n’est plus active.
    panel.setHidesOnDeactivate(false);
    panel.setLevel(NSPopUpMenuWindowLevel);
    panel.setCollectionBehavior(behavior());
    panel.setOpaque(false);
    panel.setBackgroundColor(Some(&NSColor::clearColor()));
    panel.setHasShadow(true);
    panel.setMovable(false);
    panel.setExcludedFromWindowsMenu(true);
    panel.setAnimationBehavior(NSWindowAnimationBehavior::UtilityWindow);

    let resizing =
        NSAutoresizingMaskOptions::ViewWidthSizable | NSAutoresizingMaskOptions::ViewHeightSizable;
    let content = NSView::initWithFrame(mtm.alloc(), frame);
    content.setAutoresizingMask(resizing);
    clip(&content);
    panel.setContentView(Some(&content));
    glass(&content);
    // Au-dessus du verre ; `addSubview` retire la vue de sa fenêtre d’origine.
    web.setFrame(content.bounds());
    web.setAutoresizingMask(resizing);
    content.addSubview(&web);

    APP.with(|slot| *slot.borrow_mut() = Some(app.clone()));
    NATIVE.with(|slot| *slot.borrow_mut() = Some(Native { panel, page: web }));
    watch_workspace();
    Ok(())
}

/// Ferme le volet quand l’utilisateur change d’app (⌘⇥, Dock) ou de bureau :
/// aucun clic ne le signale. Observé pendant toute la vie de l’app.
fn watch_workspace() {
    use objc2_app_kit::{
        NSWorkspace, NSWorkspaceActiveSpaceDidChangeNotification,
        NSWorkspaceDidActivateApplicationNotification,
    };
    use objc2_foundation::{NSNotification, NSOperationQueue};
    let center = NSWorkspace::sharedWorkspace().notificationCenter();
    // SAFETY: constantes AppKit, valides pendant toute la vie du processus.
    let events = unsafe {
        [
            (NSWorkspaceDidActivateApplicationNotification, "changement d’app"),
            (NSWorkspaceActiveSpaceDidChangeNotification, "changement de bureau"),
        ]
    };
    for (name, reason) in events {
        let block = block2::RcBlock::new(move |_: NonNull<NSNotification>| {
            with_app(|app| crate::menubar::hide_outside(app, reason));
        });
        // SAFETY: le bloc ne capture qu’un texte statique et s’exécute sur la file
        // principale ; le centre de notifications garde l’observateur.
        let _ = unsafe {
            center.addObserverForName_object_queue_usingBlock(
                Some(name),
                None,
                Some(&NSOperationQueue::mainQueue()),
                &block,
            )
        };
    }
}

/// Sur tous les bureaux, y compris l’espace plein écran d’une autre app, sans
/// jamais devenir une fenêtre que Mission Control ou ⌘` proposent.
fn behavior() -> NSWindowCollectionBehavior {
    use NSWindowCollectionBehavior as B;
    B::CanJoinAllSpaces | B::FullScreenAuxiliary | B::Transient | B::IgnoresCycle
}

/// Place le panneau (points AppKit, origine en bas à gauche) et le montre avec
/// le clavier, sans activer Hindsight.
pub fn present(x: f64, y: f64, width: f64, height: f64) -> Result<(), String> {
    let Some(panel) = panel() else {
        return Err("Volet de barre des menus non créé.".into());
    };
    panel.setFrame_display(
        NSRect::new(NSPoint::new(x, y), NSSize::new(width, height)),
        true,
    );
    panel.orderFrontRegardless();
    panel.makeKeyWindow();
    let page = NATIVE.with(|slot| slot.borrow().as_ref().map(|native| native.page.clone()));
    if let Some(page) = page {
        panel.makeFirstResponder(Some(&page));
    }
    refresh_shadow();
    Ok(())
}

/// Le verre suit le thème de la page, pas celui du système : texte clair sur
/// verre sombre et inversement, même quand l’app a son propre thème.
pub fn set_theme(dark: bool) {
    use objc2_app_kit::{
        NSAppearance, NSAppearanceCustomization, NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
    };
    let Some(panel) = panel() else {
        return;
    };
    // SAFETY: constantes AppKit, valides pendant toute la vie du processus.
    let name = unsafe {
        if dark {
            NSAppearanceNameDarkAqua
        } else {
            NSAppearanceNameAqua
        }
    };
    panel.setAppearance(NSAppearance::appearanceNamed(name).as_deref());
}

pub fn dismiss() {
    if let Some(panel) = panel() {
        panel.orderOut(None);
    }
}

/// Ajuste la hauteur en gardant le haut sous l’icône et le bas au-dessus du Dock.
pub fn resize(height: f64, minimum: f64) {
    let Some(panel) = panel() else {
        return;
    };
    let frame = panel.frame();
    let top = frame.origin.y + frame.size.height;
    let floor = panel
        .screen()
        .map_or(f64::MIN, |screen| screen.visibleFrame().origin.y + 8.0);
    let height = height.min((top - floor).max(minimum));
    panel.setFrame_display(
        NSRect::new(
            NSPoint::new(frame.origin.x, top - height),
            NSSize::new(frame.size.width, height),
        ),
        true,
    );
    refresh_shadow();
}

/// Le clic s’est-il produit dans le panneau ?
pub fn owns(window: &NSWindow) -> bool {
    panel().is_some_and(|panel| {
        std::ptr::eq(
            Retained::as_ptr(&panel).cast::<NSWindow>(),
            window as *const NSWindow,
        )
    })
}

/// AppKit calcule l’ombre d’après l’opacité de la fenêtre et la garde en cache.
/// Calculée avant que le verre arrondi et la page transparente soient dessinés à
/// la nouvelle taille, elle garde des coins carrés (vu à la première ouverture,
/// quand le volet grandit) : la recalculer maintenant, puis pendant le rendu.
fn refresh_shadow() {
    fn invalidate() {
        if let Some(panel) = panel() {
            panel.invalidateShadow();
        }
    }
    invalidate();
    with_app(|app| {
        let app = app.clone();
        std::thread::spawn(move || {
            // Écarts entre deux recalculs : 150 ms, 400 ms puis 1 s après l’appel.
            for wait in [150, 250, 600] {
                std::thread::sleep(Duration::from_millis(wait));
                let _ = app.run_on_main_thread(invalidate);
            }
        });
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn panel_joins_full_screen_spaces_without_becoming_a_managed_window() {
        use NSWindowCollectionBehavior as B;
        let flags = behavior();
        assert!(flags.contains(B::CanJoinAllSpaces | B::FullScreenAuxiliary | B::IgnoresCycle));
        assert!(!flags.intersects(
            B::Primary | B::FullScreenPrimary | B::MoveToActiveSpace | B::ParticipatesInCycle
        ));
    }
}
