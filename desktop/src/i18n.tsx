import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import { getLanguage, getLocale, setLanguage, translate, type Language } from './i18n-core';
export { getLanguage, getLocale, setLanguage, translate, type Language } from './i18n-core';

const I18nContext = createContext({
  language: getLanguage(),
  locale: getLocale(),
  setLanguage: (_language: Language) => {},
  t: translate,
});

export function I18nProvider({ children }: { children: ReactNode }) {
  const [language, updateLanguage] = useState<Language>(getLanguage);
  document.documentElement.lang = language;
  const value = useMemo(
    () => ({
      language,
      locale: language === 'fr' ? 'fr-CA' : 'en-CA',
      setLanguage: (next: Language) => {
        setLanguage(next);
        updateLanguage(next);
      },
      t: (fr: string, en: string) => (language === 'fr' ? fr : en),
    }),
    [language],
  );
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export const useI18n = () => useContext(I18nContext);
