// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPayload} from "l1-contracts/governance/interfaces/IPayload.sol";
import {
    IGovernance,
    Configuration
} from "l1-contracts/governance/interfaces/IGovernance.sol";
import {Timestamp} from "l1-contracts/shared/libraries/TimeMath.sol";
import {IRegistry} from "l1-contracts/governance/interfaces/IRegistry.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {AZIP1And3Payload} from "../src/AZIP1And3Payload.sol";

/// @notice Fork-simulate the AZIP-1/3 payload against live L1 state.
///
/// Usage:
///   forge script script/AZIP1And3Sim.s.sol --rpc-url $L1_RPC_URL -vvv
///
/// Optionally pass PAYLOAD=0x... to simulate an already-deployed payload
/// instead of deploying a fresh copy in-memory.
contract AZIP1And3Sim is Script {
    address internal constant GOVERNANCE =
        0x1102471Eb3378FEE427121c9EfcEa452E4B6B75e;
    address internal constant V4_ROLLUP =
        0xAe2001f7e21d5EcABf6234E9FDd1E76F50F74962;
    address internal constant REGISTRY =
        0x35b22e09Ee0390539439E24f06Da43D83f90e298;

    function run() public {
        IPayload payload;
        try vm.envAddress("PAYLOAD") returns (address p) {
            payload = IPayload(p);
            console.log("Using deployed payload:", p);
        } catch {
            payload = IPayload(address(new AZIP1And3Payload()));
            console.log("Deployed ephemeral payload:", address(payload));
        }
        // Precondition: the Registry's canonical rollup must be the v4
        // rollup we're about to renounce ownership of. If this drifts, the
        // payload is targeting the wrong contract.
        address canonical = address(IRegistry(REGISTRY).getCanonicalRollup());
        console.log("Registry canonical rollup:", canonical);
        require(
            canonical == V4_ROLLUP,
            "Registry.getCanonicalRollup() != hardcoded V4_ROLLUP"
        );

        // Snapshot pre-state.
        Configuration memory pre = IGovernance(GOVERNANCE).getConfiguration();
        address preOwner = Ownable(V4_ROLLUP).owner();

        console.log("\n=== Pre-state ===");
        _logConfig(pre);
        console.log("v4 rollup owner:", preOwner);

        // Execute actions as Governance would.
        IPayload.Action[] memory actions = payload.getActions();
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("\n=== Action", i, "===");
            console.log("Target:", actions[i].target);

            vm.startStateDiffRecording();
            vm.prank(GOVERNANCE);
            (bool ok, bytes memory ret) = actions[i].target.call(
                actions[i].data
            );
            if (!ok) {
                console.logBytes(ret);
                revert("Action call failed");
            }
            _logWrites(vm.stopAndReturnStateDiff());
        }

        // Snapshot post-state.
        Configuration memory post = IGovernance(GOVERNANCE).getConfiguration();
        address postOwner = Ownable(V4_ROLLUP).owner();

        console.log("\n=== Post-state ===");
        _logConfig(post);
        console.log("v4 rollup owner:", postOwner);
        require(postOwner == address(0), "rollup ownership not renounced");

        console.log("\n=== Derived effects ===");
        uint256 withdrawalDelay = Timestamp.unwrap(post.votingDelay) /
            5 +
            Timestamp.unwrap(post.votingDuration) +
            Timestamp.unwrap(post.executionDelay);
        console.log("new withdrawalDelay (seconds):", withdrawalDelay);

        // Sanity checks matching the AZIP specs.
        require(
            Timestamp.unwrap(post.executionDelay) == 2 days,
            "executionDelay != 2 days"
        );
        require(
            Timestamp.unwrap(post.votingDelay) ==
                Timestamp.unwrap(pre.votingDelay),
            "votingDelay mutated"
        );
        require(
            Timestamp.unwrap(post.votingDuration) ==
                Timestamp.unwrap(pre.votingDuration),
            "votingDuration mutated"
        );
        require(
            Timestamp.unwrap(post.gracePeriod) ==
                Timestamp.unwrap(pre.gracePeriod),
            "gracePeriod mutated"
        );
        require(post.quorum == pre.quorum, "quorum mutated");
        require(
            post.requiredYeaMargin == pre.requiredYeaMargin,
            "margin mutated"
        );
        require(post.minimumVotes == pre.minimumVotes, "minVotes mutated");
        require(postOwner == address(0), "ownership not renounced");

        console.log("\nAll post-conditions hold.");
    }

    function _logConfig(Configuration memory c) internal pure {
        console.log("  votingDelay:     ", Timestamp.unwrap(c.votingDelay));
        console.log("  votingDuration:  ", Timestamp.unwrap(c.votingDuration));
        console.log("  executionDelay:  ", Timestamp.unwrap(c.executionDelay));
        console.log("  gracePeriod:     ", Timestamp.unwrap(c.gracePeriod));
        console.log("  quorum:          ", c.quorum);
        console.log("  requiredYeaMargin:", c.requiredYeaMargin);
        console.log("  minimumVotes:    ", c.minimumVotes);
        console.log(
            "  lockDelay:       ",
            Timestamp.unwrap(c.proposeConfig.lockDelay)
        );
        console.log("  lockAmount:      ", c.proposeConfig.lockAmount);
    }

    function _logWrites(Vm.AccountAccess[] memory accesses) internal pure {
        for (uint256 i = 0; i < accesses.length; i++) {
            uint256 writes = 0;
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; j++) {
                if (
                    accesses[i].storageAccesses[j].isWrite &&
                    !accesses[i].storageAccesses[j].reverted
                ) {
                    writes++;
                }
            }
            if (writes > 0) {
                console.log(
                    "  Contract:",
                    accesses[i].account,
                    "writes:",
                    writes
                );
            }
        }
    }
}
