import { createRoot } from 'react-dom/client';

const root = createRoot(document.getElementById('root')!);
// Volet de la barre des menus (menubar.rs) : sa propre page, légère, sans la feuille de la fenêtre.
if (new URLSearchParams(location.search).get('view') === 'menu') {
  document.documentElement.dataset.native = String(Boolean(window.__TAURI_INTERNALS__));
  const { default: MenuApp } = await import('./MenuApp');
  root.render(<MenuApp />);
} else {
  const { renderWindow } = await import('./main-window');
  renderWindow(root);
}
