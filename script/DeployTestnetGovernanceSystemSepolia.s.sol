// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {CompoundGovernor} from "contracts/CompoundGovernor.sol";
import {DeployTestnetGovernanceSystem} from "script/DeployTestnetGovernanceSystem.s.sol";

// Token amounts mirror mainnet. Durations are shortened so a proposal can go from creation to execution in under an
// hour on Sepolia, which produces a block every 12 seconds, like mainnet.
contract DeployTestnetGovernanceSystemSepolia is DeployTestnetGovernanceSystem {
    // Serves as both guardians. It is also the deployer, so it keeps all COMP not sent to the timelock and hands it out
    // to testers as needed.
    address constant TESTNET_ADMIN = 0x16B57aeC1F9BB7F63686A87378Add160270C8f9D;

    // Lets proposals move COMP held by governance.
    uint256 constant TIMELOCK_COMP = 1_000_000e18;

    uint256 constant TIMELOCK_DELAY = 5 minutes;
    uint256 constant TIMELOCK_MINIMUM_DELAY = 0;
    // Same as mainnet.
    uint256 constant TIMELOCK_GRACE_PERIOD = 14 days;

    uint48 constant VOTING_DELAY = 25; // blocks, ~5 minutes
    uint32 constant VOTING_PERIOD = 150; // blocks, ~30 minutes
    uint48 constant LATE_QUORUM_VOTE_EXTENSION = 25; // blocks, ~5 minutes
    // Same as mainnet.
    uint256 constant PROPOSAL_THRESHOLD = 25_000e18;
    // Same as mainnet.
    uint256 constant QUORUM = 400_000e18;
    // Same as the mainnet proposal guardian's expiration, 2030-02-28 00:00:00 UTC.
    uint96 constant PROPOSAL_GUARDIAN_EXPIRATION = 1_898_467_200;
    // The next proposal ID on mainnet at the time this script was written, so IDs look like mainnet's.
    uint256 constant NEXT_PROPOSAL_ID = 615;

    // Script entrypoint
    function run() public override {
        DeployTestnetGovernanceSystem.run();
    }

    function _getTokenParams() internal pure override returns (TokenParams memory) {
        return TokenParams({allocations: new CompAllocation[](0), timelockAllocation: TIMELOCK_COMP});
    }

    function _getTimelockParams() internal pure override returns (TimelockParams memory) {
        return TimelockParams({
            delay: TIMELOCK_DELAY, minimumDelay: TIMELOCK_MINIMUM_DELAY, gracePeriod: TIMELOCK_GRACE_PERIOD
        });
    }

    function _getGovernorParams() internal pure override returns (GovernorParams memory) {
        return GovernorParams({
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            proposalThreshold: PROPOSAL_THRESHOLD,
            quorum: QUORUM,
            lateQuorumVoteExtension: LATE_QUORUM_VOTE_EXTENSION,
            whitelistGuardian: TESTNET_ADMIN,
            proposalGuardian: CompoundGovernor.ProposalGuardian({
                account: TESTNET_ADMIN, expiration: PROPOSAL_GUARDIAN_EXPIRATION
            }),
            nextProposalId: NEXT_PROPOSAL_ID
        });
    }
}
