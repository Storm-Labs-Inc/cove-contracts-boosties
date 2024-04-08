# Simulating Gnosis Safe transactions and exporting them to JSON

## Run the script against a forked network

```bash
forge script script/ops_multisig/OpsMultisig_2024_04_07.sol --fork-url $MAINNET_RPC_URL -vvvv
```

If the script is successful, it will output the path to the broadcast json file in `broadcast/` directory.

## Convert the broadcast json to Gnosis Trnsaction Builder JSON format

```bash
jq '{chainId: (.chain | tostring), meta: {}, transactions: [.transactions[] | {to: .transaction.to, value: (try (.transaction.value | tonumber | tostring) catch "0"), data: .transaction.data}]}' broadcast/OpsMultisig_2024_04_07.sol/1/dry-run/run-latest.json > script/ops_multisig/OpsMultisig_2024_04_07.json
```

## Import the outputted JSON to Gnosis Safe Transaction Builder Plugin
