import { MessageCircle } from "lucide-react";

interface FooterProps {
  isDarkTheme: boolean;
}

export function Footer({ isDarkTheme }: FooterProps) {
  return (
    <footer
      className={`fixed inset-x-0 bottom-0 z-0 h-[560px] md:h-[520px] transition-colors duration-500 ease-out ${
        isDarkTheme ? "text-white" : "text-zinc-900"
      }`}
      style={{ backgroundColor: isDarkTheme ? "#171721" : "#fafafa" }}
      aria-hidden={!isDarkTheme}
    >
      <div className="relative z-20 mx-auto flex h-full max-w-7xl flex-col px-6 py-8 md:py-10">
        <div className="relative flex-1">
          <div
            className="absolute left-1/2 top-[54%] flex w-full max-w-2xl flex-col items-center text-center"
            style={{ transform: "translate(-50%, -50%)" }}
          >
            <h2 className="max-w-md text-3xl font-semibold leading-tight tracking-tight md:text-4xl">
              Have questions?
            </h2>
            <a
              href="mailto:hello@neuralese.com"
              className={`mt-8 inline-flex items-center gap-3 rounded-full border px-7 py-4 text-sm font-semibold transition-colors ${
                isDarkTheme
                  ? "border-white/20 text-white hover:border-white/40 hover:bg-white/5"
                  : "border-zinc-300 text-zinc-900 hover:border-zinc-500 hover:bg-zinc-100"
              }`}
            >
              <MessageCircle size={18} />
              Contact Neuralese Team
            </a>
          </div>
        </div>

        <div className={`border-t pt-7 transition-colors duration-500 ease-out ${
          isDarkTheme ? "border-white/10" : "border-zinc-200/80"
        }`}>
          <div className="flex flex-col gap-6 md:flex-row md:items-center md:justify-between">
            <div className="flex items-center gap-3">
              <img
                src="/demo_assets/neuralese-logo.png"
                alt="Neuralese"
                className="h-8 w-8 object-contain"
              />
              <span className="font-semibold tracking-tight">Neuralese</span>
            </div>

            <div className={`flex flex-col gap-3 text-sm md:flex-row md:items-center md:gap-8 ${
              isDarkTheme ? "text-zinc-400" : "text-zinc-500"
            }`}>
              <span>Built for modern classrooms</span>
              <span className={`hidden h-4 w-px md:block ${
                isDarkTheme ? "bg-white/20" : "bg-zinc-300"
              }`} />
              <span>&copy; {new Date().getFullYear()} Neuralese</span>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
