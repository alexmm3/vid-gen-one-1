const fs = require('fs');
const file = 'supabase/functions/_shared/pipeline-orchestrator.ts';
let code = fs.readFileSync(file, 'utf8');

const oldFunc = `function storeOutputs(context: PipelineContext, stepName: string, outputMapping: Json, result: Json): void {
  // Store in the steps namespace
  if (!context.steps) {
    context.steps = {};
  }
  (context.steps as any)[stepName] = { output: result };

  // Also map to specific context keys if requested
  for (const [contextKey, resultPath] of Object.entries(outputMapping)) {
    if (typeof resultPath === "string") {
      let path = resultPath;
      if (path.startsWith("result.")) {
        path = path.substring(7); // remove "result."
      }
      const parts = path.split(".");
      // deno-lint-ignore no-explicit-any
      let current: any = result;
      for (const part of parts) {
        if (current == null) break;
        current = current[part];
      }
      if (current !== undefined) {
        context[contextKey] = current;
      }
    }
  }
}`;

const newFunc = `function storeOutputs(context: PipelineContext, stepName: string, outputMapping: Json, result: Json): void {
  console.log(\`[storeOutputs] stepName=\${stepName}, outputMapping type=\${typeof outputMapping}\`);
  if (!context.steps) {
    context.steps = {};
  }
  (context.steps as any)[stepName] = { output: result };

  if (!outputMapping) return;
  if (typeof outputMapping === "string") {
    try { outputMapping = JSON.parse(outputMapping); } catch (e) {}
  }

  for (const [contextKey, resultPath] of Object.entries(outputMapping)) {
    console.log(\`[storeOutputs] mapping contextKey=\${contextKey} from resultPath=\${resultPath}\`);
    if (typeof resultPath === "string") {
      let path = resultPath;
      if (path.startsWith("result.")) {
        path = path.substring(7);
      }
      const parts = path.split(".");
      // deno-lint-ignore no-explicit-any
      let current: any = result;
      for (const part of parts) {
        if (current == null) break;
        current = current[part];
      }
      console.log(\`[storeOutputs] mapped contextKey=\${contextKey} to value=\${current}\`);
      if (current !== undefined) {
        context[contextKey] = current;
      }
    }
  }
}`;

code = code.replace(oldFunc, newFunc);
fs.writeFileSync(file, code);
console.log("Patched storeOutputs");
