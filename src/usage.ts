// What the desk's model calls would cost at API prices: each call's tokens by model, kept per kind of work (docs/api.md →
// Usage). Claude Code prices its own calls (modelUsage's costUSD); your agent's transcripts are priced from PRICES.
import { Context, Effect } from "effect";
import { field, isRecord, jsonOf, num, str } from "./narrow.ts";

export const WORK = {
  triage: "Sorting and scoring the Inbox",
  review: "AI reviews",
  issue: "Issue pre-reviews",
  automation: "Automations",
  comments: "Reviewers' comments",
  sessions: "Sessions that need you",
  attribution: "Bot PRs opened for you",
  merging: "Merging",
  agent: "Ask your agent",
  other: "Other",
} as const;
export type WorkKind = keyof typeof WORK;

export interface Usage {
  model: string;
  input: number;
  output: number;
  cache_read: number;
  cache_write: number;
  cost: number | null; // USD at API prices; null for a model PRICES doesn't know
}

// Which work a model call is for, set where the call starts; one with none counts as Other.
const WorkOf = Context.Reference<WorkKind>("desk/WorkOf", { defaultValue: () => "other" });
export const as =
  (work: WorkKind) =>
  <A, E, R>(e: Effect.Effect<A, E, R>): Effect.Effect<A, E, R> =>
    Effect.provideService(e, WorkOf, work);

// Where calls are recorded: the running desk's store (Desk.start), else nowhere.
let sink: ((work: WorkKind, usage: Usage[]) => void) | null = null;
export function meterTo(to: typeof sink): void {
  sink = to;
}
export const meter = (usage: Usage[]): Effect.Effect<void> =>
  Effect.gen(function* () {
    const work = yield* WorkOf;
    if (usage.length) sink?.(work, usage);
  });

// USD per million tokens. A cache write is 1.25× input for 5 minutes, 2× for an hour.
const PRICES: [prefix: string, input: number, output: number, cacheRead: number][] = [
  ["claude-fable-5-2", 8, 40, 0.2],
  ["claude-mythos-5-2", 8, 40, 0.2],
  ["claude-fable-5", 10, 50, 1],
  ["claude-opus-5-5", 4, 20, 0.2],
  ["claude-opus-5", 5, 25, 0.5],
  ["claude-opus-4", 5, 25, 0.5],
  ["claude-sonnet-5-5", 2, 10, 0.1],
  ["claude-sonnet-5", 2, 10, 0.2],
  ["claude-sonnet-4", 3, 15, 0.3],
  ["claude-haiku-5-5", 0.1, 0.5, 0.01],
  ["claude-haiku-4", 1, 5, 0.1],
];
const priceOf = (model: string) => PRICES.find(([p]) => model.startsWith(p));

// claude -p's modelUsage: { [model]: { inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens, costUSD } }.
export function claudeUsage(modelUsage: unknown): Usage[] {
  if (!isRecord(modelUsage)) return [];
  return Object.entries(modelUsage).map(([model, u]) => {
    const n = (k: string) => num(field(u, k)) ?? 0;
    return {
      model,
      input: n("inputTokens"),
      output: n("outputTokens"),
      cache_read: n("cacheReadInputTokens"),
      cache_write: n("cacheCreationInputTokens"),
      cost: num(field(u, "costUSD")) ?? null,
    };
  });
}

// A transcript's model requests, each once (Claude Code writes a message's blocks as entries of their own, each with its
// usage), priced from PRICES.
export function transcriptUsage(jsonl: string): { id: string; at: string; usage: Usage }[] {
  const requests = new Map<string, { id: string; at: string; usage: Usage }>();
  for (const line of jsonl.split("\n")) {
    if (!line.includes('"assistant"')) continue;
    const entry = jsonOf(line);
    const at = str(field(entry, "timestamp")) ?? "";
    const msg = field(entry, "message");
    const id = str(field(msg, "id"));
    const model = str(field(msg, "model"));
    const u = field(msg, "usage");
    if (field(entry, "type") !== "assistant" || !at || !id || !model || model === "<synthetic>" || !isRecord(u) || requests.has(id))
      continue;
    const n = (v: unknown) => num(v) ?? 0;
    const hour = n(field(u.cache_creation, "ephemeral_1h_input_tokens"));
    const write = n(u.cache_creation_input_tokens);
    const one: Usage = {
      model,
      input: n(u.input_tokens),
      output: n(u.output_tokens),
      cache_read: n(u.cache_read_input_tokens),
      cache_write: write,
      cost: null,
    };
    const p = priceOf(model);
    if (p) {
      const [, input, output, read] = p;
      one.cost = (one.input * input + one.output * output + one.cache_read * read + (write - hour) * input * 1.25 + hour * input * 2) / 1e6;
    }
    requests.set(id, { id, at, usage: one });
  }
  return [...requests.values()];
}
