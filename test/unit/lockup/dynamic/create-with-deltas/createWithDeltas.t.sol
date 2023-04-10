// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ud2x18 } from "@prb/math/UD2x18.sol";
import { Solarray } from "solarray/Solarray.sol";

import { ISablierV2LockupDynamic } from "src/interfaces/ISablierV2LockupDynamic.sol";
import { Errors } from "src/libraries/Errors.sol";
import { LockupDynamic } from "src/types/DataTypes.sol";

import { Dynamic_Unit_Test } from "../Dynamic.t.sol";

contract CreateWithDeltas_Dynamic_Unit_Test is Dynamic_Unit_Test {
    uint256 internal streamId;

    function setUp() public virtual override {
        Dynamic_Unit_Test.setUp();

        // Load the stream id.
        streamId = dynamic.nextStreamId();
    }

    /// @dev it should revert.
    function test_RevertWhen_DelegateCall() external {
        bytes memory callData = abi.encodeCall(ISablierV2LockupDynamic.createWithDeltas, defaultParams.createWithDeltas);
        (bool success, bytes memory returnData) = address(dynamic).delegatecall(callData);
        expectRevertDueToDelegateCall(success, returnData);
    }

    modifier whenNoDelegateCall() {
        _;
    }

    /// @dev it should revert.
    function test_RevertWhen_LoopCalculationOverflowsBlockGasLimit() external whenNoDelegateCall {
        LockupDynamic.SegmentWithDelta[] memory segments = new LockupDynamic.SegmentWithDelta[](250_000);
        vm.expectRevert(bytes(""));
        createDefaultStreamWithDeltas(segments);
    }

    modifier whenLoopCalculationsDoNotOverflowBlockGasLimit() {
        _;
    }

    function test_RevertWhen_DeltasZero() external whenNoDelegateCall whenLoopCalculationsDoNotOverflowBlockGasLimit {
        uint40 startTime = getBlockTimestamp();
        LockupDynamic.SegmentWithDelta[] memory segments = defaultParams.createWithDeltas.segments;
        segments[1].delta = 0;
        uint256 index = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.SablierV2LockupDynamic_SegmentMilestonesNotOrdered.selector,
                index,
                startTime + segments[0].delta,
                startTime + segments[0].delta
            )
        );
        createDefaultStreamWithDeltas(segments);
    }

    modifier whenDeltasNotZero() {
        _;
    }

    function test_RevertWhen_MilestonesCalculationsOverflows_StartTimeNotLessThanFirstSegmentMilestone()
        external
        whenNoDelegateCall
        whenLoopCalculationsDoNotOverflowBlockGasLimit
        whenDeltasNotZero
    {
        unchecked {
            uint40 startTime = getBlockTimestamp();
            LockupDynamic.SegmentWithDelta[] memory segments = defaultParams.createWithDeltas.segments;
            segments[0].delta = UINT40_MAX;
            vm.expectRevert(
                abi.encodeWithSelector(
                    Errors.SablierV2LockupDynamic_StartTimeNotLessThanFirstSegmentMilestone.selector,
                    startTime,
                    startTime + segments[0].delta
                )
            );
            createDefaultStreamWithDeltas(segments);
        }
    }

    function test_RevertWhen_MilestonesCalculationsOverflows_SegmentMilestonesNotOrdered()
        external
        whenNoDelegateCall
        whenLoopCalculationsDoNotOverflowBlockGasLimit
        whenDeltasNotZero
    {
        unchecked {
            uint40 startTime = getBlockTimestamp();

            // Create new segments that overflow when the milestones are eventually calculated.
            LockupDynamic.SegmentWithDelta[] memory segments = new LockupDynamic.SegmentWithDelta[](2);
            segments[0] = LockupDynamic.SegmentWithDelta({ amount: 0, exponent: ud2x18(1e18), delta: startTime + 1 });
            segments[1] = LockupDynamic.SegmentWithDelta({
                amount: DEFAULT_SEGMENTS_WITH_DELTAS[0].amount,
                exponent: DEFAULT_SEGMENTS_WITH_DELTAS[0].exponent,
                delta: UINT40_MAX
            });

            // Expect a {SegmentMilestonesNotOrdered} error.
            uint256 index = 1;
            vm.expectRevert(
                abi.encodeWithSelector(
                    Errors.SablierV2LockupDynamic_SegmentMilestonesNotOrdered.selector,
                    index,
                    startTime + segments[0].delta,
                    startTime + segments[0].delta + segments[1].delta
                )
            );

            // Create the stream.
            createDefaultStreamWithDeltas(segments);
        }
    }

    modifier whenMilestonesCalculationsDoNotOverflow() {
        _;
    }

    function test_CreateWithDeltas()
        external
        whenNoDelegateCall
        whenLoopCalculationsDoNotOverflowBlockGasLimit
        whenDeltasNotZero
        whenMilestonesCalculationsDoNotOverflow
    {
        // Make the sender the stream's funder
        address funder = users.sender;

        // Load the initial protocol revenues.
        uint128 initialProtocolRevenues = dynamic.protocolRevenues(DEFAULT_ASSET);

        // Expect the assets to be transferred from the funder to {SablierV2LockupDynamic}.
        expectTransferFromCall({
            from: funder,
            to: address(dynamic),
            amount: DEFAULT_DEPOSIT_AMOUNT + DEFAULT_PROTOCOL_FEE_AMOUNT
        });

        // Expect the broker fee to be paid to the broker.
        expectTransferFromCall({ from: funder, to: users.broker, amount: DEFAULT_BROKER_FEE_AMOUNT });

        // Expect a {CreateLockupDynamicStream} event to be emitted.
        vm.expectEmit({ emitter: address(dynamic) });
        emit CreateLockupDynamicStream({
            streamId: streamId,
            funder: funder,
            sender: users.sender,
            recipient: users.recipient,
            amounts: DEFAULT_LOCKUP_CREATE_AMOUNTS,
            asset: DEFAULT_ASSET,
            cancelable: true,
            segments: DEFAULT_SEGMENTS,
            range: DEFAULT_DYNAMIC_RANGE,
            broker: users.broker
        });

        // Create the stream.
        createDefaultStreamWithDeltas();

        // Assert that the stream has been created.
        LockupDynamic.Stream memory actualStream = dynamic.getStream(streamId);
        assertEq(actualStream, defaultStream);

        // Assert that the next stream id has been bumped.
        uint256 actualNextStreamId = dynamic.nextStreamId();
        uint256 expectedNextStreamId = streamId + 1;
        assertEq(actualNextStreamId, expectedNextStreamId, "nextStreamId");

        // Assert that the protocol fee has been recorded.
        uint128 actualProtocolRevenues = dynamic.protocolRevenues(DEFAULT_ASSET);
        uint128 expectedProtocolRevenues = initialProtocolRevenues + DEFAULT_PROTOCOL_FEE_AMOUNT;
        assertEq(actualProtocolRevenues, expectedProtocolRevenues, "protocolRevenues");

        // Assert that the NFT has been minted.
        address actualNFTOwner = dynamic.ownerOf({ tokenId: streamId });
        address expectedNFTOwner = defaultParams.createWithDeltas.recipient;
        assertEq(actualNFTOwner, expectedNFTOwner, "NFT owner");
    }
}
