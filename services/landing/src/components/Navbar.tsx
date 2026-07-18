import { useEffect, useRef } from "react";
import { Button } from "./ui/button";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { useI18n } from "../i18n/context";
import { useConfig } from "../i18n/useConfig";

export function Navbar() {
  const { t } = useI18n();
  const linksRef = useRef<HTMLDivElement>(null);
  const { c } = useConfig();

  useEffect(() => {
    let frameId = 0;

    const updateLinkContrast = () => {
      frameId = 0;
      const links = linksRef.current;
      if (!links) return;

      const linkRect = links.getBoundingClientRect();
      const linkX = linkRect.left + linkRect.width / 2;
      const linkY = linkRect.top + linkRect.height / 2;
      const darkSurfaces = document.querySelectorAll<HTMLElement>("[data-dark-nav-surface]");

      const isOverDark = Array.from(darkSurfaces).some((surface) => {
        const rect = surface.getBoundingClientRect();
        return linkX >= rect.left && linkX <= rect.right && linkY >= rect.top && linkY <= rect.bottom;
      });

      links.setAttribute("data-over-dark", isOverDark ? "true" : "false");
    };

    const requestUpdate = () => {
      if (frameId) return;
      frameId = window.requestAnimationFrame(updateLinkContrast);
    };

    updateLinkContrast();
    window.addEventListener("scroll", requestUpdate, { passive: true });
    window.addEventListener("resize", requestUpdate);

    return () => {
      if (frameId) window.cancelAnimationFrame(frameId);
      window.removeEventListener("scroll", requestUpdate);
      window.removeEventListener("resize", requestUpdate);
    };
  }, []);

  return (
    <nav className="navbar fixed left-1/2 top-3 z-50 w-[calc(100%-2rem)] max-w-7xl -translate-x-1/2 overflow-visible rounded-full border shadow-[0_18px_60px_rgba(0,0,0,0.10)]">
      <div className="navbar-bg absolute inset-0 rounded-full" style={{ opacity: 0.25 }} />
      <div
        className="absolute inset-0 rounded-full"
        style={{
          backgroundColor: "transparent",
          opacity: 0.9,
          backdropFilter: "blur(12px) saturate(1.3)",
          WebkitBackdropFilter: "blur(12px) saturate(1.3)",
        }}
      />
      <div className="relative z-10 flex items-center justify-between px-4 py-3 md:grid md:grid-cols-[1fr_auto_1fr] md:px-6">
        {/* Logo — always visible */}
        <div className="flex items-center gap-2 shrink-0">
          <img
            src="/demo_assets/neuralese-logo.png"
            alt={t("nav_logo_alt")}
            className="w-9 h-9 object-contain"
          />
          <span className="navbar-brand font-semibold text-xl tracking-tight">
            Neuralese
          </span>
        </div>

        {/* Nav links — desktop only, centred */}
        <div ref={linksRef} className="hidden md:flex items-center justify-center gap-9">
          <a href="#features" className="nav-link text-sm font-medium">{t("nav_features")}</a>
          <a href="#teachers" className="nav-link text-sm font-medium">{t("nav_for_teachers")}</a>
        </div>

        {/* Right controls — lang switcher + CTA */}
        <div className="flex items-center justify-end gap-2 shrink-0">
          <LanguageSwitcher />
          <a href={c("download_url")} download>
            <Button className="px-4 md:px-6 text-sm">{t("nav_try_free")}</Button>
          </a>
        </div>
      </div>
    </nav>
  );
}
