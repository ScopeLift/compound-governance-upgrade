// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorStorageUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

/// @title GovernorStorageEnumIdsUpgradeable
/// @author [ScopeLift](https://scopelift.co)
/// @notice Modified GovernorStorageUpgradeable contract that provides enumerable proposal IDs.
/// @custom:security-contact TODO: Add security contact
abstract contract GovernorStorageEnumIdsUpgradeable is Initializable, GovernorStorageUpgradeable {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /// @custom:storage-location erc7201:openzeppelin.storage.GovernorStorageEnumIds
    struct GovernorStorageEnumIdsStorage {
        uint256 _nextProposalId;
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

    /// @inheritdoc GovernorStorageUpgradeable
    /// @dev Hook into the proposing mechanism, but creates proposalId using an enumeration from storage,
    /// and creates a mapping between the hashed proposalId and the enumerated proposalId.
    function _propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description,
        address proposer
    ) internal virtual override returns (uint256 proposalId) {
        uint256 hashedProposalId =
            GovernorStorageUpgradeable._propose(_targets, _values, _calldatas, _description, proposer);
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        proposalId = $._nextProposalId;
        $._nextProposalId += 1;
        $._proposalIdToHashedId[proposalId] = hashedProposalId;
    }

    /// @notice Version of {IGovernor-queue} with only enumerated `proposalId` as an argument.
    /// @param _proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the hashed proposal ID
    /// needed by the GovernorStorageUpgradeable queue function.
    function queue(uint256 _proposalId) public virtual override {
        GovernorStorageUpgradeable.queue(_getHashedProposalId(_proposalId));
    }

    /// @notice Version of {IGovernor-execute} with only enumerated `proposalId` as an argument.
    /// @param _proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the hashed proposal ID
    /// needed by the GovernorStorageUpgradeable execute function.
    function execute(uint256 _proposalId) public payable virtual override {
        GovernorStorageUpgradeable.execute(_getHashedProposalId(_proposalId));
    }

    /// @notice Version of {IGovernor-cancel} with only enumerated `proposalId` as an argument.
    /// @param _proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the hashed proposal ID
    /// needed by the GovernorStorageUpgradeable cancel function.
    function cancel(uint256 _proposalId) public virtual override {
        GovernorStorageUpgradeable.cancel(_getHashedProposalId(_proposalId));
    }

    /// @inheritdoc GovernorUpgradeable
    /// @dev We override this function to map the externally-used enumerated proposal ID the
    /// hashed proposal ID needed by the GovernorUpgradeable _castVote function.
    function _castVote(
        uint256 _proposalId,
        address _account,
        uint8 _support,
        string memory _reason,
        bytes memory _params
    ) internal virtual override returns (uint256) {
        return GovernorUpgradeable._castVote(_getHashedProposalId(_proposalId), _account, _support, _reason, _params);
    }

    function _getHashedProposalId(uint256 _proposalId) public view returns (uint256) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        return $._proposalIdToHashedId[_proposalId];
    }
}
