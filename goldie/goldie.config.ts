import type { GoldieConfig } from "/Users/ervenstnoel/.npm/_npx/18a971dee120d222/node_modules/goldie/dist/config.d.ts";

const APP_ROOT = "/Users/ervenstnoel/Documents/Nanobeasts Native";

const config: GoldieConfig = {
  appRoot: APP_ROOT,
  appPath: `${APP_ROOT}/build/Goldie/Build/Products/Release-iphonesimulator/Nanobeasts.app`,
  bundleId: "com.twosyntaxerrors.nanobeasts.native",
  devices: ["iphone-6.9"],
  locales: ["en-US"],
  appearance: "dark",
  frame: { variant: "17-pro-blue" },
  theme: {
    background:
      "radial-gradient(circle at 76% 12%, rgba(44,214,212,.28), transparent 30%), linear-gradient(155deg, #061113 0%, #0B2225 56%, #16383A 100%)",
    headlineColor: "#F7FFFE",
    subheadColor: "#A9DAD6",
    fontFamily: '"Montserrat", -apple-system, "SF Pro Display", system-ui, sans-serif',
    copyHeightRatio: 0.22,
    deviceWidthRatio: 0.8,
    template: "uniform",
    layout: "classic",
  },
  store: {
    name: "Nanobeasts",
    subtitle: { "en-US": "Walk. Hatch. Evolve." },
    developer: "Two Syntax Errors",
    category: "Health & Fitness",
    rating: 4.9,
    ratingCount: "2.4K Ratings",
    ageRating: "4+",
    price: "Free",
    description: {
      "en-US":
        "Turn everyday movement into a creature-collecting adventure. Track workouts, hatch eggs, evolve Nanobeasts, and share every route with the rewards you discovered along the way.",
    },
  },
  scenes: [
    {
      kind: "screenshot",
      id: "evolution",
      flow: "store-01-evolution",
      headline: { "en-US": "Every step evolves" },
      subhead: { "en-US": "Movement unlocks creatures, stages, and surprises." },
    },
    {
      kind: "screenshot",
      id: "workout",
      flow: "store-02-workout",
      headline: { "en-US": "Explore as you move" },
      subhead: { "en-US": "Track your route, clear the fog, and grow your companion." },
    },
    {
      kind: "screenshot",
      id: "share",
      flow: "store-03-share",
      headline: { "en-US": "Share the whole adventure" },
      subhead: { "en-US": "Post your route, stats, evolution, and newest egg." },
    },
    {
      kind: "screenshot",
      id: "dex",
      flow: "store-04-dex",
      headline: { "en-US": "Discover every species" },
      subhead: { "en-US": "Build a field guide powered by your daily movement." },
    },
    {
      kind: "screenshot",
      id: "stats",
      flow: "store-05-stats",
      headline: { "en-US": "See your momentum" },
      subhead: { "en-US": "Spot streaks, patterns, and your strongest days." },
    },
    {
      kind: "preview",
      id: "preview",
      segments: [
        { id: "evolve", flow: "store-preview-01-evolve", holdSeconds: 5 },
        { id: "train", flow: "store-preview-02-train", holdSeconds: 5 },
        { id: "share", flow: "store-preview-03-share", holdSeconds: 5 },
      ],
    },
  ],
};

export default config;
