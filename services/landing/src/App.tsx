/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { useEffect } from "react";
import { Navbar } from "./components/Navbar";
import { Hero } from "./components/Hero";
import { Features } from "./components/Features";
import { TeacherSection } from "./components/TeacherSection";
import { Footer } from "./components/Footer";

export default function App() {
  useEffect(() => {
    const root = document.documentElement;
    let frameId = 0;
    let currentTheme: "light" | "dark" | null = null;

    const updateTheme = () => {
      frameId = 0;
      const teacherSection = document.getElementById("teachers");
      if (!teacherSection) return;

      const rect = teacherSection.getBoundingClientRect();
      const nextTheme: "light" | "dark" =
        rect.top <= window.innerHeight * 0.45 ? "dark" : "light";

      if (nextTheme !== currentTheme) {
        currentTheme = nextTheme;
        // Single DOM write — zero React re-renders, CSS handles all transitions
        root.setAttribute("data-theme", nextTheme);
      }
    };

    const requestUpdate = () => {
      if (frameId) return;
      frameId = window.requestAnimationFrame(updateTheme);
    };

    const observer = new IntersectionObserver(requestUpdate, {
      rootMargin: "0px",
      threshold: 0,
    });

    const teacherSection = document.getElementById("teachers");
    if (teacherSection) observer.observe(teacherSection);

    updateTheme();
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
    <div className="app-root min-h-screen selection:bg-blue-100 selection:text-blue-900 font-sans">
      <Navbar />
      <main className="relative z-10">
        <Hero />
        <Features />
        <TeacherSection />
      </main>
      <div aria-hidden="true" className="h-[360px]" />
      <Footer />
    </div>
  );
}
