// Settings → Usage: what the desk's model calls would have cost at API prices, by kind of work, each with its models, then
// by model. Read from the desk's ledger (src/usage.ts); nothing here is billed.
import { Effect } from "effect";
import { useState } from "react";
import type { UsageTotal, UsageView } from "../../../src/types.ts";
import { api, runUi } from "../api.ts";
import { useKeyed } from "../keyed.ts";
import { SkLines } from "./Skeleton.tsx";

const WINDOWS = [
  { days: 7, label: "Last 7 days" },
  { days: 30, label: "Last 30 days" },
  { days: 0, label: "Since it started counting" },
];

const money = (usd: number) =>
  usd > 0 && usd < 0.01 ? "under $0.01" : `$${usd.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const tokens = (n: number) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}K` : String(n));
const plural = (n: number, one: string) => `${n.toLocaleString("en-US")} ${one}${n === 1 ? "" : "s"}`;
// "claude-opus-5-5[1m]" → "Opus 5.5"; what isn't Claude's as it is.
function modelName(id: string): string {
  const m = /^claude-([a-z]+)-(\d+)(?:-(\d+))?/.exec(id);
  if (!m) return id;
  return `${m[1]![0]!.toUpperCase()}${m[1]!.slice(1)} ${m[2]}${m[3] ? `.${m[3]}` : ""}`;
}

interface Group {
  key: string;
  cost: number;
  calls: number;
  unpriced: number;
  rows: UsageTotal[];
}
// Rows summed by `by`, costliest first.
function groups(rows: UsageTotal[], by: "work" | "model"): Group[] {
  const out = new Map<string, Group>();
  for (const r of rows) {
    const key = by === "work" ? r.work : modelName(r.model);
    const g = out.get(key) ?? { key, cost: 0, calls: 0, unpriced: 0, rows: [] };
    g.cost += r.cost;
    g.calls += r.calls;
    g.unpriced += r.unpriced;
    g.rows.push(r);
    out.set(key, g);
  }
  return [...out.values()].sort((a, b) => b.cost - a.cost || b.calls - a.calls);
}

export function Usage({ active, refresh }: { active: boolean; refresh: number }) {
  const [days, setDays] = useState(30);
  const [view, setView] = useState<UsageView | null>(null);
  const [error, setError] = useState("");
  useKeyed(active ? `${refresh} ${days}` : null, (signal) => {
    runUi(
      api.usage(days || null).pipe(
        Effect.match({
          onSuccess: (v) => {
            setView(v);
            setError("");
          },
          onFailure: (e) => {
            setError(e.message);
          },
        }),
      ),
      { signal },
    );
  });

  if (!view || view.days !== (days || null))
    return (
      <div className="lines s-sheet">
        {error ? (
          <div className="setting s-status">
            <div className="s-label-col">
              <p className="s-label">Couldn't load usage</p>
              <p className="s-help t-bad">{error}</p>
            </div>
          </div>
        ) : (
          <div className="setting" aria-hidden="true">
            <SkLines count={2} />
          </div>
        )}
      </div>
    );
  const total = view.rows.reduce((n, r) => n + r.cost, 0);
  const calls = view.rows.reduce((n, r) => n + r.calls, 0);
  const since = view.first ? new Date(view.first).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" }) : null;
  const work = groups(view.rows, "work");
  const models = groups(view.rows, "model");
  return (
    <>
      <div className="lines s-sheet">
        <div className="setting">
          <div className="s-label-col">
            <p className="s-label">
              <span className="us-cost">{money(total)}</span> at API prices
            </p>
            <p className="s-help">
              {calls
                ? `${plural(calls, "model call")}: what the desk's work would cost if it paid Anthropic per token instead of running on your plan.`
                : "No model calls in this window yet."}
              {since && ` Counting since ${since}.`}
            </p>
          </div>
          <div className="s-control">
            <select
              aria-label="Window"
              className="input choice"
              value={days}
              onChange={(e) => {
                setDays(Number(e.target.value));
              }}
            >
              {WINDOWS.map((w) => (
                <option key={w.days} value={w.days}>
                  {w.label}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>
      {work.length > 0 && (
        <>
          <h2 className="group-head">By work</h2>
          <div className="lines s-sheet">
            {work.map((g) => (
              <div key={g.key} className="setting">
                <div className="s-label-col">
                  <p className="s-label">{view.work[g.key] ?? g.key}</p>
                  <p className="s-help">
                    {groups(g.rows, "model")
                      .map((m) => `${m.key}: ${money(m.cost)}, ${plural(m.calls, "call")}`)
                      .join(" · ")}
                    {g.unpriced > 0 && `. ${plural(g.unpriced, "call")} on a model with no known price, left out.`}
                  </p>
                </div>
                <div className="s-control us-cost">{money(g.cost)}</div>
              </div>
            ))}
          </div>
          <h2 className="group-head">By model</h2>
          <div className="lines s-sheet">
            {models.map((g) => {
              const sum = (k: "input" | "output" | "cache_read" | "cache_write") => g.rows.reduce((n, r) => n + r[k], 0);
              return (
                <div key={g.key} className="setting">
                  <div className="s-label-col">
                    <p className="s-label">{g.key}</p>
                    <p className="s-help">
                      {plural(g.calls, "call")}: {tokens(sum("input"))} in, {tokens(sum("output"))} out, {tokens(sum("cache_read"))} read
                      from cache, {tokens(sum("cache_write"))} written to it
                    </p>
                  </div>
                  <div className="s-control us-cost">{money(g.cost)}</div>
                </div>
              );
            })}
          </div>
        </>
      )}
      <p className="cr-note">
        Claude Code prices its own calls; your agent's runs are priced from its transcripts at Anthropic's list prices. Codex and OpenCode
        runs, and the decision model's (OpenRouter), aren't counted.
      </p>
    </>
  );
}
