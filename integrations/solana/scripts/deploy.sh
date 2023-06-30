#!/bin/bash
# comment: generator of vanish address off-chain
### one time computation
### long time vanish
# solana-keygen grind --starts-with autono1as:1
### quick vanish
# solana-keygen grind --starts-with au:1


# networks lists: https://docs.solana.com/ru/clusters
# NETWORK=localhost
NETWORK=https://api.devnet.solana.com
# NETWORK=https://api.testnet.solana.com
# progmramId
# result of generation
PPKEYFILE=storage-deploy/auyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE.json
PD=auyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE

## Don't save auyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE.json in public github!
# Wrote keypair to auyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE.json
# mkdir -p storage-deploy
# mv auyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE.json storage-deploy/ 
if [ ! -d storage-deploy ]; then
	mkdir storage-deploy
        mv ${PD}.json storage-deploy
fi

if [ ! -f ${PPKEYFILE} ]; then
	echo "missing ${PPKEYFILE}"
	exit 1
fi

# compile
# progmramId = dauyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE in ServiceRegistrySolana.sol
solang compile contracts/ServiceRegistrySolana.sol --release -o storage-deploy/ --target solana -v

if [ ! -f storage-deploy/ServiceRegistrySolana.so ]; then
        echo "missing storage-deploy/ServiceRegistrySolana.so"
        exit 1
fi

# deployer address
# for new: solana-keygen new
# https://docs.solana.com/ru/wallet-guide/hardware-wallets/ledger
WALLET="/home/andrey/.config/solana/id.json"
WALLETK=$(solana address -k /home/andrey/.config/solana/id.json)
# or for ledger
# bash linux key=index
#WALLET="usb://ledger?key=0"
# zsh mac os key=index
#WALLET="usb://ledger\?key=0"
# configure to deploy
# solana config set --keypair ${WALLET}
# Full patch!!!
# solana config set --keypair /home/andrey/.config/solana/id.json 
# solana-keygen pubkey usb://ledger?key=42
solana config set --url ${NETWORK}

# run validator if not running. only for localhost
if [[ "${NETWORK}" =~ .*"localhost".* ]]; then
	HTTP_CODE=$(curl -sL -w "%{http_code}\n" http://127.0.0.1:8899 -o /dev/null)
	echo $HTTP_CODE
	# Analyze HTTP return code
	if [ ${HTTP_CODE} -ne 405 ] ; then
		screen -d -m solana-test-validator --reset
		sleep 30
	fi
	# airdrop to deployer wallet
	solana airdrop 100
fi
# try airdrop from test/devnet
solana airdrop 1
solana balance ${WALLETK} -u ${NETWORK}

# https://solana.stackexchange.com/questions/4083/blockhash-expired-5-retries-remaining
# 
v1=$(solana --version)
v2=$(solana cluster-version)
if [[ "${v1}" =~ .*"${v2}".* ]]; then
	echo "solana version is OK"
else
	echo "solana version mismatch. deploy not possible. long life to this blockchain!"
	echo "details: https://solana.stackexchange.com/questions/4083/blockhash-expired-5-retries-remaining"
        # dirty fix: sh -c $(curl -sSfL https://release.solana.com/v1.14.19/install)
	exit 1
fi

# deploy
# NOTES: you must (!) have enough test SOL to deploy
# OR Error: Account xxx has insufficient funds for spend (5.90205912 SOL) + fee (0.00421 SOL)
solana program deploy --url ${NETWORK} -v --program-id ${PPKEYFILE} storage-deploy/ServiceRegistrySolana.so
solana balance ${PD} -u ${NETWORK}
solana program show ${PD}
# unused parse
# BPD=$(solana program show auyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE | grep Balance | cut -d' ' -f2 )
# ProgramData=$(solana program show auyg6wcFyEotWhgwBm5bShJW48JBQBNezSnP1ZCALUE | grep ProgramData | cut -d' ' -f3 )
solana rent 20000
### if ${rent} > ${BPD}
#solana transfer ${ProgramData} ${rent} --allow-unfunded-recipient

# shutdown solana-test-validator (eat hdd space) - only for localnet
#screen -ls | grep Detached | cut -d. -f1 | awk '{print $1}' | xargs kill
