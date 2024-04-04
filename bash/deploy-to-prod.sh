#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='1' forge script script/Deployments.s.sol --rpc-url $MAINNET_RPC_URL --sender $DEPLOYER_ADDRESS --account deployer --broadcast --verify -vvv && ./forge-deploy sync;
DEPLOYMENT_CONTEXT='1' forge script script/Deployments.s.sol --rpc-url $MAINNET_RPC_URL -s "verifyPostDeploymentState()" -vvv;