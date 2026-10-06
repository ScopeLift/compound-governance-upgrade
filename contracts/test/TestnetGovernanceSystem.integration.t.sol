// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";
import {GovernorSettingsUpgradeable} from "contracts/extensions/GovernorSettingsUpgradeable.sol";
import {IGovernor} from "contracts/extensions/IGovernor.sol";
import {IComp} from "contracts/interfaces/IComp.sol";
import {TestnetTimelock} from "contracts/testnet/TestnetTimelock.sol";
import {DeployTestnetGovernanceSystemSepolia} from "script/DeployTestnetGovernanceSystemSepolia.s.sol";

contract DeployTestnetGovernanceSystemSepoliaHarness is DeployTestnetGovernanceSystemSepolia {
    function exposed_getGovernorParams() external pure returns (GovernorParams memory) {
        return _getGovernorParams();
    }
}

abstract contract TestnetGovernanceSystemTest is Test {
    struct SystemUnderTest {
        CompoundGovernor governor;
        CompoundGovernor governorImplementation;
        TestnetTimelock timelock;
        IComp comp;
        ProxyAdmin proxyAdmin;
        uint256 configuredNextProposalId;
    }

    struct Proposal {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    uint8 constant VOTE_FOR = 1;

    CompoundGovernor governor;
    CompoundGovernor governorImplementation;
    TestnetTimelock timelock;
    IComp comp;
    ProxyAdmin proxyAdmin;
    uint256 configuredNextProposalId;

    function setUp() public virtual {
        _setUpNetwork();
        SystemUnderTest memory _system = _fetchOrDeploySystem();
        governor = _system.governor;
        governorImplementation = _system.governorImplementation;
        timelock = _system.timelock;
        comp = _system.comp;
        proxyAdmin = _system.proxyAdmin;
        configuredNextProposalId = _system.configuredNextProposalId;
    }

    function _setUpNetwork() internal virtual;

    function _fetchOrDeploySystem() internal virtual returns (SystemUnderTest memory);

    function test_GovernorAdministersTheTimelockWhichOwnsTheGovernorProxyAdmin() external view {
        assertEq(timelock.admin(), address(governor));
        assertEq(timelock.pendingAdmin(), address(0));
        assertEq(governor.timelock(), address(timelock));
        assertEq(proxyAdmin.owner(), address(timelock));
        assertEq(_governorImplementationAddress(), address(governorImplementation));
        assertEq(address(governor.token()), address(comp));
        assertEq(governor.proposalCount(), configuredNextProposalId - 1);
    }

    function test_ProposalPassedByDelegatedHoldersMovesTimelockCompAndUpdatesGovernorSettingsAfterTheDelay() external {
        address _proposer = _delegatedVoterWithQuorum("proposer");
        address _recipient = makeAddr("recipient");
        uint256 _grantAmount = 1000e18;
        uint32 _newVotingPeriod = uint32(governor.votingPeriod() * 2);
        uint256 _timelockCompBefore = comp.balanceOf(address(timelock));
        _dealComp(address(timelock), _timelockCompBefore + _grantAmount);

        Proposal memory _proposal = _buildProposal(
            address(comp),
            abi.encodeCall(IComp.transfer, (_recipient, _grantAmount)),
            address(governor),
            abi.encodeCall(GovernorSettingsUpgradeable.setVotingPeriod, (_newVotingPeriod)),
            "Grant COMP from the timelock and lengthen the voting period"
        );

        // The first proposal on the fresh governor takes the configured next proposal ID.
        uint256 _proposalId = _propose(_proposer, _proposal);
        assertEq(_proposalId, configuredNextProposalId);

        // The proposer's votes alone pass the proposal, which is then queued in the timelock.
        _voteFor(_proposalId, _proposer);
        _jumpPastVotingDeadline(_proposalId);
        governor.queue(_proposalId);
        assertEq(uint8(governor.state(_proposalId)), uint8(IGovernor.ProposalState.Queued));

        // The timelock refuses to execute until its delay has elapsed.
        if (timelock.delay() > 0) {
            vm.expectRevert("Timelock::executeTransaction: Transaction hasn't surpassed time lock.");
            governor.execute(_proposalId);
        }

        vm.warp(governor.proposalEta(_proposalId));
        governor.execute(_proposalId);

        assertEq(uint8(governor.state(_proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(comp.balanceOf(_recipient), _grantAmount);
        assertEq(comp.balanceOf(address(timelock)), _timelockCompBefore);
        assertEq(governor.votingPeriod(), _newVotingPeriod);
        assertEq(governor.proposalCount(), configuredNextProposalId);
    }

    function test_GovernanceUpgradesTheGovernorImplementationThroughTheTimelockOwnedProxyAdmin() external {
        address _proposer = _delegatedVoterWithQuorum("proposer");
        CompoundGovernor _newImplementation = new CompoundGovernor();
        uint256 _votingDelayBefore = governor.votingDelay();

        Proposal memory _proposal = _buildProposal(
            address(proxyAdmin),
            abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (ITransparentUpgradeableProxy(address(governor)), address(_newImplementation), "")
            ),
            "Upgrade the governor implementation"
        );

        uint256 _proposalId = _propose(_proposer, _proposal);
        _passQueueAndExecute(_proposalId, _proposer);

        // The proxy now points at the new implementation, with the governor's state carried across the upgrade.
        assertEq(_governorImplementationAddress(), address(_newImplementation));
        assertEq(uint8(governor.state(_proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(governor.proposalCount(), configuredNextProposalId);
        assertEq(governor.votingDelay(), _votingDelayBefore);
        assertEq(timelock.admin(), address(governor));
        assertEq(proxyAdmin.owner(), address(timelock));
    }

    function test_QueuedProposalExpiresOnceTheTimelockGracePeriodPasses() external {
        address _proposer = _delegatedVoterWithQuorum("proposer");
        Proposal memory _proposal = _buildProposal(
            address(governor),
            abi.encodeCall(GovernorSettingsUpgradeable.setVotingDelay, (uint48(1))),
            "Shorten the voting delay"
        );

        uint256 _proposalId = _propose(_proposer, _proposal);
        _voteFor(_proposalId, _proposer);
        _jumpPastVotingDeadline(_proposalId);
        governor.queue(_proposalId);

        // Still executable on the last second of the grace period, as reported by the governor.
        vm.warp(governor.proposalEta(_proposalId) + timelock.GRACE_PERIOD() - 1);
        assertEq(uint8(governor.state(_proposalId)), uint8(IGovernor.ProposalState.Queued));

        // The governor reads the testnet timelock's grace period to decide the proposal has expired.
        vm.warp(governor.proposalEta(_proposalId) + timelock.GRACE_PERIOD());
        assertEq(uint8(governor.state(_proposalId)), uint8(IGovernor.ProposalState.Expired));
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                _proposalId,
                IGovernor.ProposalState.Expired,
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
                    | bytes32(1 << uint8(IGovernor.ProposalState.Queued))
            )
        );
        governor.execute(_proposalId);
    }

    function _governorImplementationAddress() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(governor), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _dealComp(address _holder, uint256 _amount) internal {
        deal(address(comp), _holder, _amount);
    }

    // Returns an account holding and self-delegating enough COMP to both propose and meet quorum on its own, with its
    // votes already checkpointed in a prior block.
    function _delegatedVoterWithQuorum(string memory _label) internal returns (address _voter) {
        _voter = makeAddr(_label);
        _dealComp(_voter, governor.quorum(governor.clock()) + governor.proposalThreshold());
        vm.prank(_voter);
        comp.delegate(_voter);
        vm.roll(block.number + 1);
    }

    function _buildProposal(address _target, bytes memory _calldata, string memory _description)
        internal
        pure
        returns (Proposal memory _proposal)
    {
        _proposal.targets = new address[](1);
        _proposal.values = new uint256[](1);
        _proposal.calldatas = new bytes[](1);
        _proposal.targets[0] = _target;
        _proposal.calldatas[0] = _calldata;
        _proposal.description = _description;
    }

    function _buildProposal(
        address _firstTarget,
        bytes memory _firstCalldata,
        address _secondTarget,
        bytes memory _secondCalldata,
        string memory _description
    ) internal pure returns (Proposal memory _proposal) {
        _proposal.targets = new address[](2);
        _proposal.values = new uint256[](2);
        _proposal.calldatas = new bytes[](2);
        _proposal.targets[0] = _firstTarget;
        _proposal.targets[1] = _secondTarget;
        _proposal.calldatas[0] = _firstCalldata;
        _proposal.calldatas[1] = _secondCalldata;
        _proposal.description = _description;
    }

    function _propose(address _proposer, Proposal memory _proposal) internal returns (uint256 _proposalId) {
        vm.prank(_proposer);
        _proposalId = governor.propose(_proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description);
    }

    function _voteFor(uint256 _proposalId, address _voter) internal {
        vm.roll(governor.proposalSnapshot(_proposalId) + 1);
        vm.prank(_voter);
        governor.castVote(_proposalId, VOTE_FOR);
    }

    function _jumpPastVotingDeadline(uint256 _proposalId) internal {
        vm.roll(governor.proposalDeadline(_proposalId) + 1);
        if (governor.state(_proposalId) != IGovernor.ProposalState.Succeeded) {
            revert("Test setup: the proposal did not succeed; check that the voter holds enough delegated COMP");
        }
    }

    function _passQueueAndExecute(uint256 _proposalId, address _voter) internal {
        _voteFor(_proposalId, _voter);
        _jumpPastVotingDeadline(_proposalId);
        governor.queue(_proposalId);
        vm.warp(governor.proposalEta(_proposalId));
        governor.execute(_proposalId);
    }

    function _runSepoliaDeployScript() internal returns (SystemUnderTest memory) {
        DeployTestnetGovernanceSystemSepoliaHarness _deploy = new DeployTestnetGovernanceSystemSepoliaHarness();
        _deploy.disableLogging();
        _deploy.run();
        return SystemUnderTest({
            governor: _deploy.governor(),
            governorImplementation: _deploy.governorImplementation(),
            timelock: _deploy.timelock(),
            comp: IComp(address(_deploy.comp())),
            proxyAdmin: _deploy.proxyAdmin(),
            configuredNextProposalId: _deploy.exposed_getGovernorParams().nextProposalId
        });
    }
}

contract TestnetGovernanceSystemLocal is TestnetGovernanceSystemTest {
    function _setUpNetwork() internal override {
        // Local EVM — no fork.
    }

    function _fetchOrDeploySystem() internal override returns (SystemUnderTest memory) {
        return _runSepoliaDeployScript();
    }
}

contract TestnetGovernanceSystemSepoliaScript is TestnetGovernanceSystemTest {
    uint256 constant FORK_BLOCK = 11_850_000;

    function _setUpNetwork() internal override {
        vm.createSelectFork("sepolia", FORK_BLOCK);
    }

    function _fetchOrDeploySystem() internal override returns (SystemUnderTest memory) {
        return _runSepoliaDeployScript();
    }
}
