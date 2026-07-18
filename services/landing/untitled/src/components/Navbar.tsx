import { useEffect, useRef, useState } from "react";
import { Button } from "./ui/button";

interface NavbarProps {
  isDarkTheme: boolean;
}

export function Navbar({ isDarkTheme }: NavbarProps) {
  const linksRef = useRef<HTMLDivElement>(null);
  const [isOverDarkSurface, setIsOverDarkSurface] = useState(false);
  const isOverDarkSurfaceRef = useRef(false);
  const useLightNavLinks = isDarkTheme || isOverDarkSurface;

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

      const nextIsOverDarkSurface = Array.from(darkSurfaces).some((surface) => {
        const rect = surface.getBoundingClientRect();
        return linkX >= rect.left && linkX <= rect.right && linkY >= rect.top && linkY <= rect.bottom;
      });

      if (nextIsOverDarkSurface !== isOverDarkSurfaceRef.current) {
        isOverDarkSurfaceRef.current = nextIsOverDarkSurface;
        setIsOverDarkSurface(nextIsOverDarkSurface);
      }
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
    <nav
      className={`fixed left-1/2 top-3 z-50 w-[calc(100%-2rem)] max-w-7xl -translate-x-1/2 overflow-hidden rounded-full border shadow-[0_18px_60px_rgba(0,0,0,0.10)] transition-colors duration-500 ease-out ${
        isDarkTheme ? "border-white/10" : "border-white/80"
      }`}
    >
      <div
        className="absolute inset-0 transition-colors duration-500 ease-out"
        style={{
          backgroundColor: isDarkTheme ? "#171721" : "#ffffff",
          opacity: 0.25,
        }}
      />
      <div
        className="absolute inset-0 transition-colors duration-500 ease-out"
        style={{
          backgroundColor: "transparent",
          opacity: 0.9,
          backdropFilter: "blur(12px) saturate(1.3)",
          WebkitBackdropFilter: "blur(12px) saturate(1.3)",
        }}
      />
      <div className="relative z-10 grid grid-cols-[1fr_auto_1fr] items-center px-5 py-3 md:px-6">
        <div className="flex items-center gap-2">
          <img
            src="/demo_assets/neuralese-logo.png"
            alt="Neuralese"
            className="w-9 h-9 object-contain"
          />
          <span className={`font-semibold text-xl tracking-tight transition-colors duration-500 ease-out ${
            isDarkTheme ? "text-white" : "text-zinc-900"
          }`}>
            Neuralese
          </span>
        </div>

        <div ref={linksRef} className="hidden md:flex items-center justify-center gap-9">
          <a href="#features" className={`text-sm font-medium transition-colors duration-500 ease-out ${
            useLightNavLinks ? "text-white/85 hover:text-white" : "text-zinc-900/75 hover:text-zinc-900"
          }`}>
            Features
          </a>
          <a href="#teachers" className={`text-sm font-medium transition-colors duration-500 ease-out ${
            useLightNavLinks ? "text-white/85 hover:text-white" : "text-zinc-900/75 hover:text-zinc-900"
          }`}>
            For Teachers
          </a>
        </div>

        <div className="flex items-center justify-end">
          <Button className="px-6">Try Free</Button>
        </div>
      </div>
    </nav>
  );
}
