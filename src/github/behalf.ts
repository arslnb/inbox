// Whose a PR an agent opened for a person is: the formats, and why each is safe, are in docs/api.md → Opened for you.
import type { Attribution, Item } from "../types.ts";

const LABEL = String.raw`(@[A-Za-z0-9][A-Za-z0-9_-]{0,38}|\*\*(?:\\\*|[^*\n]){1,60}\*\*)`;
// Junior's runtime-owned block: "via A, B." (once "Requested by A."), A being who asked first.
const JUNIOR = new RegExp(
  String.raw`<!-- junior-request-attribution:start -->\s*(?:via|Requested by)\s+${LABEL}[^\n]*\s*<!-- junior-request-attribution:end -->`,
);
// A whole line of its own: Devin's "Requested by: @login", or "via @login.", "On behalf of @login", maybe in _ or *.
const LINE = new RegExp(String.raw`^[ \t]*[_*]?(?:requested by:?|on behalf of|via)[ \t]+${LABEL}\.?[_*]?[ \t]*$`, "gim");
// GitHub's Copilot coding agent writes no line: whoever asked it is its PR's human assignee.
const ASSIGNS = new Set(["copilot", "copilot-swe-agent"]);

const unbold = (label: string) => (label.startsWith("@") ? label : label.slice(2, -2).replaceAll("\\*", "*").trim());

// Who a PR's description says it was opened for: "@login", a name, or "" when none or when its lines disagree.
export function requesterOf(markdown: string): string {
  const block = JUNIOR.exec(markdown)?.[1];
  if (block) return unbold(block);
  const named = new Set([...markdown.matchAll(LINE)].map((m) => unbold(m[1]!)));
  return named.size === 1 ? [...named][0]! : "";
}

type Facts = Pick<Item, "kind" | "author" | "author_bot" | "assignees" | "requester" | "via">;
type IsBot = (login: string, flagged?: boolean) => boolean;
const lc = (s: string) => s.toLowerCase();

// Who a bot's PR was opened for: its agent's line, else Copilot's one human assignee, else what the light model read
// (`read`, undefined until it has). Undefined for a person's PR or an issue.
export function attributionOf(it: Facts, isBot: IsBot, read?: string): Attribution | undefined {
  if (it.kind !== "pr" || !isBot(it.author, it.author_bot)) return undefined;
  const agent = it.author;
  // Stored before the desk read requesters: its via line, until the item is fetched again.
  const line = it.requester ?? it.via ?? "";
  if (line) return { person: line, agent, source: "line" };
  const people = it.assignees.filter((a) => !ASSIGNS.has(lc(a)) && !isBot(a));
  if (ASSIGNS.has(lc(agent)) && people.length === 1) return { person: `@${people[0]!}`, agent, source: "assignee" };
  if (read) return { person: read, agent, source: "model" };
  return { person: "", agent, source: "none" };
}

// A bot's PR is yours when its attribution names you by login and it assigns you, names you by your GitHub profile name
// or one you gave (`names`, compared by letters alone: "greg.pstrucha" is "Greg Pstrucha"), or is Copilot's with you its
// only human assignee. The light model's read counts as a line does. A person's PR is only ever its author's.
export function onBehalf(it: Facts, me: string, names: readonly string[], isBot: IsBot, read?: string): boolean {
  const a = attributionOf(it, isBot, read);
  if (!a || !me || lc(it.author) === lc(me)) return false;
  const r = a.person;
  if (a.source === "assignee") return lc(r.slice(1)) === lc(me);
  if (r.startsWith("@")) return lc(r.slice(1)) === lc(me) && it.assignees.some((x) => lc(x) === lc(me));
  const letters = (s: string) => s.toLowerCase().replaceAll(/[^\p{L}\p{N}]/gu, "");
  return !!r && !!letters(r) && names.some((n) => letters(n) === letters(r));
}
