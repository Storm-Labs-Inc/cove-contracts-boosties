# smart-contracts-core

[![codecov](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core/branch/master/graph/badge.svg?token=TT68C116IT)](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core)
[![CI](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml)

# Installation

Tested with node 18.16.1 and python 3.9.17

```sh
# Install python dependencies
pip install -r requirements.txt
# Install node dependencies
pnpm install
# Install submodules as forge libraries
forge install
```

# Compilation

```sh
# Build contracts
pnpm build
# Run tests
pnpm test
```

# Deploying contracts to live network

## Local mainnet fork

```sh
# Fork the mainnet on local network using anvil with the provided script
pnpm anvil-fork
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
