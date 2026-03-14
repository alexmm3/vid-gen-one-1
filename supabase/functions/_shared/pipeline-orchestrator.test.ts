import { assertEquals, assertExists } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { runPipeline, PipelineContext } from "./pipeline-orchestrator.ts";
import { Logger } from "./logger.ts";

// Mock Supabase Client
class MockSupabaseClient {
  public db: Record<string, any[]> = {
    pipeline_steps: [],
    pipeline_executions: [],
    pipeline_step_executions: [],
    generations: [{ id: "gen-123", pipeline_execution_id: null }],
  };

  public storage = {
    from: (bucket: string) => ({
      upload: async (path: string, data: any, opts: any) => {
        return { data: { path }, error: null };
      },
      getPublicUrl: (path: string) => {
        return { data: { publicUrl: `https://mock-storage.com/${bucket}/${path}` } };
      }
    })
  };

  from(table: string) {
    return {
      select: (cols: string) => {
        let result = this.db[table] || [];
        return {
          eq: (key: string, val: any) => {
            result = result.filter((r) => r[key] === val);
            return {
              eq: (key2: string, val2: any) => {
                result = result.filter((r) => r[key2] === val2);
                return {
                  order: () => ({ data: result, error: null }),
                  single: () => ({ data: result[0], error: null }),
                  maybeSingle: () => ({ data: result[0], error: null }),
                };
              },
              order: () => ({ data: result, error: null }),
              single: () => ({ data: result[0], error: null }),
              maybeSingle: () => ({ data: result[0], error: null }),
            };
          },
          order: () => ({ data: result, error: null }),
          single: () => ({ data: result[0], error: null }),
          maybeSingle: () => ({ data: result[0], error: null }),
        };
      },
      insert: (data: any) => {
        const id = `mock-id-${Date.now()}-${Math.random()}`;
        const record = { id, ...data };
        if (!this.db[table]) this.db[table] = [];
        this.db[table].push(record);
        return {
          select: () => ({
            single: () => ({ data: record, error: null }),
          }),
        };
      },
      update: (data: any) => {
        return {
          eq: (key: string, val: any) => {
            if (this.db[table]) {
              for (let i = 0; i < this.db[table].length; i++) {
                if (this.db[table][i][key] === val) {
                  this.db[table][i] = { ...this.db[table][i], ...data };
                }
              }
            }
            return { data: null, error: null };
          },
        };
      },
      delete: () => {
        return {
          eq: (key: string, val: any) => {
            if (this.db[table]) {
              this.db[table] = this.db[table].filter((r) => r[key] !== val);
            }
            return {
              not: () => ({ data: null, error: null })
            };
          }
        };
      }
    };
  }
}

// Mock fetch
const originalFetch = globalThis.fetch;
globalThis.fetch = async (url: string | URL | Request, options?: RequestInit) => {
  const urlStr = url.toString();
  
  // Mock image fetch
  if (urlStr.includes("mock-image.com")) {
    return new Response(new Uint8Array([1, 2, 3]), {
      headers: { "content-type": "image/jpeg" },
    });
  }

  // Mock Gemini
  if (urlStr.includes("generativelanguage.googleapis.com")) {
    return new Response(JSON.stringify({
      candidates: [{
        content: {
          parts: [{
            inline_data: {
              mime_type: "image/jpeg",
              data: btoa("mock-enhanced-image-data")
            }
          }]
        }
      }]
    }));
  }

  // Mock Grok Vision / Text
  if (urlStr.includes("api.x.ai/v1/chat/completions")) {
    const body = JSON.parse(options?.body as string);
    let content = "Mocked text response";
    if (body.model.includes("vision")) {
      content = "A beautiful mocked description of the image.";
    } else {
      content = "An enriched mocked prompt for video generation.";
    }
    return new Response(JSON.stringify({
      choices: [{
        message: { content }
      }]
    }));
  }

  // Mock Grok Video
  if (urlStr.includes("api.x.ai/v1/videos/generations")) {
    return new Response(JSON.stringify({
      request_id: `grok-req-${Date.now()}`
    }));
  }

  return originalFetch(url, options);
};

