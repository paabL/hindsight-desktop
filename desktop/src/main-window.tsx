import { createRoot } from 'react-dom/client';
import App from './App';
import { I18nProvider } from './i18n';
import './styles.css';

/** Fenêtre principale : mêmes imports, dans le même ordre, qu’avant le volet de la barre des menus. */
export function renderWindow(root: ReturnType<typeof createRoot>) {
  root.render(
    <I18nProvider>
      <App />
    </I18nProvider>,
  );
}
