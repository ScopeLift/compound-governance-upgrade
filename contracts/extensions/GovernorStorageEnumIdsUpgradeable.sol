// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0-rc.0) (governance/extensions/GovernorStorage.sol)

pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {console2} from "forge-std/Test.sol";

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
        uint256 _startingProposalId;
        uint256[] _proposalIds;
        mapping(uint256 proposalId => ProposalDetails) _proposalDetails;
    }

    // @dev This is needed so that the overridden function can access the GovernorUpgradeable storage
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Governor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GovernorStorageLocation =
        0x7c712897014dbe49c045ef1299aa2d5f9e67e48eea4403efa21f1e0f3ac0cb00;

    function _getGovernorStorageLocation() private pure returns (GovernorStorage storage $) {
        assembly {
            $.slot := GovernorStorageLocation
        }
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
        $._startingProposalId = _startingProposalId;
    }

    /**
     * @dev Check that the current state of a proposal matches the requirements described by the `allowedStates` bitmap.
     * This bitmap should be built using `_encodeStateBitmap`.
     *
     * If requirements are not met, reverts with a {GovernorUnexpectedProposalState} error.
     */
    function _validateStateViaBitmap(uint256 proposalId, bytes32 allowedStates) private view returns (ProposalState) {
        ProposalState currentState = state(proposalId);
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0)) {
            revert GovernorUnexpectedProposalState(proposalId, currentState, allowedStates);
        }
        return currentState;
    }

    /**
     * @dev Replicates the behavior of GovernorUpgradeable `_propose` but using the enumerated (not-hashed) proposalId.
     */
    function _proposeViaEnumId(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) private {
        GovernorStorage storage $ = _getGovernorStorageLocation();
        if (targets.length != values.length || targets.length != calldatas.length || targets.length == 0) {
            revert GovernorInvalidProposalLength(targets.length, calldatas.length, values.length);
        }
        if ($._proposals[proposalId].voteStart != 0) {
            revert GovernorUnexpectedProposalState(proposalId, state(proposalId), bytes32(0));
        }

        uint256 snapshot = clock() + votingDelay();
        uint256 duration = votingPeriod();

        ProposalCore storage proposal = $._proposals[proposalId];
        proposal.proposer = proposer;
        proposal.voteStart = SafeCast.toUint48(snapshot);
        proposal.voteDuration = SafeCast.toUint32(duration);

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            snapshot + duration,
            description
        );
    }

    /**
     * @dev Replicates the behavior of GovernorUpgradeable `queue` but using the enumerated (not-hashed) proposalId.
     */
    function _queueViaEnumId(uint256 proposalId, ProposalDetails memory details) private {
        GovernorStorage storage $ = _getGovernorStorageLocation();

        _validateStateViaBitmap(proposalId, _encodeStateBitmap(ProposalState.Succeeded));

        uint48 etaSeconds =
            _queueOperations(proposalId, details.targets, details.values, details.calldatas, details.descriptionHash);

        if (etaSeconds != 0) {
            $._proposals[proposalId].etaSeconds = etaSeconds;
            emit ProposalQueued(proposalId, etaSeconds);
        } else {
            revert GovernorQueueNotImplemented();
        }
    }

    /**
     * @dev Replicates the behavior of GovernorUpgradeable `execute` but using the enumerated (not-hashed) proposalId.
     */
    function _executeViaEnumId(uint256 proposalId, ProposalDetails memory details) public payable virtual {
        GovernorStorage storage $ = _getGovernorStorageLocation();

        _validateStateViaBitmap(
            proposalId, _encodeStateBitmap(ProposalState.Succeeded) | _encodeStateBitmap(ProposalState.Queued)
        );

        // mark as executed before calls to avoid reentrancy
        $._proposals[proposalId].executed = true;

        // before execute: register governance call in queue.
        if (_executor() != address(this)) {
            for (uint256 i = 0; i < details.targets.length; ++i) {
                if (details.targets[i] == address(this)) {
                    $._governanceCall.pushBack(keccak256(details.calldatas[i]));
                }
            }
        }

        _executeOperations(proposalId, details.targets, details.values, details.calldatas, details.descriptionHash);

        // after execute: cleanup governance call queue.
        if (_executor() != address(this) && !$._governanceCall.empty()) {
            $._governanceCall.clear();
        }

        emit ProposalExecuted(proposalId);
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
    ) internal virtual override returns (uint256) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        uint256 proposalId = $._startingProposalId;
        ProposalDetails memory details = ProposalDetails({
            targets: targets,
            values: values,
            calldatas: calldatas,
            descriptionHash: keccak256(bytes(description))
        });
        _proposeViaEnumId(proposalId, targets, values, calldatas, description, proposer);

        // store
        $._proposalIds.push(proposalId);
        $._proposalDetails[proposalId] = details;
        $._startingProposalId += 1;

        return proposalId;
    }

    /**
     * @dev Version of {IGovernorTimelock-queue} with only enumerated `proposalId` as an argument.
     */
    function queue(uint256 proposalId) public virtual {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        // here, using storage is more efficient than memory
        ProposalDetails storage details = $._proposalDetails[proposalId];
        _queueViaEnumId(proposalId, details);
    }

    /**
     * @dev Version of {IGovernor-execute} with only `proposalId` as an argument.
     */
    function execute(uint256 proposalId) public payable virtual {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        // here, using storage is more efficient than memory
        ProposalDetails storage details = $._proposalDetails[proposalId];
        _executeViaEnumId(proposalId, details);
    }

    /**
     * @dev ProposalId version of {IGovernor-cancel}.
     */
    function cancel(uint256 proposalId) public virtual {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        // here, using storage is more efficient than memory
        ProposalDetails storage details = $._proposalDetails[proposalId];
        cancel(details.targets, details.values, details.calldatas, details.descriptionHash);
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
