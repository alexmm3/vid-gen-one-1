// The backend doesn't currently generate typed Supabase database schema bindings for edge
// functions. Using the raw client type makes table inserts/updates collapse to `never`
// during local Deno checks, even though the functions are valid at runtime.
//
// Keep the client surface permissive here and recover domain safety with local row/DTO
// interfaces in the function code where it matters.

// deno-lint-ignore no-explicit-any
export type SupabaseClientLike = any;
