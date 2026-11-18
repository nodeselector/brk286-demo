# BRK286 demo

Demo repository for native Actions dependency locking (`actions.lock`) and the
native egress firewall. Everything is harmless: no secrets, no real attack.

| Workflow | Demo |
| --- | --- |
| [`ci-locked.yml`](.github/workflows/ci-locked.yml) | A: uses tags; `actions.lock` pins the commits, including the transitive `diff-stats@v1`. B: an imposter commit for its `pr-note@v3` step is rejected. |
| [`ci-sha-pinned.yml`](.github/workflows/ci-sha-pinned.yml) | A: pins by full SHA and isn't in `actions.lock`, so it follows a moved transitive tag. |
| [`release.yml`](.github/workflows/release.yml) | D: a pre-release license check whose runtime-fetched helper is blocked by [`egress-firewall.yaml`](.github/egress-firewall.yaml). |

Scripts, branches, reset steps and the Ctrl-R stage history: [demo/README.md](demo/README.md).
