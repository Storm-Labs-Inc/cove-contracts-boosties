#!/bin/sh

# Define the handler function
function cleanup {
    echo "\nExiting..."
    echo "Cleaning up ./deployments/1-fork/ folder..."
    # Your cleanup commands here
    rm -rf ./deployments/1-fork/*
}
# Trap specific signals and run the cleanup function
trap cleanup EXIT
# Clean up before running anvil
echo "\nCleaning up ./deployments/1-fork/ folder..."
rm -rf ./deployments/1-fork/*
# Run anvil
source .env
anvil --auto-impersonate --fork-url $MAINNET_RPC_URL --fork-block-number 19578210 --steps-tracing