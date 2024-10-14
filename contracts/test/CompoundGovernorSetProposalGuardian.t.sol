// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {ProposalTest} from "contracts/test/helpers/ProposalTest.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";

contract CompoundGovernorIsWhitelistedTest is ProposalTest {
    function testFuzz_SetsProposalGuardianAsTimelock(CompoundGovernor.ProposalGuardian memory _proposalGuardian)
        public
    {
        vm.prank(TIMELOCK_ADDRESS);
        governor.setProposalGuardian(_proposalGuardian);
        (address _account, uint96 _expiration) = governor.proposalGuardian();
        assertEq(_account, _proposalGuardian.account);
        assertEq(_expiration, _proposalGuardian.expiration);
    }

    function testFuzz_EmitsEventWhenAProposalGuardianIsSetByTheTimelock(
        CompoundGovernor.ProposalGuardian memory _proposalGuardian
    ) public {
        (address _currentAccount, uint96 _currentExpiration) = governor.proposalGuardian();
        vm.expectEmit();
        emit CompoundGovernor.ProposalGuardianSet(
            _currentAccount, _currentExpiration, _proposalGuardian.account, _proposalGuardian.expiration
        );
        vm.prank(TIMELOCK_ADDRESS);
        governor.setProposalGuardian(_proposalGuardian);
    }

    function testFuzz_RevertIf_CallerIsNotTimelock(
        CompoundGovernor.ProposalGuardian memory _proposalGuardian,
        address _caller
    ) public {
        vm.assume(_caller != TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSelector(CompoundGovernor.Unauthorized.selector, bytes32("Not timelock"), _caller)
        );
        vm.prank(_caller);
        governor.setProposalGuardian(_proposalGuardian);
    }
}
