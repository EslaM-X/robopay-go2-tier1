# Unitree Go2 Tier 1 — paid embodied skills in MuJoCo + PyBullet + Webots

**Scope: simulator-only submission.** No physical robot is involved; the
x402 payment gate and the wire contract are exercised end to end in peer-mode
Zenoh, and on-chain settlement (Base Sepolia, EIP-3009) is exercised live and
provably.

A paid RoboPay action arriving on the tunnel's Zenoh topic starts a Go2 skill
episode on the **official** MuJoCo model (`google-deepmind/mujoco_menagerie`
`unitree_go2`). Nine skills are available — `wave`, `sit`, `stand`, `stop`,
`bow`, `nod`, `turn_to_face`, `hold` and **`navigate_obstacle`** — each driven
by a joint-space PD trajectory controller with gravity compensation, **never**
a recorded motion or built-in demo. The same joint configurations are
recomputed in PyBullet (from a kinematic URDF generated deterministically from
the *same* `go2.xml`) and compared, so the paid action is a real, measured
embodiment in both simulators.

The chain, top to bottom:

    paid action (x402 / AIP) -> tunnel -> Zenoh "robot/tunnel/action"
    -> subscriber -> validate envelope + x402 payment gate -> Go2 skill
    -> joint PD on the mujoco_menagerie model -> metrics
    -> result on "robot/tunnel/result" (correlated by actionId)

## Skills

| skill | what happens | measured |
|---|---|---|
| `wave` | front-right paw lifts in a greeting arc, body-weight compensated | pawLift 0.167 m, body stays at 0.283 m |
| `sit` | crouch into a sit posture, then return | sitDepth 0.145 m |
| `stand` | return to the home standing stance | home stance re-measured |
| `stop` | safe stop: halt motion, return to the stable home stance | `\|bodyZ - home\| < 0.02` |
| `bow` | dip the front into a play bow | bowPitchDeg 18.8 deg |
| `nod` | gentle full-body greeting bob | nodDepth 0.040 m |
| `turn_to_face` | yaw toward `headingDeg` (static-stability shuffle); reports achieved yaw + residual honestly | 17.2 deg toward heading 30, residual 12.9 deg |
| `hold` | hold the stance for `seconds` | stable at 0.283 m |
| `navigate_obstacle` | steer a slow diagonal trot through a static obstacle course to a goal (potential-field planner, physics contacts) | 3/3 waypoints, 0 contacts, min clearance 0.047 m, final goal distance 0.099 m |

Every successful skill returns the body to the home stance height afterwards
(`|bodyZ - 0.283| < 0.02`), so paid actions can run back to back.

## Obstacle navigation (`navigate_obstacle`)

Steering uses a **measured calf-gain calibration** (`STEER_TABLE` in
`go2_control.py`): the shared calf gain `kc` scales `calf = -1.8 + kc*off`
and produces a monotone, straight-line net heading over **-21.7°..0°** — so a
descending course is followed as clean, low-drift segments. A **potential-field
local planner** pulls toward a look-ahead point on the waypoint segment and
repels from obstacles. **Obstacle contact is detected by the MuJoCo physics
engine** (contact pairs on `obs_*` geoms), never a distance estimate.
`TIMEOUT` and `COLLISION` are proper error results; `test_adversarial_nav.py`
proves both on the real controller path (unreachable goal -> `TIMEOUT`;
blocking obstacle -> `COLLISION`, 8 simultaneous contact pairs).

Measured on the committed course (`simulation/docs/obstacle_nav_report.json`,
course drawn in `obstacle_course_map.svg`):

| metric | result |
|---|---|
| waypoints reached | 3/3 |
| path length | 4.535 m |
| obstacle contacts | 0 |
| min clearance | 0.047 m |
| final goal distance | 0.099 m |
| heading error | 26.9 deg |

## End-to-end flow

```
paid action (x402) → tunnel → Zenoh robot/tunnel/action
    → robopay_link.py → validate envelope + payment gate (durable replay)
    → joint-space Go2 controller on mujoco_menagerie
    → metrics → result on robot/tunnel/result (correlated by actionId)
    → settle ONLY on status:success (local ledger; optional Base Sepolia)
```

## Why this clears the RoboPay success criteria

- **Real action, not a demo** — each skill is a joint-space trajectory driven
  by the controller; physics metrics are measured (paw lift, sit depth, torso
  pitch/yaw, body height, achieved heading, obstacle contacts), not scripted.
- **Payment safety** — settle **only** on `status: success`; unpaid ⇒ 402 +
  `PAYMENT-REQUIRED`, forged/expired receipts ⇒ 402, replay ⇒ 409, tampered
  `paramsHash` ⇒ `INVALID_PARAMS`. Every failure path returns an error result
  and never settles (`test_payment_gate.py`, `test_result_semantics.py`).
- **Sim-to-sim** — the same joint configurations are recomputed in PyBullet
  from a kinematic URDF generated from the same `go2.xml`; foot-tip positions
  agree to **1 cm tolerance with observed worst-case 0.02 cm**
  (`simulation/pybullet/go2_sim2sim_report.json`). A Webots R2025a supervisor
  harness is committed and honestly SKIPs when the runtime is missing
  (`simulation/webots/`).
- **Durable replay** — idempotency keys / txHashes survive a store restart
  (`test_durable_replay.py`).
