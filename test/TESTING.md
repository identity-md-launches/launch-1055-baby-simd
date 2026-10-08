# Baby SIMD test coverage

Run `forge build` and `forge test` from the repository root. The additions use
the existing compiler/configuration and require no packages, RPC, environment
variables, FFI, or files under `test/scratch/`.

The original `BSIMDToken.t.sol` remains unchanged. It covers deployment, metadata,
full launch allocation, basic ERC-20 operations, failure paths, events, absence
of common privileged entry points, forbidden runtime opcodes, and fuzzed transfers.

`BSIMDToken.adversarial.t.sol` adds arbitrary recipients, isolation of approvals
between owners and spenders, finite-allowance rollback after overdraw (including
self-transfers), retries after failure, repeated infinite-allowance spending and
revocation, the max-1 finite-allowance boundary, zero-value delegated transfers,
self-approval, and rejection of zero recipients with infinite approval. Each of
its four fuzz properties has 1,000 runs configured inline.

`BSIMDToken.invariant.t.sol` runs 256 sequences of 64 actions on chain ID 1. Only
the handler's seven explicit action selectors are targeted. Its independent
ledger starts with the constructor's entire 1e27 supply; it does not mint test
balances or derive expected balances from the implementation. After each action,
the invariant compares every tracked balance and owner/spender allowance, checks
zero-address state, and checks both the sum of balances and fixed total supply.
Rejected calls must preserve the ledger. Unexpected handler reverts fail the
campaign. After every sequence, each holder must be able to transfer its entire
balance back to the deployer.

All token destinations in the invariant are in its closed actor set, which
includes the specified PoolManager address. Pranking that address checks token
transfer compatibility only. This repository's suite does not execute a Uniswap
v4 pool, validate Merkle proofs, or check deployed mainnet code. The provided
protected launch harness covers actual local v4 seeding and swaps in the launch
verifier; it is not compiled as part of this standalone suite. A mainnet fork
exercise of the real factory, distributor, PoolManager and paired currency is
still owed by the launch operator. BSIMDToken itself makes no external calls.

Local result: `forge build` succeeded and all 29 tests passed with no skips,
including 16,384 invariant-handler calls. No reproducible implementation defect
was identified; these tests do not establish correctness outside their scope.
