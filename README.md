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

# Compiliation

```sh
# Build contracts
pnpm build
# Run tests
pnpm test
```

# Deploying contracts to live network

## Local mainnet fork

```sh
# Run a fork network using anvil
anvil --rpc-url <fork_network_rpc_url>
```

Keep this terminal session going to keep the fork network alive.

Then in another terminal session:

```sh
# Deploy contracts to local fork network
pnpm localDeploy
```

- deployments will be in `deployments/<chainId>-fork`
- make sure to not commit `broadcast/`
- if trying to deploy new contract either use the default deployer functions or generate them with
  `$./forge-deploy gen-deployer`
