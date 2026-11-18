# BRK286 demo scripts

```text
demo/
├── reset.sh        before each take: back to demo-baseline, prints GREEN or RED
├── lib.sh          shared settings and helpers (sourced, not run)
├── locks/          ci.lock: main's actions.lock at demo-baseline
├── a/              Demo A: moved transitive tag
├── d/              Demo D: egress firewall
├── history.txt     stage commands in demo order, for Ctrl-R
├── history.zsh     loads history.txt into this shell's history
└── zsh/            ZDOTDIR that loads your zsh config, then history.zsh
```

Run every script from the repository root, for example `demo/a/move-tag.sh`.
They're idempotent and need an authenticated `gh` with write access to the demo
repositories.

## Ctrl-R history

[`history.txt`](history.txt) lists the commands typed during the talk, taken
from the shell history of rehearsals, in demo order. To search it with Ctrl-R in a zsh, run this once in that shell:

```sh
. demo/history.zsh
```

It swaps in a history list that holds only those commands and lives in memory:
nothing is read from or written to `~/.zsh_history`, and commands typed in that
shell don't stick around. `fc -P` brings your own history back. To load it in
every new terminal instead, start zsh with `ZDOTDIR` set to this repo's
`demo/zsh` (the demo VS Code workspace does this through
`terminal.integrated.env.osx`). Opening a new terminal gives a fresh copy.

## Moved transitive tag (Demo A)