// Set env vars
Deno.env.set("GEMINI_API_KEY", "mock-gemini-key");
Deno.env.set("GROK_API_KEY", "mock-grok-key");

Deno.test("Scenario A: Image Enhancement -> Video Generation", async () => {
  const mockSupabase = new MockSupabaseClient();
  const logger = new Logger("test-scenario-a");

  // Setup pipeline steps
  mockSupabase.db.pipeline_steps = [
    {
      id: "step-1",
      pipeline_id: "pipe-A",
      step_order: 0,
      step_type: "image_enhance",
      name: "Enhance Image",
      provider: "gemini",
      is_active: true,
      is_required: true,
      config: {
        model: "gemini-2.0-flash-exp",
        prompt_template: "Make it cinematic. {{user_prompt}}",
      },
      input_mapping: { image: "pipeline.user_image" },
      output_mapping: { enhanced_image: "result.image_url" },
    },
    {
      id: "step-2",
      pipeline_id: "pipe-A",
      step_order: 1,
      step_type: "video_generate",
      name: "Generate Video",
      provider: "grok",
      is_active: true,
      is_required: true,
      config: {
        model: "grok-imagine-video",
        image_source: "enhanced_image",
        duration: 5,
      },
      input_mapping: { image: "pipeline.enhanced_image", prompt: "pipeline.effect_concept" },
      output_mapping: { provider_request_id: "result.request_id" },
    }
  ];

  const context: PipelineContext = {
    user_image: "https://mock-image.com/photo.jpg",
    user_prompt: "Add some magic",
    effect_id: "effect-1",
    effect_name: "Cinematic Magic",
    effect_concept: "A magical cinematic scene",
  };

  const result = await runPipeline("pipe-A", "gen-123", context, mockSupabase as any, logger);

  assertExists(result.pipelineExecutionId);
  assertExists(result.providerRequestId);
  assertEquals(result.context.enhanced_image, `https://mock-storage.com/pipeline-artifacts/pipeline/${result.pipelineExecutionId}/enhanced.jpg`);
  
  // Verify DB state
  const execs = mockSupabase.db.pipeline_executions;
  assertEquals(execs.length, 1);
  assertEquals(execs[0].status, "running"); // because video is running async
  assertEquals(execs[0].current_step, 2);
  
  const stepExecs = mockSupabase.db.pipeline_step_executions;
  assertEquals(stepExecs.length, 2);
  assertEquals(stepExecs[0].status, "completed");
  assertEquals(stepExecs[1].status, "completed");
});

