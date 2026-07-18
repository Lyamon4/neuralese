import { Check, Cpu, LockKeyhole, MonitorPlay, Route } from "lucide-react";
import { useI18n } from "../i18n/context";

export function TeacherSection() {
  const { t } = useI18n();

  const classroomCards = [
    {
      numberKey: "card_01_number",
      titleKey: "card_01_title",
      descKey: "card_01_desc",
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
            {t("card_01_badge")}
          </div>
        </div>
      ),
    },
    {
      numberKey: "card_02_number",
      titleKey: "card_02_title",
      descKey: "card_02_desc",
      gradient: "from-blue-600 via-indigo-500 to-violet-500",
      visual: (
        <div className="w-full max-w-[260px] space-y-3">
          <div className="w-fit rounded-2xl bg-slate-950/65 px-4 py-3 text-sm font-semibold text-white shadow-xl">
            {t("card_02_step1")}
          </div>
          <div className="w-fit rounded-2xl bg-slate-950/65 px-4 py-3 text-sm font-semibold text-white shadow-xl">
            {t("card_02_step2")}
          </div>
          <div className="ml-auto w-fit rounded-full bg-white px-4 py-2 text-sm font-semibold text-violet-600 shadow-xl">
            {t("card_02_checking")}
          </div>
        </div>
      ),
    },
    {
      numberKey: "card_03_number",
      titleKey: "card_03_title",
      descKey: "card_03_desc",
      gradient: "from-indigo-500 via-purple-500 to-pink-500",
      visual: (
        <div className="flex flex-col items-center gap-4">
          <div className="rounded-2xl bg-white px-5 py-4 text-left text-sm font-semibold text-zinc-900 shadow-2xl">
            <div className="mb-2 text-zinc-500">{t("card_03_progress_label")}</div>
            <div className="flex items-center gap-2">
              <span className="rounded-md bg-blue-100 px-2 py-1 text-blue-700">{t("card_03_count")}</span>
              <span className="rounded-md bg-orange-100 px-2 py-1 text-orange-700">{t("card_03_status")}</span>
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
      numberKey: "card_04_number",
      titleKey: "card_04_title",
      descKey: "card_04_desc",
      gradient: "from-rose-500 via-orange-500 to-amber-500",
      visual: (
        <div className="rounded-2xl bg-white px-5 py-5 text-zinc-900 shadow-2xl">
          <div className="mb-4 flex items-center gap-3 text-sm font-bold text-zinc-400">
            <MonitorPlay size={18} />
            {t("card_04_badge")}
          </div>
          <div className="space-y-3 text-sm font-medium">
            <div className="flex items-center justify-between gap-8">
              <span>{t("card_04_cpu")}</span>
              <span className="h-2 w-24 rounded-full bg-gradient-to-r from-pink-500 to-orange-400" />
            </div>
            <div className="flex items-center justify-between gap-8">
              <span>{t("card_04_gpu")}</span>
              <span className="h-2 w-16 rounded-full bg-gradient-to-r from-pink-500 to-orange-400" />
            </div>
            <div className="flex items-center justify-between gap-8">
              <span>{t("card_04_webgl")}</span>
              <Cpu size={16} className="text-orange-500" />
            </div>
          </div>
        </div>
      ),
    },
  ];

  return (
    <section id="teachers" className="teacher-section page-paint-section relative overflow-hidden">
      <div className="relative z-10 max-w-7xl mx-auto px-6 py-16 md:py-24">
        <div className="max-w-2xl mb-16">
          <h2 data-theme-trigger className="teacher-heading text-3xl md:text-5xl font-semibold tracking-tight mb-6">
            {t("teacher_heading")}
          </h2>
          <p className="teacher-sub text-lg leading-relaxed">
            {t("teacher_sub_prefix")}{" "}
            <strong className="teacher-strong">{t("teacher_sub_highlight")}</strong>{" "}
            {t("teacher_sub_suffix")}
          </p>
        </div>

        <div className="w-full">
          <div className="classroom-card-row grid gap-4 md:grid-cols-2 xl:flex xl:items-stretch">
            {classroomCards.map((card, i) => (
              <div
                key={i}
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
                      {t(card.numberKey)}
                    </div>
                    <h3 className="text-xl font-semibold tracking-tight">
                      {t(card.titleKey)}
                    </h3>
                    <p className="classroom-card-description mt-3 max-w-sm text-sm leading-relaxed text-white/78">
                      {t(card.descKey)}
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