Two workflows run the same labeler.
[`ci-sha-pinned.yml`](../.github/workflows/ci-sha-pinned.yml) pins
[`nodeselector/pr-size-labeler`](https://github.com/nodeselector/pr-size-labeler)
by full commit SHA;
[`ci-locked.yml`](../.github/workflows/ci-locked.yml) uses plain
tags and lets `actions.lock` pin the commits. The labeler calls
[`nodeselector/diff-stats@v1`](https://github.com/nodeselector/diff-stats) by tag.

| Workflow | In `actions.lock` |
| --- | --- |
| [`ci-locked.yml`](../.github/workflows/ci-locked.yml) | Yes, including `diff-stats@v1` at its reviewed commit |
| [`ci-sha-pinned.yml`](../.github/workflows/ci-sha-pinned.yml) | No |

When `diff-stats` tag `v1` moves to the commit on its `unreviewed` branch, the
SHA-pinned-only workflow runs that commit (it prints an "UNREVIEWED diff-stats
commit ran" banner) and the locked workflow keeps running the reviewed commit.
Everything is harmless: the unreviewed commit only prints the banner.

| Script | What it does |
| --- | --- |
| `demo/reset.sh` | Before each take. Moves the tags back to the reviewed commits, disables the Require lockfile policy, force-moves `main` back to tag `demo-baseline` (undoing the live `gh actions-lock` commits), puts this checkout on a clean `main` at that commit (local changes go to `git stash`, local commits to a `reset-backup/<time>` branch), checks `main`, and prints GREEN or RED. |
| `demo/a/move-tag.sh` | Points `diff-stats` tag `v1` at the unreviewed commit, starts both workflows on `main` and prints their run URLs without waiting. |
| `demo/a/dispatch.sh` | Backup: runs both workflows on `main` again, waits, and prints which `diff-stats` commit each ran, with run URLs. |

`main`'s `actions.lock` ([`locks/ci.lock`](locks/ci.lock)) locks only `ci-locked.yml` during Demo A so it's short on screen.
Demo B widens it live: `rm .github/workflows/ci-sha-pinned.yml`, then `gh actions-lock`.

`reset.sh` refuses to rewind `main` when it changed files outside `.github/`
since `demo-baseline`. To keep a change pushed to `main`, move the tag:
`git push -f origin main:refs/tags/demo-baseline`.

## Lockfile verification: imposter commit (Demo B)

[`nodeselector/pr-note`](https://github.com/nodeselector/pr-note) is a fork of
[`Steve-Glass/pr-note`](https://github.com/Steve-Glass/pr-note). Its
`imposter-commit` branch holds commit
[`177435a`](https://github.com/Steve-Glass/pr-note/commit/177435a434f84257b283b9f46dfc2fc36d3abba4).
That commit only prints an "IMPOSTER pr-note commit ran" banner. Because forks share
objects, the commit is reachable under the upstream name, but it isn't on
any upstream tag or branch.

Both workflows also call pr-note: [`ci-locked.yml`](../.github/workflows/ci-locked.yml)
as `Steve-Glass/pr-note@v3`, [`ci-sha-pinned.yml`](../.github/workflows/ci-sha-pinned.yml)
pinned to v3's commit `47713a3`. pr-note handles only `issue_comment`, so under
`workflow_dispatch` it posts nothing. Two reference branches each change one file:

| Branch | Change | Caught by |
| --- | --- | --- |
| `imposter-pin` | `ci-locked.yml` pins pr-note at `177435a` | `gh actions-lock` refuses to write the entry: "Pinned commit not in upstream history" |
| `forged-lock` | `actions.lock` records `177435a` for `steve-glass/pr-note@v3` | The run fails at Set up job: the lockfile pin doesn't match ref `v3` |

Demo B has no scripts: each step is one `gh actions-lock` or `git` command.

## Egress firewall: a helper changed after review (Demo D)

[`nodeselector/license-check@v1`](https://github.com/nodeselector/license-check/tree/v1)
loads its default license policy by running a helper fetched at runtime:
`curl -fsSL https://nodeselector.github.io/license-check/helper.sh | bash`. The
helper is served from that repository's `gh-pages` branch. The lockfile pins
v1's code, but it can't pin what that code downloads while it runs.

[`release.yml`](../.github/workflows/release.yml), a pre-release license check, runs the same
locked job on `ubuntu-24.04-firewall` and `ubuntu-24.04`.
[`egress-firewall.yaml`](../.github/egress-firewall.yaml) allows
`nodeselector.github.io`, so the helper loads on both. The updated helper
(`helper-updated` branch) also quietly POSTs a fixed marker and the runner name to
`evilnodeselector.github.io`, a host that isn't allowlisted (it only ends with the
allowed `nodeselector.github.io`; no site needs to exist there). It prints
nothing about the call, so both job logs look clean. The firewall runner blocks
the call and logs it in its decision log; `d/egress-run.sh` prints that verdict.
The plain runner has no firewall and no decision log, so the run can't show what
its call did; it's there so the two job logs can be compared side by side.

| Script | What it does |
| --- | --- |
| `demo/d/update-helper.sh` | Moves `gh-pages` to the updated helper commit and waits until Pages serves it. No new release; the lock stays valid. |
| `demo/d/egress-run.sh` | Dispatches `release.yml`, then prints each job's helper output (no sign of the POST), then the firewall runner's per-host verdict from its decision log: ALLOWED and BLOCKED hosts (blocks with no process, the runner image's own DNS and NTP traffic, are left out). |

`reset.sh` puts `gh-pages` back on the clean helper.

## Require lockfile policy

The repository has a **Require lockfile** Actions policy (Preview), configured
under Settings → Actions → Policies. When it's active, runs of workflows that
aren't in `actions.lock`, such as `ci-sha-pinned.yml`, end in `startup_failure`.
`reset.sh` sets it back to disabled, because Demo A runs that workflow.

## Regenerating the locks

Name the locked workflow so the comparison workflow stays unlocked:

```sh
gh actions-lock --no-narrow --no-interactive .github/workflows/ci-locked.yml  # locks/ci.lock
```

Delete `actions.lock` first; the CLI only adds entries to an existing one. If
upstream `Steve-Glass/pr-note@v3` moves, update `PRNOTE_LOCKED` in [`lib.sh`](lib.sh);
`reset.sh` checks it.
