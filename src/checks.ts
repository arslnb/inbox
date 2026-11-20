// A PR's checks as its review lists them: what's wrong first, and where CI stands in words and a colour.

import type { Check, Checks } from "./types.ts";

const ORDER: Check["state"][] = ["failing", "cancelled", "running", "passing", "skipped"];

// null for a commit nothing ran on. Only a failing check the base branch requires is red; an optional one failing, one
// cancelled or one still running is amber.
export function checksView(checks: Check[]): Checks | null {
  if (!checks.length) return null;
  const list = checks.toSorted((a, b) => ORDER.indexOf(a.state) - ORDER.indexOf(b.state) || a.name.localeCompare(b.name));
  const has = (f: (c: Check) => boolean) => list.some(f);
  if (has((c) => c.state === "failing" && !c.optional)) return { said: "Checks failing", tone: "bad", list };
  if (has((c) => c.state === "failing" || c.state === "cancelled")) return { said: "Some checks failing", tone: "warn", list };
  if (has((c) => c.state === "running")) return { said: "Checks running", tone: "warn", list };
  return { said: "Checks passing", tone: "good", list };
}
