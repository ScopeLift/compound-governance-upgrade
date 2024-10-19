// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0-rc.0) (governance/extensions/GovernorStorage.sol)

pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

/// @title GovernorStorageEnumIdsUpgradeable
/// @author [ScopeLift](https://scopelift.co)
/// @notice Modified GovernorStorageUpgradeable contract that provides enumerable proposal IDs.
/// @custom:security-contact TODO: Add security contact
abstract contract GovernorStorageEnumIdsUpgradeable is Initializable, GovernorUpgradeable {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    /// @dev Storage structure to store proposal details.
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
        mapping(uint256 proposalId => uint256) _proposalIdToHashedId;
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

    /// @inheritdoc GovernorUpgradeable
    /// @dev Hook into the proposing mechanism, but creates proposalId using an enumeration from storage,
    /// and creates a mapping between the hashed proposalId and the enumerated proposalId.
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

        uint256 hashedProposalId = super._propose(targets, values, calldatas, description, proposer);
        $._proposalIdToHashedId[proposalId] = hashedProposalId;
    }

    /// @inheritdoc GovernorUpgradeable
    /// @dev We override this function to map the externally-used enumerated proposal ID the
    /// hashed proposal ID needed by the GovernorUpgradeable _castVote function.
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override(GovernorUpgradeable)
        returns (uint256)
    {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        uint256 hashedProposalId = $._proposalIdToHashedId[proposalId];
        return GovernorUpgradeable._castVote(hashedProposalId, account, support, reason, params);
    }

    /// @notice Version of {IGovernor-queue} with only enumerated `proposalId` as an argument.
    /// @param proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the proposal details
    /// needed by the GovernorUpgradeable queue function.
    function queue(uint256 proposalId) public virtual {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        GovernorUpgradeable.queue(targets, values, calldatas, descriptionHash);
    }

    /// @notice Version of {IGovernor-execute} with only enumerated `proposalId` as an argument.
    /// @param proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the proposal details
    /// needed by the GovernorUpgradeable execute function.
    function execute(uint256 proposalId) public payable virtual {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        GovernorUpgradeable.execute(targets, values, calldatas, descriptionHash);
    }

    /// @notice Version of {IGovernor-cancel} with only enumerated `proposalId` as an argument.
    /// @param proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the proposal details
    /// needed by the GovernorUpgradeable cancel function.
    function cancel(uint256 proposalId) public virtual {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        GovernorUpgradeable.cancel(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc GovernorUpgradeable
    /// @dev We override this function support both external(enumerated) and internal(hashed) proposal IDs.
    /// When called by external function, `proposalId` should be the enumerated proposalId.
    /// When called by internal governor functions, `proposalId` parameter is the hashed proposalId.
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        uint256 hashedProposalId = $._proposalIdToHashedId[proposalId];
        if (hashedProposalId == 0) {
            hashedProposalId = proposalId;
        }
        return super.state(hashedProposalId);
    }

    /// @notice Returns the number of stored proposals.
    /// @return The number of stored proposals.
    function proposalCount() public view virtual returns (uint256) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        return $._proposalIds.length;
    }

    /// @notice Returns the details of a proposalId. Reverts if `proposalId` is not a known proposal.
    /// @param proposalId The enumerated proposal ID.
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

    /// @notice Returns the details (including the proposalId) of a proposal given its sequential index.
    /// @param index The index of the proposal.
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
