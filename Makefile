# Setups

install		:;	npm i && git submodule update --init --recursive

# Linting and Formatting

lint		:;	solhint ./src/* # Solhint from Protofire: https://github.com/protofire/solhint

# Testing

watch		:;	[ contract ] && forge test --verbosity -vvvvv --match-contract ${contract} --watch || forge test --watch --fork-url ${rpc}
tests		:;	[ test ] && forge test --match-test ${test} || forge test

# Coverage https://github.com/linux-test-project/lcov (brew install lcov)

cover		:;	forge coverage --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage
show		:;	npx http-server ./coverage

# Utilities

clean		:;	forge clean

# Build and Deploy