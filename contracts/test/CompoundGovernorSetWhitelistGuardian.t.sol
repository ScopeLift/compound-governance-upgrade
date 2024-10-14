// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {ProposalTest} from "contracts/test/helpers/ProposalTest.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";

contract CompoundGovernorSetWhitelistGuardianTest is ProposalTest {
    function testFuzz_SetsWhitelistGuardianAsTimelock(address _whitelistGuardian) public {
        vm.prank(TIMELOCK_ADDRESS); // TODO: This is not sufficient, you must pass a proposal in order to
            // get past `_checkGovernance`.
        governor.setWhitelistGuardian(_whitelistGuardian);
        assertEq(governor.whitelistGuardian(), _whitelistGuardian);
    }

    function testFuzz_EmitsEventWhenAWhitelistGuardianIsSet(address _whitelistGuardian) public {
        vm.expectEmit();
        emit CompoundGovernor.WhitelistGuardianSet(governor.whitelistGuardian(), _whitelistGuardian);
        vm.prank(TIMELOCK_ADDRESS);
        governor.setWhitelistGuardian(_whitelistGuardian);
    }

    function testFuzz_RevertIf_CallerIsNotTimelock(address _whitelistGuardian, address _caller) public {
        vm.assume(_caller != TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSelector(CompoundGovernor.Unauthorized.selector, bytes32("Not timelock"), _caller)
        );
        vm.prank(_caller);
        governor.setWhitelistGuardian(_whitelistGuardian);
    }
}
