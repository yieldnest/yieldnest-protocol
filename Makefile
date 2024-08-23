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

# make ynEigen path=script/ynEigenDeployer/input/input-template.json    
ynEigen :; ./script/ynEigenDeployer/bash/deployYnEigen.sh ${path}

    