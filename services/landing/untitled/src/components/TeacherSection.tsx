import { Check, Cpu, LockKeyhole, MonitorPlay, Route } from "lucide-react";

interface TeacherSectionProps {
  isDarkTheme: boolean;
}

export function TeacherSection({ isDarkTheme }: TeacherSectionProps) {
  const classroomCards = [
    {
      number: "01",
      title: "Lock the room",
      description: "Keep the whole class on the same step while students build.",
      gradient: "from-emerald-600 via-teal-500 to-cyan-500",
      visual: (
        <div className="relative flex flex-col items-center">
          <div className="flex h-28 w-28 items-center justify-center rounded-[1.5rem] bg-white text-emerald-500 shadow-2xl">
            <LockKeyhole size={44} strokeWidth={2.4} />
          </div>
          <div className="absolute -right-4 top-20 flex h-12 w-12 items-center justify-center rounded-full border-[5px] border-teal-400 bg-emerald-500 text-white shadow-xl">
            <Check size={24} strokeWidth={2.6} />
          </div>
          <div className="mt-5 rounded-full bg-white px-5 py-2 text-sm font-semibold text-emerald-700 shadow-xl">
            Synced
          </div>
        </div>
      ),
    },
    {
      number: "02",
      title: "Guide every step",
      description: "Validate work live and nudge students through each concept.",
      gradient: "from-blue-600 via-indigo-500 to-violet-500",
      visual: (
        <div className="w-full max-w-[260px] space-y-3">
          <div className="w-fit rounded-2xl bg-slate-950/65 px-4 py-3 text-sm font-semibold text-white shadow-xl">
            Build a CNN layer
          </div>
          <div className="w-fit rounded-2xl bg-slate-950/65 px-4 py-3 text-sm font-semibold text-white shadow-xl">
            Connect pooling
          </div>
          <div className="ml-auto w-fit rounded-full bg-white px-4 py-2 text-sm font-semibold text-violet-600 shadow-xl">
            Checking...
          </div>
        </div>
      ),
    },
    {
      number: "03",
      title: "Run live lessons",
      description: "Track progress, spot blockers, and keep the room moving.",
      gradient: "from-indigo-500 via-purple-500 to-pink-500",
      visual: (
        <div className="flex flex-col items-center gap-4">
          <div className="rounded-2xl bg-white px-5 py-4 text-left text-sm font-semibold text-zinc-900 shadow-2xl">
            <div className="mb-2 text-zinc-500">Class progress</div>
            <div className="flex items-center gap-2">
              <span className="rounded-md bg-blue-100 px-2 py-1 text-blue-700">32</span>
              <span className="rounded-md bg-orange-100 px-2 py-1 text-orange-700">active</span>
            </div>
          </div>
          <div className="flex items-center gap-3 text-white/70">
            <span className="h-2.5 w-2.5 rounded-full bg-white/50" />
            <span className="h-3 w-3 rounded-full bg-white" />
            <Route size={17} />
            <span className="h-2.5 w-2.5 rounded-full bg-white/50" />
          </div>
        </div>
      ),
    },
    {
      number: "04",
      title: "Works on laptops",
      description: "Browser-first lessons that do not need expensive hardware.",
      gradient: "from-rose-500 via-orange-500 to-amber-500",
      visual: (
        <div className="rounded-2xl bg-white px-5 py-5 text-zinc-900 shadow-2xl">
          <div className="mb-4 flex items-center gap-3 text-sm font-bold text-zinc-400">
            <MonitorPlay size={18} />
            Browser ready
          </div>
          <div className="space-y-3 text-sm font-medium">
            <div className="flex items-center justify-between gap-8">
              <span>CPU</span>
              <span className="h-2 w-24 rounded-full bg-gradient-to-r from-pink-500 to-orange-400" />
            </div>
            <div className="flex items-center justify-between gap-8">
              <span>GPU</span>
              <span className="h-2 w-16 rounded-full bg-gradient-to-r from-pink-500 to-orange-400" />
            </div>
            <div className="flex items-center justify-between gap-8">
              <span>WebGL</span>
              <Cpu size={16} className="text-orange-500" />
            </div>
          </div>
        </div>
      ),
    },
  ];

  return (
    <section
      id="teachers"
      className={`page-paint-section relative overflow-hidden transition-colors duration-500 ease-out ${
        isDarkTheme ? "text-white" : "text-zinc-900"
      }`}
      style={{ backgroundColor: isDarkTheme ? "#171721" : "#fafafa" }}
    >
      <div className="relative z-10 max-w-7xl mx-auto px-6 py-16 md:py-24">
        <div className="max-w-2xl mb-16">
          <h2 data-theme-trigger className={`text-3xl md:text-5xl font-semibold tracking-tight mb-6 transition-colors duration-500 ease-out ${
            isDarkTheme ? "text-white" : "text-zinc-900"
          }`}>
            Built for the classroom.
          </h2>
          <p className={`text-lg leading-relaxed transition-colors duration-500 ease-out ${
            isDarkTheme ? "text-zinc-400" : "text-zinc-600"
          }`}>
            Achieve up to <strong className={isDarkTheme ? "text-white" : "text-zinc-900"}>2x faster learning improvements</strong> with your students. Neuralese provides educators with the tools needed to manage, pace, and deliver impactful AI lessons without requiring specialized hardware.
          </p>
        </div>

        <div className="w-full">
          <div className="classroom-card-row grid gap-4 md:grid-cols-2 xl:flex xl:items-stretch">
            {classroomCards.map((card) => {
              return (
                <div
                  key={card.number}
                  data-classroom-card
                  tabIndex={0}
                  className={`classroom-card classroom-luminous-card relative flex min-h-[460px] overflow-hidden rounded-[1.75rem] bg-gradient-to-br ${card.gradient} p-6 text-white outline-none md:min-h-[500px] xl:basis-0`}
                >
                  <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_20%,rgba(255,255,255,0.28),transparent_32%)]" />
                  <div className="classroom-card-content relative z-10 flex w-full flex-col">
                    <div className="flex flex-1 items-center justify-center">
                      {card.visual}
                    </div>
                    <div>
                      <div className="mb-4 font-mono text-sm font-bold text-white/80">
                        {card.number}
                      </div>
                      <h3 className="text-xl font-semibold tracking-tight">
                        {card.title}
                      </h3>
                      <p className="classroom-card-description mt-3 max-w-sm text-sm leading-relaxed text-white/78">
                        {card.description}
                      </p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
