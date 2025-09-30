#!/bin/sh

# Define the handler function
function cleanup {
    echo "\nExiting..."
    echo "Cleaning up ./deployments/8453-fork/ folder..."
    # Your cleanup commands here
    rm -rf ./deployments/8453-fork/*
}
# Trap specific signals and run the cleanup function
trap cleanup EXIT
# Clean up before running anvil
echo "\nCleaning up ./deployments/8453-fork/ folder..."
rm -rf ./deployments/8453-fork/*
# Run anvil
source .env
anvil --auto-impersonate --fork-url $BASE_RPC_URL --fork-block-number 36238140 --steps-tracing
