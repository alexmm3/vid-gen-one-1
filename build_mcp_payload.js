const fs = require('fs');
const path = require('path');

const files = [];

function addFile(filePath, name, transform = (c) => c) {
  const content = fs.readFileSync(filePath, 'utf8');
  files.push({
    name,
    content: transform(content)
  });
}

// Add index.ts
addFile(
  'supabase/functions/generate-video/index.ts',
  'index.ts',
  (c) => c.replace(/\.\.\/_shared\//g, './_shared/')
);

// Add shared files
const sharedFiles = [
  'pipeline-orchestrator.ts',
  'providers/gemini-image.ts',
  'providers/grok-video.ts',
  'providers/grok-text.ts',
  'providers/grok-vision.ts',
  'aspect-ratio.ts',
  'logger.ts',
  'url-utils.ts',
  'subscription-check.ts'
];

for (const sf of sharedFiles) {
  addFile(`supabase/functions/_shared/${sf}`, `_shared/${sf}`);
}

const payload = {
  name: 'generate-video',
  entrypoint_path: 'index.ts',
  verify_jwt: false,
  files
};

fs.writeFileSync('mcp_payload.json', JSON.stringify(payload, null, 2));
console.log('Payload written to mcp_payload.json');
