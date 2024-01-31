#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='1-fork' forge script script/Deployments.s.sol --rpc-url http://localhost:8545 --broadcast -v && ./forge-deploy sync;
