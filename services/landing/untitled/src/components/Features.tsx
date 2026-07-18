import { MediaAsset } from "./MediaAsset";

const features = [
  {
    id: "visual-graph",
    title: "See the math, don't write it.",
    description:
      "Connect layers like building blocks. Understand the flow of data instantly. The 'glass box' approach ensures students actually comprehend what happens under the hood.",
    placeholderText:
      "Upload a GIF/Video here showing the drag-and-drop node graph system. Demonstrate connecting a Convolutional layer to a Pooling layer.",
    assetSrc: "/demo_assets/visual_editor.mp4",
    assetType: "video" as const,
  },
  {
    id: "axon",
    title: "Your personal teaching assistant.",
    description:
      "Meet Axon, the built-in AI tutor. Axon helps students understand what each layer does, answers questions in real-time, and guides them when they're stuck.",
    placeholderText:
      "Upload an image or GIF showing the Axon chat interface. Demonstrate Axon explaining 'MaxPooling' clearly to a student.",
    assetSrc: "/demo_assets/axon_mentor.png",
    assetType: "image" as const,
    reverse: true,
  },
  {
    id: "simulations",
    title: "Put theories to the test.",
    description:
      "Validate models instantly. Watch your trained neural networks drive an autonomous car or navigate a maze right in the browser. See decisions manifest in observable behavior.",
    placeholderText:
      "Upload a video of the Lua-scripted simulator. Show a 2D car driving itself autonomously based on the trained model.",
    assetSrc: "/demo_assets/car_sim.mp4",
    assetType: "video" as const,
  },
];

interface FeaturesProps {
  isDarkTheme: boolean;
}

export function Features({ isDarkTheme }: FeaturesProps) {
  return (
    <section
      id="features"
      className="page-paint-section py-24 transition-colors duration-500 ease-out"
      style={{ backgroundColor: isDarkTheme ? "#171721" : "#fafafa" }}
    >
      <div className="max-w-7xl mx-auto px-6">
        <div className="text-center max-w-2xl mx-auto mb-24">
          <h2 className={`text-3xl md:text-5xl font-semibold tracking-tight mb-4 transition-colors duration-500 ease-out ${
            isDarkTheme ? "text-white" : "text-zinc-900"
          }`}>
            Demystify AI for everyone.
          </h2>
          <p className={`text-lg transition-colors duration-500 ease-out ${
            isDarkTheme ? "text-zinc-300" : "text-zinc-600"
          }`}>
            We removed the programming barriers so students can focus purely on architectural and conceptual understanding.
          </p>
        </div>

        <div className="space-y-32">
          {features.map((feature) => (
            <div
              key={feature.id}
              className={`grid items-center gap-12 lg:gap-24 md:grid-cols-2 ${
                feature.reverse ? "md:[&>*:first-child]:col-start-2 md:[&>*:last-child]:col-start-1 md:[&>*:last-child]:row-start-1" : ""
              }`}
            >
              <div>
                <h3 className={`text-3xl md:text-4xl font-semibold mb-4 tracking-tight transition-colors duration-500 ease-out ${
                  isDarkTheme ? "text-white" : "text-zinc-900"
                }`}>
                  {feature.title}
                </h3>
                <p className={`text-lg leading-relaxed transition-colors duration-500 ease-out ${
                  isDarkTheme ? "text-zinc-300" : "text-zinc-600"
                }`}>
                  {feature.description}
                </p>
              </div>

              <div
                className={`aspect-[4/3] rounded-[2rem] border shadow-xl overflow-hidden relative block transition-colors duration-500 ease-out ${
                  isDarkTheme ? "border-white/10 shadow-black/40" : "border-zinc-200/60 shadow-zinc-200/50"
                }`}
                style={{ backgroundColor: isDarkTheme ? "#171721" : "#ffffff" }}
              >
                <div className="absolute inset-0 border border-white/60 rounded-[2rem] pointer-events-none z-20" />
                <MediaAsset
                  src={feature.assetSrc}
                  type={feature.assetType}
                  placeholderText={feature.placeholderText}
                  className="absolute inset-0 w-full h-full"
                  isVideoIcon={feature.assetType === "video"}
                />
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
