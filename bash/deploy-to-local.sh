#!/bin/sh

source .env
DEPLOYMENT_CONTEXT='1-fork' forge script script/Deployments.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v && ./forge-deploy sync;
