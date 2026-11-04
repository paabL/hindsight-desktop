import type { Row } from './types';
import { translate as t } from './i18n-core';
export const host = window.__TAURI_INTERNALS__ ? 'Tauri' : 'Navigateur';

export async function nativeRequest(command: string, args: Row = {}) {
  if (window.__TAURI_INTERNALS__) {
    const { invoke } = await import('@tauri-apps/api/core');
    return invoke('bridge', { request: { command, args } });
  }
  throw new Error(
    t(
      'Les données et les actions locales sont disponibles dans l’application desktop. Vous pouvez explorer l’exemple depuis Réglages.',
      'Local data and actions are available in the desktop app. You can explore an example from Settings.',
    ),
  );
}

export async function pickDirectory(
  title = t('Choisir le dossier mémoire', 'Choose the memory folder'),
): Promise<string | null> {
  if (window.__TAURI_INTERNALS__) {
    const { open } = await import('@tauri-apps/plugin-dialog');
    const selected = await open({
      directory: true,
      multiple: false,
      title,
    });
    return typeof selected === 'string' ? selected : null;
  }
  throw new Error(
    t(
      'Ouvrez l’application desktop pour choisir un dossier sur ce Mac.',
      'Open the desktop app to choose a folder on this Mac.',
    ),
  );
}

export async function saveExport(filename: string, base64: string): Promise<boolean> {
  if (window.__TAURI_INTERNALS__) {
    const { invoke } = await import('@tauri-apps/api/core');
    return invoke('save_export', { filename, base64 });
  }
  // Le choix du fichier est explicite et le contenu provient uniquement d’un export demandé.
  const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  const blob = new Blob([bytes]);
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  return true;
}

export async function pickDocuments(): Promise<string[]> {
  if (window.__TAURI_INTERNALS__) {
    const { open } = await import('@tauri-apps/plugin-dialog');
    const selected = await open({
      directory: false,
      multiple: true,
      title: t('Ajouter des documents au dossier mémoire', 'Add documents to the memory folder'),
      filters: [{ name: 'Documents', extensions: ['tex', 'md', 'pdf'] }],
    });
    return Array.isArray(selected) ? selected : typeof selected === 'string' ? [selected] : [];
  }
  throw new Error(
    t(
      'Ouvrez l’application desktop pour ajouter des documents sur ce Mac.',
      'Open the desktop app to add documents on this Mac.',
    ),
  );
}
