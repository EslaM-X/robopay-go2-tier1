# Unitree Go2 Tier 1 — paid actions drive the Go2 in simulation

**Scope: simulator-only submission.** No physical robot is involved; the
x402 payment gate and the wire contract are exercised end to end in peer-mode
Zenoh, and the on-chain settlement step (Base Sepolia, EIP-3009) is exercised
live and provably.

A paid RoboPay action arriving on the tunnel's Zenoh topic starts a Go2 skill
episode on the official MuJoCo model (`google-deepmind/mujoco_menagerie`
`unitree_go2`). Nine skills are available — wave, sit, stand, stop, bow, nod,
turn_to_face, hold and **navigate_obstacle** — each driven by a joint-space PD
trajectory controller, not by any recorded motion. The same joint
configurations are recomputed in PyBullet (from a kinematic URDF generated
deterministically from the *same* `go2.xml`) with a measured agreement between
the two engines.

The chain, top to bottom:

    paid action (x402 / AIP) -> tunnel -> Zenoh "robot/tunnel/action"
    -> subscriber -> validate envelope + x402 payment gate -> Go2 skill
    -> joint PD on the mujoco_menagerie model -> metrics
    -> result on "robot/tunnel/result" (correlated by actionId)

## Skills

| skill | what happens | measured |
|---|---|---|
| `wave` | front-right paw lifts in an arc and lowers back (body-weight compensation while airborne) | pawLift 0.167 m, body stays at home |
| `sit` | body crouches into a sit posture, then returns | sitDepth 0.145 m |
| `stand` | returns to the home standing stance | returns to home body height |
| `stop` | safe stop: halts all motion and returns to the stable home stance | returns to home body height |
| `bow` | front dips into a play bow | bowPitchDeg 18.8 deg |
| `nod` | full-body greeting bob | nodDepth 0.040 m |
| `turn_to_face` | yaws toward `headingDeg` (bounded yaw torque + hip-abduction shuffle), reports achieved yaw and remaining error honestly | yawed 17.2 deg toward heading 30 |
| `hold` | holds the stance for `seconds` | stance stable |
| `navigate_obstacle` | slow diagonal trot through a static obstacle course to a goal; potential-field planner + physics contacts | 3/3 waypoints, 0 contacts, min clearance 0.047 m, final goal distance 0.099 m |

Every successful skill returns the body to the home stance height afterwards
(|bodyZ − home| < 0.02, where `home` is the robot's own settled resting
height), so paid actions can run back to back.

The Go2 model exposes torque `motor` actuators (no native position
actuators), so the controller wraps them in a small PD position servo while
keeping the model's torque limits intact.

## Obstacle navigation (`navigate_obstacle`)

Steering uses a **measured calf-gain calibration** (`STEER_TABLE` in
`go2_control.py`): the shared calf gain `kc` scales `calf = -1.8 + kc*off`
and produces a monotone straight-line net heading over **-21.7°..0°** — so a
descending course is followed as clean, low-drift segments. A
**potential-field local planner** pulls toward a look-ahead point on the
waypoint segment (keeping the requested bearing inside the calibrated range)
and repels from obstacles. **Obstacle contact is detected by the MuJoCo
physics engine** (contact pairs on `obs_*` geoms injected by
`obstacle_world.py`), never a distance estimate. `TIMEOUT` and `COLLISION` are
proper error results; `test_adversarial_nav.py` proves both on the real
controller path (unreachable goal → `TIMEOUT`; blocking obstacle →
`COLLISION`, 8 simultaneous contact pairs).

## Requirements

- Python 3.10+ (tested 3.12), `pip install mujoco>=3.1.3 numpy pybullet cryptography eclipse-zenoh eth-account`
- The MuJoCo Go2 model needs MuJoCo 3.1.3+ (menagerie requirement).
- No tunnel binary is needed for the tests: the payment gate is a faithful
  Python reimplementation of the tunnel's x402 decisions (see below), and the
  wire tests publish the exact `handlers.PostAction` event schema.

