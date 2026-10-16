const MODEL_PROFILES = [
  {
    match: /^gemini-/i,
    protocol: "gemini-native",
    label: "Gemini",
  },
  {
    match: /^doubao-seedream-/i,
    protocol: "seedream",
    label: "Doubao Seedream",
  },
  {
    match: /^(gpt-image-|qwen-image-)/i,
    protocol: "openai-images",
    label: "OpenAI Images compatible",
  },
];

function getModelProfile(model) {
  if (typeof model !== "string" || model.trim() === "") {
    return { protocol: "unknown", label: "Unknown" };
  }
  return MODEL_PROFILES.find((profile) => profile.match.test(model.trim())) || {
    protocol: "unknown",
    label: "Unknown",
  };
}

function getModelFamily(model) {
  const protocol = getModelProfile(model).protocol;
  if (protocol === "gemini-native") return "gemini";
  if (protocol === "seedream") return "seedream";
  if (protocol === "openai-images") return "openai-images";
  return "unknown";
}

module.exports = { MODEL_PROFILES, getModelFamily, getModelProfile };
