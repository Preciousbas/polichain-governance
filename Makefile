CHAIN      := sepolia
ALCHEMY_RPC := https://eth-sepolia.g.alchemy.com/v2/$(ALCHEMY_API_KEY)
TATUM_RPC   := https://ethereum-sepolia.gateway.tatum.io
SIGNATURE_ID ?= $(SIGNATURE_ID)  
SENDER_ADDR ?= $(SENDER_ADDR)
TREASURY_ADDR ?= $(TREASURY_ADDR)
MULTISIG_ADDR ?= $(MULTISIG_ADDR)   
PRIVATE_KEY ?= $(PRIVATE_KEY)  

SCRIPT_PATH := script/DeployGovernor.s.sol:GovernanceDeployment

# -----------------------------
# Targets
# -----------------------------

## Clean artifacts and cache
clean:
	forge clean

## Compile contracts
build:
	forge build

## Run tests
test:
	forge test -vvv

## Deploy to Sepolia using Alchemy RPC + Tatum KMS
deploy-testnet:
	@echo "Deploying governance contracts to $(CHAIN) with Alchemy RPC..."
	@TREASURY=$(TREASURY_ADDR) \
	 MULTISIG=$(MULTISIG_ADDR) \
	forge script $(SCRIPT_PATH) \
		--rpc-url $(ALCHEMY_RPC) \
		--broadcast \
		--private-key $(PRIVATE_KEY) \
		-vvv

dry-run:
	@TREASURY=$(TREASURY_ADDR) \
 	MULTISIG=$(MULTISIG_ADDR) \
	forge script $(SCRIPT_PATH) \
		--rpc-url $(ALCHEMY_RPC) \
		--sender $(SENDER_ADDR) \
		--json > deployment_transactions.json

debug:
	@echo "JSON content:"
	@cat deployment_transactions.json | jq '.'
	@echo "First transaction:"
	@cat deployment_transactions.json | jq '.transactions[0]'

deploy:
	curl -X POST "https://api.tatum.io/v3/ethereum/transaction" \
		-H "x-api-key: $(TATUM_API_KEY)" \
		-H "Content-Type: application/json" \
		-d '{
			"chain": "ETH",
			"signatureId": "'$(SIGNATURE_ID)'",
			"to": "0xContractDeploymentAddressIfAny",
			"gasLimit": "5000000",
			"nonce": "0",
			"tx": "'"$(jq -c .transactions[0] ./broadcast/DeployGovernor.s.sol/11155111/run-latest.json)"'"
		}'


## Verify deployment
verify-deployment:
	@echo "Verifying deployment against Alchemy RPC..."
	@if [ -f "./broadcast/DeployGovernor.s.sol/11155111/run-latest.json" ]; then \
		DEPLOYED_ADDR=$$(jq -r '.transactions[] | select(.contractName=="SimpleGovernor") | .contractAddress' \
			./broadcast/DeployGovernor.s.sol/11155111/run-latest.json); \
		echo "Governor deployed at: $$DEPLOYED_ADDR"; \
		cast call $$DEPLOYED_ADDR "owner()" --rpc-url $(ALCHEMY_RPC); \
	else \
		echo "No deployment artifacts found"; \
	fi

## Show last deployment artifacts
show-artifacts:
	@cat ./broadcast/DeployGovernor.s.sol/$(CHAIN)-*/run-latest.json | jq

## Start Tatum KMS Daemon for signing
kms-daemon:
	@echo "Starting Tatum KMS Daemon for ETH Sepolia..."