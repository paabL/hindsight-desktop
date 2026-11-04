export type Language = 'fr' | 'en';
export const languageStorageKey = 'hindsight-desktop-language';

function preferredLanguage(): Language {
  try {
    const saved =
      typeof window === 'undefined' ? null : window.localStorage.getItem(languageStorageKey);
    if (saved === 'fr' || saved === 'en') return saved;
  } catch {}
  return 'en';
}

let language = preferredLanguage();
export const getLanguage = () => language;
export const getLocale = () => (language === 'fr' ? 'fr-CA' : 'en-CA');
export const translate = (fr: string, en: string) => (language === 'fr' ? fr : en);

export function setLanguage(next: Language) {
  language = next;
  try {
    if (typeof window !== 'undefined') window.localStorage.setItem(languageStorageKey, next);
  } catch {}
}
