# cove-contracts-boosties

![cove](./assets/cove.png)

<div align="center">

[![codecov](https://codecov.io/gh/Storm-Labs-Inc/cove-contracts-boosties/branch/master/graph/badge.svg?token=TT68C116IT)](https://codecov.io/gh/Storm-Labs-Inc/cove-contracts-boosties)
[![CI](https://github.com/Storm-Labs-Inc/cove-contracts-boosties/actions/workflows/ci.yml/badge.svg)](https://github.com/Storm-Labs-Inc/cove-contracts-boosties/actions/workflows/ci.yml)
[![Discord](https://img.shields.io/discord/1162443184681533470?logo=discord&label=discord)](https://discord.gg/xdhvEFVsE9)
[![X (formerly Twitter) Follow](https://img.shields.io/twitter/follow/cove_fi)](https://twitter.com/intent/user?screen_name=cove_fi)

</div>

This repository contains the core smart contracts for the Cove Protocol. It includes Boosties (a liquid locker and
staking platform for Yearn), a governance token, and auxiliary contracts.

The testing suite includes unit, integration, fork, and invariant tests.

For detailed documentation, visit the [GitBook](https://docs.cove.finance/).

> [!IMPORTANT]
> You acknowledge that there are potential uses of the [Licensed Work] that
> could be deemed illegal or noncompliant under U.S. law. You agree that you
> will not use the [Licensed Work] for any activities that are or may
> reasonably be expected to be deemed illegal or noncompliant under U.S. law.
> You also agree that you, and not [Storm Labs], are responsible for any
> illegal or noncompliant uses of the [Licensed Work] that you facilitate,
> enable, engage in, support, promote, or are otherwise involved with.

## Prerequisites

Ensure you have the following installed:

- [Node.js](https://nodejs.org/) (v18.16.1)
- [Python](https://www.python.org/) (v3.9.17)
- [Rust](https://www.rust-lang.org/) (v1.75.0)

## Installation

Install [rust using rustup](https://rustup.rs/):

```sh
rustup update
```

Setup [pyenv](https://github.com/pyenv/pyenv?tab=readme-ov-file#installation) and install the python dependencies:

```sh
pyenv install 3.9.17
pyenv virtualenv 3.9.17 cove-contracts-boosties
pyenv local cove-contracts-boosties
pip install -r requirements.txt
```

Install the forge libraries as submodules:

```sh
forge install
```

Install node and build dependencies:

```sh
pnpm install
```

## Usage

Build forge-deploy if not already built:

```sh
pnpm forge-deploy:build
```

Build the contracts:

```sh
pnpm build
```

Run the tests:

```sh
pnpm test
```

### Run invariant tests (echidna)

[Install echidna](https://github.com/crytic/echidna?tab=readme-ov-file#installation) and run the test for each Echidna
test contract:

> Echidna may fail if the contracts are not built cleanly. If you encounter issues, try running
> `pnpm clean && pnpm build` before running the tests.

```sh
pnpm invariant-test ERC20RewardsGauge_EchidnaTest
```

### Run slither static analysis

[Install slither](https://github.com/crytic/slither?tab=readme-ov-file#how-to-install) and run the tool:

```sh
pnpm slither
```

To run the [upgradeability checks](https://github.com/crytic/slither/wiki/Upgradeability-Checks) with
`slither-check-upgradeability`:

```sh
pnpm slither-upgradeability
```

### Run semgrep static analysis

[Install semgrep](https://github.com/semgrep/semgrep?tab=readme-ov-file#option-2-getting-started-from-the-cli) and run
the tool:

```sh
pnpm semgrep
```

## Deploying contracts to a live network

### Local mainnet fork

Fork mainnet on the local network using anvil with the provided script:

```sh
pnpm fork:mainnet
```

Keep this terminal session going to keep the fork network alive.

Then in another terminal session, deploy the contracts to the local network:

```sh
pnpm deploy:local
```

- Deployments will be in `deployments/<chainId>-fork`.
- Make sure to not commit `broadcast/`.
- If trying to deploy new contract either use the default deployer functions or generate them
  with`$./forge-deploy gen-deployer`.

### Mainnet

First ensure the `.env` file is set up with the correct addresses for the mainnet deployment.

Add the deployer account to the `cast` wallet management:

```sh
cast wallet import deployer --interactive
```

This will prompt you to enter the private key and the password for the deployer account. Then deploy the contracts to
the mainnet:

```sh
pnpm deploy:prod
```

- Deployments will be in `deployments/<chainId>`.

Once the script finishes running, commit the new deployments to the repository.

## Contract Architecture

### Boosties

![boosties](./assets/boosties.png)

## Audits

Smart contract audits of the Cove Protocol are available [here](https://github.com/Storm-Labs-Inc/cove-audits).
