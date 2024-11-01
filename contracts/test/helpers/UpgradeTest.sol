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
import {CompoundGovernorTest} from "contracts/test/helpers/CompoundGovernorTest.sol";

abstract contract UpgradeTest is CompoundGovernorTest {
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
        vm.roll(vm.getBlockNumber() + 1); // move up one block so not in the same block as when queued
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

    function _passQueueAndExecuteBravoProposal(uint256 _bravoProposalId) public {
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
}
