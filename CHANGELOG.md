# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [v1.0.1] - 2026-08-16

### Added

- `Dockerfile` + `publish-docker-image` workflow — the full reproducible
  environment ships as a public container image on GitHub Container Registry
  (`ghcr.io/eslam-x/robopay-go2-tier1`), rebuilt from every `v*` tag.

### Fixed

- Docker build on `python:3.12-slim` — added `build-essential` so `pybullet`'s
  native extension compiles.

## [v1.0.0] - 2026-08-15

### Added

- Authorship archive of the Unitree Go2 Tier-1 RoboPay submission
  ([PR #89](https://github.com/fabricfoundation/RoboPay/pull/89)).
- Registry profile `unitree.go2.mujoco-pybullet-sim.v1` — 9 priced skills
  (`wave`, `sit`, `stand`, `stop`, `bow`, `nod`, `turn_to_face`, `hold`,
  `navigate_obstacle`), x402 payment policy, execution mapping, skill-contract
  tests.
- `simulation/` — joint-space PD controller on the official
  `mujoco_menagerie` model, payment gate, Zenoh link, durable replay, obstacle
  navigation with potential-field planner, EIP-3009 settlement module, and 9
  test suites.
- PyBullet kinematic sim-to-sim (worst-case 0.02 cm agreement) and Webots
  R2025a supervisor harness (honest SKIP without the runtime).
- `Go2 Simulation Tests` CI workflow; `verify_go2_tier1.sh` single-command
  acceptance run; evidence media (`go2.gif`, obstacle course map, settlement
  proofs).
