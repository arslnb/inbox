import { placeNotes, type Item, type Note, type NotesView, type Standing } from "../../src/types.ts";

// Note writes the desk's view doesn't show yet, by id: the note as you left it, null once done; a new one under a temporary id.
export type NoteEdits = Readonly<Record<string, Note | null>>;

const notesOf = (v: NotesView) => [...v.due, ...v.urgent, ...v.open, ...v.fyi, ...v.later];
const isNote = (n: Note | null): n is Note => n !== null;

export const dropKey = <T>(r: Readonly<Record<string, T>>, key: string): Record<string, T> =>
  Object.fromEntries(Object.entries(r).filter(([k]) => k !== key));

// The desk's notes with yours on them, placed as the desk places them.
export function withNoteEdits(v: NotesView, edits: NoteEdits, now: string): NotesView {
  const ids = new Set(Object.keys(edits));
  if (!ids.size) return v;
  return placeNotes([...notesOf(v).filter((n) => !ids.has(n.id)), ...Object.values(edits).filter(isNote)], now);
}

// Your edits the desk's view now has drop off: a done note gone, a saved one as it was saved.
export function settleNoteEdits(v: NotesView, edits: NoteEdits): NoteEdits {
  const desk = new Map(notesOf(v).map((n) => [n.id, n]));
  const left = Object.entries(edits).filter(([id, n]) => {
    const d = desk.get(id);
    if (n === null) return !!d;
    return !d || d.text !== n.text || d.remind_at !== n.remind_at || d.section !== n.section;
  });
  return left.length === Object.keys(edits).length ? edits : Object.fromEntries(left);
}

// Your reviewer changes a review's read doesn't show yet, by who as its list names them (a login, or @team), lower case.
export type ReviewerAsks = Readonly<Record<string, "asked" | "removed">>;

const ORDER: readonly Standing["state"][] = ["changes requested", "asked", "approved", "commented"];

// A review's reviewers with your changes on them: a removed one off the list, an added one asked, and one asked again
// keeps their verdict, asked again, as the desk will list them.
export function withReviewerAsks(list: Standing[], asks: ReviewerAsks): Standing[] {
  if (!Object.keys(asks).length) return list;
  const by = new Map(list.map((s) => [s.who.toLowerCase(), s]));
  for (const [who, how] of Object.entries(asks)) {
    if (how === "removed") by.delete(who);
    else {
      const had = by.get(who);
      const verdict = had?.state === "approved" || had?.state === "changes requested";
      by.set(who, verdict ? { ...had, again: true } : { who: had?.who ?? who, state: "asked" });
    }
  }
  return [...by.values()].toSorted((a, b) => ORDER.indexOf(a.state) - ORDER.indexOf(b.state));
}

// Your changes the review's read now has drop off: an asked one among its review requests, a removed one not.
export function settleReviewerAsks(requests: Item["review_requests"], asks: ReviewerAsks): ReviewerAsks {
  const asked = new Set(requests.map((r) => (r.type === "team" ? `@${r.reviewer}` : r.reviewer).toLowerCase()));
  const left = Object.entries(asks).filter(([who, how]) => asked.has(who) !== (how === "asked"));
  return left.length === Object.keys(asks).length ? asks : Object.fromEntries(left);
}
