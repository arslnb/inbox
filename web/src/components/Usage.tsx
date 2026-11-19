// Settings → Usage: what you closed each day, as a contribution graph; then what the desk's Claude calls would have cost
// at API prices, by kind of work or by model. Read from the desk's ledger (src/usage.ts); nothing here is billed.
import { Effect } from "effect";
import { useState } from "react";
import type { UsageTotal, UsageView } from "../../../src/types.ts";
import { api, runUi } from "../api.ts";
import { cls } from "../format.ts";
import { useKeyed } from "../keyed.ts";
import { SkLines } from "./Skeleton.tsx";

const WINDOWS = [
  { days: 7, label: "Last 7 days" },
  { days: 30, label: "Last 30 days" },
  { days: 0, label: "Since it started counting" },
];
const DAY = 86_400_000;
const WEEKS = 53;

const money = (usd: number) =>
  usd > 0 && usd < 0.01 ? "under $0.01" : `$${usd.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const tokens = (n: number) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}K` : String(n));
const short = (d: Date) => d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
const dayKey = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
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

// The last 53 weeks, a column a week from Sunday, today last; a month's name over the week it starts in. Narrow, the
// older half folds away (styles.css).
function Closed({ closed, now }: { closed: Record<string, number>; now: string }) {
  const today = new Date(now);
  today.setHours(12, 0, 0, 0);
  const start = new Date(today.getTime() - ((WEEKS - 1) * 7 + today.getDay()) * DAY);
  const top = Math.max(1, ...Object.values(closed));
  const total = Object.values(closed).reduce((n, v) => n + v, 0);
  const weeks = Array.from({ length: WEEKS }, (_w, w) =>
    Array.from({ length: 7 }, (_d, d) => new Date(start.getTime() + (w * 7 + d) * DAY)),
  );
  return (
    <>
      <h2 className="group-head">
        Closed per day <span className="count">{total.toLocaleString("en-US")} in the last year</span>
      </h2>
      <div className="lines s-sheet">
        <figure className="cg" aria-label={`${total} items closed in the last year`}>
          {weeks.map((days, w) => {
            const first = days[0]!;
            const opens = w > 0 && first.getMonth() !== weeks[w - 1]![0]!.getMonth();
            return (
              <div key={dayKey(first)} className="cg-wk">
                <span className="cg-mo">{opens ? first.toLocaleDateString("en-US", { month: "short" }) : ""}</span>
                {days.map((d) => {
                  const n = d > today ? -1 : (closed[dayKey(d)] ?? 0);
                  return (
                    <span
                      key={d.getDay()}
                      className={cls("cg-day", n < 0 && "cg-future")}
                      data-level={n > 0 ? Math.min(4, Math.ceil((4 * n) / top)) : 0}
                      title={n < 0 ? undefined : `${short(d)}: ${n} closed`}
                    />
                  );
                })}
              </div>
            );
          })}
        </figure>
      </div>
      <p className="cr-note">Items you marked Done or approved off your desk, and PRs you or your agent merged or closed.</p>
    </>
  );
}

export function Usage({ active, refresh }: { active: boolean; refresh: number }) {
  const [days, setDays] = useState(30);
  const [by, setBy] = useState<"work" | "model">("work");
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
  const unpriced = view.rows.some((r) => r.unpriced > 0);
  // The window's dates: from when counting started, if that's later.
  const now = Date.parse(view.now);
  const from = Math.max(view.first ? Date.parse(view.first) : 0, view.days ? now - view.days * DAY : 0);
  const shown = groups(view.rows, by);
  return (
    <>
      <Closed closed={view.closed} now={view.now} />
      <h2 className="group-head">Cost at API prices</h2>
      <div className="lines s-sheet">
        <div className="setting us-total">
          <div className="s-label-col">
            <p className="s-label">
              <span className="us-cost">{money(total)}</span>
              {unpriced && " or more: some models have no known price"}
            </p>
            <p className="s-help">
              {view.first ? `${short(new Date(from))} – ${short(new Date(now))}. ` : "Nothing counted yet. "}
              What the desk's Claude calls would cost per token instead of on your plan. Codex, OpenCode and the decision model aren't
              counted.
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
      {shown.length > 0 && (
        <>
          <h2 className="group-head us-by">
            {(["work", "model"] as const).map((k) => (
              <button
                key={k}
                type="button"
                aria-pressed={by === k}
                onClick={() => {
                  setBy(k);
                }}
              >
                By {k}
              </button>
            ))}
          </h2>
          <div className="lines s-sheet">
            {shown.map((g) => {
              const sum = (k: "input" | "output" | "cache_read" | "cache_write") => g.rows.reduce((n, r) => n + r[k], 0);
              const models = groups(g.rows, "model");
              const help =
                by === "model"
                  ? `${tokens(sum("input"))} in, ${tokens(sum("output"))} out, ${tokens(sum("cache_read"))} read from cache, ${tokens(sum("cache_write"))} written to it`
                  : models.length === 1
                    ? models[0]!.key
                    : models.map((m) => `${m.key} ${money(m.cost)}`).join(" · ");
              return (
                <div key={g.key} className="setting">
                  <div className="s-label-col">
                    <p className="s-label">{by === "work" ? (view.work[g.key] ?? g.key) : g.key}</p>
                    <p className="s-help">
                      {help}
                      {g.unpriced > 0 && ". Partly on a model with no known price."}
                    </p>
                  </div>
                  <div className="s-control us-cost">{g.cost === 0 && g.unpriced > 0 ? "No price" : money(g.cost)}</div>
                </div>
              );
            })}
          </div>
        </>
      )}
    </>
  );
}
