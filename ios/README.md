# Inbox for iPhone (v0)

Your desk on your phone: the same lists as the window (Inbox, Blocked, Merging, Archive), read from the desk on your
computer over Tailscale. SwiftUI, iOS 17 or newer, iPhone only, no third-party packages. So far it has only run in the
Simulator.

The phone pairs as a **phone** (a bearer token the desk takes as its own window's, unlike a machine's, which is an
agent's). So it shows everything, it triages (Done, Snooze, Mute, Back on the desk, Undo), and its store can send what
the window sends: see [What the phone writes](#what-the-phone-writes-and-what-it-leaves). A phone paired before this
(as a device) is still refused every write: disconnect it and pair again.

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
| `-settings`                                    | the settings sheet                                                      |
| `-empty`                                       | the desk as if nothing were on it                                       |
| `-connect [-connectAddress <text>] [-connectError "<words>"]` | the connect screen, with that address and those words in red |

## Look at it

```bash
ios/shots.sh                 # every state, light and dark, into ios/.shots/
ios/shots.sh inbox item-pr   # only these
```

It builds, installs on the booted simulator, starts the mock on port 47841 (and stops it), and writes
`ios/.shots/<state>-<light|dark>.png` for: `connect`, `connect-error`, `inbox`, `inbox-scrolled`, `inbox-empty`,
`blocked`, `merging`, `archive`, `item-pr` (with an AI review), `item-issue`, `question`, `session`, `settings` and
`offline` (a desk that isn't there). It won't shoot while something already answers on that port (a mock you started by
hand has whatever you did to it since): stop that first, or set `SHOTS_PORT`.

Look at them after any change here, as `npm run shots` is looked at for the window: clipped or cut text, weights (a
title is 500, a heading 650, a row's facts 400), the facts line when it runs out of room, both appearances, and the top
and bottom edges. What a shot can't show (the page menu, a row's swipe and long press, the toast's Undo, pull to
refresh), try by hand against the mock.

## On a real phone

Not tried on a phone yet: v0 has only run in the Simulator, and the project has no signing team set. When you do:

1. On the desk's computer: Settings → Tailscale → **Use it from your other devices** (or `desk serve --tailscale`).
   The desk then answers at `https://<machine>.<tailnet>.ts.net` on your tailnet only. It needs the `tailscale` command
   on the desk's PATH.
2. On the phone: Tailscale on, signed in with the **same login** that owns the desk's computer.
3. On the desk's computer: `desk pair`. It prints the address and a code (one try, 10 minutes).
4. In the app: the address and the code, or paste the whole link it prints (`https://<name>/pair#<code>`) into the
   address field.

The app trades the code once for a token and keeps it in the Keychain (this device only); the address is in
UserDefaults. Settings → Disconnect forgets the token on the phone. The device stays listed on the desk until you revoke
it there (Settings → This device): if you do, the phone's next request is refused and it goes back to the connect
screen.

Checked in the Simulator on the desk's own Mac, through a desk served at its tailnet address: pairing with the link,
the token on every read, a refused write (403), a desk still starting (503, in its words) and the event stream, which
`tailscale serve` passes through as it comes. The first request after serving is turned on can time out once, while
Tailscale gets the address its certificate: Connect again with the same code, which an unanswered try doesn't burn.

## What the phone writes, and what it leaves

A paired phone is your hands like the window (`fromDesk()` in `src/server.ts`; README → Safety). `Store` has one method
for each write, in the "Writing" part of `Inbox/Store.swift`: `approve`, `comment`, `reply`, `ready`, `askReviewers`,
`github` (the row's Merge and the More menu: close, convert to draft, reopen, re-request review, remove me as a
reviewer, request changes), `handOff`, `backToDesk`, `answer` and `kick`. Each sends once (`busy(id)` while it's on its
way), says what the window says when it lands, shows the desk's own words when it's refused, and reads the desk again.
The toast's Undo reopens a PR you closed and makes a converted draft ready again, as the window's does. The pages don't
offer these yet: they still say an action is done on the desk's computer.

Left for the computer: a comment on a diff line (the phone draws no diff), a session's Open and its attach command
(both act on the desk's computer), Ask your agent, and everything in Settings.

What it calls: reads (`/api/overview`, `/api/queue`, `/api/inflight`, `/api/item`, `/api/inquiries/:id`,
`/api/reviewers/:id`, `/api/events`, `/health`), `POST /api/act` (done, snooze, mute, unmute, restore, seen, inflight,
takeback), `/api/undo`, `/api/sync`, the writes above (`/api/review/:id/approve|comment|reply|ready|reviewers`,
`/api/github`, `/api/inquiries/:id/answer`, `/api/sessions/:id/kick`) and, once, `/api/pair`. For what reviewers said it
reads `/api/review/:id?ahead=1`, always with `ahead`: without it the desk would start your AI review and your agent's
read. The whole diff rides along in that answer and is skipped.

Not in v0: the diff, the filter, notes (shown, not written or finished), Claude's work on
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
| A question, a session, Settings, bubbles    | `Inbox/Views/Pages.swift`                                                              |
| The connect screen                          | `Inbox/Views/ConnectView.swift`                                                        |
| The fonts                                   | `Inbox/Fonts/` (copies of `web/src/fonts`, see its README)                             |
| The app icon                                | `Inbox/Assets.xcassets/AppIcon.appiconset` (the mark, full-bleed on petrol)            |
