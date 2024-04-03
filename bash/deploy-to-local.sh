#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='1-fork' forge script script/Deployments.s.sol --rpc-url http://localhost:8545 --account deployer --sender 0x8842fe65a7db9bb5de6d50e49af19496da09f9b5 --broadcast -vvv && ./forge-deploy sync;
