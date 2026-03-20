const fs = require('fs');
const file = 'supabase/functions/_shared/pipeline-orchestrator.ts';
let code = fs.readFileSync(file, 'utf8');

const oldFunc = `function resolveInputs(context: PipelineContext, inputMapping: Json): Json {
  const resolved: Json = {};
  for (const [key, path] of Object.entries(inputMapping)) {
    if (typeof path === "string") {
      resolved[key] = resolveContextValue(context, path);
    } else {
      resolved[key] = path;
    }
  }
  return resolved;
}`;

const newFunc = `function resolveInputs(context: PipelineContext, inputMapping: Json): Json {
  const resolved: Json = {};
  if (!inputMapping) return resolved;
  let mapping = inputMapping;
  if (typeof mapping === "string") {
    try { mapping = JSON.parse(mapping); } catch (e) {}
  }
  for (const [key, path] of Object.entries(mapping)) {
    if (typeof path === "string") {
      resolved[key] = resolveContextValue(context, path);
      console.log(\`[resolveInputs] key=\${key}, path=\${path}, resolved=\${resolved[key]}\`);
    } else {
      resolved[key] = path;
    }
  }
  return resolved;
}`;

code = code.replace(oldFunc, newFunc);
fs.writeFileSync(file, code);
console.log("Patched resolveInputs");
