// SPDX-License-Identifier: MIT
// slither-disable-start reentrancy-benign
pragma solidity 0.8.26;

contract CompoundGovernorConstants {
    // These constants are taken from the existing GovernorBravoDelegate contract.

    uint48 INITIAL_VOTING_DELAY = 13_140; // The delay before voting on a proposal may take place, once proposed, in
        // blocks
    uint32 INITIAL_VOTING_PERIOD = 19_710; // The duration of voting on a proposal, in blocks
    uint256 INITIAL_PROPOSAL_THRESHOLD = 25_000e18; // The number of votes required in order for a voter to become a
        // proposer
    uint256 INITIAL_QUORUM = 400_000e18; // 400,000 = 4% of Comp

    uint48 INITIAL_VOTE_EXTENSION = 7200; // About 2 days in blocks - Prevents sudden move/accumulation of tokens before
        // voting.

    // The address of the COMP token
    address COMP_TOKEN_ADDRESS = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    // The address of the Timelock
    address payable TIMELOCK_ADDRESS = payable(0x6d903f6003cca6255D85CcA4D3B5E5146dC33925);

    // The fork block for testing
    uint256 FORK_BLOCK = 20_885_000;
}