Developed and validated on Windows 11 (python 3.12); the same tests run on
ubuntu-latest via CI (`.github/workflows/go2-simulation-tests.yml`).

## Setup

```sh
cd simulation
./setup.sh   # fetch the official menagerie unitree_go2 assets (pinned commit, idempotent)
```

## Tests

Each test prints its checks as JSON and PASS/FAIL, and exits nonzero on
failure.

```sh
cd simulation/go2
python3 test_go2_control.py        # every skill's physics actually happen
python3 test_payment_gate.py       # x402 gate: 402/400/409, no-settle-on-failure
python3 test_result_semantics.py   # success/error results, replay, tampering
python3 test_link.py               # paid action -> Zenoh -> episode -> result
python3 test_obstacle_nav.py       # calf-gain steering + potential-field nav
python3 test_adversarial_nav.py    # honest TIMEOUT / COLLISION failure matrix
python3 test_durable_replay.py     # replay keys survive a store restart
python3 test_settlement.py         # EIP-3009 offline proof + no-settle-on-failure
cd ../pybullet
python3 test_sim2sim_go2.py        # same poses in MuJoCo and PyBullet, compared
cd ../webots
bash run_webots_sim2sim.sh         # real Webots R2025a sim-to-sim (or honest SKIP)
```

**One command:** `bash simulation/verify_go2_tier1.sh` runs every acceptance
test above and exits nonzero if any fails.

`test_payment_gate.py` drives the gate directly (unpaid -> 402 +
PAYMENT-REQUIRED, expired/forged receipts -> 402, replayed idempotencyKey /
txHash -> 409, and a settlement ledger proving that only `"status":
"success"` results settle). `test_result_semantics.py` runs the full link
with peer-mode Zenoh and proves every failure path returns an error result.
`test_link.py` publishes one valid paid `wave` action and expects a success
result carrying the physics metrics (pawLift, bodyZ) correlated by actionId.

## Wire contract

Zenoh topics (peer mode; the link and the test harness discover each other on
localhost, no separate router needed):

| topic | direction | schema |
|---|---|---|
| `robot/tunnel/action` | tunnel -> robot | tunnel event: `{payload, transaction_details, timestamp}`; `payload` is the action envelope `{actionId, robotId, skillId, params, paramsHash, idempotencyKey, payment}` |
| `robot/tunnel/result` | robot -> relay | `{"status": "success", actionId, skill, result: {message, metrics}}` or `{"status": "error", actionId, skill, error: {code, message}}` |

The skill catalog lives in `go2/skills.json` (9 priced skills — the 8 base
skills at $0.002 each plus `navigate_obstacle` at $0.005; printed at startup
for discovery). `robopay_link.py` validates every envelope: unknown skill,
out-of-schema or tampered params (`paramsHash` is sha256 of canonical JSON),
wrong robotId, and replayed `idempotencyKey` all produce an error result and
never actuate the robot. Error codes: `UNKNOWN_SKILL, INVALID_PARAMS,
WRONG_ROBOT, REJECTED_PAYMENT, UNPAID, DUPLICATE, ACTION_FAILED`. **The relay
must settle only on `"status": "success"`** — `test_result_semantics.py`
proves every failure path yields an error result (no-settle-on-failure
evidence).

Note on the return path: the tunnel in this repo does not yet consume
execution results, so publishing them on the documented result topic is the
integration point this submission provides — the relay can subscribe there to
correlate by `actionId` and decide settlement.

