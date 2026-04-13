// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {IPayload} from "l1-contracts/governance/interfaces/IPayload.sol";
import {IGovernance, Configuration} from "l1-contracts/governance/interfaces/IGovernance.sol";
import {Timestamp} from "l1-contracts/shared/libraries/TimeMath.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/// @notice Payload implementing AZIP-1 (reduce execution delay to 2 days) and
/// AZIP-3 (renounce ownership of the v4 rollup).
contract AZIP1And3Payload is IPayload {
    IGovernance public constant GOVERNANCE = IGovernance(0x1102471Eb3378FEE427121c9EfcEa452E4B6B75e);
    address public constant V4_ROLLUP = 0xAe2001f7e21d5EcABf6234E9FDd1E76F50F74962;

    uint256 public constant NEW_EXECUTION_DELAY = 2 days;

    function getActions() external view override(IPayload) returns (IPayload.Action[] memory) {
        IPayload.Action[] memory res = new IPayload.Action[](2);

        // AZIP-1: reduce executionDelay to 2 days while preserving every other
        // governance parameter at its current on-chain value.
        Configuration memory config = GOVERNANCE.getConfiguration();
        config.executionDelay = Timestamp.wrap(NEW_EXECUTION_DELAY);

        res[0] = Action({
            target: address(GOVERNANCE),
            data: abi.encodeWithSelector(IGovernance.updateConfiguration.selector, config)
        });

        // AZIP-3: renounce ownership of the v4 rollup, making it fully immutable.
        res[1] = Action({
            target: V4_ROLLUP,
            data: abi.encodeWithSelector(Ownable.renounceOwnership.selector)
        });

        return res;
    }

    function getURI() external pure override(IPayload) returns (string memory) {
        return "https://github.com/AztecProtocol/governance/pull/7";
    }
}
