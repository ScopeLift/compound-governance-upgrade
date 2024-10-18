// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {ProposalTest} from "contracts/test/helpers/ProposalTest.sol";

contract CompoundGovernorEnumIdsTest is ProposalTest {
    function _buildBasicProposal(uint256 _newThreshold) private view returns (Proposal memory _proposal) {
        address[] memory _targets = new address[](1);
        _targets[0] = address(governor);

        uint256[] memory _values = new uint256[](1);
        _values[0] = 0;

        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = _buildProposalData("setProposalThreshold(uint256)", abi.encode(_newThreshold));
        _proposal = Proposal(_targets, _values, _calldatas, "Set New Proposal Threshold");
    }

    function testFuzz_ProposalIdsAreSequential(uint256 _newValue) public {
        _newValue = bound(_newValue, INITIAL_PROPOSAL_THRESHOLD, INITIAL_PROPOSAL_THRESHOLD + 10);
        Proposal memory _proposal1 = _buildBasicProposal(_newValue);
        vm.prank(delegatee);
        uint256 _proposalId1 =
            governor.propose(_proposal1.targets, _proposal1.values, _proposal1.calldatas, _proposal1.description);

        Proposal memory _proposal2 = _buildBasicProposal(_newValue + 1);
        vm.prank(delegatee);
        uint256 _proposalId2 =
            governor.propose(_proposal2.targets, _proposal2.values, _proposal2.calldatas, _proposal2.description);
        assertEq(_proposalId2, _proposalId1 + 1);
    }
}
