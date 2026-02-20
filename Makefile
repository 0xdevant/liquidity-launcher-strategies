include .env

.PHONY: all test clean

install:
	forge install

test:
	forge test --isolate --show-progress

coverage:
	forge coverage --ir-minimum --report lcov

verify:
	@forge verify-contract $(CONTRACT_ADDRESS) $(CONTRACT_NAME) --show-standard-json-input > $(CONTRACT_NAME)_standard_json_input.json