Payment gate: `payment_gate.py` mirrors the tunnel's x402 middleware
decision semantics so the simulator-only submission exercises the same flow
end to end — receipts are Ed25519-signed by a local facilitator whose key is
persisted next to the module (so the payer side and the robot side share one
trusted facilitator, like the tunnel trusts the advertised facilitator
public key), a replayed idempotencyKey or txHash is a 409, and settlement is
recorded only for success results. Replay protection is durable
(file-backed store; `test_durable_replay.py` proves keys survive a restart).
No private keys or secrets leave the repo. By default settlement stays on
the local facilitator ledger; **optional on-chain settlement** (Base
Sepolia, EIP-3009) is available through `go2/settlement_base_sepolia.py`
when `BASE_SEPOLIA_RPC_URL` + `PRIVATE_KEY` are set (`test_settlement.py`
verifies the guards).

Configuration (env vars, defaults in parentheses):

- `ROBOPAY_ACTION_TOPIC` (`robot/tunnel/action`), `ROBOPAY_RESULT_TOPIC`
  (`robot/tunnel/result`), `ROBOPAY_ROBOT_ID` (`test-robot`, matching
  `tunnel/config.json`)
- `GO2_MODEL_PATH` (default
  `models/mujoco_menagerie/unitree_go2/scene.xml` relative to `simulation/`)

### Robot identity, wallet binding and safety

- **Robot identity** — `ROBOPAY_ROBOT_ID` binds the robot to the payee
  wallet through the tunnel's `config.json` (`robot_id` +
  `evm_payee_address`). Every envelope is checked against `robotId`; a
  mismatch returns `WRONG_ROBOT` and never actuates the robot.
- **Safe stop** — the `stop` skill is the fail-safe action: it halts motion
  and returns the robot to the stable home stance on a short timeline. Any
  payer can request it at any time.
- **Testnet** — the profile's payment policy targets `eip155:84532` (Base
  Sepolia testnet); configure `network` and `token_address` in
  `tunnel/config.json` for the chain you settle on.
- **Security warning** — private keys must only be supplied through
  environment variables or a secret manager (e.g. the facilitator key file
  used by the simulator gate). Never hardcode, commit, or log private keys;
  `simulation/.gitignore` and the repo `.gitignore` exclude `.env`, `*.b64`,
  `keys/` and `simulation/models/`. The simulator writes its facilitator key
  next to `payment_gate.py` on first run for local-only playback and it
  should not be treated as a production secret.

The machine-readable robot profile (skills, payment policy, execution
mapping, example envelope, skill-contract tests, validation report) lives
under `registry/vendors/unitree/go2/unitree.go2.mujoco-pybullet-sim.v1/`.

## Sim-to-sim results

Go2 (`test_sim2sim_go2.py`): each skill's salient pose is captured in MuJoCo
(wave peak lift, sit deepest crouch, bow max pitch, nod max dip, end of turn,
home) and recomputed in PyBullet via the committed kinematic URDF
`pybullet/go2_simple_kin.urdf`, which is generated from the same `go2.xml`
by `make_go2_kin_urdf.py` (joint frames, axes and limits read straight from
the MJCF — PyBullet cannot parse the menagerie MJCF 3.x directly), so the two
engines share the same kinematics by construction. Foot-tip positions agree
to **1 cm tolerance with observed worst-case 0.02 cm** across all poses and
all four feet (`pybullet/go2_sim2sim_report.json`).

Webots (`webots/test_sim2sim_go2_webots.py`): a sim-to-sim *harness* is
committed for the Webots R2025a runtime (real Supervisor code reading
physics-reported foot positions; no placeholders). It reports
`skipped_webots_runtime_missing` and is NOT claimed as a measured result
until run under Webots against a world importing the unitree_ros go2 URDF.

Expected outputs — success (`test_link.py`) and failure
(`test_result_semantics.py`) results on `robot/tunnel/result`:

```json
{"actionId": "act_...", "skill": "wave", "status": "success",
 "result": {"message": "Action completed",
            "metrics": {"pawLift": 0.167, "bodyZ": 0.283, "...": "..."}}}
{"actionId": "act_...", "skill": "turn_to_face", "status": "error",
 "error": {"code": "INVALID_PARAMS", "message": "'headingDeg' must be degrees with |v| <= 180.0"}}
```

