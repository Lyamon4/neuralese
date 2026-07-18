import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useState,
} from "react";

import en from "../../public/locales/text_en.json";
import ru from "../../public/locales/text_ru.json";
import kz from "../../public/locales/text_kz.json";

export type Locale = "en" | "ru" | "kz";

export const LOCALES: { code: Locale; label: string; flag: string }[] = [
  { code: "en", label: "English",  flag: "EN" },
  { code: "ru", label: "Русский",  flag: "RU" },
  { code: "kz", label: "Қазақша", flag: "KZ" },
];

type Strings = Record<string, string>;

const ALL_STRINGS: Record<Locale, Strings> = { en, ru, kz };

interface I18nContextValue {
  locale: Locale;
  setLocale: (l: Locale) => void;
  t: (key: string) => string;
  ready: boolean;
}

const I18nContext = createContext<I18nContextValue>({
  locale: "en",
  setLocale: () => {},
  t: (k) => k,
  ready: true,
});

function detectLocale(): Locale {
  try {
    const saved = localStorage.getItem("neuralese_locale") as Locale | null;
    if (saved && ["en", "ru", "kz"].includes(saved)) return saved;
    const browser = navigator.language.split("-")[0].toLowerCase();
    if (browser === "ru") return "ru";
    if (browser === "kk") return "kz";
  } catch {}
  return "en";
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(detectLocale);

  const setLocale = useCallback((l: Locale) => {
    localStorage.setItem("neuralese_locale", l);
    setLocaleState(l);
  }, []);

  const t = useCallback(
    (key: string): string => ALL_STRINGS[locale][key] ?? key,
    [locale]
  );

  return (
    <I18nContext.Provider value={{ locale, setLocale, t, ready: true }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  return useContext(I18nContext);
}
