# Inbox for iPhone (v0)

Your desk on your phone: the same lists as the window (Inbox, Blocked, Merging, Archive), read from the desk on your
computer over Tailscale. SwiftUI, iOS 17 or newer, iPhone only, no third-party packages. So far it has only run in the
Simulator.

The phone pairs as a **phone** (a bearer token the desk takes as its own window's, unlike a machine's, which is an
agent's). So it shows everything, it triages (Done, Snooze, Mute, Back on the desk, Undo), and it does what an item is
on your desk for: approve, comment (on a PR, or on a line of its diff), reply, mark ready, ask reviewers, merge, hand off for merge, answer a question, kick
a session. See [What the phone does](#what-the-phone-does-and-what-it-leaves). A phone paired before this (as a device)
is still refused every write: disconnect it and pair again.

## Build and test

Xcode 26 is all you need; the project (`Inbox.xcodeproj`) is checked in.

```bash
cd ios
SIM='platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild -project Inbox.xcodeproj -scheme Inbox -destination "$SIM" -derivedDataPath .build build
xcodebuild -project Inbox.xcodeproj -scheme Inbox -destination "$SIM" -derivedDataPath .build test
```

Or open `ios/Inbox.xcodeproj` in Xcode and press Run. Use `xcodebuild`/`xcrun`, not a bare `swift` on your PATH.

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). After adding, removing or renaming a file: `cd ios && xcodegen generate`, and commit the
project with the change.

`npm run check` neither builds nor tests this folder (Prettier skips `ios/` too): the commands above are its check. The
tests (`InboxTests`) decode every response the app reads from saved copies of the mock desk's answers
(`InboxTests/Fixtures`), hold the wording to the window's (`web/src/format.ts`, `notices.ts`), and run the client against
the desk's exact refusals through a stubbed `URLProtocol`. They never touch the network.

## Run it in the Simulator

Against the mock desk (fake data, nothing real is touched):

```bash
# in the repo's root; needs npm install
MOCK_PORT=47841 MOCK_NO_POLL=1 node --disable-warning=ExperimentalWarning web/mock/server.ts
```

Run the app, and on its first screen type `http://localhost:47841`. No code is asked for: the Simulator shares your
Mac's localhost, and the desk's own computer needs no token.

Against your own desk on the same Mac: start the desktop app (or `desk serve`) and type `http://localhost:47823`.
Triage there is real: Done on the phone is Done on your desk (the toast's Undo takes it back).

A Debug build also reads launch arguments, for trying one state without tapping to it (none is saved; a Release build
ignores them):

```bash
xcrun simctl launch booted dev.inbox.ios -deskURL http://localhost:47841 -page merging
```

| Argument                                       | Shows                                                                   |
| ---------------------------------------------- | ----------------------------------------------------------------------- |
| `-deskURL http://localhost:<port>`             | that desk (localhost only), leaving the saved one alone                 |
| `-page inbox\|blocked\|merging\|archive`       | that page                                                               |
| `-open <owner/repo#n>`                         | an item's page; `-open inquiry:<id>` a question, `-open session:<id>` a session |
| `-scrollTo standard`                           | the Inbox scrolled to a section (`urgent`, `standard`, `fyi`)           |
| `-box approve\|comment\|changes\|reviewers\|reply\|answer` | with `-open`: that page's box, opened once the page has loaded |
| `-part checks\|reviewers`                      | with `-open`: that line of a PR's State, opened                         |
| `-scroll diff\|thread\|said`                   | with `-open`: a PR's page scrolled to its diff, the first thread on a line of it, or what reviewers said |
| `-scroll guide\|step-<n>\|note`                | with `-open`: the guided review's first step, a later one (from 0), or the AI review's first note on a line |
| `-ai open`                                     | with `-open`: the AI review's fold, opened                              |
| `-review.view guided\|traditional`             | the diff's order where a review has steps, for this launch (the saved choice is left alone) |
| `-said waiting\|more`                          | with `-open`: the first waiting conversation's own words unfolded, or the ones not waiting on you opened |
| `-comment <path>:<line>`                       | with `-open`: the box for a comment on that line of the new file        |
| `-settings`                                    | the settings sheet                                                      |
| `-empty`                                       | the desk as if nothing were on it                                       |
| `-connect [-connectAddress <text>] [-connectError "<words>"]` | the connect screen, with that address and those words in red |
| `-connect -scan "<text>"`                      | the connect screen as if the camera had read that QR (the Simulator has no camera) |

## Look at it

```bash
ios/shots.sh                 # every state, light and dark, into ios/.shots/
ios/shots.sh inbox item-pr   # only these
```

It builds, installs on the booted simulator, starts the mock on port 47841 (and stops it), and writes
`ios/.shots/<state>-<light|dark>.png` for: `connect` (in the Simulator, Scan the code is off and says why), `connect-error`, `connect-scan-wrong` (a QR that isn't a desk's), `inbox`, `inbox-scrolled`, `inbox-empty`,
`blocked`, `merging`, `archive`, `item-pr` (with an AI review, folded, and its State; Approve), `item-pr-ai-open` (a
review with a goal, its fold opened), `item-pr-guided` (a step of the guide, its diagram as text), `item-pr-guided-note`
(Look here and a potential bug under their line), `item-pr-guided-end` (the last step, its test file folded, the guide's
end), `item-pr-ai-stale` (on an earlier commit, a new one being written), `item-pr-ai-failed` (Try again),
`item-pr-ai-running`, `item-pr-ai-none` (Ask Claude for one), `item-pr-guided-large` (a step at an accessibility text
size), `item-pr-checks` (a failing
run, its checks opened), `item-pr-own` (your PR: who reviews it, + Add reviewers), `item-pr-diff` (its diff in Traditional, from the first file),
`item-pr-diff-thread` (a thread under its line), `item-pr-line-comment` (the box for a comment on a line), `item-issue` (Comment), `item-reply` (what
waits on your reply, each with your agent's read), `item-pr-said` (what one of them wrote, unfolded), `item-pr-more-conversations` (the ones not waiting on you, the first opened), `item-draft` (Ready for review; its description's first paragraph where a review would be), `item-mine` (Hand off for merge), `item-merging` (Back to desk),
the boxes `approve`, `reply`, `reviewers` and `answer`, `question`, `session`, `session-kick`, `item-large` and `item-largest` (accessibility
text sizes, where the bar's quiet buttons fold into More and the longest call to action keeps its words), `settings` and `offline` (a desk that isn't
there). It won't shoot while something already answers on that port (a mock you started by
hand has whatever you did to it since): stop that first, or set `SHOTS_PORT`.

Look at them after any change here, as `npm run shots` is looked at for the window: clipped or cut text, weights (a
title is 500, a heading 650, a row's facts 400), the facts line when it runs out of room, both appearances, and the top
and bottom edges: an opened page has no navigation bar, so its first line sits under the status bar and its bar at the
foot stays on one line. What a shot can't show (the page menu, a row's swipe and long press, the More menu, a write and
its toast or refusal, the toast's Undo, pull to refresh, and the swipe back from the left edge on each opened page, which
`Views/Acting.swift` keeps alive with the bar hidden), try by hand against the mock.

## On a real phone

Not tried on a phone yet: v0 has only run in the Simulator, and the project has no signing team set. When you do:

1. On the desk's computer: Settings → Tailscale → **Use it from your other devices** (or `desk serve --tailscale`).
   The desk then answers at `https://<machine>.<tailnet>.ts.net` on your tailnet only. It needs the `tailscale` command
   on the desk's PATH.
2. On the phone: Tailscale on, signed in with the **same login** that owns the desk's computer.
3. On the desk's computer: Settings → Network → **Pair a device**. It shows a QR, the address and a code (one try,
   10 minutes).
