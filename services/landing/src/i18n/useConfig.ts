import { useEffect, useState } from "react";
import { useI18n } from "./context";

type ConfigValue = string | Record<string, string>;
type Config = Record<string, ConfigValue>;
let cache: Config | null = null;

export function useConfig() {
  const { locale } = useI18n();
  const [config, setConfig] = useState<Config>(cache ?? {});

  useEffect(() => {
    if (cache) return;
    fetch("/locales/config.json")
      .then((r) => r.json())
      .then((data) => { cache = data; setConfig(data); });
  }, []);

  // Supports two shapes:
  // - "key": "url"                              -> same for every locale
  // - "key": { "default": "url", "en": "url" }   -> per-locale override, falls back to "default"
  const c = (key: string): string => {
    const value = config[key];
    if (value == null) return key;
    if (typeof value === "string") return value;
    return value[locale] ?? value.default ?? key;
  };

  return { c };
}