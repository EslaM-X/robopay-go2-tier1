FROM python:3.12-slim

LABEL org.opencontainers.image.title="robopay-go2-tier1"
LABEL org.opencontainers.image.description="Unitree Go2 Tier-1 RoboPay simulator — 9 paid embodied skills, x402 gate, sim-to-sim, live Base Sepolia settlement proof"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/EslaM-X/robopay-go2-tier1"

# git is required by simulation/setup.sh (sparse clone of mujoco_menagerie)
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY . .

RUN pip install --no-cache-dir \
        mujoco>=3.1.3 numpy pybullet cryptography eclipse-zenoh eth-account

# Fetch pinned official Go2 model assets (idempotent; menagerie BSD-3-Clause)
RUN cd simulation && bash setup.sh

WORKDIR /workspace/simulation

# One-command verification: every acceptance test, exit nonzero on failure
CMD ["bash", "verify_go2_tier1.sh"]
