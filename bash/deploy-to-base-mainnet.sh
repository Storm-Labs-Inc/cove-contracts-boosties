#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='8453' forge script script/DeployBaseMasterRegistries.s.sol --rpc-url $BASE_RPC_URL --sender $DEPLOYER_ADDRESS --account deployer --broadcast --verify -vvv &&
    ./forge-deploy sync &&
    DEPLOYMENT_CONTEXT='8453' forge script script/DeployBaseMasterRegistries.s.sol --rpc-url $BASE_RPC_URL -s "verifyPostDeploymentState()" -vvv
