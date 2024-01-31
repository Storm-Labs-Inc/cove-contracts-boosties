#!/bin/sh

# Define the handler function
cleanup() {
    echo "\nYou hit Ctrl+C. Cleaning up and exiting..."
    # Your cleanup commands here
    rm -rf ./deployments/1-fork/*
    exit 0 # Exit cleanly
}

# Trap SIGINT (Ctrl+C) and call the cleanup function
trap cleanup SIGINT

source .env
anvil --auto-impersonate --fork-url $MAINNET_RPC_URL --fork-block-number 19122720