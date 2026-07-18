import { useState, useEffect, useRef } from "react";
import { Play } from "lucide-react";

interface MediaAssetProps {
  src: string;
  type: "video" | "image";
  placeholderText: string;
  className?: string;
  isVideoIcon?: boolean;
  objectFit?: "cover" | "contain";
  playWhenVisible?: boolean;
}

const objectFitClass = {
  cover: "object-cover",
  contain: "object-contain",
};

export function MediaAsset({
  src,
  type,
  placeholderText,
  className = "",
  isVideoIcon,
  objectFit = "cover",
  playWhenVisible = false,
}: MediaAssetProps) {
  const [assetExists, setAssetExists] = useState<boolean | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    let isMounted = true;
    if (type === 'image') {
      const img = new Image();
      img.onload = () => isMounted && setAssetExists(true);
      img.onerror = () => isMounted && setAssetExists(false);
      img.src = src;
    } else if (type === 'video') {
      const video = document.createElement('video');
      video.onloadeddata = () => isMounted && setAssetExists(true);
      video.onerror = () => isMounted && setAssetExists(false);
      video.src = src;
      video.load();
    }
    return () => { isMounted = false; };
  }, [src, type]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || type !== "video" || !playWhenVisible || !assetExists) return;

    const updatePlayback = () => {
      const rect = video.getBoundingClientRect();
      const shouldPlay =
        rect.top <= window.innerHeight * 0.6 &&
        rect.bottom > 0;

      if (shouldPlay) {
        void video.play();
      } else {
        video.pause();
      }
    };

    const observer = new IntersectionObserver(
      updatePlayback,
      { threshold: 0.1 }
    );

    observer.observe(video);
    window.addEventListener("scroll", updatePlayback, { passive: true });
    window.addEventListener("resize", updatePlayback);
    video.addEventListener("loadedmetadata", updatePlayback);
    updatePlayback();

    return () => {
      observer.disconnect();
      window.removeEventListener("scroll", updatePlayback);
      window.removeEventListener("resize", updatePlayback);
      video.removeEventListener("loadedmetadata", updatePlayback);
    };
  }, [assetExists, playWhenVisible, type]);

  if (assetExists === null) {
    return <div className={`animate-pulse bg-zinc-100 ${className}`} />;
  }

  if (assetExists) {
    if (type === "video") {
      return (
        <video 
          ref={videoRef}
          src={src} 
          autoPlay={!playWhenVisible}
          muted 
          loop 
          playsInline 
          preload={playWhenVisible ? "metadata" : "auto"}
          className={`${objectFitClass[objectFit]} ${className}`}
        />
      );
    }
    return <img src={src} alt="" className={`${objectFitClass[objectFit]} ${className}`} />;
  }

  // Placeholder
  return (
    <div className={`flex items-center justify-center relative overflow-hidden bg-zinc-50 ${className}`}>
      <div className="absolute inset-0 bg-gradient-to-br from-zinc-100 to-zinc-200" />
      <div className="relative z-10 text-center p-6 w-full h-full flex flex-col items-center justify-center">
        <div className="border border-dashed border-zinc-300 bg-white/60 backdrop-blur-sm rounded-xl p-6 md:p-8 max-w-sm shadow-sm w-full">
          {isVideoIcon && (
            <div className="w-16 h-16 bg-white/90 backdrop-blur rounded-2xl flex items-center justify-center mx-auto mb-5 text-zinc-400 shadow-[0_2px_8px_rgba(0,0,0,0.05)] border border-zinc-100">
              <Play size={24} className="ml-1" />
            </div>
          )}
          <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest mb-3">Media Placeholder</p>
          <p className="text-zinc-600 font-medium leading-relaxed mb-4 text-sm md:text-base">
            {placeholderText}
          </p>
          <div className="bg-zinc-100 rounded-lg py-2 px-3 inline-block">
             <p className="text-xs font-mono text-zinc-500 break-all">{src}</p>
          </div>
        </div>
      </div>
    </div>
  );
}
