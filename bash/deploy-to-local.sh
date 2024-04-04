#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='1-fork' forge script script/Deployments.s.sol --rpc-url http://localhost:8545 --sender $DEPLOYER_ADDRESS --unlocked --broadcast -vvv && ./forge-deploy sync;
DEPLOYMENT_CONTEXT='1-fork' forge script script/Deployments.s.sol --rpc-url http://localhost:8545 -s "verifyPostDeploymentState()" -vvv;