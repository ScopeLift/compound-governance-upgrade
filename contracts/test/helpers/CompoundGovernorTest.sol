// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {CompoundGovernorConstants} from "script/CompoundGovernorConstants.sol";
import {DeployCompoundGovernor} from "script/DeployCompoundGovernor.s.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";
import {GovernorBravoDelegate} from "contracts/GovernorBravoDelegate.sol";
import {IComp} from "contracts/interfaces/IComp.sol";

contract CompoundGovernorTest is Test, CompoundGovernorConstants {
    CompoundGovernor governor;
    IComp token;
    ICompoundTimelock timelock;
    address owner;
    address whitelistGuardian;
    CompoundGovernor.ProposalGuardian proposalGuardian;
    uint96 constant PROPOSAL_GUARDIAN_EXPIRY = 1_739_768_400;

    GovernorBravoDelegate public constant GOVERNOR_BRAVO = GovernorBravoDelegate(GOVERNOR_BRAVO_DELEGATE_ADDRESS);

    function setUp() public virtual {
        // set the RPC URL and the fork block number to create a local execution fork for testing
        vm.createSelectFork(vm.envOr("RPC_URL", string("Please set RPC_URL in your .env file")), FORK_BLOCK);

        if (_useDeployedCompoundGovernor()) {
            // Set the governor to be the deployed CompoundGovernor
            governor = CompoundGovernor(payable(DEPLOYED_UPGRADE_CANDIDATE));
            owner = governor.owner();
            whitelistGuardian = governor.whitelistGuardian();
            (proposalGuardian.account, proposalGuardian.expiration) = governor.proposalGuardian();
        } else {
            // set the owner of the governor (use the anvil default account #0, if no environment variable is set)
            owner = vm.envOr("DEPLOYER_ADDRESS", 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
            whitelistGuardian = makeAddr("WHITELIST_GUARDIAN_ADDRESS");
            proposalGuardian = CompoundGovernor.ProposalGuardian(COMMUNITY_MULTISIG_ADDRESS, PROPOSAL_GUARDIAN_EXPIRY);

            // Deploy the CompoundGovernor contract
            DeployCompoundGovernor _deployer = new DeployCompoundGovernor();
            _deployer.setUp();
            governor = _deployer.run(owner, whitelistGuardian, proposalGuardian);
            governor = _deployer.run(owner, whitelistGuardian, proposalGuardian);
        }
        timelock = ICompoundTimelock(payable(governor.timelock()));
        token = governor.token();
        vm.label(GOVERNOR_BRAVO_DELEGATE_ADDRESS, "GovernorBravoDelegate");
        vm.label(owner, "Owner");
        vm.label(address(governor), "CompoundGovernor");
        vm.label(address(timelock), "Timelock");
        vm.label(COMP_TOKEN_ADDRESS, "CompToken");
    }

    function _useDeployedCompoundGovernor() internal pure virtual returns (bool) {
        return false;
    }

    function _shouldPassAndExecuteUpgradeProposal() internal pure virtual returns (bool) {
        return true;
    }

    function _timelockOrWhitelistGuardian(uint256 _randomSeed) internal view returns (address) {
        return _randomSeed % 2 == 0 ? TIMELOCK_ADDRESS : whitelistGuardian;
    }
}
