# smart-contracts-core

[![codecov](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core/branch/master/graph/badge.svg?token=TT68C116IT)](https://codecov.io/gh/Storm-Labs-Inc/smart-contracts-core)
[![CI](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Storm-Labs-Inc/smart-contracts-core/actions/workflows/ci.yml)
[![Discord](https://img.shields.io/discord/1162443184681533470?logo=discord&label=discord&labelColor=070909&color=E9FEA2)](https://discord.gg/xdhvEFVsE9)
[![X (formerly Twitter) Follow](https://img.shields.io/twitter/follow/cove_fi)](https://twitter.com/intent/user?screen_name=cove_fi)

![cove](https://github.com/Storm-Labs-Inc/smart-contracts-core/assets/972382/a572543c-9797-4a2c-a394-18050ca25e72)

This repository contains the core smart contracts for the Cove Protocol. This currently includes a liquid locker and
staking platform for Yearn, governance token, as well as auxiliary contracts.

For additional documentation, please refer to the [GitBook](https://docs.cove.finance/).

## Installation

Tested with node 18.16.1, python 3.9.17, and rustc 1.75.0.

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

## Usage

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
pnpm invariant-test
```

## Deploying contracts to a live network

### Local mainnet fork

```sh
# Fork mainnet on the local network using anvil with the provided script
pnpm fork:mainnet
```

Keep this terminal session going to keep the fork network alive.

Then in another terminal session:

```sh
# Deploy the contracts to the local network
pnpm deploy:local
```

- Deployments will be in `deployments/<chainId>-fork`.
- Make sure to not commit `broadcast/`.
- If trying to deploy new contract either use the default deployer functions or generate them with
  `$./forge-deploy gen-deployer`.
