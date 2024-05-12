// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../dev/Deployment.sol";
import "../interfaces/IStaking.sol";


contract StakingTest is Deployment
	{
    bytes32[] public poolIDs;

    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);
    address public constant charlie = address(0x3333);


	constructor()
		{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			initializeContracts();

		vm.prank(address(initialDistribution));
		zero.transfer(DEPLOYER, 100000000 ether);

		grantAccessAlice();
		grantAccessBob();
		grantAccessCharlie();
		grantAccessDeployer();
		grantAccessDefault();
		}


    function setUp() public
    	{
    	IERC20 token1 = new TestERC20("TEST", 18);
		IERC20 token2 = new TestERC20("TEST", 18);
		IERC20 token3 = new TestERC20("TEST", 18);

        poolIDs = new bytes32[](3);
        poolIDs[0] = PoolUtils.STAKED_ZERO;
       	poolIDs[1] = PoolUtils._poolID(token1, token2);
        poolIDs[2] = PoolUtils._poolID(token2, token3);

        // Whitelist lp
		vm.startPrank( address(dao) );
        poolsConfig.whitelistPool(  token1, token2);
        poolsConfig.whitelistPool(  token2, token3);
		vm.stopPrank();

		vm.prank(DEPLOYER);
		zero.transfer( address(this), 100000 ether );

        // This contract approves max to staking so that ZERO rewards can be added
        zero.approve(address(staking), type(uint256).max);

        // Alice gets some zero and pool lps and approves max to staking
        zero.transfer(alice, 100 ether);
        vm.prank(alice);
        zero.approve(address(staking), type(uint256).max);

        // Bob gets some zero and pool lps and approves max to staking
        zero.transfer(bob, 100 ether);
        vm.prank(bob);
        zero.approve(address(staking), type(uint256).max);

        // Charlie gets some zero and pool lps and approves max to staking
        zero.transfer(charlie, 100 ether);
        vm.prank(charlie);
        zero.approve(address(staking), type(uint256).max);
    	}


	function totalStakedForPool( bytes32 poolID ) public view returns (uint256)
		{
		bytes32[] memory _poolIDs = new bytes32[](1);
		_poolIDs[0] = poolID;

		return staking.totalSharesForPools(_poolIDs)[0];
		}


	// A unit test which tests a user stakes various amounts of ZERO tokens and checks that the user's freeXZERO, total shares of STAKED_ZERO and the contract's ZERO balance are updated correctly.
	function testStakingVariousAmounts() public {
	uint256 startingBalance = zero.balanceOf( address(staking) );

    // Alice stakes 5 ether of ZERO tokens
    vm.prank(alice);
    staking.stakeZERO(5 ether);
    assertEq(staking.userVeZERO(alice), 5 ether);
    assertEq(staking.userShareForPool(alice, PoolUtils.STAKED_ZERO), 5 ether);
    assertEq(zero.balanceOf(address(staking)) - startingBalance, 5 ether);


    // Bob stakes 10 ether of ZERO tokens
    vm.prank(bob);
    staking.stakeZERO(10 ether);
    assertEq(staking.userVeZERO(bob), 10 ether);
    assertEq(staking.userShareForPool(bob, PoolUtils.STAKED_ZERO), 10 ether);
    assertEq(zero.balanceOf(address(staking)) - startingBalance, 15 ether);

    // Charlie stakes 20 ether of ZERO tokens
    vm.prank(charlie);
    staking.stakeZERO(20 ether);
    assertEq(staking.userVeZERO(charlie), 20 ether);
    assertEq(staking.userShareForPool(charlie, PoolUtils.STAKED_ZERO), 20 ether);
    assertEq(zero.balanceOf(address(staking)) - startingBalance, 35 ether);

    // Alice stakes an additional 3 ether of ZERO tokens
    vm.prank(alice);
    staking.stakeZERO(3 ether);
    assertEq(staking.userVeZERO(alice), 8 ether);
    assertEq(staking.userShareForPool(alice, PoolUtils.STAKED_ZERO), 8 ether);
    assertEq(zero.balanceOf(address(staking)) - startingBalance, 38 ether);
    }


	// A unit test which tests a user trying to unstake more ZERO tokens than they have staked, and checks that the transaction reverts with an appropriate error message.
	function testUnstakeMoreThanStaked() public {
	// Alice stakes 5 ZERO
	vm.prank(alice);
	staking.stakeZERO(5 ether);

	// Try to unstake 10 ZERO, which is more than Alice has staked
	vm.expectRevert("Cannot unstake more than the amount staked");
	staking.unstake(10 ether, 4);
	}


	// A unit test which tests a user unstaking ZERO tokens with various numbers of weeks for the unstaking duration, including edge cases like minimum and maximum weeks allowed, and checks that the resulting claimable ZERO and completion time are calculated correctly.
	function testUnstakingZEROWithVariousDurations() public {

	vm.startPrank(alice);

    uint256 initialStake = 100 ether;

    // Alice stakes ZERO
    staking.stakeZERO(initialStake);

    // Set different unstaking durations
    uint256[] memory durations = new uint256[](3);
    durations[0] = stakingConfig.minUnstakeWeeks();
    durations[1] = 14;
    durations[2] = stakingConfig.maxUnstakeWeeks();

	// Test unstaking with different durations
	for (uint256 i = 0; i < durations.length; i++)
		{
		uint256 unstakeAmount = 20 ether;
		uint256 duration = durations[i];

		// Unstake ZERO
		uint256 unstakeID = staking.unstake(unstakeAmount, duration);
		Unstake memory unstake = staking.unstakeByID(unstakeID);

		// Check unstake info
		assertEq(unstake.wallet, alice);
		assertEq(unstake.unstakedVeZERO, unstakeAmount);
		assertEq(unstake.completionTime, block.timestamp + duration * 1 weeks);

		// Calculate expected claimable ZERO
		uint256 expectedClaimableZERO0 = staking.calculateUnstake(unstakeAmount, duration);
		uint256 expectedClaimableZERO;
		if ( i == 0 )
			expectedClaimableZERO = (unstakeAmount * stakingConfig.minUnstakePercent()) / 100;
		if ( i == 1 )
			expectedClaimableZERO =7840000000000000000;
		if ( i == 2 )
			expectedClaimableZERO =20 ether;

		assertEq(expectedClaimableZERO0, expectedClaimableZERO);
		assertEq(unstake.claimableZERO, expectedClaimableZERO);

		// Warp time to complete unstaking
		vm.warp(unstake.completionTime);

		// Recover ZERO
		uint256 zeroBalance = zero.balanceOf(alice);
		staking.recoverZERO(unstakeID);

		// Check recovered ZERO
		assertEq(zero.balanceOf(alice) - zeroBalance, expectedClaimableZERO);
		}
   	}


	function totalStakedOnPlatform() internal view returns (uint256)
		{
		bytes32[] memory pools = new bytes32[](1);
		pools[0] = PoolUtils.STAKED_ZERO;
	
		return staking.totalSharesForPools(pools)[0];
		}
		
		
	// A unit test which tests a user unstaking ZERO tokens, and checks that the user's freeXZERO, total shares of STAKED_ZERO, the unstakeByID mapping, and the user's unstakeIDs are updated correctly.
	function testUnstake() public {
    uint256 stakeAmount = 10 ether;

    vm.startPrank(alice);
    staking.stakeZERO(stakeAmount);

    uint256 unstakeAmount = 5 ether;
    uint256 numWeeks = 4;
	uint256 unstakeID = staking.unstake(unstakeAmount, numWeeks);
	Unstake memory unstake = staking.unstakeByID(unstakeID);

	assertEq(unstake.wallet, alice);
	assertEq(unstake.unstakedVeZERO, unstakeAmount);
	assertEq(unstake.completionTime, block.timestamp + numWeeks * (1 weeks));

	uint256 userFreeXZERO = staking.userVeZERO(alice);
	assertEq(userFreeXZERO, stakeAmount - unstakeAmount);

	uint256 totalStaked = totalStakedOnPlatform();
	assertEq(totalStaked, stakeAmount - unstakeAmount);

	uint256[] memory userUnstakeIDs = staking.userUnstakeIDs(alice);
	assertEq(userUnstakeIDs[userUnstakeIDs.length - 1], unstakeID);
    }


	// A unit test which tests a user cancelling an unstake request in various scenarios, such as before and after the unstake completion time, and checks that the user's freeXZERO, total shares of STAKED_ZERO, and the unstakeByID mapping are updated correctly.
	function testCancelUnstake() public {
	vm.startPrank(alice);

	// Alice stakes 10 ether
	staking.stakeZERO(10 ether);
	assertEq(staking.userVeZERO(alice), 10 ether);
	assertEq(totalStakedOnPlatform(), 10 ether);

	// Alice creates an unstake request with 5 ether for 3 weeks
	uint256 unstakeID = staking.unstake(5 ether, 3);
	assertEq(staking.userVeZERO(alice), 5 ether);
	assertEq(totalStakedOnPlatform(), 5 ether);

	// Alice cancels the unstake request before the completion time
	vm.warp(block.timestamp + 2 weeks);
	staking.cancelUnstake(unstakeID);
	assertEq(staking.userVeZERO(alice), 10 ether);
	assertEq(totalStakedOnPlatform(), 10 ether);
	assertTrue(uint256(staking.unstakeByID(unstakeID).status) == uint256(UnstakeState.CANCELLED));

	// Try to cancel the unstake again
	vm.expectRevert("Only PENDING unstakes can be cancelled");
	staking.cancelUnstake(unstakeID);

	// Alice creates another unstake request with 5 ether for 4 weeks
	unstakeID = staking.unstake(5 ether, 4);
	assertEq(staking.userVeZERO(alice), 5 ether);
	assertEq(totalStakedOnPlatform(), 5 ether);

	// Alice tries to cancel the unstake request after the completion time
	vm.warp(block.timestamp + 5 weeks);
	vm.expectRevert("Unstakes that have already completed cannot be cancelled");
	staking.cancelUnstake(unstakeID);

	// Alice's freeXZERO and total shares of STAKED_ZERO remain the same
	assertEq(staking.userVeZERO(alice), 5 ether);
	assertEq(totalStakedOnPlatform(), 5 ether);
	}


	// A unit test which tests a user recovering ZERO tokens after unstaking in various scenarios, such as early unstaking with a fee, and checks that the user's ZERO balance, the unstakeByID mapping, and the earlyUnstake fee distribution are updated correctly.
	function testRecoverZEROAfterUnstaking() public {
	vm.startPrank(alice);

	// Alice stakes 5 ether of ZERO
	staking.stakeZERO(5 ether);

	uint256 startingZeroSupply = zero.totalSupply();

	// Unstake with 3 weeks penalty
	uint256 unstakeID = staking.unstake(5 ether, 3);

	// Verify that unstake is pending
	Unstake memory u = staking.unstakeByID(unstakeID);
	assertEq(uint256(u.status), uint256(UnstakeState.PENDING));

	// Alice's xZERO balance should be 0
	assertEq(staking.userVeZERO(alice), 0 ether);

	// Advance time by 3 weeks
	vm.warp(block.timestamp + 3 * 1 weeks);

	// Alice recovers her ZERO
	staking.recoverZERO(unstakeID);

	// Verify that unstake is claimed
	u = staking.unstakeByID(unstakeID);
	assertEq(uint256(u.status), uint256(UnstakeState.CLAIMED));

	// Alice should have received the expected amount of ZERO
	uint256 claimableZERO = u.claimableZERO;
	assertEq(zero.balanceOf(alice), 95 ether + claimableZERO);

	// Verify the earlyUnstakeFee was burnt
	uint256 earlyUnstakeFee = u.unstakedVeZERO - claimableZERO;

	uint256 burnedZero = startingZeroSupply - zero.totalSupply();
	assertEq( burnedZero, earlyUnstakeFee);
	}



	// A unit test to check that users without exchange access cannot stakeZERO
	function testUserWithoutAccess() public
		{
		vm.expectRevert( "Sender does not have exchange access" );
		vm.prank(address(0xDEAD));
        staking.stakeZERO(1 ether);
		}


	// A unit test which tests the unstakesForUser function for a user with various numbers of unstake requests, and checks that the returned Unstake structs array is accurate.
	function testUnstakesForUser() public {
        vm.startPrank(alice);

        Unstake[] memory noUnstakes = staking.unstakesForUser(alice);
        assertEq( noUnstakes.length, 0 );

        // stake some ZERO
        uint256 amountToStake = 10 ether;
        staking.stakeZERO(amountToStake);

        staking.unstake(2 ether, 5);
        staking.unstake(3 ether, 6);
        staking.unstake(4 ether, 7);

        // unstake with different weeks to create multiple unstake requests
        Unstake[] memory unstakes = staking.unstakesForUser(alice);

        // Check the length of the returned array
        assertEq(unstakes.length, 3);

        // Check the details of each unstake struct
        Unstake memory unstake1 = unstakes[0];
        Unstake memory unstake2 = unstakes[1];
        Unstake memory unstake3 = unstakes[2];

        assertEq(uint256(unstake1.status), uint256(UnstakeState.PENDING));
        assertEq(unstake1.wallet, alice);
        assertEq(unstake1.unstakedVeZERO, 2 ether);

        assertEq(uint256(unstake2.status), uint256(UnstakeState.PENDING));
        assertEq(unstake2.wallet, alice);
        assertEq(unstake2.unstakedVeZERO, 3 ether);

        assertEq(uint256(unstake3.status), uint256(UnstakeState.PENDING));
        assertEq(unstake3.wallet, alice);
        assertEq(unstake3.unstakedVeZERO, 4 ether);
    }


	// A unit test which tests the userVeZERO function for various users and checks that the returned freeXZERO balance is accurate.
	function testUserBalanceXZERO2() public {
        // Alice stakes 5 ether
        vm.prank(alice);
        staking.stakeZERO(5 ether);
        assertEq(staking.userVeZERO(alice), 5 ether);

        // Bob stakes 10 ether
        vm.prank(bob);
        staking.stakeZERO(10 ether);
        assertEq(staking.userVeZERO(bob), 10 ether);

        // Charlie stakes 20 ether
        vm.prank(charlie);
        staking.stakeZERO(20 ether);
        assertEq(staking.userVeZERO(charlie), 20 ether);

        // Alice unstakes 2 ether
        vm.prank(alice);
        uint256 unstakeID = staking.unstake(2 ether, 5);
        Unstake memory unstakeInfo = staking.unstakeByID(unstakeID);
        assertEq(unstakeInfo.unstakedVeZERO, 2 ether);
        assertEq(staking.userVeZERO(alice), 3 ether);

        // Bob unstakes 5 ether
        vm.prank(bob);
        unstakeID = staking.unstake(5 ether, 5);
        unstakeInfo = staking.unstakeByID(unstakeID);
        assertEq(unstakeInfo.unstakedVeZERO, 5 ether);
        assertEq(staking.userVeZERO(bob), 5 ether);

        // Charlie unstakes 10 ether
        vm.prank(charlie);
        unstakeID = staking.unstake(10 ether, 5);
        unstakeInfo = staking.unstakeByID(unstakeID);
        assertEq(unstakeInfo.unstakedVeZERO, 10 ether);
        assertEq(staking.userVeZERO(charlie), 10 ether);
    }


	// A unit test which tests the totalStakedOnPlatform function and checks that the returned total amount of staked ZERO is accurate.
	function testUserBalanceXZERO() public {
        // Alice stakes 50 ether (ZERO)
        vm.prank(alice);
        staking.stakeZERO(50 ether);
        assertEq(staking.userVeZERO(alice), 50 ether);

        // Bob stakes 70 ether (ZERO)
        vm.prank(bob);
        staking.stakeZERO(70 ether);
        assertEq(staking.userVeZERO(bob), 70 ether);

        // Charlie stakes 30 ether (ZERO)
        vm.prank(charlie);
        staking.stakeZERO(30 ether);
        assertEq(staking.userVeZERO(charlie), 30 ether);

        // Alice unstakes 20 ether
        vm.prank(alice);
        uint256 aliceUnstakeID = staking.unstake(20 ether, 4);
        // Check Alice's new balance
        assertEq(staking.userVeZERO(alice), 30 ether);

        // Bob unstakes 50 ether
        vm.prank(bob);
        staking.unstake(50 ether, 4);
        // Check Bob's new balance
        assertEq(staking.userVeZERO(bob), 20 ether);

        // Charlie unstakes 10 ether
        vm.prank(charlie);
        staking.unstake(10 ether, 4);
        // Check Charlie's new balance
        assertEq(staking.userVeZERO(charlie), 20 ether);

        // Alice cancels unstake
        vm.prank(alice);
        staking.cancelUnstake(aliceUnstakeID);
        // Check Alice's new balance
        assertEq(staking.userVeZERO(alice), 50 ether);

        uint256 totalStaked = totalStakedOnPlatform();
       	assertEq(totalStaked, 90 ether);

    }


	// A unit test which tests the userUnstakeIDs function for various users and checks that the returned array of unstake IDs is accurate.
	function testUserUnstakeIDs() public {
        // Alice stakes 10 ether
        vm.startPrank(alice);
        staking.stakeZERO(10 ether);
        assertEq(staking.userVeZERO(alice), 10 ether);

        // Alice unstakes 5 ether for 3 weeks
        uint256 aliceUnstakeID1 = staking.unstake(5 ether, 3);
        assertEq(staking.unstakeByID(aliceUnstakeID1).unstakedVeZERO, 5 ether);

        // Alice unstakes another 2 ether for 2 weeks
        uint256 aliceUnstakeID2 = staking.unstake(2 ether, 2);
        assertEq(staking.unstakeByID(aliceUnstakeID2).unstakedVeZERO, 2 ether);

        // Check that Alice's unstake IDs are correct
        assertEq(staking.userUnstakeIDs(alice).length, 2);
        assertEq(staking.userUnstakeIDs(alice)[0], aliceUnstakeID1);
        assertEq(staking.userUnstakeIDs(alice)[1], aliceUnstakeID2);

		vm.stopPrank();

        // Bob stakes 20 ether
        vm.startPrank(bob);
        staking.stakeZERO(20 ether);
        assertEq(staking.userVeZERO(bob), 20 ether);

        // Bob unstakes 10 ether for 4 weeks
        uint256 bobUnstakeID1 = staking.unstake(10 ether, 4);
        assertEq(staking.unstakeByID(bobUnstakeID1).unstakedVeZERO, 10 ether);

        // Check that Bob's unstake IDs are correct
        assertEq(staking.userUnstakeIDs(bob).length, 1);
        assertEq(staking.userUnstakeIDs(bob)[0], bobUnstakeID1);

        // Charlie doesn't stake anything, so he should have no unstake IDs
        assertEq(staking.userUnstakeIDs(charlie).length, 0);
    }


	// A unit test which tests multiple users staking ZERO tokens simultaneously and checks that the users' freeXZERO, total shares of STAKED_ZERO, and the contract's ZERO balance are updated correctly without conflicts.
	function testSimultaneousStaking() public {
        uint256 initialZeroBalance = zero.balanceOf(address(staking));
        uint256 aliceStakeAmount = 10 ether;
        uint256 bobStakeAmount = 20 ether;
        uint256 charlieStakeAmount = 30 ether;

        // Alice stakes
        vm.prank(alice);
        staking.stakeZERO(aliceStakeAmount);

        // Bob stakes
        vm.prank(bob);
        staking.stakeZERO(bobStakeAmount);

        // Charlie stakes
        vm.prank(charlie);
        staking.stakeZERO(charlieStakeAmount);

        // Check that freeXZERO, totalShares and contract's ZERO balance are updated correctly
        assertEq(staking.userVeZERO(alice), aliceStakeAmount);
        assertEq(staking.userVeZERO(bob), bobStakeAmount);
        assertEq(staking.userVeZERO(charlie), charlieStakeAmount);

        assertEq(totalStakedForPool(PoolUtils.STAKED_ZERO), aliceStakeAmount + bobStakeAmount + charlieStakeAmount);
        assertEq(zero.balanceOf(address(staking)), initialZeroBalance + aliceStakeAmount + bobStakeAmount + charlieStakeAmount);
    }


	// A unit test which tests a user trying to stake a negative amount of ZERO tokens and checks that the transaction reverts with an appropriate error message.
	function testStakeNegativeAmount() public {
        uint256 initialBalance = staking.userVeZERO(alice);
        uint256 amountToStake = uint256(int256(-1));

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(alice);
        staking.stakeZERO(amountToStake);

        // Assert that Alice's balance remains unchanged
        assertEq(staking.userVeZERO(alice), initialBalance);
    }

	// A unit test which tests multiple users trying to cancel each other's unstake requests and checks that only the original staker can cancel the request.
	function testCancelUnstake2() public {
        uint256 amountToStake = 10 ether;

        // Alice stakes ZERO
        vm.prank(alice);
        staking.stakeZERO(amountToStake);
        assertEq(staking.userVeZERO(alice), amountToStake);

        // Alice unstakes
        vm.prank(alice);
        uint256 aliceUnstakeID = staking.unstake(amountToStake, 4);
        assertEq(staking.userVeZERO(alice), 0);

        // Bob tries to cancel Alice's unstake request, should revert
        vm.prank(bob);
        vm.expectRevert("Sender is not the original staker");
        staking.cancelUnstake(aliceUnstakeID);

        // Charlie tries to cancel Alice's unstake request, should revert
        vm.prank(charlie);
        vm.expectRevert("Sender is not the original staker");
        staking.cancelUnstake(aliceUnstakeID);

        // Alice cancels her unstake request
        vm.prank(alice);
        staking.cancelUnstake(aliceUnstakeID);
        assertEq(staking.userVeZERO(alice), amountToStake);

        // Verify unstake status is CANCELLED
        Unstake memory unstake = staking.unstakeByID(aliceUnstakeID);
        assertEq(uint256(unstake.status), uint256(UnstakeState.CANCELLED));
    }


	// A unit test which tests multiple users trying to recover each other's ZERO tokens after unstaking and checks that only the original staker can recover the tokens.
	 function testRecoverZero() public {
            // Alice, Bob and Charlie stake 50 ZERO each
            vm.prank(alice);
            staking.stakeZERO(50 ether);
            vm.prank(bob);
            staking.stakeZERO(50 ether);
            vm.prank(charlie);
            staking.stakeZERO(50 ether);

            // Ensure they have staked correctly
            assertEq(staking.userVeZERO(alice), 50 ether);
            assertEq(staking.userVeZERO(bob), 50 ether);
            assertEq(staking.userVeZERO(charlie), 50 ether);

            // They unstake after a week
            vm.prank(alice);
            uint256 aliceUnstakeID = staking.unstake(10 ether, 2);
            vm.prank(bob);
            uint256 bobUnstakeID = staking.unstake(20 ether, 2);
            vm.prank(charlie);
            uint256 charlieUnstakeID = staking.unstake(30 ether, 2);

            // Warp time by a week
            vm.warp(block.timestamp + 2 weeks);

            // They try to recover each other's ZERO
            vm.startPrank(alice);
            vm.expectRevert("Sender is not the original staker");
            staking.recoverZERO(bobUnstakeID);
            vm.expectRevert("Sender is not the original staker");
            staking.recoverZERO(charlieUnstakeID);
            vm.stopPrank();

            vm.startPrank(bob);
            vm.expectRevert("Sender is not the original staker");
            staking.recoverZERO(aliceUnstakeID);
            vm.expectRevert("Sender is not the original staker");
            staking.recoverZERO(charlieUnstakeID);
            vm.stopPrank();

            vm.startPrank(charlie);
            vm.expectRevert("Sender is not the original staker");
            staking.recoverZERO(aliceUnstakeID);
            vm.expectRevert("Sender is not the original staker");
            staking.recoverZERO(bobUnstakeID);
            vm.stopPrank();

            // They recover their own ZERO
            uint256 aliceZero = zero.balanceOf(alice);
	 		uint256 bobZero = zero.balanceOf(bob);
            uint256 charlieZero = zero.balanceOf(charlie);

            vm.prank(alice);
            staking.recoverZERO(aliceUnstakeID);
            vm.prank(bob);
            staking.recoverZERO(bobUnstakeID);
            vm.prank(charlie);
            staking.recoverZERO(charlieUnstakeID);

            // Check the amount of ZERO that was recovered
            // With a two week unstake, only 20% of the originally staked ZERO is recovered
            assertEq(zero.balanceOf(alice) - aliceZero, 2 ether);
            assertEq(zero.balanceOf(bob) - bobZero, 4 ether);
            assertEq(zero.balanceOf(charlie) - charlieZero, 6 ether);

            // Check the final xZERO balances
            assertEq(staking.userVeZERO(alice), 40 ether);
            assertEq(staking.userVeZERO(bob), 30 ether);
            assertEq(staking.userVeZERO(charlie), 20 ether);
        }


	// A unit test to check if the contract reverts when trying to stake an amount of ZERO greater than the user's balance.
	function testStakeExcessZERO() public {
		vm.startPrank(alice);

        uint256 initialAliceBalance = zero.balanceOf(alice);
        uint256 excessAmount = initialAliceBalance + 1 ether;

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        staking.stakeZERO(excessAmount);
    }


	// A unit test to check if the contract reverts when trying to unstake using an invalid unstakeID.
	function testInvalidUnstakeID() public
        {
        uint256 invalidUnstakeID = type(uint256).max;  // Assuming max uint256 is an invalid unstakeID

        vm.startPrank(alice);

        vm.expectRevert("Only PENDING unstakes can be claimed");
        staking.recoverZERO(invalidUnstakeID);
        }


	// A unit test to check if the contract reverts when trying to cancel an already completed unstake.
	function testCancelCompletedUnstakeRevert() public {
        // User Alice unstakes
        uint256 amountToStake = 10 ether;
        uint256 numWeeks = 6;

        vm.startPrank(alice);
        staking.stakeZERO(amountToStake);
        uint256 unstakeID = staking.unstake(amountToStake, numWeeks);

        // Increase block time to complete unstake
        uint256 secondsIntoTheFuture = numWeeks * 1 weeks;
        vm.warp(block.timestamp + secondsIntoTheFuture);

        // User Alice tries to cancel the completed unstake
        vm.expectRevert("Unstakes that have already completed cannot be cancelled");
        staking.cancelUnstake(unstakeID);
    }


	// A unit test to check if the contract reverts when trying to recover ZERO from a non-PENDING unstake.
	function testRecoverZEROFromNonPendingUnstake() public {
        uint256 amountToStake = 10 ether;
        uint256 numWeeks = 10;

        // Alice stakes some ZERO
        vm.startPrank(alice);
        staking.stakeZERO(amountToStake);

        // Alice unstakes the xZERO
        uint256 unstakeID = staking.unstake(amountToStake, numWeeks);

        // Wait for a few seconds
        vm.warp(block.timestamp + 1);

        // Alice cancels the unstake
        staking.cancelUnstake(unstakeID);

        // Now Alice tries to recover the ZERO from the cancelled unstake
        vm.expectRevert("Only PENDING unstakes can be claimed");
        staking.recoverZERO(unstakeID);
    }


	// A unit test to check if the contract reverts when trying to recover ZERO from an unstake that does not belong to the sender.
	function testRecoverZEROFromUnstakeNotBelongingToSender() public {

		uint256 aliceStartingBalance = zero.balanceOf(alice);

        // Alice stakes some ZERO
        vm.startPrank(alice);
        staking.stakeZERO(10 ether);

        // Alice unstakes
        uint256 unstakeID = staking.unstake(5 ether, 52);
        vm.stopPrank();

        // Bob tries to recover ZERO from Alice's unstake
        vm.startPrank(bob);
        vm.expectRevert("Unstake has not completed yet");
        staking.recoverZERO(unstakeID);

        // Warp into the future to complete unstaking duration
        vm.warp(block.timestamp + 52 weeks);

        // Bob tries to recover ZERO again from Alice's unstake after it completed
        vm.expectRevert("Sender is not the original staker");
        staking.recoverZERO(unstakeID);
		vm.stopPrank();

        // Alice should still be able to recover her ZERO
        vm.prank(alice);
        staking.recoverZERO(unstakeID);

        // Verify that Alice's ZERO balance increased
        assertEq(zero.balanceOf(alice), aliceStartingBalance - 5 ether);
        }


	// A unit test to check if the contract reverts when trying to stake ZERO without allowing the contract to spend ZERO on the user's behalf.
	function testStakeWithNoAllowance() public {
	vm.startPrank(alice);

	zero.approve( address(staking), 0 );

	// Alice stakes 5 ether of ZERO
	vm.expectRevert( "ERC20: insufficient allowance" );
	staking.stakeZERO(5 ether);
	}


	// A unit test to check if the contract reverts when trying to cancel an unstake that does not exist.
		function testCancelUnstakeNonExistent() public {
    		vm.startPrank(alice);

    		// Alice stakes 10 ether
    		staking.stakeZERO(10 ether);
    		assertEq(staking.userVeZERO(alice), 10 ether);
    		assertEq(totalStakedOnPlatform(), 10 ether);

    		// Alice creates an unstake request with 5 ether for 3 weeks
    		uint256 unstakeID = staking.unstake(5 ether, 3);
    		assertEq(staking.userVeZERO(alice), 5 ether);
    		assertEq(totalStakedOnPlatform(), 5 ether);

    		// Now we try to cancel a non-existent unstake request

    		// Add 10 to unstakeID to ensure it doesn't exist
    		unstakeID += 10;
    		vm.expectRevert("Only PENDING unstakes can be cancelled");
    		staking.cancelUnstake(unstakeID);
    	}


	// A unit test to check if the contract reverts when trying to unstake xZERO without first staking any ZERO.
	function testUnstakeWithoutStaking() public {
		// Alice tries to unstake 5 ether of xZERO, without having staked any ZERO
		vm.prank(alice);
		vm.expectRevert("Cannot unstake more than the amount staked");
		staking.unstake(5 ether, 4);
	}


	// A unit test which tests a user staking zero ZERO tokens, and checks an error occurs
	function testStakeZeroZero() public {
        vm.prank(alice);

        // Alice tries to stake 0 ether of ZERO tokens
        vm.expectRevert("Cannot increase zero share");
        staking.stakeZERO(0 ether);
    }


	// A unit test which tests a user able to recover ZERO tokens from multiple pending unstakes simultaneously and checks that the user's ZERO balance and each unstakeByID mapping are updated correctly.
	function testMultipleUnstakeRecovery() public {
        vm.startPrank(alice);

		staking.stakeZERO(60 ether);

        // Create multiple unstake requests
        uint256[] memory unstakeIDs = new uint256[](3);
        unstakeIDs[0] = staking.unstake(20 ether, 12);
        unstakeIDs[1] = staking.unstake(15 ether, 12);
        unstakeIDs[2] = staking.unstake(25 ether, 12);

        // Advance time by 12 weeks to complete unstaking
        vm.warp(block.timestamp + 12 * 1 weeks);

        // Recover ZERO for each unstake request
        for (uint256 i = 0; i < unstakeIDs.length; i++) {
            uint256 zeroBalance = zero.balanceOf(alice);
            staking.recoverZERO(unstakeIDs[i]);

            // Check recovered ZERO
            Unstake memory unstake = staking.unstakeByID(unstakeIDs[i]);
	        assertEq(uint256(unstake.status), uint256(UnstakeState.CLAIMED));
            assertEq(zero.balanceOf(alice) - zeroBalance, unstake.claimableZERO);
        }
    }


	// A unit test to check if the contract reverts when trying to stake ZERO with zero balance.
	function testStakeZEROWithZeroBalance() public {
        // Get initial balance
        uint256 initialZeroBalance = zero.balanceOf(alice);

        // Stake all ZERO tokens
        vm.startPrank(alice);
        staking.stakeZERO(initialZeroBalance);

        // Try to stake additional ZERO tokens when balance is 0
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        staking.stakeZERO(1 ether);
    }


	// A unit test which tests a user with multiple pending unstakes that have different completion times, and checks that the user can only recover ZERO tokens for the unstakes that have passed the completion time.
	function testMultiplePendingUnstakesWithDifferentCompletionTimes() public {
        vm.startPrank(alice);

        // Alice stakes 30 ether of ZERO
        staking.stakeZERO(30 ether);

        // Alice starts unstaking 10 ether with 2 weeks unstaking duration
        uint256 unstakeID1 = staking.unstake(10 ether, 2);
        uint256 completion1 = block.timestamp + 2 weeks;

        // Alice starts unstaking 10 ether with 5 weeks unstaking duration
        uint256 unstakeID2 = staking.unstake(10 ether, 5);
        uint256 completion2 = block.timestamp + 5 weeks;

        // Alice starts unstaking 10 ether with 7 weeks unstaking duration
        uint256 unstakeID3 = staking.unstake(10 ether, 7);
        uint256 completion3 = block.timestamp + 7 weeks;

        // Alice tries to recover ZERO before the first unstake completes
        vm.expectRevert("Unstake has not completed yet");
        staking.recoverZERO(unstakeID1);

        // Alice tries to recover ZERO after the first completion time but before the second
        vm.warp(completion1);
        staking.recoverZERO(unstakeID1);
        vm.expectRevert("Unstake has not completed yet");
        staking.recoverZERO(unstakeID2);

        // Alice tries to recover ZERO after the second completion time but before the third
        vm.warp(completion2);
        staking.recoverZERO(unstakeID2);
        vm.expectRevert("Unstake has not completed yet");
        staking.recoverZERO(unstakeID3);

        // Alice recovers ZERO after the third unstake completes
        vm.warp(completion3);
        staking.recoverZERO(unstakeID3);
    }


	// A unit test to check if a transaction is reverted when attempting to set the unstaking duration longer than the maximum weeks allowed for the unstake duration.
	function testUnstakeDurationTooLong() public {
            uint256 maxUnstakeWeeks = stakingConfig.maxUnstakeWeeks();

            vm.startPrank(alice);
            staking.stakeZERO(10 ether);

            vm.expectRevert("Unstaking duration too long");
            staking.unstake(5 ether, maxUnstakeWeeks + 1);
        }


	// A unit test to check if a transaction is reverted when attempting to set the unstaking duration shorter than the minimum weeks allowed for the unstake duration.
	function testUnstakeDurationTooShort() public {
            uint256 minUnstakeWeeks = stakingConfig.minUnstakeWeeks();

            vm.startPrank(alice);
            staking.stakeZERO(10 ether);

            vm.expectRevert("Unstaking duration too short");
            staking.unstake(5 ether, minUnstakeWeeks - 1);
        }


	// A unit test to check if the user's freeXZERO, total shares of STAKED_ZERO correctly decrease only by the unstaked amount (and not more than that) when a user makes an unstake request.
	function testUnstakingDecreasesOnlyByUnstakedAmount() public {
        // Alice stakes 10 ether of ZERO tokens
        vm.startPrank(alice);
        staking.stakeZERO(10 ether);
        assertEq(staking.userVeZERO(alice), 10 ether);
        assertEq(staking.userShareForPool(alice, PoolUtils.STAKED_ZERO), 10 ether);

        // Alice unstakes 5 ether of ZERO tokens
        uint256 unstakeAmount = 5 ether;
        staking.unstake(unstakeAmount, 4);

        // Check that Alice's freeXZERO and total shares of STAKED_ZERO have decreased only by the unstaked amount
        assertEq(staking.userVeZERO(alice), 10 ether - unstakeAmount);
        assertEq(staking.userShareForPool(alice, PoolUtils.STAKED_ZERO), 10 ether - unstakeAmount);

        // Try to unstake more than the remaining xZERO balance, expect to revert
        vm.expectRevert("Cannot unstake more than the amount staked");
        staking.unstake(10 ether - unstakeAmount + 1, 4);
    }


	// A unit test that checks the proper burning of ZERO tokens when the expeditedUnstakeFee is applied.
	function testExpeditedUnstakeBurnsZero() external {
        // Alice stakes ZERO to receive xZERO
        uint256 amountToStake = 10 ether;
        vm.prank(alice);
        staking.stakeZERO(amountToStake);

        // Alice unstakes all of her xZERO with the minimum unstake weeks to incur an expedited unstake fee
        uint256 unstakeWeeks = stakingConfig.minUnstakeWeeks();
        uint256 initialZeroSupply = zero.totalSupply();
        vm.prank(alice);
        uint256 unstakeID = staking.unstake(amountToStake, unstakeWeeks);

        // Warp block time to after the unstaking completion time
        uint256 completionTime = block.timestamp + unstakeWeeks * 1 weeks;
        vm.warp(completionTime);

        // Calculate the claimable ZERO (which would be less than the unstaked amount due to the expedited fee)
        uint256 claimableZERO = staking.calculateUnstake(amountToStake, unstakeWeeks);
        uint256 expeditedUnstakeFee = amountToStake - claimableZERO;

		uint256 existingBalance = zero.balanceOf(alice);

        // Alice recovers the ZERO after completing unstake
        vm.prank(alice);
        staking.recoverZERO(unstakeID);

        // Calculate the new total supply of ZERO after burning the expedited unstake fee
        uint256 newZeroSupply = zero.totalSupply();

        // Check if the expedited unstake fee was correctly burnt
        assertEq(newZeroSupply, initialZeroSupply - expeditedUnstakeFee);

        // Check if the correct amount of ZERO was returned to Alice after unstaking
        assertEq(zero.balanceOf(alice), existingBalance + claimableZERO);
    }



	// A unit test that checks proper access restriction for calling stakeZERO function.
	function testUserWithoutExchangeAccessCannotStakeZERO() public {
        vm.expectRevert("Sender does not have exchange access");
        vm.prank(address(0xdead));
        staking.stakeZERO(1 ether);
    }


	// A unit test that verifies the correct amount of xZERO is assigned to the user in relation to the staked ZERO.
	function testCorrectXZEROAssignment() public {
        // Assume Deployment set up the necessary initial distribution and approvals

        address user = alice; // Use Alice for the test

        // Arrange: Stake amounts ranging from 1 to 5 ether for testing
        uint256[] memory stakeAmounts = new uint256[](5);
        for (uint256 i = 0; i < stakeAmounts.length; i++)
          stakeAmounts[i] = (i + 1) * 1 ether;

        // Act and Assert:
        for (uint256 i = 0; i < stakeAmounts.length; i++)
        	{
        	uint256 startingStaked = staking.userVeZERO(user);

			// Alice stakes ZERO
			vm.prank(user);
			staking.stakeZERO(stakeAmounts[i]);

			uint256 amountStaked = staking.userVeZERO(user) - startingStaked;

			// Check that Alice is assigned the correct amount of xZERO
			assertEq(amountStaked, stakeAmounts[i], "Unexpected xZERO balance after staking");
			}
	    }


	// A unit test that ensures proper handling of edge cases for numWeeks in calculateUnstake (boundary values).
	function testCalculateUnstakeEdgeCases() public {
        uint256 unstakedVeZERO = 10 ether;

        // Test with minimum unstake weeks
        uint256 minUnstakeWeeks = stakingConfig.minUnstakeWeeks();
        vm.prank(address(staking));
        uint256 claimableZEROMin = staking.calculateUnstake(unstakedVeZERO, minUnstakeWeeks);
        uint256 expectedClaimableZEROMin = (unstakedVeZERO * stakingConfig.minUnstakePercent()) / 100;
        assertEq(claimableZEROMin, expectedClaimableZEROMin);

        // Test with maximum unstake weeks
        uint256 maxUnstakeWeeks = stakingConfig.maxUnstakeWeeks();
        vm.prank(address(staking));
        uint256 claimableZEROMax = staking.calculateUnstake(unstakedVeZERO, maxUnstakeWeeks);
        uint256 expectedClaimableZEROMax = unstakedVeZERO;
        assertEq(claimableZEROMax, expectedClaimableZEROMax);

        // Test with weeks one less than minimum
        vm.expectRevert("Unstaking duration too short");
        staking.calculateUnstake(unstakedVeZERO, minUnstakeWeeks - 1);

        // Test with weeks one more than maximum
        vm.expectRevert("Unstaking duration too long");
        staking.calculateUnstake(unstakedVeZERO, maxUnstakeWeeks + 1);
    }


	// A unit test that checks the correct user's unstakeIDs list is maintained after several unstakes and cancels.
	function testMaintainCorrectUnstakeIDsListAfterUnstakesAndCancels() public {
        // Alice stakes 25 ether which gives her 25 ether worth of xZERO
        vm.startPrank(alice);
        staking.stakeZERO(25 ether);

        // Alice performs 3 unstake operations with 5 ether each
        uint256 unstakeID1 = staking.unstake(5 ether, 4);
        uint256 unstakeID2 = staking.unstake(5 ether, 4);
        uint256 unstakeID3 = staking.unstake(5 ether, 4);

        // Verify that unstake IDs are recorded correctly
        uint256[] memory aliceUnstakeIDs = staking.userUnstakeIDs(alice);
        assertEq(aliceUnstakeIDs[0], unstakeID1);
        assertEq(aliceUnstakeIDs[1], unstakeID2);
        assertEq(aliceUnstakeIDs[2], unstakeID3);

        // Alice cancels her second unstake
        staking.cancelUnstake(unstakeID2);
        // Verify that second unstake ID now has a UnstakeState of CANCELLED
        Unstake memory canceledUnstake = staking.unstakeByID(unstakeID2);
        assertEq(uint256(canceledUnstake.status), uint256(UnstakeState.CANCELLED));

        // Alice performs an additional unstake operation with 5 ether
        uint256 unstakeID4 = staking.unstake(5 ether, 4);

        // Alice unstake IDs should still include the cancelled ID and the new unstake ID
        aliceUnstakeIDs = staking.userUnstakeIDs(alice);

        assertEq(aliceUnstakeIDs.length, 4); // Ensure we have 4 unstake IDs
        assertEq(aliceUnstakeIDs[0], unstakeID1);
        assertEq(aliceUnstakeIDs[1], unstakeID2);
        assertEq(aliceUnstakeIDs[2], unstakeID3);
        assertEq(aliceUnstakeIDs[3], unstakeID4);

        // All unstake IDs should correspond to the correct Unstake data
        assertEq(staking.unstakeByID(aliceUnstakeIDs[0]).unstakedVeZERO, 5 ether);
        assertEq(staking.unstakeByID(aliceUnstakeIDs[1]).unstakedVeZERO, 5 ether);
        assertEq(uint256(staking.unstakeByID(aliceUnstakeIDs[1]).status), uint256(UnstakeState.CANCELLED)); // This is the cancelled one
        assertEq(staking.unstakeByID(aliceUnstakeIDs[2]).unstakedVeZERO, 5 ether);
        assertEq(staking.unstakeByID(aliceUnstakeIDs[3]).unstakedVeZERO, 5 ether);

        vm.stopPrank();
    }


	// A unit test to verify proper permission checks for cancelUnstake and recoverZERO functions.
	function testPermissionChecksForCancelUnstakeAndRecoverZERO() public {
		uint256 stakeAmount = 10 ether;
		uint256 unstakeAmount = 5 ether;
		uint256 unstakeWeeks = 4;

		// Alice stakes ZERO
		vm.prank(alice);
		staking.stakeZERO(stakeAmount);

		// Alice tries to unstake
		vm.startPrank(alice);
		uint256 aliceUnstakeID = staking.unstake(unstakeAmount, unstakeWeeks);
		vm.stopPrank();

		// Bob should not be able to cancel Alice's unstake
		vm.startPrank(bob);
		vm.expectRevert("Sender is not the original staker");
		staking.cancelUnstake(aliceUnstakeID);
		vm.stopPrank();

		// Alice cancels her unstake
		vm.prank(alice);
		staking.cancelUnstake(aliceUnstakeID);

		// The xZERO balance should be as if nothing was unstaked since the unstake was cancelled
		assertEq(staking.userVeZERO(alice), stakeAmount);

		// Alice tries to unstake again
		vm.prank(alice);
		aliceUnstakeID = staking.unstake(unstakeAmount, unstakeWeeks);

		// Warp to the future beyond the unstake completion time
		vm.warp(block.timestamp + unstakeWeeks * 1 weeks);

		// Bob should not be able to recover ZERO from Alice's unstake
		vm.prank(bob);
		vm.expectRevert("Sender is not the original staker");
		staking.recoverZERO(aliceUnstakeID);

		// Alice recovers ZERO from her unstake
		vm.prank(alice);
		staking.recoverZERO(aliceUnstakeID);

		// Verify the xZERO balance decreased by unstaked amount and ZERO balance increased by claimed amount
		uint256 aliceXZeroBalance = staking.userVeZERO(alice);
		uint256 aliceZeroBalance = zero.balanceOf(alice);
		assertEq(aliceXZeroBalance, stakeAmount - unstakeAmount);

		Unstake memory unstake = staking.unstakeByID(aliceUnstakeID);

		// Started with 100 ether and staked 10 ether originally
		assertEq(aliceZeroBalance, 90 ether + unstake.claimableZERO);
	}


	// A unit test that ensures staking more than the user's ZERO balance fails appropriately.
	function testStakingMoreThanBalance() external {
        uint256 initialAliceBalance = zero.balanceOf(alice);
        uint256 excessiveAmount = initialAliceBalance + 1 ether;

        vm.startPrank(alice);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        staking.stakeZERO(excessiveAmount);

        vm.stopPrank();
    }


	// A unit test that confirms correct UnstakeState updates after cancelUnstake and recoverZERO calls.
	function testUnstakeStateUpdatesAfterCancelAndRecover() public {
        uint256 stakeAmount = 10 ether;
        uint256 unstakeAmount = 5 ether;
        uint256 unstakeDuration = 4;

        // Alice stakes
        vm.prank(alice);
        staking.stakeZERO(stakeAmount);

        // Alice initiates an unstake request
        vm.prank(alice);
        uint256 unstakeID = staking.unstake(unstakeAmount, unstakeDuration);

        // Check the initial state of the unstake
        Unstake memory initialUnstake = staking.unstakeByID(unstakeID);
        assertEq(uint256(initialUnstake.status), uint256(UnstakeState.PENDING), "Unstake should be pending");

        // Cancel the unstake request
        vm.prank(alice);
        staking.cancelUnstake(unstakeID);

        // Check the state of the unstake after cancellation
        Unstake memory cancelledUnstake = staking.unstakeByID(unstakeID);
        assertEq(uint256(cancelledUnstake.status), uint256(UnstakeState.CANCELLED), "Unstake should be cancelled");

        // Alice tries to recover ZERO after cancellation, which should fail
        vm.prank(alice);
        vm.expectRevert("Only PENDING unstakes can be claimed");
        staking.recoverZERO(unstakeID);

        // Alice initiates another unstake which she will attempt to recover
        vm.prank(alice);
        unstakeID = staking.unstake(unstakeAmount, unstakeDuration);

        // Advance time to after the unstake duration
        vm.warp(block.timestamp + 4 weeks);

        // Recover ZERO from the unstake
        vm.prank(alice);
        staking.recoverZERO(unstakeID);

        // Check the state of the unstake after recovery
        Unstake memory recoveredUnstake = staking.unstakeByID(unstakeID);
        assertEq(uint256(recoveredUnstake.status), uint256(UnstakeState.CLAIMED), "Unstake should be claimed");
    }


	// A unit test that confirms no ZERO is recoverable if recoverZERO is called on an unstake with UnstakeState.CANCELLED.
	function testCannotRecoverZEROFromCancelledUnstake() public {
        // Alice stakes 10 ZERO
        vm.startPrank(alice);
        uint256 amountToStake = 10 ether;
        staking.stakeZERO(amountToStake);

        // Alice unstakes 5 ZERO with 4 weeks duration
        uint256 numWeeks = 4;
        uint256 unstakeID = staking.unstake(5 ether, numWeeks);

        // Alice cancels the unstake
        staking.cancelUnstake(unstakeID);

        // Assert the unstake status is CANCELLED
        Unstake memory unstake = staking.unstakeByID(unstakeID);
        assertEq(uint256(unstake.status), uint256(UnstakeState.CANCELLED));

        // Attempt to recover ZERO should fail since unstake is cancelled
        vm.expectRevert("Only PENDING unstakes can be claimed");
        staking.recoverZERO(unstakeID);

        vm.stopPrank();
    }
	}
