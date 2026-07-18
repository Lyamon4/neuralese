import { useEffect, useRef } from "react";
import { Button } from "./ui/button";
import { Play } from "lucide-react";
import { MediaAsset } from "./MediaAsset";
import { WebGLBackground } from "./WebGLBackground";

interface HeroProps {
  isDarkTheme: boolean;
}

export function Hero({ isDarkTheme }: HeroProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let ticking = false;

    const updateParallax = () => {
      if (containerRef.current) {
        const currentScroll = window.scrollY;
        const vh = window.innerHeight;
        
        // 1. Движение вверх (скорость)
        const speed = 0.15;
        const offset = currentScroll * speed;
        containerRef.current.style.setProperty("--parallax-offset", `${offset}px`);

        // 2. Исчезновение строго в диапазоне от 1.2 до 1.6 экрана
        const fadeStart = vh * 1.2;
        const fadeEnd = vh * 1.6;
        
        let opacity = 1;
        
        if (currentScroll >= fadeEnd) {
          opacity = 0;
        } else if (currentScroll > fadeStart) {
          // Интерполяция значения между fadeStart и fadeEnd
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
    
    // Инициализация при первой загрузке
    updateParallax();

    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <div ref={containerRef} className="relative z-2 w-full overflow-hidden">
      <div className={`absolute inset-0 transition-opacity duration-700 ease-out ${
        isDarkTheme ? "opacity-0" : "opacity-100"
      }`}>
        <WebGLBackground />
      </div>
      <div
        className={`pointer-events-none fixed left-1/2 top-1/2 z- w-[min(1500px,125vw)] transition-opacity duration-700 ease-out ${
          isDarkTheme ? "opacity-0" : "opacity-35"
        }`}
        style={{ 
          transform: "translate3d(-50%, calc(-30% - var(--parallax-offset, 0px)), 0)",
          opacity: isDarkTheme ? 0 : "calc(0.35 * var(--parallax-opacity, 1))"
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
          <h1 className={`text-5xl md:text-7xl font-semibold tracking-tight mb-6 leading-[1.1] transition-colors duration-700 ease-out ${
            isDarkTheme ? "text-white" : "text-zinc-900"
          }`}>
            Teach AI by <br className="hidden md:block" /> building it.
          </h1>
          
          <p className={`text-lg md:text-xl mb-10 max-w-2xl mx-auto leading-relaxed transition-colors duration-700 ease-out ${
            isDarkTheme ? "text-zinc-300" : "text-zinc-600"
          }`}>
            The visual, interactive platform that lets anyone design, train, and understand neural networks. No coding or advanced math required.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Button size="lg" className="w-full sm:w-auto shadow-xl">
              Try Neuralese Free
            </Button>
            <Button size="lg" variant="secondary" className="w-full sm:w-auto gap-2 shadow-xl">
              <Play size={18} className="fill-white/80" />
              Watch Demo
            </Button>
          </div>
        </div>

        <div className="w-full mt-16 md:mt-24">
          <div
            className={`relative aspect-[92/45] w-full max-w-5xl mx-auto rounded-[2rem] overflow-hidden border shadow-2xl block transition-colors duration-700 ease-out ${
              isDarkTheme ? "border-white/10 shadow-black/40" : "border-zinc-200/60 shadow-zinc-200/50"
            }`}
            style={{ backgroundColor: isDarkTheme ? "#171721" : "#f4f4f5" }}
            data-dark-nav-surface
          >
            {/* Inner ring for realism */}
            <div className="absolute inset-0 border border-white/40 rounded-[2rem] pointer-events-none z-20" />
            
            <MediaAsset
              src="/demo_assets/main_demo.mp4"
              type="video"
              isVideoIcon
              objectFit="contain"
              playWhenVisible
              className="w-full h-full"
              placeholderText=""
            />
          </div>
        </div>
      </section>
    </div>
  );
}