Deno.test("Scenario B: Vision Analysis -> Prompt Enrichment -> Video Generation", async () => {
  const mockSupabase = new MockSupabaseClient();
  const logger = new Logger("test-scenario-b");

  // Setup pipeline steps
  mockSupabase.db.pipeline_steps = [
    {
      id: "step-1",
      pipeline_id: "pipe-B",
      step_order: 0,
      step_type: "image_analyze",
      name: "Analyze Image",
      provider: "grok",
      is_active: true,
      is_required: true,
      config: {
        model: "grok-vision",
        prompt_template: "Describe this image.",
        output_key: "image_description"
      },
      input_mapping: { image: "pipeline.user_image" },
      output_mapping: { image_description: "result.image_description" },
    },
    {
      id: "step-2",
      pipeline_id: "pipe-B",
      step_order: 1,
      step_type: "prompt_enrich",
      name: "Enrich Prompt",
      provider: "grok",
      is_active: true,
      is_required: true,
      config: {
        model: "grok-text",
        prompt_template: "Image: {{image_description}}. Effect: {{effect_concept}}. User says: {{user_prompt}}. Make a prompt.",
        output_key: "enriched_prompt"
      },
      input_mapping: { prompt_context: "pipeline.image_description" },
      output_mapping: { enriched_prompt: "result.enriched_prompt" },
    },
    {
      id: "step-3",
      pipeline_id: "pipe-B",
      step_order: 2,
      step_type: "video_generate",
      name: "Generate Video",
      provider: "grok",
      is_active: true,
      is_required: true,
      config: {
        model: "grok-imagine-video",
        prompt_source: "enriched_prompt",
        duration: 10,
      },
      input_mapping: { image: "pipeline.user_image", prompt: "pipeline.enriched_prompt" },
      output_mapping: { provider_request_id: "result.request_id" },
    }
  ];

  const context: PipelineContext = {
    user_image: "https://mock-image.com/photo2.jpg",
    user_prompt: "Make it funny",
    effect_id: "effect-2",
    effect_name: "Funny Animal",
    effect_concept: "An animal doing funny things",
  };

  const result = await runPipeline("pipe-B", "gen-124", context, mockSupabase as any, logger);

  assertExists(result.pipelineExecutionId);
  assertExists(result.providerRequestId);
  assertEquals(result.context.image_description, "A beautiful mocked description of the image.");
  assertEquals(result.context.enriched_prompt, "An enriched mocked prompt for video generation.");
  
  // Verify DB state
  const execs = mockSupabase.db.pipeline_executions;
  assertEquals(execs.length, 1);
  assertEquals(execs[0].current_step, 3);
  
  const stepExecs = mockSupabase.db.pipeline_step_executions;
  assertEquals(stepExecs.length, 3);
  assertEquals(stepExecs[0].status, "completed");
  assertEquals(stepExecs[1].status, "completed");
  assertEquals(stepExecs[2].status, "completed");
});

Deno.test("Scenario C: Step Failure Handling (Required Step)", async () => {
  const mockSupabase = new MockSupabaseClient();
  const logger = new Logger("test-scenario-c");

  // Override fetch to simulate a failure
  const oldFetch = globalThis.fetch;
  globalThis.fetch = async (url: string | URL | Request, options?: RequestInit) => {
    if (url.toString().includes("generativelanguage.googleapis.com")) {
      return new Response("Internal Server Error", { status: 500 });
    }
    return oldFetch(url, options);
  };

  mockSupabase.db.pipeline_steps = [
    {
      id: "step-1",
      pipeline_id: "pipe-C",
      step_order: 0,
      step_type: "image_enhance",
      name: "Enhance Image",
      provider: "gemini",
      is_active: true,
      is_required: true, // This will abort the pipeline
      config: { model: "gemini-2.0-flash-exp", prompt_template: "Enhance" },
      input_mapping: { image: "pipeline.user_image" },
      output_mapping: { enhanced_image: "result.image_url" },
    },
    {
      id: "step-2",
      pipeline_id: "pipe-C",
      step_order: 1,
      step_type: "video_generate",
      name: "Generate Video",
      provider: "grok",
      is_active: true,
      is_required: true,
      config: { model: "grok-imagine-video" },
      input_mapping: {},
      output_mapping: {},
    }
  ];

  const context: PipelineContext = {
    user_image: "https://mock-image.com/photo.jpg",
    user_prompt: "",
    effect_id: "effect-3",
    effect_name: "Fail Test",
    effect_concept: "Test",
  };

  try {
    await runPipeline("pipe-C", "gen-125", context, mockSupabase as any, logger);
    throw new Error("Should have thrown");
  } catch (e: any) {
    assertEquals(e.message.includes("Pipeline step \"Enhance Image\" failed"), true);
  }

  // Verify DB state
  const execs = mockSupabase.db.pipeline_executions;
  assertEquals(execs[0].status, "failed");
  
  const stepExecs = mockSupabase.db.pipeline_step_executions;
  assertEquals(stepExecs.length, 1); // Only first step attempted
  assertEquals(stepExecs[0].status, "failed");

  // Restore fetch
  globalThis.fetch = oldFetch;
});
