// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title GovernorStorageEnumIdsUpgradeable
/// @author [ScopeLift](https://scopelift.co)
/// @notice Modified GovernorStorageUpgradeable contract that provides enumerable proposal IDs.
/// @custom:security-contact TODO: Add security contact
abstract contract GovernorStorageEnumIdsUpgradeable is Initializable, GovernorUpgradeable {
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

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Governor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GovernorStorageLocation =
        0x7c712897014dbe49c045ef1299aa2d5f9e67e48eea4403efa21f1e0f3ac0cb00;

    function _getGovernorUpgradeableStorage() private pure returns (GovernorStorage storage $) {
        assembly {
            $.slot := GovernorStorageLocation
        }
    }

    /// @inheritdoc GovernorUpgradeable
    /// @dev Overrides the proposing mechanism, to create an enumerated proposal ID from storage,
    /// and emits that enumerated proposal ID in the ProposalCreated event, while also creating
    /// a hashed proposal ID for use by the GovernorUpgradeable parent contract.
    /// Also creates a mapping between the hashed proposal ID and the enumerated proposal ID.
    function _propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description,
        address proposer
    ) internal virtual override returns (uint256 _proposalId) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        _proposalId = $._nextProposalId;
        uint256 _hashedProposalId = hashProposal(_targets, _values, _calldatas, keccak256(bytes(_description)));

        $._proposalIds.push(_proposalId);
        $._proposalDetails[_proposalId] = ProposalDetails({
            targets: _targets,
            values: _values,
            calldatas: _calldatas,
            descriptionHash: keccak256(bytes(_description))
        });
        $._proposalIdToHashedId[_proposalId] = _hashedProposalId;
        $._nextProposalId += 1;

        if (_targets.length != _values.length || _targets.length != _calldatas.length || _targets.length == 0) {
            revert GovernorInvalidProposalLength(_targets.length, _calldatas.length, _values.length);
        }
        if (_getGovernorUpgradeableStorage()._proposals[_hashedProposalId].voteStart != 0) {
            revert GovernorUnexpectedProposalState(_hashedProposalId, state(_hashedProposalId), bytes32(0));
        }

        uint256 snapshot = clock() + votingDelay();

        ProposalCore storage proposal = _getGovernorUpgradeableStorage()._proposals[_hashedProposalId];
        proposal.proposer = proposer;
        proposal.voteStart = SafeCast.toUint48(snapshot);
        proposal.voteDuration = SafeCast.toUint32(votingPeriod());

        emit ProposalCreated(
            _proposalId,
            proposer,
            _targets,
            _values,
            new string[](_targets.length),
            _calldatas,
            snapshot,
            snapshot + votingPeriod(),
            _description
        );
        $._proposalIdToHashedId[_proposalId] = _hashedProposalId;
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
    ) internal virtual override(GovernorUpgradeable) returns (uint256) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        uint256 _hashedProposalId = $._proposalIdToHashedId[_proposalId];
        return GovernorUpgradeable._castVote(_hashedProposalId, _account, _support, _reason, _params);
    }

    /// @notice Version of {IGovernor-queue} with only enumerated `proposalId` as an argument.
    /// @param _proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the proposal details
    /// needed by the GovernorUpgradeable queue function.
    function queue(uint256 _proposalId) public virtual {
        (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas, bytes32 _descriptionHash) =
            proposalDetails(_proposalId);
        GovernorUpgradeable.queue(_targets, _values, _calldatas, _descriptionHash);
    }

    /// @notice Version of {IGovernor-execute} with only enumerated `proposalId` as an argument.
    /// @param _proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the proposal details
    /// needed by the GovernorUpgradeable execute function.
    function execute(uint256 _proposalId) public payable virtual {
        (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas, bytes32 _descriptionHash) =
            proposalDetails(_proposalId);
        GovernorUpgradeable.execute(_targets, _values, _calldatas, _descriptionHash);
    }

    /// @notice Version of {IGovernor-cancel} with only enumerated `proposalId` as an argument.
    /// @param _proposalId The enumerated proposal ID.
    /// @dev Uses the externally-used enumerated proposal ID to find the proposal details
    /// needed by the GovernorUpgradeable cancel function.
    function cancel(uint256 _proposalId) public virtual {
        (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas, bytes32 _descriptionHash) =
            proposalDetails(_proposalId);
        GovernorUpgradeable.cancel(_targets, _values, _calldatas, _descriptionHash);
    }

    /// @inheritdoc GovernorUpgradeable
    /// @dev We override this function support both external(enumerated) and internal(hashed) proposal IDs.
    /// When called by external function, `proposalId` should be the enumerated proposalId.
    /// When called by internal governor functions, `proposalId` parameter is the hashed proposalId.
    function state(uint256 _proposalId) public view virtual override returns (ProposalState) {
        uint256 hashedProposalId = _getGovernorStorageEnumIdsStorage()._proposalIdToHashedId[_proposalId];

        // Directly use the original proposal ID if the hashed proposal ID is not found
        return super.state(hashedProposalId == 0 ? _proposalId : hashedProposalId);
    }

    /// @notice Returns the number of stored proposals.
    /// @return The number of stored proposals.
    function proposalCount() public view virtual returns (uint256) {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        return $._proposalIds.length;
    }

    /// @notice Returns the details of a proposalId. Reverts if `proposalId` is not a known proposal.
    /// @param _proposalId The enumerated proposal ID.
    function proposalDetails(uint256 _proposalId)
        public
        view
        virtual
        returns (address[] memory, uint256[] memory, bytes[] memory, bytes32)
    {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        ProposalDetails memory _details = $._proposalDetails[_proposalId];
        if (_details.descriptionHash == 0) {
            revert GovernorNonexistentProposal(_proposalId);
        }
        return (_details.targets, _details.values, _details.calldatas, _details.descriptionHash);
    }

    /// @notice Returns the details (including the proposalId) of a proposal given its sequential index.
    /// @param _index The index of the proposal.
    function proposalDetailsAt(uint256 _index)
        public
        view
        virtual
        returns (
            uint256 _proposalId,
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _calldatas,
            bytes32 _descriptionHash
        )
    {
        GovernorStorageEnumIdsStorage storage $ = _getGovernorStorageEnumIdsStorage();
        _proposalId = $._proposalIds[_index];
        (_targets, _values, _calldatas, _descriptionHash) = proposalDetails(_proposalId);
    }
}