4. In the app: **Scan the code** and point it at the QR. Scan it in the app, not with the phone's Camera app, which
   opens the link in Safari and spends the code there. Or type the address and the code (`desk pair` prints both), or
   paste the whole link (`https://<name>/pair#<code>`) into the address field.

Scan the code takes only a desk's pairing link: any other QR is said to be none, in red under the viewfinder, and
nothing is asked of anyone, so no try is spent. A desk's link is traded once and the sheet closes; a refusal (a used
code, Tailscale off) shows on the connect screen with the address kept and the code field empty for a new one. The live
camera, iOS's ask for it and the screen for a camera that was refused can't run in the Simulator, which has no camera:
only what happens with what was read is tested (`-scan`, `AddressTests`, `StoreTests`).

The app trades the code once for a token and keeps it in the Keychain (this device only); the address is in
UserDefaults. Settings → Disconnect forgets the token on the phone. The device stays listed on the desk until you revoke
it there (Settings → Network): if you do, the phone's next request is refused and it goes back to the connect
screen.

Checked in the Simulator on the desk's own Mac, through a desk served at its tailnet address, when the app still paired
as a machine (kind `device`): pairing with the link, the token on every read, a desk still starting (503, in its words)
and the event stream, which `tailscale serve` passes through as it comes. Not yet checked through a real tailnet:
pairing as a phone (kind `phone`) and any write with its token; `test/remote.test.ts` holds the desk's side of both, and
the app's writes are checked against the mock. The first request after serving is turned on can time out once, while
Tailscale gets the address its certificate: Connect again with the same code, which an unanswered try doesn't burn.

