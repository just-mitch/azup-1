# azup-1

Governance payload implementing two AZIPs for [AztecProtocol/governance#7](https://github.com/AztecProtocol/governance/pull/7):

- **AZIP-1** — reduce Governance `executionDelay` from 30 days to 2 days.
- **AZIP-3** — renounce ownership of the v4 rollup at `0xAe2001f7e21d5EcABf6234E9FDd1E76F50F74962`.

The payload is a single contract (`src/AZIP1And3Payload.sol`) whose `getActions()` returns:

1. `Governance.updateConfiguration(newConfig)` — reads the current on-chain `Configuration`, overrides only `executionDelay` to `2 days`, and preserves every other field.
2. `Rollup.renounceOwnership()` — transfers ownership of the v4 rollup to `address(0)`.

## Addresses

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Governance | `0x1102471Eb3378FEE427121c9EfcEa452E4B6B75e` |
| v4 Rollup  | `0xAe2001f7e21d5EcABf6234E9FDd1E76F50F74962` |

## Setup

```bash
git submodule update --init --recursive
forge build
```

Submodules are pinned to:

- `lib/l1-contracts` → [`v4.1.3`](https://github.com/AztecProtocol/l1-contracts/releases/tag/v4.1.3) (matches [aztec-packages v4.1.3](https://github.com/AztecProtocol/aztec-packages/releases/tag/v4.1.3))
- `lib/openzeppelin-contracts` → `v5.5.0`
- `lib/forge-std` → `v1.15.0`

## Test

```bash
forge test -vvv
```

Unit tests mock `Governance.getConfiguration()` via `vm.etch` and verify:

- Two actions are returned with the correct targets.
- Action 0 encodes `updateConfiguration` with `executionDelay = 2 days` and every other field copied from the pre-image config.
- Action 1 encodes `renounceOwnership()` against the v4 rollup.
- `getURI()` returns the PR link.

## Simulate on a mainnet fork

The simulation script (`script/AZIP1And3Sim.s.sol`) forks live L1 state, pranks Governance, executes each action in order, and asserts the post-state matches the AZIP specs.

```bash
# ephemeral: deploys the payload in-memory inside the fork
forge script script/AZIP1And3Sim.s.sol --rpc-url $L1_RPC_URL -vvv

# against an already-deployed payload
PAYLOAD=0xYourDeployedPayload \
  forge script script/AZIP1And3Sim.s.sol --rpc-url $L1_RPC_URL -vvv
```

The script prints:

- Pre-state: full `Configuration` and v4 rollup `owner()`.
- Per-action: target address and storage-write count.
- Post-state: full `Configuration` and v4 rollup `owner()` (should be `0x0`).
- Derived effects: new `withdrawalDelay = votingDelay/5 + votingDuration + executionDelay` (expected ~9.6 days).

It `require`s:

- `executionDelay == 2 days`
- `votingDelay`, `votingDuration`, `gracePeriod`, `quorum`, `requiredYeaMargin`, `minimumVotes`, and `proposeConfig` unchanged from pre-state
- `v4Rollup.owner() == address(0)`

### Note on `updateConfiguration` authorization

`Governance.updateConfiguration` may be gated to `onlySelf` (i.e. only callable by Governance as part of `execute`). If the simple `vm.prank(GOVERNANCE)` path reverts on a real fork, switch the sim to drive the full propose → vote → execute lifecycle against the forked Governance contract rather than calling `updateConfiguration` directly.

## Deploy

```bash
forge create src/AZIP1And3Payload.sol:AZIP1And3Payload \
  --rpc-url $L1_RPC_URL \
  --private-key $DEPLOYER_PK \
  --broadcast \
  --verify --verifier etherscan \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Then propose the deployed address through the Aztec governance proposer flow.
