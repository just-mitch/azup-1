// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {Test} from "forge-std/Test.sol";
import {AZIP1And3Payload} from "../src/AZIP1And3Payload.sol";
import {IPayload} from "l1-contracts/governance/interfaces/IPayload.sol";
import {
    IGovernance,
    Configuration,
    ProposeWithLockConfiguration
} from "l1-contracts/governance/interfaces/IGovernance.sol";
import {Timestamp} from "l1-contracts/shared/libraries/TimeMath.sol";
import {Ownable} from "@oz/access/Ownable.sol";

contract MockGovernance {
    Configuration internal config;

    function setConfiguration(Configuration memory _c) external {
        config = _c;
    }

    function getConfiguration() external view returns (Configuration memory) {
        return config;
    }
}

contract AZIP1And3PayloadTest is Test {
    AZIP1And3Payload internal payload;

    address internal constant GOVERNANCE =
        0x1102471Eb3378FEE427121c9EfcEa452E4B6B75e;
    address internal constant V4_ROLLUP =
        0xAe2001f7e21d5EcABf6234E9FDd1E76F50F74962;

    Configuration internal seedConfig;

    function setUp() public {
        seedConfig = Configuration({
            proposeConfig: ProposeWithLockConfiguration({
                lockDelay: Timestamp.wrap(1 days),
                lockAmount: 1e18
            }),
            votingDelay: Timestamp.wrap(3 days),
            votingDuration: Timestamp.wrap(7 days),
            executionDelay: Timestamp.wrap(30 days),
            gracePeriod: Timestamp.wrap(7 days),
            quorum: 1000e18,
            requiredYeaMargin: 4e17,
            minimumVotes: 500e18
        });

        MockGovernance impl = new MockGovernance();
        vm.etch(GOVERNANCE, address(impl).code);
        MockGovernance(GOVERNANCE).setConfiguration(seedConfig);

        payload = new AZIP1And3Payload();
    }

    function test_GetActions_Length() public view {
        assertEq(payload.getActions().length, 2);
    }

    function test_GetActions_UpdateConfiguration() public view {
        IPayload.Action[] memory actions = payload.getActions();
        assertEq(actions[0].target, GOVERNANCE);

        bytes memory data = actions[0].data;
        bytes4 sel;
        assembly {
            sel := mload(add(data, 32))
        }
        assertEq(sel, IGovernance.updateConfiguration.selector);

        bytes memory body = new bytes(data.length - 4);
        for (uint256 i = 0; i < body.length; i++) {
            body[i] = data[i + 4];
        }
        Configuration memory decoded = abi.decode(body, (Configuration));

        // AZIP-1: executionDelay reduced to 2 days, everything else preserved.
        assertEq(Timestamp.unwrap(decoded.executionDelay), 2 days);
        assertEq(
            Timestamp.unwrap(decoded.votingDelay),
            Timestamp.unwrap(seedConfig.votingDelay)
        );
        assertEq(
            Timestamp.unwrap(decoded.votingDuration),
            Timestamp.unwrap(seedConfig.votingDuration)
        );
        assertEq(
            Timestamp.unwrap(decoded.gracePeriod),
            Timestamp.unwrap(seedConfig.gracePeriod)
        );
        assertEq(decoded.quorum, seedConfig.quorum);
        assertEq(decoded.requiredYeaMargin, seedConfig.requiredYeaMargin);
        assertEq(decoded.minimumVotes, seedConfig.minimumVotes);
        assertEq(
            Timestamp.unwrap(decoded.proposeConfig.lockDelay),
            Timestamp.unwrap(seedConfig.proposeConfig.lockDelay)
        );
        assertEq(
            decoded.proposeConfig.lockAmount,
            seedConfig.proposeConfig.lockAmount
        );
    }

    function test_GetActions_RenounceV4Ownership() public view {
        IPayload.Action[] memory actions = payload.getActions();
        assertEq(actions[1].target, V4_ROLLUP);
        assertEq(
            actions[1].data,
            abi.encodeWithSelector(Ownable.renounceOwnership.selector)
        );
    }

    function test_GetURI() public view {
        assertEq(
            payload.getURI(),
            "https://github.com/AztecProtocol/governance/pull/7"
        );
    }
}
