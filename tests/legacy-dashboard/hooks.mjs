// Node loader hooks: stub Deno-only imports so the real izzy-compensation handler runs under Node.
const STUBS = {
  "@supabase/functions-js/edge-runtime.d.ts": "export {};",
};
export async function resolve(specifier, context, next) {
  if (STUBS[specifier]) return { url: "stub:" + specifier, shortCircuit: true };
  if (specifier.endsWith("_shared/auth.ts")) return { url: "stub:auth", shortCircuit: true };
  if (specifier.endsWith("_shared/supabase.ts")) return { url: "stub:supabase", shortCircuit: true };
  return next(specifier, context);
}
export async function load(url, context, next) {
  if (url === "stub:auth") {
    return { format: "module", shortCircuit: true, source: "export async function requireSession(){ return globalThis.__SESSION; }" };
  }
  if (url === "stub:supabase") {
    return { format: "module", shortCircuit: true, source: "export function createAdminClient(){ return globalThis.__DB.client(); }" };
  }
  if (url.startsWith("stub:")) {
    return { format: "module", shortCircuit: true, source: STUBS[url.slice(5)] };
  }
  return next(url, context);
}
