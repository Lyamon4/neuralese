import { useEffect, useRef, useState } from "react";
import { Button } from "./ui/button";
import { Play } from "lucide-react";
import { MediaAsset } from "./MediaAsset";
import { WebGLBackground } from "./WebGLBackground";
import { useI18n } from "../i18n/context";
import { useConfig } from "../i18n/useConfig";

export function Hero() {
  const { t } = useI18n();
  const { c } = useConfig();  // ← here
  const containerRef = useRef<HTMLDivElement>(null);
  const [demoAspectRatio, setDemoAspectRatio] = useState(92 / 45);

  useEffect(() => {
    let ticking = false;

    const updateParallax = () => {
      if (containerRef.current) {
        const currentScroll = window.scrollY;
        const vh = window.innerHeight;
        const speed = 0.15;
        const offset = currentScroll * speed;
        containerRef.current.style.setProperty("--parallax-offset", `${offset}px`);

        const fadeStart = vh * 1.2;
        const fadeEnd = vh * 1.6;
        let opacity = 1;
        if (currentScroll >= fadeEnd) {
          opacity = 0;
        } else if (currentScroll > fadeStart) {
          opacity = 1 - (currentScroll - fadeStart) / (fadeEnd - fadeStart);
        }
        containerRef.current.style.setProperty("--parallax-opacity", `${opacity}`);
      }
      ticking = false;
    };

    const handleScroll = () => {
      if (!ticking) {
        window.requestAnimationFrame(updateParallax);
        ticking = true;
      }
    };

    window.addEventListener("scroll", handleScroll, { passive: true });
    updateParallax();
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <div ref={containerRef} className="relative z-2 w-full overflow-hidden">
      <div className="hero-webgl absolute inset-0">
        <WebGLBackground />
      </div>
      <div
        className="pointer-events-none fixed left-1/2 top-1/2 z- w-[min(1500px,125vw)] hero-neural-img"
        style={{
          transform: "translate3d(-50%, calc(-30% - var(--parallax-offset, 0px)), 0)",
          opacity: "calc(0.35 * var(--parallax-opacity, 1))",
        }}
      >
        <img
          src="/demo_assets/hero-neural-graph.png"
          alt=""
          className="w-full select-none blur-[8px] brightness-[1.85] saturate-[1.9]"
          draggable={false}
        />
      </div>
      <section className="relative z-10 pt-32 pb-20 px-6 md:pt-40 md:pb-32 max-w-7xl mx-auto flex flex-col items-center text-center">
        <div className="max-w-3xl">
          <h1
            className="hero-heading text-5xl md:text-7xl font-semibold tracking-tight mb-6 leading-[1.1]"
            style={{ fontFamily: '"Fraunces", ui-serif, Georgia, serif' }}
          >
            {t("hero_heading_line1")} <br className="hidden md:block" /> {t("hero_heading_line2")}
          </h1>
          <p className="hero-sub text-lg md:text-xl mb-10 max-w-2xl mx-auto leading-relaxed">
            {t("hero_sub")}
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
<a href={c("download_url")} download>
  <Button size="lg" className="w-full sm:w-auto gap-2 shadow-xl">
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-5 w-5 fill-current">
      <path d="M3 5.1 10.7 4v7.4H3V5.1Zm8.8-1.25L21 2.5v8.9h-9.2V3.85ZM3 12.6h7.7V20L3 18.9v-6.3Zm8.8 0H21v8.9l-9.2-1.3v-7.6Z" />
    </svg>
    {t("hero_cta_download")}
  </Button>
</a>
            <a href="#hero-demo">
  <Button size="lg" variant="secondary" className="w-full sm:w-auto gap-2 shadow-xl">
    <Play size={18} className="fill-white/80" />
    {t("hero_cta_watch")}
  </Button>
</a>
          </div>
        </div>

        <div className="w-full mt-16 md:mt-24">
          <div
            id="hero-demo"
            className="hero-demo-frame relative w-full max-w-5xl mx-auto rounded-[2rem] overflow-hidden border shadow-2xl block transition-[aspect-ratio] duration-500 ease-out"
            style={{ aspectRatio: demoAspectRatio }}
            data-dark-nav-surface
          >
            <div className="absolute inset-0 border border-white/40 rounded-[2rem] pointer-events-none z-20" />
            <MediaAsset
              src={c("video_main_demo")}
              type="video"
              isVideoIcon
              objectFit="contain"
              playWhenVisible
              className="hero-demo-media w-full h-full"
              placeholderText=""
              onAspectRatioChange={setDemoAspectRatio}
            />
          </div>
        </div>
      </section>
    </div>
  );
}