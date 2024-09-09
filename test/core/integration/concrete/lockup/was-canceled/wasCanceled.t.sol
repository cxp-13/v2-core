// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22 <0.9.0;

import { Errors } from "src/core/libraries/Errors.sol";
import { Integration_Test } from "./../../../Integration.t.sol";
import { Lockup_Integration_Shared_Test } from "./../../../shared/lockup/Lockup.t.sol";

abstract contract WasCanceled_Integration_Concrete_Test is Integration_Test, Lockup_Integration_Shared_Test {
    uint256 internal defaultStreamId;

    function setUp() public virtual override(Integration_Test, Lockup_Integration_Shared_Test) { }

    function test_RevertGiven_Null() external {
        uint256 nullStreamId = 1729;
        vm.expectRevert(abi.encodeWithSelector(Errors.SablierLockup_Null.selector, nullStreamId));
        lockup.wasCanceled(nullStreamId);
    }

    modifier givenNotNull() {
        defaultStreamId = createDefaultStream();
        _;
    }

    function test_GivenCanceledStream() external givenNotNull {
        bool wasCanceled = lockup.wasCanceled(defaultStreamId);
        assertFalse(wasCanceled, "wasCanceled");
    }

    function test_GivenNotCanceledStream() external givenNotNull {
        lockup.cancel(defaultStreamId);
        bool wasCanceled = lockup.wasCanceled(defaultStreamId);
        assertTrue(wasCanceled, "wasCanceled");
    }
}
