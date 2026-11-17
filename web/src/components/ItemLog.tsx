// An item's log, for tuning your rules: where it stands now and what that rests on (the rule and its trace, what Claude
// weighed, the criteria), then how it got there, each move with its evidence beside what happened on GitHub, newest first.
import { Effect } from "effect";
import { useEffect, useRef, useState } from "react";
import type { ActivityEvent, ItemDetail, PlacedEntry, PlacingRule } from "../../../src/types.ts";
import { api, runUi } from "../api.ts";
import { age, aiName, BUCKET_LABEL, cls, eventText } from "../format.ts";
import { useKeyed } from "../keyed.ts";
import { placedEvidence, placedLine, WHERE_LABEL } from "../view.ts";
import { PlacementView } from "./Detail.tsx";

type Line = { at: string; key: string; placed?: PlacedEntry; event?: ActivityEvent };

export function ItemLog({
  id,
  loads,
  now,
  me,
  onBack,
  onRule,
}: {
  id: string;
  loads: number; // bumped on every refresh: a move shows as it lands
  now: number;
  me: string;
  onBack: () => void;
  onRule: (rule: PlacingRule) => void; // See the rule: Rules with it shown
}) {
  const [d, setD] = useState<ItemDetail | string | null>(null); // string: why it couldn't load
  const seq = useRef(0);
  useKeyed(`${id} ${loads}`, (signal) => {
    const n = ++seq.current;
    runUi(
      api.item(id).pipe(
        Effect.match({
          onSuccess: (r) => {
            if (n === seq.current) setD(r);
          },
          onFailure: (e) => {
            if (n === seq.current) setD((cur) => (cur && typeof cur === "object" ? cur : e.message));
          },
        }),
      ),
      { signal },
    );
  });

  const back = useRef(onBack);
  back.current = onBack;
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if (e.key !== "Escape" || e.repeat || e.metaKey || e.ctrlKey || e.altKey || e.isComposing) return;
      const t = e.target instanceof HTMLElement ? e.target : document.body;
      if (!t.closest("input, textarea, select, [contenteditable='true']")) back.current();
    };
    window.addEventListener("keydown", h);
    return () => {
      window.removeEventListener("keydown", h);
    };
  }, []);

  if (d === null) return <div className="inquiry item-log" aria-busy="true" />;
  if (typeof d === "string")
    return (
      <div className="inquiry item-log">
        <p className="t-bad">{d}</p>
      </div>
    );

  const { card } = d;
  const main = d.placements.find((p) => p.board === card.board) ?? d.placements[0];
  const latest = d.log[0];
  const lines: Line[] = [
    ...d.log.map((p) => ({ at: p.at, key: `p${p.seq}`, placed: p })),
    ...d.activity.map((e) => ({ at: e.at, key: `e${e.seq}`, event: e })),
  ].sort((a, b) => b.at.localeCompare(a.at));
  const where = latest ? WHERE_LABEL[latest.where] : card.section ? WHERE_LABEL[card.section] : "";
  return (
    <div className="inquiry item-log">
      <header className="rv-head">
        <p className="rv-ref">
          <span className="inq-kind">Log</span>
          <span className="rv-by">
            {card.repo}#{card.number}
          </span>
        </p>
        <h1 className="rv-title">{card.title}</h1>
      </header>

      <section className="log-now" aria-label="Now">
        <h2 className="d-head">Now</h2>
        <p className="log-head">
          <b>{where.replace(/^./, (c) => c.toUpperCase())}</b>
          {card.score !== undefined && card.section && ` · score ${card.score}`}
          {(card.reason ?? card.why) && ` · ${card.reason ?? card.why}`}
        </p>
        {card.rule && (
          <p>
            Placed by{" "}
            {card.rule.id ? (
              <>
                GitHub's rule <code>{card.rule.id}</code>
              </>
            ) : (
              "a rule of yours"
            )}
            : {card.rule.why}.{" "}
            <button
              type="button"
              className="link-btn"
              onClick={() => {
                if (card.rule) onRule(card.rule);
              }}
            >
              See the rule
            </button>
          </p>
        )}
        {main?.judge?.bucket && (
          <p>
            {main.judge.by ?? aiName()} said {BUCKET_LABEL[main.judge.bucket].toLowerCase()}
            {main.judge.why && `: ${main.judge.why}`}
          </p>
        )}
        {!!d.judge?.signals.length && (
          <details className="trace-toggle" open>
            <summary>What {aiName()} weighs</summary>
            <ul className="plain log-signals">
              {d.judge.signals.map((s) => (
                <li key={s.key}>
                  <span className="quiet">{s.weight} of 10</span> {s.bucket ? `${BUCKET_LABEL[s.bucket]}: ` : ""}
                  {s.why} <span className="quiet">({s.from})</span>
                </li>
              ))}
            </ul>
          </details>
        )}
        {main && (
          <details className="trace-toggle">
            <summary>Rule trace on the {main.board} board</summary>
            <PlacementView p={main} />
          </details>
        )}
      </section>

      <section className="log-history" aria-label="History">
        <h2 className="d-head">How it got here</h2>
        {lines.length === 0 && <p className="quiet">Nothing yet: the desk writes this as it places it.</p>}
        <ol className="plain log-lines">
          {lines.map((l) => (
            <li key={l.key} className={cls(l.placed ? "log-placed" : "log-event")}>
              <span className="log-age quiet" title={new Date(l.at).toLocaleString()}>
                {age(l.at, now)}
              </span>
              {l.placed ? (
                <div>
                  <p className="log-what">{placedLine(l.placed)}</p>
                  <ul className="plain log-evidence">
                    {placedEvidence(l.placed).map((x) => (
                      <li key={x}>{x}</li>
                    ))}
                  </ul>
                </div>
              ) : (
                l.event && <p className="log-what quiet">{eventText(l.event, me)}</p>
              )}
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