A phone paired by a build that paired as a machine holds a token the desk refuses every write: at its next launch the
app forgets it and asks to pair again (revoke the old pairing in Settings → Network).

## What the phone does, and what it leaves

A paired phone is your hands like the window (`fromDesk()` in `src/server.ts`; README → Safety). An opened page has one
bar at its foot: Back, More, Snooze, Done, and the one call to action the item is there for, in the window's words.
When they don't fit on one line More becomes its three dots, then Snooze and Done fold into it (large text only: at the
default size all four fit beside the longest name, Hand off for merge).

- **A PR or an issue.** The row's own call to action (Ready for review, Add reviewers, Reply, Merge); else Approve on
  someone else's PR, Comment on an issue, Hand off for merge on yours once it's through review (`Card.act(open:)`). In
  Merging the bar has Back to desk. More has Mute, Comment, Add reviewers (on your draft: Ready for review, asking
  reviewers, which marks it ready and asks them in one go), Hand off for merge, exactly the GitHub writes
  under On GitHub the writes the desk allows now, as the window's More (`Card.actions` less convert to draft, ready and
  reopen: Close, Merge now, Request changes, Re-request review, Remove me as a reviewer), Open on GitHub and Copy GitHub
  link. Approve, Merge and Request changes are pinned to the commit the page last drew (`Store.pins`, moved by every
  review that lands, as the window since 9f5819a): a push the page redrew is yours to approve, one it hasn't drawn yet
  the desk refuses, its words kept in the sheet. Whether you may approve is the desk's say (`approve.ok`): where it
  says no on an open PR, Approve is off and the page says why ("Can't approve: you approved this commit.").
- **The AI review.** As the window draws it. Its goal leads, in ink (an older review without one leads with its
  summary's first sentence). Then the verdict line: Look closely, Skim it or Skip it, how risky and the first reason
  why, "on an earlier commit" when a push has left it behind. Pressed, the line opens the rest: the summary, "Also
  risky:", Interfaces (each name, what changed, "breaking", what it means; a press goes to its line of the diff),
  Could be better, and a diagram no step draws. Every PR opens folded. Never folded: "In the stack:", "Not quite what
  the description says:" and "Since your review:". Its concerns are listed only when they can't sit in the code (a
  review of an earlier commit, or one with no notes). While one is written: "Claude is reviewing it. The notes land in
  the code below in a minute or two.", later with how long and which try. A failed one says why and when your agent
  tries again, with **Try again**; an open PR with none has **Ask Claude for one**; a closed one says "No AI review."
  Both ask your agent, so they spend it: only a press does (`Store.askReview()`), never opening the page. The words
  "Claude is reviewing api#4127." show at once, the desk's events redraw the page, a second press meanwhile does
  nothing, and only the desk's own refusal is a bubble (its answer comes when the review is written, minutes later,
  so nothing waits for it). A PR in Merging has neither link: it's your agent's. Your own PR shows this only once a
  review exists, is being written or failed. All of it is the model's words: plain text, a URL never a link.
- **A PR's State.** Under the AI review, a table of one line each: Checks (red when one that counts fails), Reviewers
  (amber on changes requested), Merge (what stands in its way) and, with no stack, Depends. Checks opens to each by
  name, shards of one check folded into one row, the passing ones behind "N more passing" past six rows; a check opens
  its page. Reviewers opens to who and where each stands, with + Add reviewers on your open PR that's ready. Under the
  title, the reviewers with a verdict: a green tick, or "changes" in amber. Your own PR with no AI review shows its
  description's first paragraph there instead. A diff or a conversation that couldn't load says so in its place.
- **Guided Review and Traditional.** A review with steps reads two ways, picked by two words above the diff; the
  choice is kept on this phone (`review.view`), Guided first. Guided is only the review's steps: "2 of 4" and the
  step's title, its words, "Check:", its note, its diagram, then its sections, each under Look or Skim and why; at its
  foot "Next: …", which goes to the next step, and after the last "End of the guide. 3 more files change outside it:
  read every file in Traditional". A potential bug no step covers still shows, under "Potential bugs outside the
  guide". A test file starts folded there. A diagram is its title, its caption and one line per edge or message
  ("Dispatch (new) → Lease (new): lease()"): the window's own fallback, never a figure.
