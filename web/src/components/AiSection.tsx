import { useMemo, useState, type ReactNode } from "react";
import { JOB_ATTEMPTS, type AiReview, type Job } from "../../../src/types.ts";
import { blocks, inline, lead, unlinked } from "../../../src/prose.ts";
import { FIT } from "../../../src/sections.ts";
import { aiName, cls } from "../format.ts";
import { Diagram } from "./Diagram.tsx";
import { ProseBlocks, spans, withCode } from "./Prose.tsx";

// The AI review's read, from the review or, until it lands, from its row's preflight (no model or time yet).
export type AiShown = Pick<AiReview, "verdict" | "risk" | "summary" | "since" | "concerns"> &
  Partial<Pick<AiReview, "model" | "at" | "intent" | "risk_reasons" | "interfaces" | "improvements" | "diagrams" | "guide">>;

export function AiSection({
  ai,
  busy,
  error,
  job,
  now,
  open,
  notes,
  onAsk,
  onLine,
}: {
  ai: AiShown | null;
  busy: boolean; // being written
  error: string | null;
  job: Job | null; // its job in the desk's ledger: how long it's run, its tries, when it tries again
  now: number;
  open: boolean;
  notes: number;
  onAsk: (() => void) | undefined; // none for a PR in Merging: it's your agent's
  onLine?: (path: string, side: "new" | "old", line: number) => void; // to a line of the diff
}) {
  const [more, setMore] = useState(false); // the rest of the summary, on this PR only: every PR opens folded
  const summary = ai?.summary ?? "";
  const goal = ai?.intent?.goal ?? "";
  // The goal leads, above the verdict; an older review without one leads with its summary's first sentence.
  const { first, rest } = useMemo(() => (goal ? { first: inline(goal), rest: blocks(summary) } : lead(blocks(summary))), [goal, summary]);
  const reasons = ai?.risk_reasons ?? [];
  const lead1 = ai && ai.risk !== "low" ? reasons[0] : undefined;
  const later = lead1 ? reasons.slice(1) : reasons;
  const ifaces = ai?.interfaces ?? [];
  const better = ai?.improvements ?? [];
  // A diagram no step draws sits in the fold, at most one.
  const loose = ai?.diagrams?.find((d) => !ai.guide?.steps.some((st) => st.diagram === d.id));
  const folds = first.length > 0 && (rest.length > 0 || later.length > 0 || ifaces.length > 0 || better.length > 0 || !!loose);
  const toggle = (label: string) => (
    <button
      type="button"
      className="link-btn rv-show"
      aria-expanded={more}
      onClick={() => {
        setMore(!more);
      }}
    >
      {label}
    </button>
  );
  const minutes = (at: string) => Math.max(1, Math.round(Math.abs(Date.parse(at) - now) / 60_000));
  const plural = (n: number) => `${n} minute${n === 1 ? "" : "s"}`;
  // Past its first couple of minutes, or on another try, the line says so rather than promise the notes soon.
  const run = job?.state === "running" ? job : null;
  const tries = run && run.attempts > 1 ? `, try ${run.attempts} of ${JOB_ATTEMPTS}` : "";
  const so = run?.started_at && now - Date.parse(run.started_at) >= 2 * 60_000 ? `, ${plural(minutes(run.started_at))} so far` : "";
  // A try that failed says so and when Claude tries again; the paused line is the desk's own words.
  const failed = !!job?.error && error === job.error;
  const said = error?.replace(/\.$/, "") ?? "";
  return (
    <section className="rv-ai" aria-label="AI review">
      {busy && (
        <p className="quiet">
          {so || tries
            ? `${aiName()} is reviewing it${so}${tries}.`
            : `${aiName()} is reviewing it. You can review it now; its notes land in the code below when it's done.`}
        </p>
      )}
      {!busy && error && (
        <p>
          {failed ? (
            <>
              {job.attempts > 1 && job.state === "failed" ? `The AI review failed ${job.attempts} times: ` : "The AI review failed: "}
              {withCode(said)}.
              {job.state === "queued" &&
                job.retry_at &&
                (Date.parse(job.retry_at) > now
                  ? ` ${aiName()} tries again in ${plural(minutes(job.retry_at))}.`
                  : ` ${aiName()} tries again shortly.`)}
            </>
          ) : (
            withCode(error)
          )}{" "}
          <button type="button" className="link-btn" disabled={!onAsk} onClick={onAsk}>
            Try again
          </button>
        </p>
      )}
      {!busy && !ai && !error && !open && <p className="quiet">No AI review.</p>}
      {!busy && !ai && !error && open && (
        <p className="quiet">
          No AI review yet.{" "}
          <button type="button" className="link-btn" disabled={!onAsk} onClick={onAsk}>
            Ask {aiName()} for one
          </button>
        </p>
      )}
      {ai && (
        <>
          {first.length > 0 && <p className="rv-gist">{spans(unlinked(first))}</p>}
          {ai.intent?.stack && <Named name="In the stack">{spans(unlinked(inline(ai.intent.stack)))}</Named>}
          {ai.intent && FIT[ai.intent.fit] && ai.intent.gap && (
            <Named name={FIT[ai.intent.fit] ?? ""}>{spans(unlinked(inline(ai.intent.gap)))}</Named>
          )}
          {/* Folded, its first lines show, fading out into Show more; inert until it's opened. */}
          {(rest.length > 0 || later.length > 0 || ifaces.length > 0 || better.length > 0 || !!loose) && (
            <div className={cls("rv-fold-body", folds && !more && "shut")} inert={folds && !more}>
              {rest.length > 0 && <ProseBlocks bs={rest} links={false} />}
              {later.length > 0 && <Named name="Also risky">{later.map((r) => r.why).join("; ")}</Named>}
              {ifaces.length > 0 && (
                <div className="rv-more-list">
                  <h3 className="rv-more-head">Interfaces</h3>
                  <ul>
                    {ifaces.map((x) => (
                      <li key={`${x.path}:${x.line}:${x.name}`}>
                        <button
                          type="button"
                          className="rv-more-item"
                          title={`${x.path}:${x.line}`}
                          onClick={() => {
                            onLine?.(x.path, x.side, x.line);
                          }}
                        >
                          <code>{x.name}</code> {x.change}
                          {x.breaking && <b> breaking</b>}
                        </button>{" "}
                        <span className="quiet">{spans(unlinked(inline(x.impact)))}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              {better.length > 0 && (
                <div className="rv-more-list">
                  <h3 className="rv-more-head">Could be better</h3>
                  <ul>
                    {better.map((x) => (
                      <li key={`${x.path}:${x.line}:${x.body}`}>
                        <button
                          type="button"
                          className="rv-more-item"
                          title={`${x.path}:${x.line}`}
                          onClick={() => {
                            onLine?.(x.path, x.side, x.line);
                          }}
                        >
                          {spans(unlinked(inline(x.body)))}
                        </button>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              {loose && (more || !folds) && <Diagram graph={loose.graph} title={loose.title} caption={loose.caption} />}
            </div>
          )}
          {folds && toggle(more ? "Show less" : "Show more")}
          {ai.since && <Named name="Since your review">{spans(unlinked(inline(ai.since)))}</Named>}
          {/* Each concern is also a note in the code; listed here only when the notes can't sit there. */}
          {notes === 0 &&
            (ai.concerns.length > 0 ? (
              <ul className="rv-concerns" aria-label="Concerns">
                {ai.concerns.map((c) => (
                  <li key={c}>{spans(unlinked(inline(c)))}</li>
                ))}
              </ul>
            ) : (
              <p className="quiet">No concerns.</p>
            ))}
        </>
      )}
    </section>
  );
}

// A named part of the AI review: its name on a line of its own, then what it says under it.
function Named({ name, children }: { name: string; children: ReactNode }) {
  return (
    <div className="rv-since">
      <h3 className="rv-more-head">{name}</h3>
      <p>{children}</p>
    </div>
  );
}
