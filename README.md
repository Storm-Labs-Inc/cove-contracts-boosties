# smart-contracts-core

[![codecov](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core/branch/master/graph/badge.svg?token=TT68C116IT)](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core)
[![CI](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml)

# Installation

Tested with node 18.16.1, python 3.9.17, and rustc 1.75.0

```sh
# Install rustc via rustup
# https://www.rust-lang.org/tools/install
rustup update
# Install python dependencies
pip install -r requirements.txt
# Install submodules as forge libraries
forge install
# Install node dependencies and build dependencies
pnpm install
# Build contracts
pnpm build
```

# Compilation

```sh
# Build forge-deploy if not already built
pnpm forge-deploy:build
# Build contracts
pnpm build
# Run tests
pnpm test
```

### Running echidna tests

```sh
# First install echidna from https://github.com/crytic/echidna
# Then run echidna tests
echidna ./echidna --config ./echidna.config.yaml --contract BaseRewardsGauge_EchidnaTest;
```

# Deploying contracts to live network

## Local mainnet fork

```sh
# Fork the mainnet on local network using anvil with the provided script
pnpm fork:mainnet
```

Keep this terminal session going to keep the fork network alive.

Then in another terminal session:

```sh
# Deploy contracts to local network
pnpm deploy:local
```

- deployments will be in `deployments/<chainId>-fork`
- make sure to not commit `broadcast/`
- if trying to deploy new contract either use the default deployer functions or generate them with
  `$./forge-deploy gen-deployer`