## Live on-chain settlement (Base Sepolia, EIP-3009)

The optional settlement module was exercised against the real Base Sepolia
chain (chainId **84532**) using the official Circle **USDC** contract
`0x036CbD53842c5426634e7929541eC2318f3dCF7e` (EIP-3009 version `2`, decimals
6). Three independent, verifiable `transferWithAuthorization` settlements
moved **1.0 USDC each** from payer to payee (txHashes in
`simulation/docs/settlement-proof.json`); each receipt logs the EIP-3009
`AuthorizationUsed` event and a `Transfer` event of exactly 1.0 USDC, and
on-chain post-checks confirmed `authorizationState(authorizer, nonce) ==
true` (consumed) for every nonce. Everything was funded **entirely from free
faucets** (Circle USDC + Base Sepolia ETH faucets; total gas under 0.000002
ETH) — no deposited capital required.

The **no-settle-on-failure contract** was proven live: with the relay in a
`timeout` result state, `settle_if_success` short-circuits before any
transaction is built, and the relay's on-chain nonce is provably unchanged
(`simulation/docs/settlement-proof-failure.json`).

Machine-readable evidence: `simulation/docs/settlement-proof.json` (success)
and `settlement-proof-failure.json` (failure). Reproduce with
`simulation/go2/prove_live_settlement.py` (requires `PRIVATE_KEY`,
`PAYEE_ADDRESS`, `BASE_SEPOLIA_RPC_URL`; **never commit keys**).

## Troubleshooting

- **Tests hang waiting for Zenoh messages**: another process may hold a
  stale session. On Linux `pkill -f robopay_link.py`; on Windows kill the
  leftover `python` processes and retry.
- **MuJoCo fails to load the model**: the menagerie Go2 model needs MuJoCo 3.1.3+.
- **HTTPS blocked when fetching models**: `GIT_HOST=git@github.com: ./setup.sh`
  clones over SSH instead.

## Layout

```
simulation/
├── setup.sh                 fetch pinned official menagerie unitree_go2 assets
├── go2/
│   ├── go2_control.py       joint-space skill controller on MuJoCo (PD servo)
│   ├── obstacle_world.py    injects static obstacle geoms into the scene
│   ├── payment_gate.py      x402 gate (402/409, settle-only-on-success, durable replay)
│   ├── settlement_base_sepolia.py  optional Base Sepolia EIP-3009 settlement (env-gated)
│   ├── robopay_link.py      action validation, payment gate, skill execution
│   ├── skills.json          priced skill catalog (discovery)
│   ├── simulate_paid_action.py
│   └── test_go2_control.py / test_payment_gate.py / test_result_semantics.py
│       / test_link.py / test_obstacle_nav.py / test_adversarial_nav.py
│       / test_durable_replay.py / test_settlement.py
├── pybullet/
│   ├── go2_simple_kin.urdf  Go2 kinematic URDF (generated from go2.xml) for sim-to-sim
│   ├── make_go2_kin_urdf.py generator (deterministic, reproducible)
│   ├── test_sim2sim_go2.py
│   └── go2_sim2sim_report.json
├── webots/
│   ├── go2_sim2sim.wbt      Webots R2025a world (rebuilt from the same MJCF)
│   ├── controllers/go2_sim2sim/  real Supervisor controller
│   ├── run_webots_sim2sim.sh     headless runner (honest SKIP without runtime)
│   └── test_sim2sim_go2_webots.py
└── docs/
    ├── go2.gif              screen recording of paid skills
    ├── go2-shots/           per-skill screenshots
    ├── go2-ci-logs.txt      paid request → Zenoh → execution → result
    ├── obstacle_course_map.svg     real physics trajectory over the course
    ├── obstacle_nav_report.json    navigation metrics
    ├── obstacle_adversarial_report.json  TIMEOUT/COLLISION failure matrix
    └── settlement-proof.json / settlement-proof-failure.json  on-chain evidence
```
