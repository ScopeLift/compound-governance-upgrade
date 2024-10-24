// SPDX-License-Identifier: BSD-3-Clause
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IComp} from "contracts/interfaces/IComp.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";
import {CompoundGovernorConstants} from "script/CompoundGovernorConstants.sol";
import {GovernorBravoDelegateStorageV1} from "contracts/GovernorBravoInterfaces.sol";

// Deploy script for the underlying implementation that will be used by both Governor proxies
contract DeployCompoundGovernor is Script, CompoundGovernorConstants {
    address constant GOVERNOR_BRAVO_DELEGATE_ADDRESS = 0xc0Da02939E1441F497fd74F78cE7Decb17B66529;

    uint256 deployerPrivateKey;

    function setUp() public virtual {
        // private key of the deployer (use the anvil default account #0 key, if no environment variable is set)
        deployerPrivateKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
    }

    function run(address _owner, address _whitelistGuardian, CompoundGovernor.ProposalGuardian memory _proposalGuardian)
        public
        returns (CompoundGovernor _governor)
    {
        GovernorBravoDelegateStorageV1 _governorBravoStorage =
            GovernorBravoDelegateStorageV1(GOVERNOR_BRAVO_DELEGATE_ADDRESS);
        uint256 _startingProposalId = _governorBravoStorage.proposalCount();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Governor implementation contract
        CompoundGovernor _implementation = new CompoundGovernor();

        // Initialize the proxy with the implementation contract and constructor arguments
        CompoundGovernor.CompoundGovernorInitializer memory _initializer = CompoundGovernor.CompoundGovernorInitializer({
            initialVotingDelay: INITIAL_VOTING_DELAY,
            initialVotingPeriod: INITIAL_VOTING_PERIOD,
            initialProposalThreshold: INITIAL_PROPOSAL_THRESHOLD,
            compAddress: IComp(COMP_TOKEN_ADDRESS),
            quorumVotes: INITIAL_QUORUM,
            timelockAddress: ICompoundTimelock(TIMELOCK_ADDRESS),
            initialVoteExtension: INITIAL_VOTE_EXTENSION,
            initialOwner: _owner,
            whitelistGuardian: _whitelistGuardian,
            proposalGuardian: _proposalGuardian,
            startingProposalId: _startingProposalId
        });

        bytes memory _initData = abi.encodeCall(CompoundGovernor.initialize, (_initializer));

        TransparentUpgradeableProxy _proxy =
            new TransparentUpgradeableProxy(address(_implementation), TIMELOCK_ADDRESS, _initData);
        _governor = CompoundGovernor(payable(address(_proxy)));

        vm.stopBroadcast();
    }
}
