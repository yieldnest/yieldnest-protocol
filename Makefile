# Setups

install		:;	npm i && git submodule update --init --recursive

# Linting and Formatting

lint		:;	solhint ./src/* # Solhint from Protofire: https://github.com/protofire/solhint

# Coverage https://github.com/linux-test-project/lcov (brew install lcov)

cover		:;	forge coverage --rpc-url ${rpc} --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage 
show		:;	npx http-server ./coverage

# Utilities

clean		:;	forge clean

# Testing

ci-test 	:;	forge test --rpc-url ${rpc} --summary --detailed --gas-report

# Build and Deploy