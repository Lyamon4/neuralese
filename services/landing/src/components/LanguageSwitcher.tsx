import { useEffect, useRef, useState } from "react";
import { LOCALES, type Locale, useI18n } from "../i18n/context";

export function LanguageSwitcher() {
  const { locale, setLocale } = useI18n();
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  // Close on Escape
  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, []);

  const current = LOCALES.find((l) => l.code === locale)!;

  return (
    <div ref={containerRef} className="lang-switcher relative">
      {/* Trigger pill */}
      <button
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        className="lang-trigger flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold tracking-wide outline-none"
      >
        <span className="lang-flag">{current.flag}</span>
        <svg
          viewBox="0 0 10 6"
          className={`lang-chevron h-2.5 w-2.5 transition-transform duration-200 ${open ? "rotate-180" : ""}`}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M1 1l4 4 4-4" />
        </svg>
      </button>

      {/* Dropdown */}
      {open && (
        <div
          role="listbox"
          aria-label="Select language"
          className="lang-dropdown absolute right-0 top-[calc(100%+8px)] z-[200] min-w-[130px] overflow-hidden rounded-2xl border py-1 shadow-xl"
        >
          {LOCALES.map((l) => {
            const isActive = l.code === locale;
            return (
              <button
                key={l.code}
                role="option"
                aria-selected={isActive}
                onClick={() => { setLocale(l.code as Locale); setOpen(false); }}
                className={`lang-option flex w-full items-center gap-3 px-4 py-2.5 text-sm font-medium outline-none ${isActive ? "lang-option--active" : ""}`}
              >
                <span className="lang-option-flag text-xs font-bold tracking-widest opacity-60">
                  {l.flag}
                </span>
                <span>{l.label}</span>
                {isActive && (
                  <svg className="ml-auto h-3.5 w-3.5 opacity-70" viewBox="0 0 12 10" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M1 5l3.5 3.5L11 1" />
                  </svg>
                )}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
