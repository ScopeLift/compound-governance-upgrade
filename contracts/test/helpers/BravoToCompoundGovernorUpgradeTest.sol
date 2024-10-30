// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";
import {CompoundGovernorConstants} from "script/CompoundGovernorConstants.sol";
import {DeployCompoundGovernor} from "script/DeployCompoundGovernor.s.sol";
import {GovernorBravoDelegate} from "contracts/GovernorBravoDelegate.sol";
import {IComp} from "contracts/interfaces/IComp.sol";
import {ProposeUpgradeBravoToCompoundGovernor} from "script/ProposeUpgradeBravoToCompoundGovernor.s.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {ProposalTest} from "contracts/test/helpers/ProposalTest.sol";

// The deployed CompooundGovernor address for testing upgradability
// TODO: for now, just a placeholder
address constant DEPLOYED_COMPOUND_GOVERNOR = 0x1111111111111111111111111111111111111111;

abstract contract BravoToCompoundGovernorUpgradeTest is ProposalTest {
    // GovernorBravo to receive upgrade proposal
    address constant GOVERNOR_BRAVO_DELEGATE_ADDRESS = 0xc0Da02939E1441F497fd74F78cE7Decb17B66529;
    GovernorBravoDelegate public constant GOVERNOR_BRAVO = GovernorBravoDelegate(GOVERNOR_BRAVO_DELEGATE_ADDRESS);

    function _getBravoProposalStartBlock(uint256 _bravoProposalId) internal view returns (uint256) {
        (,,, uint256 _startBlock,,,,,,) = GOVERNOR_BRAVO.proposals(_bravoProposalId);
        return _startBlock;
    }

    function _getBravoProposalEndBlock(uint256 _bravoProposalId) internal view returns (uint256) {
        (,,,, uint256 _endBlock,,,,,) = GOVERNOR_BRAVO.proposals(_bravoProposalId);
        return _endBlock;
    }

    function _jumpToActiveBravoProposal(uint256 _bravoProposalId) internal {
        vm.roll(_getBravoProposalStartBlock(_bravoProposalId) + 1);
    }

    function _jumpToBravoVoteComplete(uint256 _bravoProposalId) internal {
        vm.roll(_getBravoProposalEndBlock(_bravoProposalId) + 1);
    }

    function _delegatesVoteOnBravoProposal(uint256 _bravoProposalId, GovernorCountingSimple.VoteType _support)
        internal
    {
        for (uint256 _index = 0; _index < _majorDelegates.length; _index++) {
            vm.prank(_majorDelegates[_index]);
            GOVERNOR_BRAVO.castVote(_bravoProposalId, uint8(_support));
        }
    }

    function _getBravoProposalEta(uint256 _bravoProposalId) internal view returns (uint256) {
        (,, uint256 _eta,,,,,,,) = GOVERNOR_BRAVO.proposals(_bravoProposalId);
        return _eta;
    }

    function _jumpPastBravoProposalEta(uint256 _bravoProposalId) internal {
        vm.roll(vm.getBlockNumber() + 1); // move up one block so we're not in the same block as when
        // queued
        vm.warp(_getBravoProposalEta(_bravoProposalId) + 1); // jump past the eta timestamp
    }

    function _passBravoProposal(uint256 _bravoProposalId) internal {
        _jumpToActiveBravoProposal(_bravoProposalId);
        _delegatesVoteOnBravoProposal(_bravoProposalId, GovernorCountingSimple.VoteType.For);
        _jumpToBravoVoteComplete(_bravoProposalId);
    }

    function _failBravoProposal(uint256 _bravoProposalId) internal {
        _jumpToActiveBravoProposal(_bravoProposalId);
        _delegatesVoteOnBravoProposal(_bravoProposalId, GovernorCountingSimple.VoteType.Against);
        _jumpToBravoVoteComplete(_bravoProposalId);
    }

    function _passAndQueueBravoProposal(uint256 _bravoProposalId) internal {
        _passBravoProposal(_bravoProposalId);
        GOVERNOR_BRAVO.queue(_bravoProposalId);
    }

    function _passQueueAndExecuteBravoProposal(uint256 _bravoProposalId) internal {
        _passAndQueueBravoProposal(_bravoProposalId);
        _jumpPastBravoProposalEta(_bravoProposalId);
        GOVERNOR_BRAVO.execute(_bravoProposalId);
    }

    function _upgradeFromBravoToCompoundGovernorViaProposalVote() internal {
        // Create the proposal to upgrade the Bravo governor to the CompoundGovernor
        ProposeUpgradeBravoToCompoundGovernor _proposeUpgrade = new ProposeUpgradeBravoToCompoundGovernor();
        uint256 _upgradeProposalId = _proposeUpgrade.run(governor);

        // Pass, queue, and execute the proposal
        _passQueueAndExecuteBravoProposal(_upgradeProposalId);
    }

    function _failProposalVoteForUpgradeFromBravoToCompoundGovernor() internal {
        // Create the proposal to upgrade the Bravo governor to the CompoundGovernor
        ProposeUpgradeBravoToCompoundGovernor _proposeUpgrade = new ProposeUpgradeBravoToCompoundGovernor();
        uint256 _upgradeProposalId = _proposeUpgrade.run(governor);

        // Pass, queue, and execute the proposal
        _failBravoProposal(_upgradeProposalId);
    }

    function _updateTimelockAdminToOldGovernor() internal {
        address _timelockAddress = governor.timelock();
        ICompoundTimelock _timelock = ICompoundTimelock(payable(_timelockAddress));
        vm.prank(_timelockAddress);
        _timelock.setPendingAdmin(GOVERNOR_BRAVO_DELEGATE_ADDRESS);
        vm.prank(address(GOVERNOR_BRAVO_DELEGATE_ADDRESS));
        _timelock.acceptAdmin();
    }

    function setUp() public virtual override {
        if (_useDeployedCompoundGovernor()) {
            // After the CompoundGovernor is deployed, the actual deployed contract can be tested.
            // create a local execution fork for testing
            vm.createSelectFork(vm.envOr("RPC_URL", string("Please set RPC_URL in your .env file")), FORK_BLOCK);

            // Set the governor to be the deployed CompoundGovernor
            governor = CompoundGovernor(payable(DEPLOYED_COMPOUND_GOVERNOR));
            owner = governor.owner();
            whitelistGuardian = governor.whitelistGuardian();
            (proposalGuardian.account, proposalGuardian.expiration) = governor.proposalGuardian();
        } else {
            // Before a CompoundGovernor is deployed, the test setup will deploy the governor.
            super.setUp();

            // restore the timelock admin to the old governor for upgrade testing
            _updateTimelockAdminToOldGovernor();
        }
        vm.label(GOVERNOR_BRAVO_DELEGATE_ADDRESS, "GovernorBravoDelegate");
        vm.label(owner, "Owner");
        vm.label(address(governor), "CompoundGovernor");
        vm.label(address(timelock), "Timelock");
        vm.label(COMP_TOKEN_ADDRESS, "CompToken");
    }

    function _useDeployedCompoundGovernor() internal virtual returns (bool);

 
    function _buildNewGovernorSetVotingDelayProposal(uint48 _amount) private view returns (Proposal memory _proposal) {
        address[] memory _targets = new address[](1);
        _targets[0] = address(governor);

        uint256[] memory _values = new uint256[](1);
        _values[0] = 0;

        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = _buildProposalData("setVotingDelay(uint48)", abi.encode(_amount));

        _proposal = Proposal(_targets, _values, _calldatas, "Set New Voting Delay on New Compound Governor");
    }

    function _buildAndSubmitOldGovernorSetVotingDelayProposal(uint256 _proposerIndex, uint _amount) internal returns (uint256 _proposalId) {
        vm.assume(_amount >= GOVERNOR_BRAVO.MIN_VOTING_DELAY() && _amount <= GOVERNOR_BRAVO.MAX_VOTING_DELAY());
        _proposerIndex = bound(_proposerIndex, 0, _majorDelegates.length - 1);
        address[] memory _targets = new address[](1);
        uint256[] memory _values = new uint256[](1);
        string[] memory _signatures = new string[](1);
        bytes[] memory _calldatas = new bytes[](1);

        _targets[0] = GOVERNOR_BRAVO_DELEGATE_ADDRESS;
        _values[0] = 0;
        _signatures[0] = "_setVotingDelay(uint256)";
        _calldatas[0] = abi.encode(uint256(_amount));

        vm.prank(_majorDelegates[0]);
        return GOVERNOR_BRAVO.propose(
            _targets, _values, _signatures, _calldatas, "Set Voting Delay on Old Governor Bravo"
        );
    }

    function test_UpgradeToCompoundGovernor() public {
        _upgradeFromBravoToCompoundGovernorViaProposalVote();
        assertEq(timelock.admin(), address(governor));
    }

    function test_FailUpgradeToCompoundGovernor() public {
        _failProposalVoteForUpgradeFromBravoToCompoundGovernor();
        assertEq(timelock.admin(), GOVERNOR_BRAVO_DELEGATE_ADDRESS);
    }

    function testFuzz_NewGovernorProposalCanBePassedAfterSuccessfulUpgrade(uint256 _proposerIndex, uint48 _newVotingDelay) public {
        _proposerIndex = bound(_proposerIndex, 0, _majorDelegates.length - 1);
        _upgradeFromBravoToCompoundGovernorViaProposalVote();
        assertEq(timelock.admin(), address(governor));
        Proposal memory _proposal = _buildNewGovernorSetVotingDelayProposal(_newVotingDelay);
        _submitPassQueueAndExecuteProposal(_majorDelegates[_proposerIndex], _proposal);
        assertEq(governor.votingDelay(), _newVotingDelay);
    }

    function testFuzz_RevertIf_OldGovernorAttemptsQueueingAfterSuccessfulUpgrade(uint256 _proposerIndex, uint _newVotingDelay) public {
        uint _originalVotingDelay = GOVERNOR_BRAVO.votingDelay();
        vm.assume(_newVotingDelay != _originalVotingDelay);
        _upgradeFromBravoToCompoundGovernorViaProposalVote();
        assertEq(timelock.admin(), address(governor));
        uint256 _proposalId = _buildAndSubmitOldGovernorSetVotingDelayProposal(_proposerIndex, _newVotingDelay);
        _passBravoProposal(_proposalId);
        vm.expectRevert("Timelock::queueTransaction: Call must come from admin.");
        GOVERNOR_BRAVO.queue(_proposalId);
        assertEq(GOVERNOR_BRAVO.votingDelay(), _originalVotingDelay);
    }

    function testFuzz_OldGovernorProposalCanBePassedAfterFailedUpgrade(uint256 _proposerIndex, uint _newVotingDelay) public {
        uint _originalVotingDelay = GOVERNOR_BRAVO.votingDelay();
        vm.assume(_newVotingDelay != _originalVotingDelay);
        console2.log("original voting delay", _originalVotingDelay);
        console2.log("new voting delay", _newVotingDelay);
        _failProposalVoteForUpgradeFromBravoToCompoundGovernor();
        assertEq(timelock.admin(), GOVERNOR_BRAVO_DELEGATE_ADDRESS);
        uint256 _proposalId = _buildAndSubmitOldGovernorSetVotingDelayProposal(_proposerIndex, _newVotingDelay);
        _passQueueAndExecuteBravoProposal(_proposalId);
        assertEq(GOVERNOR_BRAVO.votingDelay(), _newVotingDelay);
    }
}
