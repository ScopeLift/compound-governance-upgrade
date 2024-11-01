// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.26;

import {BravoToCompoundGovernorUpgradeTest} from "contracts/test/helpers/BravoToCompoundGovernorUpgradeTest.sol";

/// 
contract BravoToCompoundUpgradeBeforeDeployTest is BravoToCompoundGovernorUpgradeTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function _useDeployedCompoundGovernor() internal pure override returns (bool) {
        // returning false indicates that a new CompoundGovernor should be deployed before the inherited tests are run.
        return false;
    }

    function _shouldPassAndExecuteUpgradeProposal() internal pure override returns (bool) {
        // returning false indicates the upgrade proposal should not be passed and executed before the inherited tests are run.
        return false;
    }
}
