// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {ProposalTest} from "contracts/test/helpers/ProposalTest.sol";

contract CompoundGovernorSetQuorumTest is ProposalTest {
    function _submitPassAndExecuteProposalToSetNewQuorum(address _proposer, uint256 _amount) public {
        address[] memory _targets = new address[](1);
        _targets[0] = address(governor);

        uint256[] memory _values = new uint256[](1);
        _values[0] = 0;

        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = _buildProposalData("setQuorum(uint256)", abi.encode(_amount));

        ConstructedProposal memory _proposal = ConstructedProposal(_targets, _values, _calldatas, "Set New Quorum");
        _submitPassQueueAndExecuteProposal(_proposer, _proposal);
    }

    function _submitAndFailProposalToSetNewQuorum(address _proposer, uint256 _amount) public {
        address[] memory _targets = new address[](1);
        _targets[0] = address(governor);

        uint256[] memory _values = new uint256[](1);
        _values[0] = 0;

        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = _buildProposalData("setQuorum(uint256)", abi.encode(_amount));

        ConstructedProposal memory _proposal = ConstructedProposal(_targets, _values, _calldatas, "Set New Quorum");
        _submitAndFailProposal(_proposer, _proposal);
    }

    function testFuzz_SetQuorum(uint256 _newQuorum) public {
        _newQuorum = bound(_newQuorum, 1, 1000);
        _submitPassAndExecuteProposalToSetNewQuorum(delegatee, _newQuorum);
        assertEq(governor.quorum(block.timestamp), _newQuorum);
    }

    function testFuzz_FailSetQuorum(uint256 _newQuorum) public {
        vm.assume(_newQuorum != INITIAL_QUORUM);
        _newQuorum = bound(_newQuorum, 1, 1000);
        _submitAndFailProposalToSetNewQuorum(delegatee, _newQuorum);
        assertNotEq(governor.quorum(block.timestamp), _newQuorum);
    }
}
