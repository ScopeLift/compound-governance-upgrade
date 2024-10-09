// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IComp} from "contracts/interfaces/IComp.sol";

/// @title CompoundGovernorVotesUpgradeable
/// @author [ScopeLift](https://scopelift.co)
/// @notice Modified GovernorVotes contract that supports Compound's COMP token.
/// @custom:security-contact TODO: Add security contact
abstract contract CompoundGovernorVotesUpgradeable is Initializable, GovernorUpgradeable {
    /// @custom:storage-location IComp:storage.CompoundGovernorVotes
    struct CompoundGovernorVotesStorage {
        IComp _token;
    }

    // keccak256(abi.encode(uint256(keccak256("storage.CompoundGovernorVotes")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CompoundGovernorVotesStorageLocation =
        0x69f1f297e68cd1b53f75e4e19d390fe2baecb721066d42c98913bf524d296400;

    function _getCompoundGovernorVotesStorage() private pure returns (CompoundGovernorVotesStorage storage $) {
        assembly {
            $.slot := CompoundGovernorVotesStorageLocation
        }
    }

    function __CompoundGovernorVotes_init(IComp _tokenAddress) internal onlyInitializing {
        __CompoundGovernorVotes_init_unchained(_tokenAddress);
    }

    function __CompoundGovernorVotes_init_unchained(IComp _tokenAddress) internal onlyInitializing {
        CompoundGovernorVotesStorage storage $ = _getCompoundGovernorVotesStorage();
        $._token = IComp(address(_tokenAddress));
    }

    /// @notice Returns the IComp token used for governance.
    /// @dev This function retrieves the token address from the contract's storage.
    /// @return IComp The COMP token interface used for governance voting.
    function token() public view virtual returns (IComp) {
        CompoundGovernorVotesStorage storage $ = _getCompoundGovernorVotesStorage();
        return $._token;
    }

    /// @notice This function implements the clock interface as specified in ERC-6372.
    /// @dev Returns the current clock value used for governance voting.
    /// @return uint48 The current block number cast to uint48.
    function clock() public view virtual override returns (uint48) {
        return Time.blockNumber();
    }

    /// @notice Returns a machine-readable description of the clock as specified in ERC-6372.
    /// @dev This function provides information about the clock mode used for governance timing.
    /// @return string A string describing the clock mode, indicating that block numbers are used
    ///         as the time measure, with the default starting point.
    function CLOCK_MODE() public view virtual override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    /// @notice Retrieves the voting weight for a specific account at a given timepoint.
    /// @dev This function overrides the base _getVotes function to use Compound's getPriorVotes mechanism.
    /// @param _account The address of the account to check the voting weight for.
    /// @param _timepoint The block number at which to check the voting weight.
    /// @param /*params*/ Unused parameter, kept for compatibility with the base function signature.
    /// @return uint256 The voting weight of the account at the specified timepoint.
    function _getVotes(address _account, uint256 _timepoint, bytes memory /*params*/ )
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return token().getPriorVotes(_account, _timepoint);
    }
}
