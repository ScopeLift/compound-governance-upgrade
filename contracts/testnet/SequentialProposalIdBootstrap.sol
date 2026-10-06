// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

/// @title SequentialProposalIdBootstrap
/// @author [ScopeLift](https://scopelift.co)
/// @custom:security-contact security@compound.finance
/// @notice A temporary proxy implementation that seeds the next proposal ID of a freshly deployed
/// `CompoundGovernor` on a test network. On mainnet, the governor's next proposal ID is set by `setNextProposalId`,
/// which continues the proposal count of the GovernorBravo deployment at a hardcoded mainnet address. No such
/// contract exists on test networks, so a fresh governor would otherwise be left unable to create proposals. A
/// deployer that still owns the governor's `ProxyAdmin` upgrades the proxy to this contract, seeds the ID, and
/// immediately upgrades back to the `CompoundGovernor` implementation.
/// @dev This contract must only ever be used as a proxy implementation via `ProxyAdmin.upgradeAndCall`, after the
/// governor has been initialized and before ownership of the `ProxyAdmin` is handed to the timelock.
contract SequentialProposalIdBootstrap {
    /// @notice Thrown when the next proposal ID has already been set, either by this contract or by
    /// `CompoundGovernor.setNextProposalId`.
    /// @param currentNextProposalId The next proposal ID already stored by the governor.
    error SequentialProposalIdBootstrap__NextProposalIdAlreadySet(uint256 currentNextProposalId);

    /// @notice Thrown when the requested next proposal ID is zero or is the sentinel the governor uses to mark the ID
    /// as unset.
    /// @param nextProposalId The rejected proposal ID.
    error SequentialProposalIdBootstrap__InvalidNextProposalId(uint256 nextProposalId);

    /// @notice The ERC-7201 storage location of `GovernorSequentialProposalIdUpgradeable`, whose first slot holds the
    /// next proposal ID.
    /// @dev keccak256(abi.encode(uint256(keccak256("storage.GovernorSequentialProposalIdStorage")) - 1)) &
    /// ~bytes32(uint256(0xff))
    bytes32 public constant SEQUENTIAL_PROPOSAL_ID_STORAGE_LOCATION =
        0x357e1d0c89980520b3654c57f444238d75a15e5f41d389a090caabe54617d800;

    /// @notice The value `GovernorSequentialProposalIdUpgradeable` stores at initialization to mark the next proposal
    /// ID as unset.
    uint256 public constant UNSET_NEXT_PROPOSAL_ID = type(uint256).max;

    /// @notice Sets the ID the governor assigns to its next proposal. It can only be called while the governor's next
    /// proposal ID is still unset, mirroring the one-time semantics of `CompoundGovernor.setNextProposalId`.
    /// @param _nextProposalId The ID to assign to the governor's next proposal. The governor's `proposalCount` will
    /// report one less than this value until a proposal is created.
    function setNextProposalId(uint256 _nextProposalId) external {
        _revertIfNextProposalIdIsInvalid(_nextProposalId);
        _revertIfNextProposalIdIsAlreadySet();

        bytes32 _slot = SEQUENTIAL_PROPOSAL_ID_STORAGE_LOCATION;
        assembly {
            sstore(_slot, _nextProposalId)
        }
    }

    /// @notice Reverts if `_nextProposalId` is zero, which the governor uses as the "no proposal" sentinel, or is the
    /// sentinel for an unset next proposal ID.
    /// @param _nextProposalId The proposal ID to check.
    function _revertIfNextProposalIdIsInvalid(uint256 _nextProposalId) internal pure {
        if (_nextProposalId == 0 || _nextProposalId == UNSET_NEXT_PROPOSAL_ID) {
            revert SequentialProposalIdBootstrap__InvalidNextProposalId(_nextProposalId);
        }
    }

    /// @notice Reverts if the governor's next proposal ID has already been set.
    function _revertIfNextProposalIdIsAlreadySet() internal view {
        bytes32 _slot = SEQUENTIAL_PROPOSAL_ID_STORAGE_LOCATION;
        uint256 _currentNextProposalId;
        assembly {
            _currentNextProposalId := sload(_slot)
        }
        if (_currentNextProposalId != UNSET_NEXT_PROPOSAL_ID) {
            revert SequentialProposalIdBootstrap__NextProposalIdAlreadySet(_currentNextProposalId);
        }
    }
}