- **The AI review in the code.** In either order its notes sit under their lines, in the sans face with a rule down
  the margin; the first of them are its concerns, each headed "Potential bug" with an amber edge. A note about the
  whole file (or on a line the diff doesn't show) sits above the file's lines. "Look here, lines 12–14:" marks where
  correctness hinges; a review of an earlier commit marks nothing.
- **A PR's diff.** Under its State and stack, every file once in the PR's order (the window's Traditional), each under
  a header that folds it and stays at the top while its lines scroll: the name with its folder cut from the head, the
  lines added and removed, and under it new, deleted or renamed from where. Lines are unified and wrapped, never
  scrolled sideways (that would fight the swipe back): the new file's number (the old one on a removed line), the
  sign, the text, a faint green or red behind what was added or removed. Then the files the desk folded away, under
  "Not worth reviewing · N files", each with why (a lockfile; no text diff). A file's first 400 lines are drawn, the
  rest are on GitHub; past about 3,000 lines in all, every file starts folded. A review thread sits under its line
  (not an outdated one), drawn as under "What was said", with Reply and Open on GitHub; a resolved one is one line until pressed. On an open PR, press a
  line to comment on it: a removed line's comment goes on the old file's side, any other on the new one's. One line
  only, pinned to the commit the diff is at. Your words show under the line as "You · sent" until the conversation
  read again has them. Code stops growing at the first accessibility text size; what people said grows on.
- **After a write** that takes it off your desk (Approve, Comment on the PR, Request changes, Close, Merge) the phone
  goes back to the list, where its toast is; the window stays on the review. Deliberate: only a comment on a line and
  a reply stay on the page. A reply leaves it only when the desk took the PR off (`Store.left()`): a reply was all it
  asked of you and this was the last one waiting.
- **What reviewers said.** Under the AI review, as the window's Conversation: "Waiting on your reply N", each with who,
  where ("src/auth.ts:42", ", outdated", or "on the PR") and when; what it comes to (your agent's gist, else the last
  comment's first line); your agent's take with its call in bold, "<agent> is reading it." or why it couldn't; "What
  azulus wrote" (or "What was said") unfolding every comment in place; then Reply and Open on GitHub. Then "N more
  conversations not waiting on you", opening to a line each, and a press on one opens its comments and a Reply. A
  thread gets a thread reply, a comment or a review a comment on the PR; a closed PR takes none. Nothing resolves a
  thread from here: "resolved" is only said. After a reply the page stays and reads the review again; until then your
  words show as "You · sent". The bar's Reply answers the first one waiting; a draft is kept per conversation. A
  comment is text: `code` in the mono face, links as their URL, GitHub's tags and headings' hashes taken off.
- **A question.** Its answers come straight under it, each a button that answers with it; Answer takes your own words;
  Dismiss lets the agent decide.
- **A session.** Kick or Resume (off until a rate limit resets), Done and Snooze.

A press sends at once, as the window's buttons do. What takes words (Approve's optional comment, Comment, Reply, Request
changes, Answer) is a sheet with a field and one named button, as tall as what's in it so it sits on the keyboard; if the desk
refuses, the sheet stays with your words and the desk's own. A write the desk never answered may still have landed: the
sheet says so and the desk is read again, rather than claiming it wasn't sent. `Store` has one method per write ("Writing" in `Inbox/Store.swift`): each sends once (`busy(id)`
meanwhile), says what the window says when it lands, and reads the desk again. The toast's Undo reopens a PR you closed
and makes a converted draft ready again.

Left for the computer: a diagram drawn as a figure and the review's drawn document (the phone shows a diagram's lines
as text), asking for an AI review of your own PR that has none (the window's More), in the diff "more
lines" around a hunk, word-level changes, syntax highlighting and a comment on a range of lines; a session's Open and its attach command
(they act on the desk's computer; the session's page says so once), Merging's Wake it, Start it now and Copy attach
command for your agent, Ask your agent, and everything in Settings.

What it calls: reads (`/api/overview`, `/api/queue`, `/api/inflight`, `/api/item`, `/api/inquiries/:id`,
`/api/reviewers/:id`, `/api/events`, `/health`), `POST /api/act` (done, snooze, mute, unmute, restore, seen, inflight,
takeback), `/api/undo`, `/api/sync`, the writes above (`/api/review/:id/approve|comment|inline|reply|ready|reviewers|ai`,
`/api/github`, `/api/inquiries/:id/answer`, `/api/sessions/:id/kick`) and, once, `/api/pair`.

What opening a PR costs: one `GET /api/review/:id` without `ahead`, exactly the window's open, so the desk may start
its AI review (`review.auto_ai`) and your agent's read of the conversations waiting on you. Every redraw after it (the
desk's events, after a write) asks with `?ahead=1`, a second after the last event, so an event never restarts a failed
job (`Store.readReview()`). A PR's page no longer asks `/api/item`: that is for issues. Rows and lists never ask for a
review, and nothing is prefetched. Nothing but a press on Ask Claude for one or Try again posts `/api/review/:id/ai`. The answer is the whole review (`ReviewView` in `Models.swift`: the order to read
its hunks in, the AI review's parts, checks, reviewers, conversations); each file's own `patch` is never kept, since
the same lines are in the order's hunks.

Not in v0: the filter, notes (shown, not written or finished), Claude's work on
Merging, people's pictures, notifications, themes other than the default light and dark, iPad.

## Where things are

| To change                                   | Edit                                                                                   |
| ------------------------------------------- | -------------------------------------------------------------------------------------- |
| What the desk's JSON looks like             | `Inbox/Models.swift` (every field optional, enums kept as strings, lists skip a bad row) |
| What it asks the desk, and errors           | `Inbox/APIClient.swift`; an address or a pairing link in `Inbox/Address.swift`         |
| State, loading, the live stream, acting     | `Inbox/Store.swift` (one `@Observable` store; the launch arguments too)                |
| The window's words (ages, snooze, bubbles)  | `Inbox/Format.swift`, kept in step with `web/src/format.ts`, `view.ts`, `notices.ts`   |
| Colours, fonts, the mark                    | `Inbox/Theme.swift` (the default theme's tokens from `web/src/styles.css`)             |
| A row                                       | `Inbox/Views/Rows.swift` (the window's two-line row, `.c-row`)                         |
| The pages and their lists, a row's menu     | `Inbox/Views/DeskView.swift`                                                           |
| An item's page                              | `Inbox/Views/ItemPage.swift`                                                           |
| A PR's State (checks, reviewers, merge)     | `Inbox/Views/ReviewState.swift`; `CheckGroup.of()` in `Format.swift` (view.ts's `checkGroups()`) |
| What reviewers said, a comment's drawing, Reply | `Inbox/Views/Said.swift` (`WhatWasSaid`; `SaidComments` and `SaidActions`, shared with the diff's threads); words in `Format.swift` (`Words.place()`, `gist()`, `takeSplit()`, `saidText()`, `replyTo()`); `Store.reply()`, `left()` |
| The AI review's block, a diagram as text    | `Inbox/Views/AiBlock.swift` (`AiSection`, `DiagramLines`); words in `Format.swift` (`Words.lead()`, `reviewing()`, `reviewFailed()`, `listsConcerns()`, `fit`); `diagramText()` in `Inbox/Guide.swift` |
| Asking for an AI review                     | `Store.askReview()`, `asking`; `APIClient.askReview()` (the one request that waits minutes) |
| The guided review, notes on lines           | `Inbox/Guide.swift` (`Diff.walk()`, `guided()`, `isTestPath()`, `placed()`, `on()`: the twins of `src/sections.ts`); `DiffModel(guided:bugs:)`; steps, `AiNote` and Look here in `Inbox/Views/DiffView.swift`; the two tabs and `reach()` in `ItemPage.swift` |
| A PR's diff: lines, order, threads, the fold | `Inbox/PatchLines.swift` (`patchLines()`, `Diff.traditional()`, `threadsOn()`, `spot()`, `DiffModel`: the twins of `src/review.ts`, `src/sections.ts` and `web/src/view.ts`); drawn by `Inbox/Views/DiffView.swift` |
| A comment on a line                         | `Store.inline()`, `APIClient.inline()`; the box is `ItemPage`'s `.line`               |
| When a PR's review is read, and the pin     | `Store.readReview()`, `closeReview()`, `pins` in `Inbox/Store.swift`                   |
| A question, a session, Settings, bubbles    | `Inbox/Views/Pages.swift`                                                              |
| An opened page's bar, the boxes that write  | `Inbox/Views/Acting.swift` (`BottomBar`, `WriteSheet`, `ReviewersSheet`, the swipe back) |
| The connect screen                          | `Inbox/Views/ConnectView.swift`                                                        |
| Scan the code (the camera, the QR it reads) | `Inbox/Views/ScanView.swift`; what counts as a desk's link: `DeskAddress.scanned()`    |
| The fonts                                   | `Inbox/Fonts/` (copies of `web/src/fonts`, see its README)                             |
| The app icon                                | `Inbox/Assets.xcassets/AppIcon.appiconset` (the mark, full-bleed on petrol)            |
