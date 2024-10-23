// SPDX-License-Identifier: BSD-3-Clause

pragma solidity 0.8.26;

import {ProposalTest} from "contracts/test/helpers/ProposalTest.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";

contract CompoundGovernorCancelTest is ProposalTest {
    function _buildAnEmptyProposal() private pure returns (Proposal memory _proposal) {
        address[] memory _targets = new address[](1);
        uint256[] memory _values = new uint256[](1);
        bytes[] memory _calldatas = new bytes[](1);
        _proposal = Proposal(_targets, _values, _calldatas, "An Empty Proposal");
    }

    function _getProposalId(Proposal memory _proposal) private view returns (uint256) {
        return governor.hashProposal(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
    }

    function _removeDelegateeVotingWeight() private {
        vm.prank(COMPOUND_COMPTROLLER);
        token.delegate(COMPOUND_COMPTROLLER);
        vm.roll(block.number + 1);
    }

    function testFuzz_ProposerCanCancelItsOwnProposal(uint256 _randomIndex) public {
        _randomIndex = bound(_randomIndex, 0, _majorDelegates.length - 1);
        address _proposer = _majorDelegates[_randomIndex];
        Proposal memory _proposal = _buildAnEmptyProposal();
        uint256 _proposalId = _getProposalId(_proposal);
        _submitPassAndQueueProposal(_proposer, _proposal);

        vm.prank(_proposer);
        governor.cancel(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
        vm.assertEq(uint256(governor.state(_proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function testFuzz_ProposalGuardianCanCancelAnyProposal(uint256 _randomIndex) public {
        _randomIndex = bound(_randomIndex, 0, _majorDelegates.length - 1);
        address _proposer = _majorDelegates[_randomIndex];
        Proposal memory _proposal = _buildAnEmptyProposal();
        uint256 _proposalId = _getProposalId(_proposal);
        _submitPassAndQueueProposal(_proposer, _proposal);

        vm.prank(proposalGuardian.account);
        governor.cancel(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
        vm.assertEq(uint256(governor.state(_proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function testFuzz_AnyoneCanCancelAProposalBelowThreshold(address _caller) public {
        vm.assume(_caller != PROXY_ADMIN_ADDRESS);
        Proposal memory _proposal = _buildAnEmptyProposal();
        uint256 _proposalId = _getProposalId(_proposal);
        _submitPassAndQueueProposal(delegatee, _proposal);
        _removeDelegateeVotingWeight();

        vm.prank(_caller);
        governor.cancel(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
        vm.assertEq(uint256(governor.state(_proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function test_WhitelistGuardianCanCancelWhitelistedProposalBelowThreshold() public {
        Proposal memory _proposal = _buildAnEmptyProposal();
        uint256 _proposalId = _getProposalId(_proposal);
        vm.prank(whitelistGuardian);
        governor.setWhitelistAccountExpiration(delegatee, block.timestamp + 2_000_000);
        _submitPassAndQueueProposal(delegatee, _proposal);
        _removeDelegateeVotingWeight();

        vm.prank(whitelistGuardian);
        governor.cancel(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
        vm.assertEq(uint256(governor.state(_proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function testFuzz_RevertIf_NonProposerOrGuardianCancelsProposalAboveThreshold(address _caller, uint256 _randomIndex)
        public
    {
        _randomIndex = bound(_randomIndex, 0, _majorDelegates.length - 1);
        address _proposer = _majorDelegates[_randomIndex];
        vm.assume(
            _caller != proposalGuardian.account && _caller != _proposer && _caller != COMPOUND_COMPTROLLER
                && _caller != PROXY_ADMIN_ADDRESS
        );
        Proposal memory _proposal = _buildAnEmptyProposal();
        _submitPassAndQueueProposal(_proposer, _proposal);

        vm.prank(_caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                CompoundGovernor.Unauthorized.selector, bytes32("Proposer above proposalThreshold"), _caller
            )
        );
        governor.cancel(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
    }

    function testFuzz_RevertIfNonWhitelistGuardianCancelsWhitelistedProposalBelowThreshold(address _caller) public {
        vm.assume(
            _caller != whitelistGuardian && _caller != proposalGuardian.account && _caller != delegatee
                && _caller != PROXY_ADMIN_ADDRESS
        );
        Proposal memory _proposal = _buildAnEmptyProposal();
        vm.prank(whitelistGuardian);
        governor.setWhitelistAccountExpiration(delegatee, block.timestamp + 2_000_000);

        _submitPassAndQueueProposal(delegatee, _proposal);
        _removeDelegateeVotingWeight();

        vm.prank(_caller);
        vm.expectRevert(
            abi.encodeWithSelector(CompoundGovernor.Unauthorized.selector, bytes32("Not whitelistGuardian"), _caller)
        );
        governor.cancel(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
    }

    function testFuzz_RevertIf_NonProposerOrGuardianCancelsWhitelistedProposalAboveThreshold(
        address _caller,
        uint256 _randomIndex
    ) public {
        _randomIndex = bound(_randomIndex, 0, _majorDelegates.length - 1);
        address _proposer = _majorDelegates[_randomIndex];
        vm.assume(
            _caller != _proposer && _caller != proposalGuardian.account && _caller != delegatee
                && _caller != PROXY_ADMIN_ADDRESS
        );
        Proposal memory _proposal = _buildAnEmptyProposal();
        vm.prank(whitelistGuardian);
        governor.setWhitelistAccountExpiration(_proposer, block.timestamp + 2_000_000);
        vm.assertTrue(governor.isWhitelisted(_proposer));

        _submitPassAndQueueProposal(_proposer, _proposal);

        vm.prank(_caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                CompoundGovernor.Unauthorized.selector, bytes32("Proposer above proposalThreshold"), _caller
            )
        );
        governor.cancel(
            _proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description))
        );
    }
}
