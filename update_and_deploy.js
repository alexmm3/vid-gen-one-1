const fs = require('fs');

// Read the edge function data
const data = JSON.parse(fs.readFileSync('/Users/alexm/.cursor/projects/Users-alexm-Documents-video-app-ios-effects/agent-tools/3b29a45d-e75a-472d-9634-08dcc38e8da0.txt', 'utf8'));

// Find gemini-image.ts
const geminiFile = data.files.find(f => f.name === '_shared/providers/gemini-image.ts');

if (geminiFile) {
  geminiFile.content = geminiFile.content.replace(
    'const apiKey = Deno.env.get("GEMINI_API_KEY");\n  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");',
    'const apiKey = Deno.env.get("GEMINI_API_KEY") || Deno.env.get("GEMENI_API_KEY");\n  if (!apiKey) throw new Error("GEMINI_API_KEY (or GEMENI_API_KEY) not configured");'
  );
}

// Write the payload for MCP
const payload = {
  name: "generate-video",
  entrypoint_path: "index.ts",
  verify_jwt: true,
  files: data.files
};

fs.writeFileSync('deploy_payload.json', JSON.stringify(payload, null, 2));
console.log("Created deploy_payload.json");