- **Live on-chain settlement (Base Sepolia, EIP-3009)** — 3 real
  `transferWithAuthorization` transactions settled 1.0 USDC each on Base
  Sepolia (chainId 84532, USDC `0x036CbD53842c5426634e7929541eC2318f3dCF7e`),
  funded entirely from free faucets; no-settle-on-failure proven on-chain
  (relay nonce unchanged). Evidence: `simulation/docs/settlement-proof.json`
  + `settlement-proof-failure.json`.
- **Reproducible** — clean checkout + `bash simulation/verify_go2_tier1.sh`,
  under 30 minutes.

## Reproduce

```sh
pip install mujoco>=3.1.3 numpy pybullet cryptography eclipse-zenoh eth-account
cd simulation
./setup.sh                      # pinned official menagerie unitree_go2 assets
cd go2
python3 test_go2_control.py     # every skill's physics actually happen
python3 test_payment_gate.py    # 402/409, settle-only-on-success
python3 test_result_semantics.py# success/error semantics, replay, tampering
python3 test_link.py            # paid action → Zenoh → episode → result
python3 test_obstacle_nav.py    # calf-gain steering + potential-field nav
python3 test_adversarial_nav.py # honest TIMEOUT / COLLISION failure matrix
python3 test_durable_replay.py  # replay keys survive a store restart
python3 test_settlement.py      # EIP-3009 offline proof + no-settle-on-failure
cd ../pybullet
python3 test_sim2sim_go2.py     # MuJoCo ⇄ PyBullet agreement (≤0.02 cm)
cd ../webots
bash run_webots_sim2sim.sh      # real Webots R2025a sim-to-sim (or honest SKIP)
```

**One command:** `bash simulation/verify_go2_tier1.sh` runs every acceptance
test above and exits nonzero if any fails.

### Optional: Enable Live Base Sepolia Settlement

```sh
export BASE_SEPOLIA_RPC_URL="https://sepolia.base.org"
export PRIVATE_KEY="0x..."          # payee private key (NEVER commit!)
export PAYEE_ADDRESS="0x..."        # derived from PRIVATE_KEY if not set
python3 test_payment_gate.py        # will attempt Base Sepolia settlement on success
```

## Layout

```
registry/vendors/unitree/go2/unitree.go2.mujoco-pybullet-sim.v1/
    robot.profile.yaml      robot identity + Zenoh runtime
    skills.yaml             the 9 skills, params, limits
    functions.yaml          agent REST contract (/action, 402)
    payment-policy.yaml     x402 pricing + settle-on-success rule
    execution-mapping.yaml  skill → simulator runtime + metrics
    examples/               paid action envelope
    tests/                  skill-contract cases
    docs/                   README + validation report
simulation/
    setup.sh                pinned fetch of official menagerie unitree_go2
    go2/                    Go2 controller, payment gate, Zenoh link, obstacle
                            navigator, durable replay, settlement module + 9
                            test suites
    pybullet/               kinematic URDF (generated from go2.xml) + sim-to-sim
    webots/                 Webots R2025a supervisor harness (honest SKIP
                            without the runtime)
    docs/                   evidence: go2.gif, CI logs, shots, obstacle reports,
                            settlement proofs
```

## Evidence media

- Screen recording: `simulation/docs/go2.gif`
- Per-skill screenshots: `simulation/docs/go2-shots/`
- Obstacle course map (real physics trajectory): `simulation/docs/obstacle_course_map.svg`
- Obstacle navigation report: `simulation/docs/obstacle_nav_report.json`
- Adversarial failure matrix: `simulation/docs/obstacle_adversarial_report.json`
- Sim-to-sim report: `simulation/pybullet/go2_sim2sim_report.json`
- Live settlement proof: `simulation/docs/settlement-proof.json` + `settlement-proof-failure.json`
- CI logs: `simulation/docs/go2-ci-logs.txt`

## Known limitations (honest scope)

- Simulator-only profile; the x402 gate mirrors the tunnel's middleware
  decision semantics in Python (not the compiled Go binary).
- Base Sepolia settlement is env-gated (needs funded payee key + RPC); the
  committed proofs are from real faucet-funded runs.
- Webots sim-to-sim is best-effort: without the runtime it writes an honest
  SKIP report and never fakes a pass.
- `turn_to_face` uses a static-stability hip-abduction shuffle (honest
  residual error reported). `navigate_obstacle` uses static obstacles only.

## Docker image

The full reproducible environment (Python deps + pinned Go2 model assets +
one-command verification) ships as a public container image:

```sh
docker pull ghcr.io/eslam-x/robopay-go2-tier1:latest
docker run --rm ghcr.io/eslam-x/robopay-go2-tier1:latest
```

The image runs `verify_go2_tier1.sh` (every acceptance test, exit nonzero on
failure) and is rebuilt from each `v*` tag by
`.github/workflows/publish-docker-image.yml`.

## Authorship archive

This repository is the **original authorship archive** of the Unitree Go2
Tier-1 submission to the RoboPay bounty ([PR #89](https://github.com/fabricfoundation/RoboPay/pull/89)).
It lives independently of any fork so the work is provably authored by
EslaM-X, timestamped by git history, and tagged for release. Every file in
`registry/` and `simulation/` is the authored submission content; see the
[ROADMAP](ROADMAP.md) for the archive's principles.

## License

MIT — © 2026 EslaM-X 🇪🇬
