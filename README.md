Baby SIMD is a plain ERC-20 named `Baby SIMD`, symbol `BSIMD`, with 18 decimals.
`BSIMDToken` mints exactly 1,000,000,000 tokens (`1000000000000000000000000000`
minor units) once to `msg.sender` in its argument-free constructor. Deploy through
the launch factory so the factory receives the entire supply. There is no owner,
admin, mint entry point, burn, proxy, upgrade, tax, fee, transfer cap or blacklist.
All token parameters are constants. Balances and user-approved allowances are the
only mutable state. The token makes no external calls.

The project has no package dependencies. With Foundry and Solidity 0.8.26 installed,
run `forge build`, `forge test` and `forge fmt --check` from this directory. The
configuration pins Solidity 0.8.26, Cancun, optimizer with 200 runs, and
`bytecode_hash = "none"`. No FFI, filesystem permissions, RPC configuration,
environment variables or compiler binaries are needed by the tests.

The launch configuration in `launch.json` is:

- Kind: `custom_token`; token contract: `BSIMDToken` in `src/BSIMDToken.sol`;
  constructor arguments: `[]`; application contracts: `[]`.
- Target chain: Ethereum mainnet, chain ID 1. Chain selection is an operational
  responsibility; the manifest schema does not accept a root `chainId` key.
- Uniswap v4 PoolManager: `0x000000000004444c5dc75cB358380D2e3dE08A90`.
- Paired currency: IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`.
- Pool fee: 3000 (0.3%); tick spacing: 60.
- Provenance opening sqrtPriceX96: `125270724187523965593206900`, assuming BSIMD
  is currency0, representing paired-currency minor units per BSIMD minor unit.
- Economics: `poolBps = 9000`, `initialMarketCapWei = "2500000000000000000000"`
  (2500 IMD in paired-currency minor units),
  `remainderTo = 0x000000000000000000000000000000000000dead`, explicitly supplied
  by the brief.

The launch factory performs distribution after deployment: it transfers the full
10% swarm allocation to its Merkle distributor, seeds the single-sided v4 pool
using up to 90% of the whole supply, and transfers any remaining units to
`remainderTo`. At these economics the nominal allocation is 100,000,000 BSIMD for
the swarm and 900,000,000 BSIMD for the pool; liquidity rounding may leave a
remainder. Neither the token nor any delivered application contract distributes
the swarm allocation. The factory and distributor are supplied by the launch
system and are not part of this project.

The deployer must derive the actual opening price from the market cap and supply
using the deployed token address order, rather than blindly using the provenance
price when IMD sorts as currency0. The deployer also chooses the valid liquidity
range, handles PoolManager unlock/settlement, and forwards rounding remainders.
The chain and protocol addresses above are task inputs. The token does not depend
on their code or special-case their balances: standard transfers work for the
factory, distributor, PoolManager and ordinary holders alike.

`transfer`, `approve` and `transferFrom` return true on success. Zero-value
transfers and self-transfers are supported; transfers from/to the zero address
and approvals to the zero address revert. Finite allowances are consumed;
`type(uint256).max` allowances remain unchanged. Failed transfers revert all
state changes, including allowance consumption. `transferFrom` requires allowance
even when called by the deployer or the holder. Approval replaces an existing
allowance and emits `Approval`; users should revoke an old allowance before
changing it when concurrent spending is a concern. Allowance spending emits
`Transfer`, without an additional `Approval` event.

Tests cover constructor allocation and its event, exact transfer delivery, full
supply and zero/self transfers, allowance overwrite/revocation/exhaustion/infinite
approval, failure rollback, zero addresses, absence of privileged functions and
forbidden runtime opcodes. Three fuzz tests run 1000 cases each, including 64-action
sequences asserting balance conservation after every action. The local launch-flow
test checks transfers and claim/buy/sell token delivery at the specified manager
address; it does not execute a real v4 pool or verify a Merkle proof. The supplied
protected harness performs real local v4 seed and swap checks in the independent
launch verifier. Mainnet fork validation, deployed-address checks, explorer
verification and independent adversarial review remain the launch operator's
responsibility. No transaction is broadcast by this project and no wallet key is
required. There are no after-launch token settings or maintenance actions.
