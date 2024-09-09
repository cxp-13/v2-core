// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22 <0.9.0;

import { Lockup } from "src/core/types/DataTypes.sol";
import { Integration_Test } from "./../../../Integration.t.sol";
import { WithdrawMax_Integration_Shared_Test } from "./../../../shared/lockup/withdrawMax.t.sol";

abstract contract WithdrawMax_Integration_Concrete_Test is Integration_Test, WithdrawMax_Integration_Shared_Test {
    function setUp() public virtual override(Integration_Test, WithdrawMax_Integration_Shared_Test) {
        WithdrawMax_Integration_Shared_Test.setUp();
    }

    function test_GivenEndTimeNotInFuture() external {
        // Warp to the stream's end.
        vm.warp({ newTimestamp: defaults.END_TIME() + 1 seconds });

        // Expect the ERC-20 assets to be transferred to the Recipient.
        expectCallToTransfer({ to: users.recipient, value: defaults.DEPOSIT_AMOUNT() });

        // It should emit a {WithdrawFromLockupStream} event.
        vm.expectEmit({ emitter: address(lockup) });
        emit WithdrawFromLockupStream({
            streamId: defaultStreamId,
            to: users.recipient,
            amount: defaults.DEPOSIT_AMOUNT(),
            asset: dai
        });

        // Make the max withdrawal.
        uint128 actualReturnedValue = lockup.withdrawMax({ streamId: defaultStreamId, to: users.recipient });

        // It should return the withdrawn amount.
        uint128 expectedReturnedValue = defaults.DEPOSIT_AMOUNT();
        assertEq(actualReturnedValue, expectedReturnedValue, "returnValue");

        // It should update the withdrawn amount.
        uint128 actualWithdrawnAmount = lockup.getWithdrawnAmount(defaultStreamId);
        uint128 expectedWithdrawnAmount = defaults.DEPOSIT_AMOUNT();
        assertEq(actualWithdrawnAmount, expectedWithdrawnAmount, "withdrawnAmount");

        // It should mark the stream as depleted.
        Lockup.Status actualStatus = lockup.statusOf(defaultStreamId);
        Lockup.Status expectedStatus = Lockup.Status.DEPLETED;
        assertEq(actualStatus, expectedStatus);

        // It should make the stream not cancelable.
        bool isCancelable = lockup.isCancelable(defaultStreamId);
        assertFalse(isCancelable, "isCancelable");

        // Assert that the not burned NFT.
        address actualNFTowner = lockup.ownerOf({ tokenId: defaultStreamId });
        address expectedNFTOwner = users.recipient;
        assertEq(actualNFTowner, expectedNFTOwner, "NFT owner");
    }

    function test_GivenEndTimeInFuture() external {
        // Simulate the passage of time.
        vm.warp({ newTimestamp: defaults.WARP_26_PERCENT() });

        // Get the withdraw amount.
        uint128 expectedWithdrawnAmount = lockup.withdrawableAmountOf(defaultStreamId);

        // Expect the assets to be transferred to the Recipient.
        expectCallToTransfer({ to: users.recipient, value: expectedWithdrawnAmount });

        // It should emit a {WithdrawFromLockupStream} event.
        vm.expectEmit({ emitter: address(lockup) });
        emit WithdrawFromLockupStream({
            streamId: defaultStreamId,
            to: users.recipient,
            amount: expectedWithdrawnAmount,
            asset: dai
        });

        // Make the max withdrawal.
        uint128 actualWithdrawnAmount = lockup.withdrawMax({ streamId: defaultStreamId, to: users.recipient });

        // It should return the withdrawable amount.
        assertEq(actualWithdrawnAmount, expectedWithdrawnAmount, "withdrawnAmount");

        // Assert that the stream's status is still "STREAMING".
        Lockup.Status actualStatus = lockup.statusOf(defaultStreamId);
        Lockup.Status expectedStatus = Lockup.Status.STREAMING;
        assertEq(actualStatus, expectedStatus);
    }
}
