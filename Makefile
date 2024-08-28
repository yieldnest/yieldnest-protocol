# Setups

install		:;	git submodule update --init --recursive

# Linting and Formatting

lint		:;	solhint ./src/* ./scripts/forge/* # Solhint from Protofire: https://github.com/protofire/solhint

# Coverage https://github.com/linux-test-project/lcov (brew install lcov)

cover		:;	forge coverage --rpc-url ${rpc} --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage 
show		:;	npx http-server ./coverage

# Utilities

clean		:;	forge clean
 
# Testing

ci-test 	:;	forge test --rpc-url ${rpc} --summary --detailed --gas-report

# Build and Deploy

build 	:;	forge build

deploy-protocol 	:;	forge script script/DeployYieldNest.s.sol:DeployYieldNest --rpc-url ${rpc} --broadcast --etherscan-api-key ${key} --verify

# Verify

verify-roles 		:;	forge script script/Verify.s.sol --rpc-url ${rpc}

# to set up cast wallet run:  cast wallet import yieldnestDeployerKey --interactive
# then import the private key with which you wish to deploy, create a password and add the public address of that key to the .env under DEPLOYER_ADDRESS.

# make ynEigen path=script/ynEigen/input/lsd-mainnet.json rpc=your-rpc-here deployer=0xYourPublicAddressThatCorrespondsToYourSavedPrivateKeyInyieldnestDeployerKey api=etherscanApiKey
deployerAccountName ?= yieldnestDeployerKey
ynEigen :; forge script script/ynEigen/YnEigenScript.s.sol:YnEigenScript --rpc-url ${rpc}  --sig "run(string)" ${path} --account ${deployerAccountName} --sender ${deployer} --broadcast --etherscan-api-key ${api} --verify

# make ynEigen-verify path=script/ynEigen/input/lsd-mainnet.json rpc=your-rpc-here
ynEigen-verify :; forge script script/ynEigen/YnEigenScript.s.sol:YnEigenScript --rpc-url ${rpc}  --sig "verify(string)" ${path} --broadcast

# alternative bash script with less inputs
# make ynEigen-bash path=script/ynEigen/input/lsd-mainnet.json
ynEigen-bash :; ./script/ynEigen/bash/deployYnEigen.sh ${path}
