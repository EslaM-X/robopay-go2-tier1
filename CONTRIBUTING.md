# Contributing

Thanks for your interest. This project is designed so a first-time contributor
can land a small, reviewable change quickly.

## Ground rules

- **Evidence stays honest.** Every measurement in this repo (paw lift, sit
  depth, obstacle contacts, settlement proofs) must stay reproducible. Never
  commit a number you did not measure. A missing runtime writes an honest SKIP
  report — never a fake pass.
- **Offline tests.** New skills, gates, and navigation features ship with tests
  that run without network or API keys. Live settlement is env-gated
  (`BASE_SEPOLIA_RPC_URL`, `PRIVATE_KEY`) and never required by the suite.
- **Small PRs.** One logical change per pull request.
- **Registry-driven.** A new skill touches the registry profile
  (`registry/vendors/unitree/go2/unitree.go2.mujoco-pybullet-sim.v1/`) — `skills.yaml`,
  `functions.yaml`, `payment-policy.yaml`, `execution-mapping.yaml`, `tests/`,
  and the skill table in `README.md`. Skills that are not executable in
  `simulation/` are not accepted.

## Getting started

1. Fork and clone.
2. `cd simulation && bash setup.sh` — pinned official menagerie `unitree_go2` assets.
3. `pip install mujoco>=3.1.3 numpy pybullet cryptography eclipse-zenoh eth-account`.
4. `cd go2 && python3 test_go2_control.py` — a single skill test must pass.

## First contribution in 6 steps

1. Pick an open issue (labels: `good first issue`, `good first contribution`,
   `help wanted`, `documentation`).
2. Read the [code of conduct](CODE_OF_CONDUCT.md) and this guide.
3. Run `bash simulation/verify_go2_tier1.sh` and keep it green.
4. Run `ruff check` and `ruff format --check` clean if you touch Python.
5. Open your pull request (use the [PR template](.github/PULL_REQUEST_TEMPLATE.md)).
6. Get reviewed — then your name goes on the contributor wall.

## Pull requests

- Add or update a test with every change.
- Keep `bash simulation/verify_go2_tier1.sh` green — it is the single acceptance
  command and it runs in CI (`Go2 Simulation Tests`).
- Update `CHANGELOG.md` with your change.
- Link the issue your PR closes.

## Labels you can grab

- `good first issue` / `good first contribution` — small, well-scoped.
- `help wanted` — maintainers would like contributions.
- `documentation` — docs-only, great starting point.
- `navigation` / `payment-gate` / `sim2sim` — feature-area work.

## Code of conduct

Be respectful and constructive. See `CODE_OF_CONDUCT.md`.
