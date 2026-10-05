// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Comp} from "contracts/Comp.sol";
import {CompoundGovernor} from "contracts/CompoundGovernor.sol";
import {IComp} from "contracts/interfaces/IComp.sol";
import {SequentialProposalIdBootstrap} from "contracts/testnet/SequentialProposalIdBootstrap.sol";
import {TestnetTimelock} from "contracts/testnet/TestnetTimelock.sol";

// Deploys a complete, standalone copy of Compound governance to a test network: the COMP token, a TestnetTimelock,
// and a CompoundGovernor behind a TransparentUpgradeableProxy whose ProxyAdmin is owned by the timelock, mirroring the
// ownership structure on mainnet. Unlike mainnet, there is no GovernorBravo to upgrade from, so the governor's next
// proposal ID is seeded through a temporary upgrade to a SequentialProposalIdBootstrap implementation while the
// deployer still owns the ProxyAdmin.
abstract contract DeployTestnetGovernanceSystem is Script {
    struct CompAllocation {
        address recipient;
        uint256 amount;
    }

    struct TokenParams {
        // Transferred from the deployer, which receives the entire COMP supply at construction.
        CompAllocation[] allocations;
        // Transferred to the timelock so proposals can move COMP held by governance. May be zero.
        uint256 timelockAllocation;
    }

    struct TimelockParams {
        uint256 delay;
        uint256 minimumDelay;
        uint256 gracePeriod;
    }

    struct GovernorParams {
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 proposalThreshold;
        uint256 quorum;
        uint48 lateQuorumVoteExtension;
        address whitelistGuardian;
        CompoundGovernor.ProposalGuardian proposalGuardian;
        uint256 nextProposalId;
    }

    // Mirrors `Comp.totalSupply`, the fixed supply minted to the deployer at construction.
    uint256 internal constant COMP_TOTAL_SUPPLY = 10_000_000e18;

    // The number of contracts the deployer creates before each of these; used to predict their addresses.
    uint64 internal constant CREATES_BEFORE_COMP = 0;
    uint64 internal constant CREATES_BEFORE_TIMELOCK = 2;
    uint64 internal constant CREATES_BEFORE_GOVERNOR_PROXY = 3;

    // Contract deployments and ProxyAdmin calls; COMP transfers are counted separately.
    uint256 internal constant FIXED_TRANSACTION_COUNT = 8;

    address public deployer;
    Comp public comp;
    CompoundGovernor public governorImplementation;
    TestnetTimelock public timelock;
    CompoundGovernor public governor;
    SequentialProposalIdBootstrap public proposalIdBootstrap;
    ProxyAdmin public proxyAdmin;

    bool internal isLogging = true;
    uint256 internal expectedTransactionCount;
    uint256 internal loggedTransactionCount;

    function run() public virtual {
        TokenParams memory _tokenParams = _getTokenParams();
        TimelockParams memory _timelockParams = _getTimelockParams();
        GovernorParams memory _governorParams = _getGovernorParams();
        _validateTokenParams(_tokenParams);
        _validateTimelockParams(_timelockParams);
        _validateGovernorParams(_governorParams);

        deployer = _readBroadcaster();
        expectedTransactionCount = _countTransactions(_tokenParams);
        _logParams(_tokenParams, _timelockParams, _governorParams);

        _deployContracts(_timelockParams, _governorParams);
        _seedNextProposalIdAndHandOffProxyAdmin(_governorParams.nextProposalId);
        _distributeComp(_tokenParams);

        _validateDeployment(_tokenParams, _timelockParams, _governorParams);
        _logDeployment();
    }

    function disableLogging() public {
        isLogging = false;
    }

    function _getTokenParams() internal view virtual returns (TokenParams memory);

    function _getTimelockParams() internal view virtual returns (TimelockParams memory);

    function _getGovernorParams() internal view virtual returns (GovernorParams memory);

    // Opens an empty broadcast region solely to learn which account will sign the broadcast transactions. No
    // transaction is recorded.
    function _readBroadcaster() internal returns (address _broadcaster) {
        vm.startBroadcast();
        (, _broadcaster,) = vm.readCallers();
        vm.stopBroadcast();
    }

    function _deployContracts(TimelockParams memory _timelockParams, GovernorParams memory _governorParams) internal {
        // The timelock must name the governor proxy as its admin at construction, and the governor must be initialized
        // with the token and timelock addresses, so all three are predicted from the deployer's nonce.
        uint64 _nonce = vm.getNonce(deployer);
        address _expectedComp = vm.computeCreateAddress(deployer, _nonce + CREATES_BEFORE_COMP);
        address _expectedTimelock = vm.computeCreateAddress(deployer, _nonce + CREATES_BEFORE_TIMELOCK);
        address _expectedGovernor = vm.computeCreateAddress(deployer, _nonce + CREATES_BEFORE_GOVERNOR_PROXY);
        bytes memory _initData = abi.encodeCall(
            CompoundGovernor.initialize,
            (
                _governorParams.votingDelay,
                _governorParams.votingPeriod,
                _governorParams.proposalThreshold,
                IComp(_expectedComp),
                _governorParams.quorum,
                ICompoundTimelock(payable(_expectedTimelock)),
                _governorParams.lateQuorumVoteExtension,
                _governorParams.whitelistGuardian,
                _governorParams.proposalGuardian
            )
        );

        vm.startBroadcast();

        // BROADCAST: deploy the COMP token, minting the entire supply to the deployer
        _logTransaction("Deploying Comp, minting the full supply to the deployer");
        comp = new Comp(deployer);

        // BROADCAST: deploy the CompoundGovernor implementation
        _logTransaction("Deploying the CompoundGovernor implementation");
        governorImplementation = new CompoundGovernor();

        // BROADCAST: deploy the TestnetTimelock with the not-yet-deployed governor proxy as its admin
        _logTransaction(string.concat("Deploying TestnetTimelock with admin ", vm.toString(_expectedGovernor)));
        timelock = new TestnetTimelock(
            _expectedGovernor, _timelockParams.delay, _timelockParams.minimumDelay, _timelockParams.gracePeriod
        );

        // BROADCAST: deploy and initialize the governor proxy, with the deployer as the temporary ProxyAdmin owner
        _logTransaction("Deploying and initializing the CompoundGovernor proxy, owned by the deployer for now");
        governor = CompoundGovernor(
            payable(address(new TransparentUpgradeableProxy(address(governorImplementation), deployer, _initData)))
        );

        // BROADCAST: deploy the bootstrap implementation used to seed the next proposal ID
        _logTransaction("Deploying SequentialProposalIdBootstrap");
        proposalIdBootstrap = new SequentialProposalIdBootstrap();

        vm.stopBroadcast();

        _validatePredictedAddress("COMP token", address(comp), _expectedComp);
        _validatePredictedAddress("timelock", address(timelock), _expectedTimelock);
        _validatePredictedAddress("governor proxy", address(governor), _expectedGovernor);
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(governor), ERC1967Utils.ADMIN_SLOT)))));
    }

    function _seedNextProposalIdAndHandOffProxyAdmin(uint256 _nextProposalId) internal {
        ITransparentUpgradeableProxy _governorProxy = ITransparentUpgradeableProxy(address(governor));
        bytes memory _seedCall = abi.encodeCall(SequentialProposalIdBootstrap.setNextProposalId, (_nextProposalId));

        vm.startBroadcast();

        // BROADCAST: upgrade the governor proxy to the bootstrap and seed the next proposal ID in the same call
        _logTransaction(string.concat("Seeding the governor's next proposal ID to ", vm.toString(_nextProposalId)));
        proxyAdmin.upgradeAndCall(_governorProxy, address(proposalIdBootstrap), _seedCall);

        // BROADCAST: upgrade the governor proxy back to the CompoundGovernor implementation
        _logTransaction("Restoring the CompoundGovernor implementation behind the proxy");
        proxyAdmin.upgradeAndCall(_governorProxy, address(governorImplementation), "");

        // BROADCAST: hand ownership of the ProxyAdmin to the timelock
        _logTransaction(
            string.concat("Transferring ProxyAdmin ownership to the timelock ", vm.toString(address(timelock)))
        );
        proxyAdmin.transferOwnership(address(timelock));

        vm.stopBroadcast();
    }

    function _distributeComp(TokenParams memory _tokenParams) internal {
        vm.startBroadcast();

        for (uint256 _index = 0; _index < _tokenParams.allocations.length; _index += 1) {
            CompAllocation memory _allocation = _tokenParams.allocations[_index];
            // BROADCAST: transfer COMP to an allocation recipient, once per allocation
            _logTransaction(
                string.concat(
                    "Transferring ", _formatComp(_allocation.amount), " COMP to ", vm.toString(_allocation.recipient)
                )
            );
            comp.transfer(_allocation.recipient, _allocation.amount);
        }

        if (_tokenParams.timelockAllocation > 0) {
            // BROADCAST: transfer COMP to the timelock
            _logTransaction(
                string.concat("Transferring ", _formatComp(_tokenParams.timelockAllocation), " COMP to the timelock")
            );
            comp.transfer(address(timelock), _tokenParams.timelockAllocation);
        }

        vm.stopBroadcast();
    }

    function _countTransactions(TokenParams memory _tokenParams) internal pure returns (uint256 _count) {
        _count = FIXED_TRANSACTION_COUNT + _tokenParams.allocations.length;
        if (_tokenParams.timelockAllocation > 0) {
            _count += 1;
        }
    }

    function _formatComp(uint256 _amount) internal view returns (string memory) {
        return vm.toString(_amount / 1e18);
    }

    function _log(string memory _msg) internal view {
        if (isLogging) {
            console2.log(_msg);
        }
    }

    function _logTransaction(string memory _description) internal {
        loggedTransactionCount += 1;
        _log(
            string.concat(
                "[", vm.toString(loggedTransactionCount), "/", vm.toString(expectedTransactionCount), "] ", _description
            )
        );
    }

    function _logParams(
        TokenParams memory _tokenParams,
        TimelockParams memory _timelockParams,
        GovernorParams memory _governorParams
    ) internal view {
        _log("Deploying a testnet Compound governance system with:");
        _log(string.concat("  deployer:                ", vm.toString(deployer)));
        _log("  Timelock");
        _log(string.concat("    delay (s):             ", vm.toString(_timelockParams.delay)));
        _log(string.concat("    minimumDelay (s):      ", vm.toString(_timelockParams.minimumDelay)));
        _log(string.concat("    gracePeriod (s):       ", vm.toString(_timelockParams.gracePeriod)));
        _log("  Governor");
        _log(string.concat("    votingDelay (blocks):  ", vm.toString(_governorParams.votingDelay)));
        _log(string.concat("    votingPeriod (blocks): ", vm.toString(_governorParams.votingPeriod)));
        _log(
            string.concat(
                "    lateQuorumVoteExtension (blocks): ", vm.toString(_governorParams.lateQuorumVoteExtension)
            )
        );
        _log(string.concat("    proposalThreshold:     ", _formatComp(_governorParams.proposalThreshold), " COMP"));
        _log(string.concat("    quorum:                ", _formatComp(_governorParams.quorum), " COMP"));
        _log(string.concat("    whitelistGuardian:     ", vm.toString(_governorParams.whitelistGuardian)));
        _log(string.concat("    proposalGuardian:      ", vm.toString(_governorParams.proposalGuardian.account)));
        _log(
            string.concat("    proposalGuardian expiration: ", vm.toString(_governorParams.proposalGuardian.expiration))
        );
        _log(string.concat("    nextProposalId:        ", vm.toString(_governorParams.nextProposalId)));
        _log("  COMP");
        for (uint256 _index = 0; _index < _tokenParams.allocations.length; _index += 1) {
            CompAllocation memory _allocation = _tokenParams.allocations[_index];
            _log(
                string.concat(
                    "    ", vm.toString(_allocation.recipient), ": ", _formatComp(_allocation.amount), " COMP"
                )
            );
        }
        _log(string.concat("    timelock: ", _formatComp(_tokenParams.timelockAllocation), " COMP"));
    }

    function _logDeployment() internal view {
        _log("Deployment complete:");
        _log(string.concat("  Comp:                            ", vm.toString(address(comp))));
        _log(string.concat("  TestnetTimelock:                 ", vm.toString(address(timelock))));
        _log(string.concat("  CompoundGovernor (proxy):        ", vm.toString(address(governor))));
        _log(string.concat("  CompoundGovernor implementation: ", vm.toString(address(governorImplementation))));
        _log(string.concat("  ProxyAdmin:                      ", vm.toString(address(proxyAdmin))));
        _log(string.concat("  SequentialProposalIdBootstrap:   ", vm.toString(address(proposalIdBootstrap))));
        _log(string.concat("  COMP remaining with deployer:    ", _formatComp(comp.balanceOf(deployer))));
        _log(string.concat("Broadcast ", vm.toString(loggedTransactionCount), " transactions"));
    }

    function _validateTokenParams(TokenParams memory _tokenParams) internal pure {
        uint256 _totalAllocated = _tokenParams.timelockAllocation;
        for (uint256 _index = 0; _index < _tokenParams.allocations.length; _index += 1) {
            CompAllocation memory _allocation = _tokenParams.allocations[_index];
            if (_allocation.recipient == address(0)) {
                revert(
                    "DeployTestnetGovernanceSystem: a COMP allocation recipient is the zero address; "
                    "set every recipient to the address that should receive COMP"
                );
            }
            if (_allocation.amount == 0) {
                revert(
                    "DeployTestnetGovernanceSystem: a COMP allocation amount is zero; "
                    "remove the allocation or give it a nonzero amount"
                );
            }
            _totalAllocated += _allocation.amount;
        }
        if (_totalAllocated > COMP_TOTAL_SUPPLY) {
            revert(
                "DeployTestnetGovernanceSystem: COMP allocations plus the timelock allocation exceed the "
                "10,000,000 COMP supply; reduce the allocated amounts"
            );
        }
    }

    function _validateTimelockParams(TimelockParams memory _timelockParams) internal pure {
        uint256 _maximumDelay = 30 days;
        if (_timelockParams.minimumDelay > _maximumDelay) {
            revert(
                "DeployTestnetGovernanceSystem: timelock minimumDelay exceeds the timelock's 30 day MAXIMUM_DELAY; "
                "lower it"
            );
        }
        if (_timelockParams.delay < _timelockParams.minimumDelay || _timelockParams.delay > _maximumDelay) {
            revert(
                "DeployTestnetGovernanceSystem: timelock delay must be at least minimumDelay and at most 30 days; "
                "adjust the delay"
            );
        }
        if (_timelockParams.gracePeriod == 0) {
            revert(
                "DeployTestnetGovernanceSystem: timelock gracePeriod is zero, so queued proposals could never be "
                "executed; set a nonzero grace period"
            );
        }
    }

    function _validateGovernorParams(GovernorParams memory _governorParams) internal view {
        if (_governorParams.votingPeriod == 0) {
            revert("DeployTestnetGovernanceSystem: governor votingPeriod is zero; set a nonzero voting period");
        }
        if (_governorParams.quorum == 0 || _governorParams.quorum > COMP_TOTAL_SUPPLY) {
            revert(
                "DeployTestnetGovernanceSystem: governor quorum must be nonzero and no more than the 10,000,000 COMP "
                "supply; adjust the quorum"
            );
        }
        if (_governorParams.proposalThreshold > COMP_TOTAL_SUPPLY) {
            revert(
                "DeployTestnetGovernanceSystem: governor proposalThreshold exceeds the 10,000,000 COMP supply, so "
                "no one could propose; lower it"
            );
        }
        if (_governorParams.whitelistGuardian == address(0)) {
            revert(
                "DeployTestnetGovernanceSystem: whitelistGuardian is the zero address; "
                "set it to the account that should manage the proposer whitelist"
            );
        }
        if (_governorParams.proposalGuardian.account == address(0)) {
            revert(
                "DeployTestnetGovernanceSystem: proposalGuardian account is the zero address; "
                "set it to the account that should be able to cancel proposals"
            );
        }
        if (_governorParams.proposalGuardian.expiration <= block.timestamp) {
            revert(
                "DeployTestnetGovernanceSystem: proposalGuardian expiration is not in the future; "
                "set it to a later timestamp"
            );
        }
        if (_governorParams.nextProposalId == 0 || _governorParams.nextProposalId == type(uint256).max) {
            revert(
                "DeployTestnetGovernanceSystem: nextProposalId must be at least 1 and less than type(uint256).max; "
                "adjust it"
            );
        }
    }

    function _validateDeployment(
        TokenParams memory _tokenParams,
        TimelockParams memory _timelockParams,
        GovernorParams memory _governorParams
    ) internal view {
        // Ownership: governor administers the timelock, and the timelock owns the governor's ProxyAdmin.
        _validateAddress("timelock admin", timelock.admin(), address(governor));
        _validateAddress("timelock pendingAdmin", timelock.pendingAdmin(), address(0));
        _validateAddress("ProxyAdmin owner", proxyAdmin.owner(), address(timelock));
        _validateAddress(
            "governor implementation",
            address(uint160(uint256(vm.load(address(governor), ERC1967Utils.IMPLEMENTATION_SLOT)))),
            address(governorImplementation)
        );

        // Timelock configuration.
        _validateUint("timelock delay", timelock.delay(), _timelockParams.delay);
        _validateUint("timelock MINIMUM_DELAY", timelock.MINIMUM_DELAY(), _timelockParams.minimumDelay);
        _validateUint("timelock GRACE_PERIOD", timelock.GRACE_PERIOD(), _timelockParams.gracePeriod);

        // Governor configuration.
        _validateAddress("governor timelock", governor.timelock(), address(timelock));
        _validateAddress("governor token", address(governor.token()), address(comp));
        _validateUint("governor votingDelay", governor.votingDelay(), _governorParams.votingDelay);
        _validateUint("governor votingPeriod", governor.votingPeriod(), _governorParams.votingPeriod);
        _validateUint("governor proposalThreshold", governor.proposalThreshold(), _governorParams.proposalThreshold);
        _validateUint("governor quorum", governor.quorum(governor.clock()), _governorParams.quorum);
        _validateUint(
            "governor lateQuorumVoteExtension",
            governor.lateQuorumVoteExtension(),
            _governorParams.lateQuorumVoteExtension
        );
        _validateAddress("governor whitelistGuardian", governor.whitelistGuardian(), _governorParams.whitelistGuardian);
        (address _proposalGuardian, uint96 _proposalGuardianExpiration) = governor.proposalGuardian();
        _validateAddress("governor proposalGuardian", _proposalGuardian, _governorParams.proposalGuardian.account);
        _validateUint(
            "governor proposalGuardian expiration",
            _proposalGuardianExpiration,
            _governorParams.proposalGuardian.expiration
        );
        _validateUint("governor next proposal ID", governor.getNextProposalId(), _governorParams.nextProposalId);

        // COMP distribution.
        for (uint256 _index = 0; _index < _tokenParams.allocations.length; _index += 1) {
            CompAllocation memory _allocation = _tokenParams.allocations[_index];
            if (comp.balanceOf(_allocation.recipient) < _allocation.amount) {
                revert(
                    string.concat(
                        "DeployTestnetGovernanceSystem: COMP allocation recipient ",
                        vm.toString(_allocation.recipient),
                        " holds less than its allocation after distribution"
                    )
                );
            }
        }
        _validateUint("timelock COMP balance", comp.balanceOf(address(timelock)), _tokenParams.timelockAllocation);
        _validateUint("broadcast transaction count", loggedTransactionCount, expectedTransactionCount);
    }

    function _validatePredictedAddress(string memory _label, address _actual, address _expected) internal view {
        if (_actual != _expected) {
            revert(
                string.concat(
                    "DeployTestnetGovernanceSystem: expected the ",
                    _label,
                    " at ",
                    vm.toString(_expected),
                    " but it was deployed to ",
                    vm.toString(_actual),
                    "; the deployment order no longer matches the address prediction"
                )
            );
        }
    }

    function _validateAddress(string memory _label, address _actual, address _expected) internal view {
        if (_actual != _expected) {
            revert(
                string.concat(
                    "DeployTestnetGovernanceSystem: ",
                    _label,
                    " is ",
                    vm.toString(_actual),
                    " but expected ",
                    vm.toString(_expected)
                )
            );
        }
    }

    function _validateUint(string memory _label, uint256 _actual, uint256 _expected) internal view {
        if (_actual != _expected) {
            revert(
                string.concat(
                    "DeployTestnetGovernanceSystem: ",
                    _label,
                    " is ",
                    vm.toString(_actual),
                    " but expected ",
                    vm.toString(_expected)
                )
            );
        }
    }
}
