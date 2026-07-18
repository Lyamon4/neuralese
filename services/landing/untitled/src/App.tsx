/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { useEffect, useRef, useState } from "react";
import { Navbar } from "./components/Navbar";
import { Hero } from "./components/Hero";
import { Features } from "./components/Features";
import { TeacherSection } from "./components/TeacherSection";
import { Footer } from "./components/Footer";

export default function App() {
  const [isDarkBackground, setIsDarkBackground] = useState(false);
  const isDarkBackgroundRef = useRef(false);

  useEffect(() => {
    let frameId = 0;

    const updateBackground = () => {
      frameId = 0;
      const teacherSection = document.getElementById("teachers");
      if (!teacherSection) return;

      const rect = teacherSection.getBoundingClientRect();
      const nextIsDarkBackground = rect.top <= window.innerHeight * 0.45;

      if (nextIsDarkBackground !== isDarkBackgroundRef.current) {
        isDarkBackgroundRef.current = nextIsDarkBackground;
        setIsDarkBackground(nextIsDarkBackground);
      }
    };

    const requestUpdate = () => {
      if (frameId) return;
      frameId = window.requestAnimationFrame(updateBackground);
    };

    const observer = new IntersectionObserver(requestUpdate, {
      rootMargin: "0px",
      threshold: 0,
    });

    const teacherSection = document.getElementById("teachers");
    if (teacherSection) {
      observer.observe(teacherSection);
    }

    updateBackground();
    window.addEventListener("scroll", requestUpdate, { passive: true });
    window.addEventListener("resize", requestUpdate);

    return () => {
      observer.disconnect();
      if (frameId) window.cancelAnimationFrame(frameId);
      window.removeEventListener("scroll", requestUpdate);
      window.removeEventListener("resize", requestUpdate);
    };
  }, []);

  return (
    <div
      className={`min-h-screen selection:bg-blue-100 selection:text-blue-900 font-sans transition-colors duration-500 ease-out ${
        isDarkBackground ? "dark" : ""
      }`}
      style={{ backgroundColor: isDarkBackground ? "#171721" : "#fafafa" }}
    >
      <Navbar isDarkTheme={isDarkBackground} />
      <main className="relative z-10">
        <Hero isDarkTheme={isDarkBackground} />
        <Features isDarkTheme={isDarkBackground} />
        <TeacherSection isDarkTheme={isDarkBackground} />
      </main>
      <div aria-hidden="true" className="h-[360px]" />
      <Footer isDarkTheme={isDarkBackground} />
    </div>
  );
}
