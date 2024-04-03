#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='1' forge script script/Deployments.s.sol --rpc-url $MAINNET_RPC_URL --account deployer --sender 0x8842fe65a7db9bb5de6d50e49af19496da09f9b5 --broadcast --verify -vvv && ./forge-deploy sync;
