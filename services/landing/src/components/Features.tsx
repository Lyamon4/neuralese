import { useState } from "react";
import { useI18n } from "../i18n/context";
import { MediaAsset } from "./MediaAsset";
import { useConfig } from "../i18n/useConfig";



export function Features() {
  const { t } = useI18n();
  const { c } = useConfig();
  const [mediaAspectRatios, setMediaAspectRatios] = useState<Record<string, number>>({});

  const rememberAspectRatio = (featureId: string, ratio: number) => {
    // Guard against bad metadata and extreme layout jumps.
    if (!Number.isFinite(ratio) || ratio < 0.75 || ratio > 2.6) return;
    setMediaAspectRatios((prev) =>
      prev[featureId] === ratio ? prev : { ...prev, [featureId]: ratio }
    );
  };

  const FEATURE_CONFIGS = [
  {
    id: "visual-graph",
    titleKey: "feature_1_title",
    descKey: "feature_1_desc",
    underlineColor: "#33a6f9",
    assetSrc: c("video_visual_editor"),
    assetType: "video" as const,
  },
  {
    id: "axon",
    titleKey: "feature_2_title",
    descKey: "feature_2_desc",
    underlineColor: "#ff6fb6",
    assetSrc: c("video_axon_mentor"),
    assetType: "video" as const,
    reverse: true,
  },
  {
    id: "simulations",
    titleKey: "feature_3_title",
    descKey: "feature_3_desc",
    underlineColor: "#77f5af",
    assetSrc: c("video_car_sim"),
    assetType: "video" as const,
  },
];

  return (
    <section id="features" className="features-section page-paint-section py-24">
      <div className="max-w-7xl mx-auto px-6">
        <div className="text-center max-w-2xl mx-auto mb-24">
          <h2 className="features-heading text-3xl md:text-5xl font-semibold tracking-tight mb-4">
            {t("features_section_heading")}
          </h2>
          <p className="features-sub text-lg">
            {t("features_section_sub")}
          </p>
        </div>

        <div className="space-y-32">
          {FEATURE_CONFIGS.map((feature) => (
            <div
              key={feature.id}
              className={`grid items-center gap-12 lg:gap-24 md:grid-cols-2 ${
                feature.reverse
                  ? "md:[&>*:first-child]:col-start-2 md:[&>*:last-child]:col-start-1 md:[&>*:last-child]:row-start-1"
                  : ""
              }`}
            >
              <div>
                <h3 className="features-heading text-3xl md:text-4xl font-semibold mb-4 tracking-tight">
                  <span
                    className="underline decoration-[0.11em] underline-offset-[0.13em]"
                    style={{ textDecorationColor: feature.underlineColor }}
                  >
                    {t(feature.titleKey)}
                  </span>
                </h3>
                <p className="features-sub text-lg leading-relaxed">
                  {t(feature.descKey)}
                </p>
              </div>

              <div
                className="features-card rounded-[2rem] border shadow-xl overflow-hidden relative block transition-[aspect-ratio] duration-500 ease-out"
                style={{ aspectRatio: mediaAspectRatios[feature.id] ?? 4 / 3 }}
              >
                <div className="absolute inset-0 border border-white/60 rounded-[2rem] pointer-events-none z-20" />
                <MediaAsset
                  src={feature.assetSrc}
                  type={feature.assetType}
                  placeholderText=""
                  className="absolute inset-0 w-full h-full"
                  isVideoIcon={feature.assetType === "video"}
                  objectFit="contain"
                  onAspectRatioChange={(ratio) => rememberAspectRatio(feature.id, ratio)}
                />
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
