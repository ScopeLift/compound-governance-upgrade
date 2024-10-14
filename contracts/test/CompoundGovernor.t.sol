// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {CompoundGovernorConstants} from "script/CompoundGovernorConstants.sol";
import {DeployCompoundGovernor} from "script/DeployCompoundGovernor.s.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";

contract CompoundGovernorTest is Test, CompoundGovernorConstants {
    CompoundGovernor governor;
    address owner;
    address whitelistGuardian;

    function setUp() public {
        // set the owner of the governor (use the anvil default account #0, if no environment variable is set)
        owner = vm.envOr("DEPLOYER_ADDRESS", 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        whitelistGuardian = vm.envOr("WHITELIST_GUARDIAN_ADDRESS", 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        // set the RPC URL and the fork block number to create a local execution fork for testing
        vm.createSelectFork(vm.envOr("RPC_URL", string("Please set RPC_URL in your .env file")), FORK_BLOCK);

        // Deploy the CompoundGovernor contract
        DeployCompoundGovernor _deployer = new DeployCompoundGovernor();
        _deployer.setUp();
        governor = _deployer.run(owner, whitelistGuardian);
    }

    function testInitialize() public view {
        assertEq(governor.quorum(governor.clock()), INITIAL_QUORUM);
        assertEq(governor.votingPeriod(), INITIAL_VOTING_PERIOD);
        assertEq(governor.votingDelay(), INITIAL_VOTING_DELAY);
        assertEq(governor.proposalThreshold(), INITIAL_PROPOSAL_THRESHOLD);
        assertEq(governor.lateQuorumVoteExtension(), INITIAL_VOTE_EXTENSION);
        assertEq(address(governor.timelock()), TIMELOCK_ADDRESS);
        assertEq(address(governor.token()), COMP_TOKEN_ADDRESS);
        assertEq(governor.owner(), owner);
    }

    function _timelockOrWhitelistGuardian(uint256 _randomSeed) internal view returns (address) {
        return _randomSeed % 2 == 0 ? TIMELOCK_ADDRESS : whitelistGuardian;
    }
}

contract SetWhitelistAccountExpiration is CompoundGovernorTest {
    function testFuzz_WhitelistAnAccountAsTimelock(address _account, uint256 _expiration) public {
        vm.prank(TIMELOCK_ADDRESS);
        governor.setWhitelistAccountExpiration(_account, _expiration);
        assertEq(governor.whitelistAccountExpirations(_account), _expiration);
    }

    function testFuzz_WhitelistAnAccountAsWhitelistGuardian(address _account, uint256 _expiration) public {
        vm.prank(whitelistGuardian);
        governor.setWhitelistAccountExpiration(_account, _expiration);
        assertEq(governor.whitelistAccountExpirations(_account), _expiration);
    }

    function testFuzz_EmitsEventWhenAnAccountIsWhitelisted(address _account, uint256 _expiration, uint256 _randomSeed)
        public
    {
        vm.prank(_timelockOrWhitelistGuardian(_randomSeed));
        vm.expectEmit();
        emit CompoundGovernor.WhitelistAccountExpirationSet(_account, _expiration);
        governor.setWhitelistAccountExpiration(_account, _expiration);
    }

    function testFuzz_RevertIf_CallerIsNotTimelockNorWhitelistGuardian(
        address _account,
        uint256 _expiration,
        address _caller
    ) public {
        vm.assume(_caller != TIMELOCK_ADDRESS && _caller != whitelistGuardian && _caller != address(governor));
        vm.prank(_caller);

        vm.expectRevert(
            abi.encodeWithSelector(CompoundGovernor.Unauthorized.selector, bytes32("Not timelock or guardian"), _caller)
        );
        governor.setWhitelistAccountExpiration(_account, _expiration);
    }
}

contract IsWhitelisted is CompoundGovernorTest {
    function testFuzz_ReturnTrueIfAnAccountIsStillWithinExpiry(
        address _account,
        uint256 _expiration,
        uint256 _timeBeforeExpiry,
        uint256 _randomSeed
    ) public {
        _expiration = bound(_expiration, 1, type(uint256).max);
        _timeBeforeExpiry = bound(_timeBeforeExpiry, 0, _expiration - 1);

        vm.prank(_timelockOrWhitelistGuardian(_randomSeed));
        governor.setWhitelistAccountExpiration(_account, _expiration);

        vm.warp(_timeBeforeExpiry);
        vm.assertEq(governor.isWhitelisted(_account), true);
    }

    function testFuzz_ReturnFalseIfAnAccountIsExpired(
        address _account,
        uint256 _expiration,
        uint256 _timeAfterExpiry,
        uint256 _randomSeed
    ) public {
        _expiration = bound(_expiration, 1, type(uint256).max - 1);
        _timeAfterExpiry = bound(_timeAfterExpiry, _expiration, type(uint256).max);

        vm.prank(_timelockOrWhitelistGuardian(_randomSeed));
        governor.setWhitelistAccountExpiration(_account, _expiration);

        vm.warp(_timeAfterExpiry);
        vm.assertEq(governor.isWhitelisted(_account), false);
    }

    function testFuzz_ReturnFalseIfAnAccountIsNotWhitelisted(address _account) public view {
        vm.assertEq(governor.isWhitelisted(_account), false);
    }
}

contract SetWhitelistGuardian is CompoundGovernorTest {
    function testFuzz_SetsWhitelistGuardianAsTimelock(address _whitelistGuardian) public {
        vm.prank(TIMELOCK_ADDRESS); // TODO: This is not sufficient, you must pass a proposal in order to
            // get past `_checkGovernance`.
        governor.setWhitelistGuardian(_whitelistGuardian);
        assertEq(governor.whitelistGuardian(), _whitelistGuardian);
    }

    function testFuzz_EmitsEventWhenAWhitelistGuardianIsSet(address _whitelistGuardian) public {
        vm.expectEmit();
        emit CompoundGovernor.WhitelistGuardianSet(governor.whitelistGuardian(), _whitelistGuardian);
        vm.prank(TIMELOCK_ADDRESS);
        governor.setWhitelistGuardian(_whitelistGuardian);
    }

    function testFuzz_RevertIf_CallerIsNotTimelock(address _whitelistGuardian, address _caller) public {
        vm.assume(_caller != TIMELOCK_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSelector(CompoundGovernor.Unauthorized.selector, bytes32("Not timelock"), _caller)
        );
        vm.prank(_caller);
        governor.setWhitelistGuardian(_whitelistGuardian);
    }
}
