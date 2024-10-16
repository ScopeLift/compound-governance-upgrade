// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0-rc.0) (governance/extensions/GovernorStorage.sol)

pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

/**
 * @dev Extension of {Governor} that implements storage of proposal details. This modules also provides primitives for
 * the enumerability of proposals.
 *
 * Use cases for this module include:
 * - UIs that explore the proposal state without relying on event indexing.
 * - Using only the proposalId as an argument in the {Governor-queue} and {Governor-execute} functions for L2 chains
 *   where storage is cheap compared to calldata.
 */
abstract contract GovernorStorageEnumIdsUpgradeable is Initializable, GovernorUpgradeable {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    struct ProposalDetails {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 descriptionHash;
    }

    /// @custom:storage-location erc7201:openzeppelin.storage.GovernorStorageEnumIds
    struct GovernorStorageEnumIdsStorage {
        uint256 _nextProposalId;
        uint256[] _proposalIds;
        mapping(uint256 proposalId => ProposalDetails) _proposalDetails;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.GovernorStorageEnumIds")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant GovernorStorageEnumIdsStorageLocation =
        0x5c5d8e664482c81661458cb19a5efbd416c87d14df05dbbd554e526aabf5a800;

    function _getGovernorStorageEnumIdsStorage() private pure returns (GovernorStorageEnumIdsStorage storage $) {
        assembly {
            $.slot := GovernorStorageEnumIdsStorageLocation
        }
    }

    function __GovernorStorageEnumIds_init(uint256 _startingProposalId) internal onlyInitializing {
        __GovernorStorageEnumIds_init_unchained(_startingProposalId);
    }

    function __GovernorStorageEnumIds_init_unchained(uint256 _startingProposalId) internal onlyInitializing {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        $._nextProposalId = _startingProposalId;
    }

    /**
     * @dev Hook into the proposing mechanism, but creates proposalId using an enumeration from storage.
     */
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal virtual override returns (uint256 proposalId) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        proposalId = $._nextProposalId;
        ProposalDetails memory details = ProposalDetails({
            targets: targets,
            values: values,
            calldatas: calldatas,
            descriptionHash: keccak256(bytes(description))
        });

        // store
        $._proposalIds.push(proposalId);
        $._proposalDetails[proposalId] = details;
        $._nextProposalId += 1;

        super._propose(targets, values, calldatas, description, proposer);
    }

    /**
     * @dev Cast a vote for a proposal, using enumerated proposalId, that is translated to a hashed proposalId.
     * Uses the {GovernorUpgradeable-_castVote} function.
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override(GovernorUpgradeable)
        returns (uint256)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        uint256 hashedProposalId = hashProposal(targets, values, calldatas, descriptionHash);
        return GovernorUpgradeable._castVote(hashedProposalId, account, support, reason, params);
    }

    /**
     * @dev Version of {IGovernorTimelock-queue} with only enumerated `proposalId` as an argument.
     */
    function queue(uint256 proposalId) public virtual {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        GovernorUpgradeable.queue(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Version of {IGovernor-execute} with only `proposalId` as an argument.
     */
    function execute(uint256 proposalId) public payable virtual {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        GovernorUpgradeable.execute(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev ProposalId version of {IGovernor-cancel}.
     */
    function cancel(uint256 proposalId) public virtual {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        GovernorUpgradeable.cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Returns the number of stored proposals.
     */
    function proposalCount() public view virtual returns (uint256) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        return $._proposalIds.length;
    }

    /**
     * @dev Returns the details of a proposalId. Reverts if `proposalId` is not a known proposal.
     */
    function proposalDetails(uint256 proposalId)
        public
        view
        virtual
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
    {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        // here, using memory is more efficient than storage
        ProposalDetails memory details = $._proposalDetails[proposalId];
        if (details.descriptionHash == 0) {
            revert GovernorNonexistentProposal(proposalId);
        }
        return (details.targets, details.values, details.calldatas, details.descriptionHash);
    }

    /**
     * @dev Returns the details (including the proposalId) of a proposal given its sequential index.
     */
    function proposalDetailsAt(uint256 index)
        public
        view
        virtual
        returns (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        )
    {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        proposalId = $._proposalIds[index];
        (targets, values, calldatas, descriptionHash) = proposalDetails(proposalId);
    }
}
