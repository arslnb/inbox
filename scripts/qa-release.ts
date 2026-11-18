// npm run qa:release [-- vX.Y.Z | path/to/Inbox-X.Y.Z.dmg]: installs a release (default the latest) as a QA copy beside
// your own app, in ~/.inbox-qa with its own port, and runs smoke-app.ts against it: the version, a first GitHub sync
// (QA_SHALLOW=1 skips it) and an item's review. Your desk (~/.inbox, :47823) is never touched. macOS only.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { envVar } from "../electron/lib.ts";
import { RELEASES } from "../src/updates.ts";

const root = path.join(import.meta.dirname, "..");
const home = envVar("QA_HOME") ?? path.join(os.homedir(), ".inbox-qa");
const port = envVar("QA_PORT") ?? "47833";
const arg = process.argv[2];

const run = (cmd: string, args: string[]) => {
  const r = spawnSync(cmd, args, { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")}: ${(r.stderr || r.stdout).trim()}`);
  return r.stdout.trim();
};

if (process.platform !== "darwin") throw new Error("qa:release installs the Mac dmg: run it on a Mac");
if (path.resolve(home) === path.join(os.homedir(), ".inbox")) throw new Error("QA_HOME can't be your desk's ~/.inbox");
if (port === "47823") throw new Error("QA_PORT can't be your desk's 47823");

let dmg: string;
if (arg?.endsWith(".dmg")) dmg = path.resolve(arg);
else {
  const repo = `${RELEASES.owner}/${RELEASES.repo}`;
  const tag = arg ?? run("gh", ["release", "view", "--repo", repo, "--json", "tagName", "--jq", ".tagName"]);
  const file = `Inbox-${tag.replace(/^v/, "")}${process.arch === "arm64" ? "-arm64" : ""}.dmg`;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "inbox-qa-"));
  console.log(`• downloading ${file} from ${repo} ${tag}`);
  run("gh", ["release", "download", tag, "--repo", repo, "--pattern", file, "--dir", dir]);
  dmg = path.join(dir, file);
}
const version = /Inbox-(\d+\.\d+\.\d+)/.exec(path.basename(dmg))?.[1];
if (!version) throw new Error(`no version in ${dmg}'s name`);

const bundle = path.join(home, "Inbox.app");
const bin = path.join(bundle, "Contents", "MacOS", "Inbox");
// A QA app left open from the last run holds the port and the bundle.
spawnSync("pkill", ["-f", bin]);
fs.mkdirSync(home, { recursive: true });
const mnt = fs.mkdtempSync(path.join(os.tmpdir(), "inbox-qa-mnt-"));
run("hdiutil", ["attach", "-nobrowse", "-quiet", "-mountpoint", mnt, dmg]);
try {
  fs.rmSync(bundle, { recursive: true, force: true });
  run("cp", ["-R", path.join(mnt, "Inbox.app"), home]);
} finally {
  run("hdiutil", ["detach", "-quiet", mnt]);
}
// Ad-hoc signed, not notarized: macOS refuses to open it with the quarantine flag on.
spawnSync("xattr", ["-dr", "com.apple.quarantine", bundle]);
console.log(`• installed Inbox ${version} at ${bundle}`);

const env: Record<string, string | undefined> = { ...process.env, DESK_HOME: home, DESK_PORT: port, SMOKE_VERSION: version };
if (!envVar("QA_SHALLOW")) env.SMOKE_DEEP = "1";
const smoke = spawnSync(process.execPath, ["--disable-warning=ExperimentalWarning", path.join(root, "scripts", "smoke-app.ts"), bin], {
  stdio: "inherit",
  env,
});
if (smoke.status !== 0) {
  console.error(`qa:release failed for Inbox ${version}; its logs are in ${path.join(home, "app", "logs")}`);
  process.exit(smoke.status ?? 1);
}
console.log(`qa:release passed for Inbox ${version}. Open the QA copy again with:
  open -n --env DESK_HOME=${home} --env DESK_PORT=${port} ${bundle}`);
