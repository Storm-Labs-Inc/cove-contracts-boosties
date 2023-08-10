# smart-contracts-core

[![codecov](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core/branch/master/graph/badge.svg?token=TT68C116IT)](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core)
[![CI](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml)

# For local deploy to fork

- `pnpm install`
- `anvil --rpc-url <fork_network_rpc_url>`
- `pnpm build`
- in another window `pnpm localDeploy`
- deployments will be in `deployments/<chainId>-fork`
- make sure to not commit `broadcast/`
- if trying to deploy new contract either use the default deployer functions or generate them with
  `$./forge-deploy gen-deployer`
