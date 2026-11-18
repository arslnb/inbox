import type { Card } from "../../src/types.ts";

export const RISK_BARS = { high: 1, medium: 2, low: 4 } as const; // risk as a signal, on a row and beside a review

// A row's signal: its AI review's risk, as the review shows it; grey with no review yet.
export const rowLit = (card: Card): number => {
  const risk = card.kind === "pr" ? (card.preflight?.risk ?? card.risk) : undefined;
  return risk ? RISK_BARS[risk] : 0;
};
