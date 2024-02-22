#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='1' forge script script/Deployments.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify -vvv && ./forge-deploy sync;
