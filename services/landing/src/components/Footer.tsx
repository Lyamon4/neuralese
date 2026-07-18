import { MessageCircle } from "lucide-react";
import { useI18n } from "../i18n/context";
import { useConfig } from "../i18n/useConfig";

export function Footer() {
  const { t } = useI18n();
  const { c } = useConfig();

  const contactEmail = c("contact_email");
  const contactHref =
    contactEmail && contactEmail !== "contact_email"
      ? `mailto:${contactEmail}`
      : "mailto:hello@neuralese.com";

  return (
    <footer className="footer fixed inset-x-0 bottom-0 z-0 h-[560px] md:h-[520px]">
      <div className="relative z-20 mx-auto flex h-full max-w-7xl flex-col px-6 py-8 md:py-10">
        <div className="relative flex-1">
          <div
            className="absolute left-1/2 top-[54%] flex w-full max-w-2xl flex-col items-center text-center"
            style={{ transform: "translate(-50%, -50%)" }}
          >
            <h2 className="footer-heading max-w-md text-3xl font-semibold leading-tight tracking-tight md:text-4xl">
              {t("footer_heading")}
            </h2>

            <a
              href={contactHref}
              className="footer-contact mt-8 inline-flex items-center gap-3 rounded-full border px-7 py-4 text-sm font-semibold transition-colors"
            >
              <MessageCircle size={18} />
              {t("footer_cta")}
            </a>
          </div>
        </div>

        <div className="footer-divider border-t pt-7">
          <div className="flex flex-col gap-6 md:flex-row md:items-center md:justify-between">
            <div className="flex items-center gap-3">
              <img
                src="/demo_assets/neuralese-logo.png"
                alt={t("footer_logo_alt")}
                className="h-8 w-8 object-contain"
              />
              <span className="footer-brand font-semibold tracking-tight">
                Neuralese
              </span>
            </div>

            <div className="footer-meta flex flex-col gap-3 text-sm md:flex-row md:items-center md:gap-8">
              <span>{t("footer_tagline")}</span>
              <span className="footer-sep hidden h-4 w-px md:block" />
              <span>&copy; {new Date().getFullYear()} Neuralese</span>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}