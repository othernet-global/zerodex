// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../dev/Deployment.sol";
import "./TestStakingRewards.sol";


// This test derives from StakingRewards itself as there are no underived instances of StakingRewards
contract SharedRewardsTest is Deployment
	{
    bytes32[] public poolIDs;

    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);
    address public constant charlie = address(0x3333);

	TestStakingRewards public stakingRewards;


	constructor()
		{
		vm.prank(DEPLOYER);
		stakingRewards = new TestStakingRewards(exchangeConfig, poolsConfig, stakingConfig );
		}


    function setUp() public
    	{
		vm.prank(address(initialDistribution));
		zero.transfer(DEPLOYER, 100000000 ether);

    	IERC20 token1 = new TestERC20("TEST", 18);
		IERC20 token2 = new TestERC20("TEST", 18);

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token1, token2);

		vm.startPrank(DEPLOYER);
		zero.transfer( address(this), zero.balanceOf(DEPLOYER));
		vm.stopPrank();

		// Pools for testing
        poolIDs = new bytes32[](2);
        poolIDs[0] = PoolUtils.STAKED_ZERO;
        poolIDs[1] = PoolUtils._poolID(token1, token2);

        // This contract approves max so that ZERO rewards can be added
        zero.approve(address(stakingRewards), type(uint256).max);

        // Alice gets some zero and approves max
        zero.transfer(alice, 100 ether);
        vm.prank(alice);
        zero.approve(address(stakingRewards), type(uint256).max);

        // Bob gets some zero and approves max
        zero.transfer(bob, 100 ether);
        vm.prank(bob);
        zero.approve(address(stakingRewards), type(uint256).max);

        // Charlie gets some zero and approves max
        zero.transfer(charlie, 100 ether);
        vm.prank(charlie);
        zero.approve(address(stakingRewards), type(uint256).max);
    	}


	// A unit test that checks if a user can increase or decrease their share in a pool, considering the pool's validity, the cooldown period, and the amount being non-zero.
	function testIncreaseDecreaseShare() public {
	vm.startPrank(DEPLOYER);
	// Alice increases her share in pools[0] by 5 ether
	stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 5 ether, true);
	vm.stopPrank();

	// Check Alice's user share after increasing
	assertEq(stakingRewards.userShareForPool(alice, poolIDs[0]), 5 ether, "Alice's share should have increased" );

	// Alice tries to decrease her share by 6 ether, should fail due to exceeding user share
	vm.expectRevert("Cannot decrease more than existing user share");
	stakingRewards.externalDecreaseUserShare(alice, poolIDs[0], 6 ether, true);

	// Increase block time by 1 second
	vm.warp(block.timestamp + 1 );

	// Alice tries to decrease her share while in cooldown period, should fail
	vm.expectRevert("Must wait for the cooldown to expire");
	stakingRewards.externalDecreaseUserShare(alice, poolIDs[0], 4 ether, true);

	// Increase block time to pass the cooldown period
	uint256 cooldown = stakingConfig.modificationCooldown();
	vm.warp(block.timestamp + cooldown);

	// Alice decreases her share in pools[0] by 4 ether
	stakingRewards.externalDecreaseUserShare(alice, poolIDs[0], 4 ether, true);

	// Check Alice's user share after decreasing
	assertEq(stakingRewards.userShareForPool(alice, poolIDs[0]), 1 ether, "Alice's share should have decreased");
	}


	// A unit test that checks whether a user can successfully claim all rewards from multiple valid pools, and the correct amount of rewards are transferred to their wallet.
	function testClaimAllRewards() public {
	vm.startPrank(DEPLOYER);
    // Alice increases her share in pools[0] and pools[1] by 5 ether each
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 5 ether, true);
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 5 ether, true);
	vm.stopPrank();

    // Add rewards to the pools
    AddedReward[] memory addedRewards = new AddedReward[](2);
    addedRewards[0] = AddedReward(poolIDs[0], 10 ether);
    addedRewards[1] = AddedReward(poolIDs[1], 20 ether);
    stakingRewards.addZERORewards(addedRewards);

    // Check Alice's pending rewards in both pools
    uint256 pendingRewardPool0 = stakingRewards.userRewardForPool(alice, poolIDs[0]);
    uint256 pendingRewardPool1 = stakingRewards.userRewardForPool(alice, poolIDs[1]);
    assertEq(pendingRewardPool0, 10 ether);
    assertEq(pendingRewardPool1, 20 ether);

    // Check Alice's ZERO balance before claiming
    uint256 aliceZeroBalanceBefore = zero.balanceOf(alice);

    // Alice claims all rewards from both pools
    bytes32[] memory claimPools = new bytes32[](2);
    claimPools[0] = poolIDs[0];
    claimPools[1] = poolIDs[1];
    vm.prank(alice);
    stakingRewards.claimAllRewards(claimPools);

    // Check Alice's ZERO balance after claiming
    uint256 aliceZeroBalanceAfter = zero.balanceOf(alice);
    assertEq(aliceZeroBalanceAfter, aliceZeroBalanceBefore + pendingRewardPool0 + pendingRewardPool1);
    }


	// A unit test that checks if the user cannot claim rewards from invalid pools.
	function testClaimRewardsFromInvalidPools() public {
    // Prepare invalid pool
    bytes32 invalidPool = bytes32(uint256(0xDEAD));

    // Try to claim rewards from an invalid pool
    // It shouldn't revert, but will not return any rewards
    bytes32[] memory invalidPools = new bytes32[](1);
    invalidPools[0] = invalidPool;
    stakingRewards.claimAllRewards(invalidPools);

    // Verify no rewards were claimed
    uint256 aliceZeroBalanceBefore = zero.balanceOf(alice);
    assertEq(aliceZeroBalanceBefore, 100 ether);
    }


	// A unit test that checks if adding ZERO rewards to multiple valid pools updates the total rewards for each pool correctly and transfers the correct amount of ZERO from the sender to the contract.
	function testAddZERORewardsToMultiplePools() public {
    uint256 initialAliceZeroBalance = zero.balanceOf(alice);
    uint256 initialContractZeroBalance = zero.balanceOf(address(stakingRewards));

    uint256 expectedTotalRewardsPool0 = stakingRewards.totalRewards(poolIDs[0]) + 10 ether;
    uint256 expectedTotalRewardsPool1 = stakingRewards.totalRewards(poolIDs[1]) + 5 ether;

    AddedReward[] memory addedRewards = new AddedReward[](2);
    addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 10 ether});
    addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 5 ether});

    vm.prank(alice);
    stakingRewards.addZERORewards(addedRewards);

    uint256 expectedAliceZeroBalance = initialAliceZeroBalance - 15 ether;
    uint256 expectedContractZeroBalance = initialContractZeroBalance + 15 ether;

    assertEq(zero.balanceOf(alice), expectedAliceZeroBalance, "Alice's zero balance should decrease by 15 ether");
    assertEq(zero.balanceOf(address(stakingRewards)), expectedContractZeroBalance, "Contract's zero balance should increase by 15 ether");

    assertEq(stakingRewards.totalRewards(poolIDs[0]), expectedTotalRewardsPool0, "Total rewards for pool 0 should increase by 10 ether");
    assertEq(stakingRewards.totalRewards(poolIDs[1]), expectedTotalRewardsPool1, "Total rewards for pool 1 should increase by 5 ether");
    }


	// A unit test that checks if the user cannot add rewards to invalid pools.
	function testInvalidPoolCannotAddRewards() public {
    bytes32 invalidPool = bytes32(uint256(0xDEAD));
    uint256 initialTotalRewards = stakingRewards.totalRewardsForPools(poolIDs)[0];

    vm.expectRevert("Invalid pool");

    AddedReward[] memory addedRewards = new AddedReward[](2);
    addedRewards[0] = AddedReward({poolID: invalidPool, amountToAdd: 10 ether});
    stakingRewards.addZERORewards( addedRewards );

    uint256 newTotalRewards = stakingRewards.totalRewardsForPools(poolIDs)[0];
    assertEq(initialTotalRewards, newTotalRewards, "Rewards should not be added to an invalid pool");
    }


	// A unit test that checks if totalSharesForPools function returns the correct total shares for each specified pool.
	function testTotalSharesForPools() public {
		vm.startPrank(DEPLOYER);
        // Alice increases shares for both pools
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 10 ether, true);
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 5 ether, true);

        // Bob increases shares for both pools
        stakingRewards.externalIncreaseUserShare(bob, poolIDs[0], 20 ether, true);
        stakingRewards.externalIncreaseUserShare(bob, poolIDs[1], 15 ether, true);

        // Charlie increases shares for both pools
        stakingRewards.externalIncreaseUserShare(charlie, poolIDs[0], 30 ether, true);
        stakingRewards.externalIncreaseUserShare(charlie, poolIDs[1], 25 ether, true);
        vm.stopPrank();

        // Check total shares for pools
        uint256[] memory totalShares = stakingRewards.totalSharesForPools(poolIDs);
        assertEq(totalShares[0], 60 ether, "Total shares for pool 0 is incorrect");
        assertEq(totalShares[1], 45 ether, "Total shares for pool 1 is incorrect");
    }


	// A unit test that checks if stakingRewards.totalRewardsForPools function returns the correct total rewards for each specified pool.
	function testTotalRewardsForPools() public {
    // Add ZERO rewards for each pool
    AddedReward[] memory addedRewards = new AddedReward[](2);
    addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 50 ether});
    addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 75 ether});
    stakingRewards.addZERORewards(addedRewards);

    addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 25 ether});
    addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 10 ether});
    stakingRewards.addZERORewards(addedRewards);

    // Check total rewards for each pool
    uint256[] memory rewards = stakingRewards.totalRewardsForPools(poolIDs);

    assertEq(rewards[0], 75 ether, "Incorrect total rewards for STAKED_ZERO pool");
    assertEq(rewards[1], 85 ether, "Incorrect total rewards for LP pool");
    }


	// A unit test that checks if userPendingReward function returns the correct pending rewards for a user in a specified pool.
	function testUserPendingReward() public {
	vm.prank(DEPLOYER);
    // Alice stakes 5 LP tokens in pools[0]
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 10 ether, false);

    // Add 10 ether rewards to pools[0]
    zero.transfer(address(stakingRewards), 10 ether);
    AddedReward[] memory addedRewards = new AddedReward[](1);
    addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 10 ether});
    stakingRewards.addZERORewards(addedRewards);

    // Check pending rewards for Alice in pools[0], should be 10 ether
    uint256 pendingRewards = stakingRewards.userRewardForPool(alice, poolIDs[0]);
    assertEq(pendingRewards, 10 ether);

    // Add another 10 ether rewards to pools[0]
    zero.transfer(address(stakingRewards), 10 ether);
    stakingRewards.addZERORewards(addedRewards);

    // Check pending rewards for Alice in pools[0], should be 20 ether
    pendingRewards = stakingRewards.userRewardForPool(alice, poolIDs[0]);
    assertEq(pendingRewards, 20 ether);

    // Bob stakes 5 LP tokens in pools[0]
	vm.prank(DEPLOYER);
    stakingRewards.externalIncreaseUserShare(bob, poolIDs[0], 5 ether, false);

    // Add another 15 ether rewards to pools[0]
    // So Alice will get an additional 10 ether rewards and Bob will get an 5 ether rewards
    // as Alice has 10 ether share and bob has 5 ether rewards
    addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 15 ether});
    stakingRewards.addZERORewards(addedRewards);

    // Check pending rewards for Alice in pools[0]
    pendingRewards = stakingRewards.userRewardForPool(alice, poolIDs[0]);
    assertEq(pendingRewards, 30 ether);

    // Check pending rewards for Bob in pools[0]
    pendingRewards = stakingRewards.userRewardForPool(bob, poolIDs[0]);
    assertEq(pendingRewards, 5 ether);
    }


	// A unit test that checks if userRewardsForPools function returns the correct pending rewards for a user in multiple specified pools.
	function testUserRewardsForPools() public {
	vm.startPrank(DEPLOYER);
    // Alice increases her share in pools[0] by 5 ether and pools[1] by 2 ether
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 5 ether, false);
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 2 ether, false);
	vm.stopPrank();

    // Add rewards to the pools
    AddedReward[] memory addedRewards = new AddedReward[](2);
    addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 10 ether});
    addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 4 ether});
    stakingRewards.addZERORewards(addedRewards);

    // Check pending rewards for Alice
    uint256[] memory expectedRewards = new uint256[](2);
    expectedRewards[0] = 10 ether;
    expectedRewards[1] = 4 ether;
    uint256[] memory actualRewards = stakingRewards.userRewardsForPools(alice, poolIDs);

    for (uint256 i = 0; i < actualRewards.length; i++)
        assertEq(actualRewards[i], expectedRewards[i], "Incorrect pending rewards for Alice");

    // Warp 1 day into the future
    vm.warp(block.timestamp + 1 days);

    // Add more rewards to the pools
    addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 20 ether});
    addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 8 ether});
    stakingRewards.addZERORewards(addedRewards);

    // Update expected rewards for Alice
    expectedRewards[0] = 30 ether;
    expectedRewards[1] = 12 ether;
    actualRewards = stakingRewards.userRewardsForPools(alice, poolIDs);

    for (uint256 i = 0; i < actualRewards.length; i++) {
        assertEq(actualRewards[i], expectedRewards[i], "Incorrect pending rewards for Alice after warp");
    }
    }


	// A unit test that checks if userShareForPools function returns the correct user share for a user in multiple specified pools.
	function testUserShareForPools() public {
	vm.startPrank(DEPLOYER);
    // Alice stakes in both pools
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 10 ether, true);
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 20 ether, true);

    // Bob stakes in both pools
    stakingRewards.externalIncreaseUserShare(bob, poolIDs[0], 15 ether, true);
    stakingRewards.externalIncreaseUserShare(bob, poolIDs[1], 25 ether, true);
	vm.stopPrank();

    // Check user shares for both Alice and Bob
    uint256[] memory aliceShares = stakingRewards.userShareForPools(alice, poolIDs);
    uint256[] memory bobShares = stakingRewards.userShareForPools(bob, poolIDs);

    // Assert Alice's shares
    assertEq(aliceShares[0], 10 ether, "Alice's share in pool 0 should be 10 ether");
    assertEq(aliceShares[1], 20 ether, "Alice's share in pool 1 should be 20 ether");

    // Assert Bob's shares
    assertEq(bobShares[0], 15 ether, "Bob's share in pool 0 should be 15 ether");
    assertEq(bobShares[1], 25 ether, "Bob's share in pool 1 should be 25 ether");
    }


	// A unit test that checks if userCooldowns function returns the correct cooldown time remaining for a user in multiple specified pools.
	function testUserCooldowns() public {
		vm.startPrank(DEPLOYER);
        // Alice increases her share for both pools which will trigger the cooldown
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 10 ether, true);
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 5 ether, true);
		vm.stopPrank();

        // Get initial cooldowns for Alice in both pools
        uint256[] memory cooldownsInitial = stakingRewards.userCooldowns(alice, poolIDs);

        // Check if the initial cooldowns are equal to the expected modification cooldown
        uint256 expectedCooldown = stakingConfig.modificationCooldown();
        assertEq(cooldownsInitial[0], expectedCooldown, "Initial cooldown for pool 0 incorrect");
        assertEq(cooldownsInitial[1], expectedCooldown, "Initial cooldown for pool 1 incorrect");

        // Warp time forward by half the cooldown duration
        uint256 halfCooldown = expectedCooldown / 2;
        vm.warp(block.timestamp + halfCooldown);

        // Get the updated cooldowns for Alice in both pools
        uint256[] memory cooldownsAfterWarp = stakingRewards.userCooldowns(alice, poolIDs);

        // Check if the updated cooldowns are correct after warping time
        assertEq(cooldownsAfterWarp[0], halfCooldown, "Cooldown for pool 0 after warp incorrect");
        assertEq(cooldownsAfterWarp[1], halfCooldown, "Cooldown for pool 1 after warp incorrect");

		vm.prank(DEPLOYER);
		vm.expectRevert( "Must wait for the cooldown to expire" );
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 10 ether, true);

        // Warp time forward to the end of the cooldown
        vm.warp(block.timestamp + halfCooldown);

		vm.prank(DEPLOYER);
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 10 ether, true);

        // Get the final cooldowns for Alice in both pools
        uint256[] memory cooldownsFinal = stakingRewards.userCooldowns(alice, poolIDs);

        // Check if the final cooldowns are 0, indicating that the cooldown has expired
        assertEq(cooldownsFinal[0], expectedCooldown, "Final cooldown for pool 0 incorrect");
        assertEq(cooldownsFinal[1], 0, "Final cooldown for pool 1 incorrect");
    }


	// A unit test where alice, bob and charlie have multiple shares and share rewards
	function testMultipleSharesAndRewards() public {
		// Initial balances
		uint256 initialZeroAlice = zero.balanceOf(alice);
		uint256 initialZeroBob = zero.balanceOf(bob);
		uint256 initialZeroCharlie = zero.balanceOf(charlie);

		// Alice, Bob, and Charlie increase their shares
		vm.startPrank(DEPLOYER);
		stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 5 ether, false);
		stakingRewards.externalIncreaseUserShare(bob, poolIDs[0], 3 ether, false);
		stakingRewards.externalIncreaseUserShare(charlie, poolIDs[0], 2 ether, false);
		vm.stopPrank();

		// Add ZERO rewards
		AddedReward[] memory addedRewards = new AddedReward[](1);
		addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 100 ether});
		stakingRewards.addZERORewards(addedRewards);

		// Check initial rewards for Alice, Bob, and Charlie
		uint256 aliceReward = stakingRewards.userRewardForPool(alice, poolIDs[0]);
		uint256 bobReward = stakingRewards.userRewardForPool(bob, poolIDs[0]);
		uint256 charlieReward = stakingRewards.userRewardForPool(charlie, poolIDs[0]);

		assertEq(aliceReward, 50 ether);
		assertEq(bobReward, 30 ether);
		assertEq(charlieReward, 20 ether);

		// Warp the time forward
		vm.warp(block.timestamp + 60 days);

		// Add more ZERO rewards
		addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 200 ether});
		stakingRewards.addZERORewards(addedRewards);

		// Check updated rewards for Alice, Bob, and Charlie
		aliceReward = stakingRewards.userRewardForPool(alice, poolIDs[0]);
		bobReward = stakingRewards.userRewardForPool(bob, poolIDs[0]);
		charlieReward = stakingRewards.userRewardForPool(charlie, poolIDs[0]);

		assertEq(aliceReward, 150 ether);
		assertEq(bobReward, 90 ether);
		assertEq(charlieReward, 60 ether);

		// Alice, Bob, and Charlie claim all rewards
		bytes32[] memory poolsToClaim = new bytes32[](1);
		poolsToClaim[0] = poolIDs[0];
		vm.prank(alice);
		stakingRewards.claimAllRewards(poolsToClaim);
		vm.prank(bob);
		stakingRewards.claimAllRewards(poolsToClaim);
		vm.prank(charlie);
		stakingRewards.claimAllRewards(poolsToClaim);

		// Check that Alice, Bob, and Charlie have no pending rewards after claiming
		aliceReward = stakingRewards.userRewardForPool(alice, poolIDs[0]);
		bobReward = stakingRewards.userRewardForPool(bob, poolIDs[0]);
		charlieReward = stakingRewards.userRewardForPool(charlie, poolIDs[0]);

		assertEq(aliceReward, 0);
		assertEq(bobReward, 0);
		assertEq(charlieReward, 0);

		// Make sure the rewarded amount is what was expected
		uint256 rewardedZeroAlice = zero.balanceOf(alice) - initialZeroAlice;
		uint256 rewardedZeroBob = zero.balanceOf(bob) - initialZeroBob;
		uint256 rewardedZeroCharlie = zero.balanceOf(charlie) - initialZeroCharlie;

		assertEq(rewardedZeroAlice, 150 ether);
		assertEq(rewardedZeroBob, 90 ether);
		assertEq(rewardedZeroCharlie, 60 ether);
		}


	// A unit test that checks if the contract correctly updates the total rewards and transfers the correct amount of ZERO tokens when adding rewards to multiple pools with varying amounts.
	function testAddZERORewards() public {
		uint256 initialZeroBalanceAlice = zero.balanceOf(address(alice));

		uint256[] memory rewardsToAdd = new uint256[](2);
		rewardsToAdd[0] = 10 ether;
		rewardsToAdd[1] = 5 ether;

		AddedReward[] memory addedRewards = new AddedReward[](2);
		addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: rewardsToAdd[0]});
		addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: rewardsToAdd[1]});

		uint256[] memory expectedTotalRewards = new uint256[](2);
		expectedTotalRewards[0] = stakingRewards.totalRewards(poolIDs[0]) + rewardsToAdd[0];
		expectedTotalRewards[1] = stakingRewards.totalRewards(poolIDs[1]) + rewardsToAdd[1];

		vm.prank(alice);
		stakingRewards.addZERORewards(addedRewards);

		uint256[] memory actualTotalRewards = stakingRewards.totalRewardsForPools(poolIDs);
		assertEq(actualTotalRewards[0], expectedTotalRewards[0], "Total rewards for pool[0] are incorrect after adding ZERO rewards");
		assertEq(actualTotalRewards[1], expectedTotalRewards[1], "Total rewards for pool[1] are incorrect after adding ZERO rewards");

		uint256 expectedZeroBalanceAlice = initialZeroBalanceAlice - (rewardsToAdd[0] + rewardsToAdd[1]);
		assertEq(zero.balanceOf(address(alice)), expectedZeroBalanceAlice, "ZERO balance is incorrect after adding rewards");
		}


	// A unit test that checks if the user cannot claim rewards from pools with zero pending rewards.
	function testCannotClaimRewardsFromZeroPendingRewards() public {
		vm.startPrank(DEPLOYER);

		// Alice increases her share in both pools
		stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 10 ether, false);
		stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 10 ether, false);
		vm.stopPrank();

		// Warp time forward to simulate rewards generation
		vm.warp(block.timestamp + 10 days);

		// Ensure that pending rewards are zero for Alice
		assertEq(stakingRewards.userRewardForPool(alice, poolIDs[0]), 0, "Initial pending rewards should be zero[0]" );
		assertEq(stakingRewards.userRewardForPool(alice, poolIDs[1]), 0, "Initial pending rewards should be zero[1]" );

		// Attempt to claim rewards for Alice, expect zero pending rewards
		uint256 initialZeroBalanceAlice = zero.balanceOf(address(alice));
		vm.prank(alice);
		stakingRewards.claimAllRewards(poolIDs);

		assertEq(zero.balanceOf(address(alice)), initialZeroBalanceAlice, "No rewards should be claimed" );
		}


	// A unit test that checks if the totalSharesForPools, stakingRewards.totalRewardsForPools, userRewardsForPools, and userShareForPools functions return empty arrays when called with empty input arrays.
	function testEmptyInputArrays() public {
		bytes32[] memory emptyPools = new bytes32[](0);

		uint256[] memory totalShares = stakingRewards.totalSharesForPools(emptyPools);
//		uint256[] memory totalRewards = stakingRewards.totalRewardsForPools(emptyPools);
		uint256[] memory userRewards = stakingRewards.userRewardsForPools(alice, emptyPools);
		uint256[] memory userShares = stakingRewards.userShareForPools(alice, emptyPools);

		assertEq(totalShares.length, 0, "totalShares.length shoudl be zero" );
//		assertEq(stakingRewards.totalRewards.length, 0, "totalRewards.length should be zero" );
		assertEq(userRewards.length, 0, "userRewards.length should be zero" );
		assertEq(userShares.length, 0, "userShares.length should be zero" );
		}


	// A unit test that checks if the userCooldowns function returns an array of 0s for cooldown times when the user is not part of any of the specified pools.
	function testUserCooldownsWhenNotInPools() public {
    // Define the pools to check
    bytes32[] memory testPools = new bytes32[](2);
    testPools[0] = poolIDs[0];
    testPools[1] = poolIDs[1];

    // Get the user's cooldowns for the specified pools
    uint256[] memory cooldowns = stakingRewards.userCooldowns(alice, testPools);

    // Verify that the cooldown times are all 0
    for (uint256 i = 0; i < cooldowns.length; i++)
    	assertEq(cooldowns[i], 0, "Cooldown time should be 0 when the user is not part of any of the specified pools");
    }


	// A unit test that checks the system's handling of multiple users (Alice, Bob, and Charlie) performing a sequence of actions such as increasing and decreasing shares, adding rewards, and claiming rewards on a shared pool, and validates the correct updating of shares, rewards, and the pool's state.
	function testMultipleUsersActions() public {

	uint256 initialZeroBalanceAlice = zero.balanceOf(address(alice));
	uint256 initialZeroBalanceBob = zero.balanceOf(address(bob));
	uint256 initialZeroBalanceCharlie = zero.balanceOf(address(charlie));

    // Alice increases share by 20 ether
	vm.startPrank(DEPLOYER);
    stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 20 ether, false);

    // Bob increases share by 20 ether
    stakingRewards.externalIncreaseUserShare(bob, poolIDs[0], 20 ether, false);

    // Charlie increases share by 40 ether
    stakingRewards.externalIncreaseUserShare(charlie, poolIDs[0], 40 ether, false);
	vm.stopPrank();

    // Warp time forward by one day
    vm.warp(block.timestamp + 1 days);

	uint256 startingBalance = zero.balanceOf( address(stakingRewards) );

    AddedReward[] memory addedRewards = new AddedReward[](1);
    addedRewards[0] = AddedReward(poolIDs[0], 40 ether);
    stakingRewards.addZERORewards(addedRewards);

	uint256 added = zero.balanceOf(address(stakingRewards)) - startingBalance;
	assertEq( added, 40 ether );

    // Alice decreases share by 10 ether
    stakingRewards.externalDecreaseUserShare(alice, poolIDs[0], 10 ether, false);

	startingBalance = zero.balanceOf( address(stakingRewards) );

    // Bob claims rewards
    // Bob should claim 10
    vm.prank(bob);
    stakingRewards.claimAllRewards(poolIDs);

	uint256 removed = startingBalance - zero.balanceOf(address(stakingRewards));
	assertEq( removed, 10 ether );

    // Bob decreases share by 10 ether
    stakingRewards.externalDecreaseUserShare(bob, poolIDs[0], 10 ether, false);

	// Add another 60 rewards
    addedRewards[0] = AddedReward(poolIDs[0], 60 ether);
    stakingRewards.addZERORewards(addedRewards);

    // Warp time forward by 15 seconds
    vm.warp(block.timestamp + 15 seconds);

    // Charlie claims rewards
    vm.prank(charlie);
    stakingRewards.claimAllRewards(poolIDs);

    // Check pool state
    uint256 poolTotalShares = stakingRewards.totalShares(poolIDs[0]);
    uint256 poolTotalRewards = stakingRewards.totalRewards(poolIDs[0]);
    assertEq(poolTotalShares, 60 ether, "Incorrect total shares for pool");
    assertEq(poolTotalRewards, 90 ether, "Incorrect total rewards for pool");

    // Check Alice's state
    assertEq(stakingRewards.userShareForPool(alice,poolIDs[0]), 10 ether, "Incorrect share for Alice");
//    assertEq(aliceShareInfo.virtualRewards, 0, "Incorrect virtual rewards for Alice");

    // Check Bob's state
    assertEq(stakingRewards.userShareForPool(bob,poolIDs[0]), 10 ether, "Incorrect share for Bob");
//    assertEq(bobShareInfo.virtualRewards, 5 ether, "Incorrect virtual rewards for Bob");

    // Check Charlie's state
    assertEq(stakingRewards.userShareForPool(charlie,poolIDs[0]), 40 ether, "Incorrect share for Charlie");
//    assertEq(charlieShareInfo.virtualRewards, 60 ether, "Incorrect virtual rewards for Charlie");

    // Check pending rewards
	assertEq( stakingRewards.userRewardForPool(alice, poolIDs[0]), 15 ether, "Incorrect pending reward for alice" );
	assertEq( stakingRewards.userRewardForPool(bob, poolIDs[0]), 10 ether, "Incorrect pending reward for bob" );
	assertEq( stakingRewards.userRewardForPool(charlie, poolIDs[0]), 0 ether, "Incorrect pending reward for charlie" );

	// Check withdrawn rewards
	uint256 zeroBalanceAlice = zero.balanceOf(address(alice));
	uint256 zeroBalanceBob = zero.balanceOf(address(bob));
	uint256 zeroBalanceCharlie = zero.balanceOf(address(charlie));

	assertEq( zeroBalanceAlice - initialZeroBalanceAlice, 5 ether, "Incorrect withdrawn rewards for alice" );
	assertEq( zeroBalanceBob - initialZeroBalanceBob, 10 ether, "Incorrect withdrawn rewards for bob" );
	assertEq( zeroBalanceCharlie - initialZeroBalanceCharlie, 60 ether, "Incorrect withdrawn rewards for charlie" );
    }


    // A unit test that checks if the addZERORewards function limits the rewards to the amount of ZERO held by the sender.
    function testAddZERORewardsLimit() public {
        uint256 aliceBalanceBefore = zero.balanceOf(alice);
        uint256 excessiveRewards = aliceBalanceBefore + 1 ether;

        // Prepare excessive rewards array
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward( poolIDs[1], excessiveRewards );

        // Make alice the caller
        vm.startPrank(alice);

        // Expect revert because the rewards exceed the ZERO balance of Alice
        vm.expectRevert( "ERC20: transfer amount exceeds balance" );
        stakingRewards.addZERORewards(addedRewards);

        // Verify the ZERO balance of Alice hasn't changed
        uint256 aliceBalanceAfter = zero.balanceOf(alice);
        assertEq(aliceBalanceBefore, aliceBalanceAfter, "Alice's balance should not have changed");
    }


	// A unit test that checks if userPendingReward function returns zero for the users and pools with zero share and zero totalReward.
	function testUserPendingRewardWithZeroShareAndZeroRewards() public {
        // Check pending rewards for Alice in pools[0], should be 0 as the user share and total rewards is 0
        uint256 pendingRewards = stakingRewards.userRewardForPool(alice, poolIDs[0]);
        assertEq(pendingRewards, 0, "Pending Rewards should be zero");

        // Check pending rewards for Bob in pools[0], should be 0 as the user share and total rewards is 0
        pendingRewards = stakingRewards.userRewardForPool(bob, poolIDs[0]);
        assertEq(pendingRewards, 0, "Pending Rewards should be zero");

        // Check pending rewards for Charlie in pools[0], should be 0 as the user share and total rewards is 0
        pendingRewards = stakingRewards.userRewardForPool(charlie, poolIDs[0]);
        assertEq(pendingRewards, 0, "Pending Rewards should be zero");

        // Check pending rewards for Alice in pools[1], should be 0 as the user share and total rewards is 0
        pendingRewards = stakingRewards.userRewardForPool(alice, poolIDs[1]);
        assertEq(pendingRewards, 0, "Pending Rewards should be zero");

        // Check pending rewards for Bob in pools[1], should be 0 as the user share and total rewards is 0
        pendingRewards = stakingRewards.userRewardForPool(bob, poolIDs[1]);
        assertEq(pendingRewards, 0, "Pending Rewards should be zero");

        // Check pending rewards for Charlie in pools[1], should be 0 as the user share and total rewards is 0
        pendingRewards = stakingRewards.userRewardForPool(charlie, poolIDs[1]);
        assertEq(pendingRewards, 0, "Pending Rewards should be zero");
    }


	// A unit test that confirms that rewards cannot be claimed from pools where the user has no shares.
	function testClaimRewardsWithNoShares() public {
            vm.prank(DEPLOYER);
            // Alice increases her share in pools[0] by 5 ether
            stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 5 ether, true);

            // Add rewards to the pools
            AddedReward[] memory addedRewards = new AddedReward[](2);
            addedRewards[0] = AddedReward(poolIDs[0], 10 ether);
            addedRewards[1] = AddedReward(poolIDs[1], 20 ether);
            stakingRewards.addZERORewards(addedRewards);

            uint256 aliceZeroBalanceBeforeClaim = zero.balanceOf(alice);

            // Alice tries to claim all rewards from both pools
            bytes32[] memory claimPools = new bytes32[](2);
            claimPools[0] = poolIDs[0];
            claimPools[1] = poolIDs[1];
            vm.prank(alice);
            stakingRewards.claimAllRewards(claimPools);
            uint256 aliceZeroBalanceAfterClaim = zero.balanceOf(alice);

            // Verify that rewards were claimed from pool[0] where Alice had shares
            assertEq(aliceZeroBalanceAfterClaim, aliceZeroBalanceBeforeClaim + 10 ether, "Alice should have claimed rewards");

            // Alice tries to claim rewards from pools[1] where she has no shares.
            // It shouldn't revert, but will not return any rewards
            claimPools = new bytes32[](1);
            claimPools[0] = poolIDs[1];
            stakingRewards.claimAllRewards(claimPools);

            // Verify no rewards were claimed
            aliceZeroBalanceAfterClaim = zero.balanceOf(alice);
            assertEq(aliceZeroBalanceAfterClaim, aliceZeroBalanceBeforeClaim + 10 ether, "Alice should not be able to claim rewards");
        }


    // A unit test that confirms that rewards cannot be claimed from pools where the user has no shares
    function testRewardsCannotBeClaimedWithoutShares() public {
        vm.prank(alice);
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 5 ether, true);

        // Add rewards to poolIDs[0]
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward(poolIDs[0], 10 ether);
        stakingRewards.addZERORewards(addedRewards);

        // Warp time to ensure potential claim is possible
        vm.warp(block.timestamp + 1 days);

        // Bob attempts to claim rewards without having any shares in poolIDs[0]
        vm.prank(bob);
        stakingRewards.claimAllRewards(poolIDs);

        // Verify Bob's ZERO balance remains unchanged since he cannot claim without shares
        assertEq(zero.balanceOf(bob), 100 ether, "Bob's ZERO balance should not have changed");
    }



    // A unit test where alice, bob and charlie have multiple shares and share rewards
    function testAliceBobCharlieMultipleSharesAndShareRewards() public {
        // Initial ZERO transfers and approvals setup are asserted in setUp(), assumes each starts with 100 ether (10^20)

        // Alice, Bob, and Charlie stake their shares in the Zero pool (STAKED_ZERO)
        vm.prank(alice);
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 20 ether, false); // externalIncreaseUserShare is assumed

        vm.prank(bob);
        stakingRewards.externalIncreaseUserShare(bob, poolIDs[0], 30 ether, false); // externalIncreaseUserShare is assumed

        vm.prank(charlie);
        stakingRewards.externalIncreaseUserShare(charlie, poolIDs[0], 50 ether, false); // externalIncreaseUserShare is assumed

        // Admin then adds ZERO rewards to the pool
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward(poolIDs[0], 100 ether); // 100 ether reward is assumed to be for the pool


        vm.startPrank(alice);
        zero.approve(address(stakingRewards), type(uint256).max);
        stakingRewards.addZERORewards(addedRewards); // addZERORewards is assumed
		vm.stopPrank();

        // Warp forward to let the rewards distribute according to the shares
        vm.warp(block.timestamp + 1 days);

        // Retrieve user rewards for each
        uint256 aliceReward = stakingRewards.userRewardForPool(alice, poolIDs[0]);
        uint256 bobReward = stakingRewards.userRewardForPool(bob, poolIDs[0]);
        uint256 charlieReward = stakingRewards.userRewardForPool(charlie, poolIDs[0]);

        // Assert that Alice, Bob, and Charlie have the correct proportion of rewards relative to their shares
        assertEq(aliceReward, (20 ether * 100 ether) / (20 ether + 30 ether + 50 ether), "Incorrect Alice reward");
        assertEq(bobReward, (30 ether * 100 ether) / (20 ether + 30 ether + 50 ether), "Incorrect Bob reward");
        assertEq(charlieReward, (50 ether * 100 ether) / (20 ether + 30 ether + 50 ether), "Incorrect Charlie reward");

		uint256 aliceStartBalance = zero.balanceOf(alice);
		uint256 bobStartBalance = zero.balanceOf(bob);
		uint256 charlieStartBalance = zero.balanceOf(charlie);

        // Alice, Bob, and Charlie claim their rewards
        vm.prank(alice);
        stakingRewards.claimAllRewards(poolIDs);
        vm.prank(bob);
        stakingRewards.claimAllRewards(poolIDs);
        vm.prank(charlie);
        stakingRewards.claimAllRewards(poolIDs);

        // Assert their zero balances have increased by the reward amounts
        uint256 aliceEndBalance = zero.balanceOf(alice);
        uint256 bobEndBalance = zero.balanceOf(bob);
        uint256 charlieEndBalance = zero.balanceOf(charlie);

        assertEq(aliceEndBalance, aliceStartBalance + aliceReward, "Alice did not receive correct rewards");
        assertEq(bobEndBalance, bobStartBalance + bobReward, "Bob did not receive correct rewards");
        assertEq(charlieEndBalance, charlieStartBalance + charlieReward, "Charlie did not receive correct rewards");

        // Finally, assert their rewards are now zero after claiming
        assertEq(stakingRewards.userRewardForPool(alice, poolIDs[0]), 0, "Alice rewards not zeroed after claim");
        assertEq(stakingRewards.userRewardForPool(bob, poolIDs[0]), 0, "Bob rewards not zeroed after claim");
        assertEq(stakingRewards.userRewardForPool(charlie, poolIDs[0]), 0, "Charlie rewards not zeroed after claim");
    }


    // A unit test that checks if the contract correctly updates the total rewards and transfers the correct amount of ZERO tokens when adding rewards to multiple pools with varying amounts
	function testRewardUpdateAndTokenTransferMultiplePools() external {
        uint256 totalPoolRewardsBefore1 = stakingRewards.totalRewards(poolIDs[0]);
        uint256 totalPoolRewardsBefore2 = stakingRewards.totalRewards(poolIDs[1]);

        uint256 rewardAmountPool1 = 10 ether;
        uint256 rewardAmountPool2 = 20 ether;

        AddedReward[] memory rewardsToAdd = new AddedReward[](2);
        rewardsToAdd[0] = AddedReward(poolIDs[0], rewardAmountPool1);
        rewardsToAdd[1] = AddedReward(poolIDs[1], rewardAmountPool2);

		uint256 initialAliceZeroBalance = zero.balanceOf(alice);

        vm.prank(alice);
        stakingRewards.addZERORewards(rewardsToAdd);

        uint256 totalPoolRewardsAfter1 = stakingRewards.totalRewards(poolIDs[0]);
        uint256 totalPoolRewardsAfter2 = stakingRewards.totalRewards(poolIDs[1]);

        uint256 aliceBalanceAfter = zero.balanceOf(alice);

        assertEq(totalPoolRewardsAfter1, totalPoolRewardsBefore1 + rewardAmountPool1, "Incorrect total rewards for pool 1 after adding.");
        assertEq(totalPoolRewardsAfter2, totalPoolRewardsBefore2 + rewardAmountPool2, "Incorrect total rewards for pool 2 after adding.");
        assertEq(aliceBalanceAfter, initialAliceZeroBalance - (rewardAmountPool1 + rewardAmountPool2), "Incorrect ZERO token transfer amount." );
    }


    // A unit test that checks if adding ZERO rewards to multiple valid pools updates the total rewards for each pool correctly and transfers the correct amount of ZERO from the sender to the contract
    function testAddZERORewardsToMultiplePools2() public {
    	// Initial balance of alice and the contract
    	uint256 initialAliceZeroBalance = zero.balanceOf(alice);
    	uint256 initialContractZeroBalance = zero.balanceOf(address(stakingRewards));

    	// Rewards to add to each pool
    	uint256 rewardPool0 = 10 ether;
    	uint256 rewardPool1 = 5 ether;

    	// Expected total rewards after adding
    	uint256 expectedTotalRewardsPool0 = stakingRewards.totalRewards(poolIDs[0]) + rewardPool0;
    	uint256 expectedTotalRewardsPool1 = stakingRewards.totalRewards(poolIDs[1]) + rewardPool1;

    	// Prepare AddedReward array
    	AddedReward[] memory addedRewards = new AddedReward[](2);
    	addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: rewardPool0});
    	addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: rewardPool1});

    	// Alice adds rewards to multiple pools
    	vm.startPrank(alice);
    	stakingRewards.addZERORewards(addedRewards);
    	vm.stopPrank();

    	// Check total rewards for each pool
    	assertEq(stakingRewards.totalRewards(poolIDs[0]), expectedTotalRewardsPool0, "Total rewards for pool 0 should match expected value");
    	assertEq(stakingRewards.totalRewards(poolIDs[1]), expectedTotalRewardsPool1, "Total rewards for pool 1 should match expected value");

    	// Check the ZERO balance of alice and the contract
    	uint256 finalAliceZeroBalance = zero.balanceOf(alice);
    	uint256 finalContractZeroBalance = zero.balanceOf(address(stakingRewards));

    	assertEq(finalAliceZeroBalance, initialAliceZeroBalance - (rewardPool0 + rewardPool1), "Alice's ZERO balance should decrease by the total rewards added");
    	assertEq(finalContractZeroBalance, initialContractZeroBalance + (rewardPool0 + rewardPool1), "Contract's ZERO balance should increase by the total rewards added");
    }


    // A unit test that checks whether a user can successfully claim all rewards from multiple valid pools, and the correct amount of rewards are transferred to their wallet
	function testClaimAllRewardsMultipleValidPools() public {
        vm.startPrank(alice);
        // Alice increases her share in poolIDs[0] and poolIDs[1] by 5 ether each (external calls).
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[0], 5 ether, true);
        stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 5 ether, true);
        vm.stopPrank();

        // Add rewards to the pools (assuming external call function present).
        AddedReward[] memory addedRewards = new AddedReward[](2);
        addedRewards[0] = AddedReward(poolIDs[0], 10 ether);
        addedRewards[1] = AddedReward(poolIDs[1], 20 ether);
        vm.startPrank(alice);
        stakingRewards.addZERORewards(addedRewards);
        vm.stopPrank();

        // Check Alice's ZERO balance before claiming.
        uint256 aliceZeroBalanceBeforeClaim = zero.balanceOf(alice);

        // Alice claims all rewards from both pools (external calls).
        vm.prank(alice);
        stakingRewards.claimAllRewards(poolIDs);

        // Check Alice's ZERO balance after claiming.
        uint256 aliceZeroBalanceAfterClaim = zero.balanceOf(alice);
        uint256 expectedRewards = 10 ether + 20 ether;

        // Assert that Alice's after-claim balance is increased by the expected reward amount.
        assertEq(aliceZeroBalanceAfterClaim, aliceZeroBalanceBeforeClaim + expectedRewards, "Incorrect reward amount transferred to Alice");
    }


    // A unit test that checks if a user can increase or decrease their share in a pool, considering the pool's validity, the cooldown period, and the amount being non-zero
    function testUserCanIncreaseOrDecreaseShare() public {
        vm.startPrank(alice);

        // Increase Alice's share in a pool by a non-zero amount within the pool's validity
        bytes32 validPoolID = poolIDs[0]; // Assuming poolIDs[0] is a valid pool for the sake of this test
        uint256 increaseAmount = 5 ether;
        stakingRewards.externalIncreaseUserShare(alice, validPoolID, increaseAmount, true);

        // Check if the share has increased correctly
        uint256 aliceShareAfterIncrease = stakingRewards.userShareForPool(alice, validPoolID);
        assertEq(aliceShareAfterIncrease, increaseAmount, "Alice's share did not increase correctly");

        // Attempt to decrease share that exceeds existing user share, expect revert
        uint256 decreaseAmountExceeding = 6 ether;
        vm.expectRevert("Cannot decrease more than existing user share");
        stakingRewards.externalDecreaseUserShare(alice, validPoolID, decreaseAmountExceeding, true);

        // Attempt to decrease share during cooldown period, expect revert
        vm.warp(block.timestamp + 1); // Warp time by 1 second
        uint256 decreaseAmountWithinShare = 4 ether;
        vm.expectRevert("Must wait for the cooldown to expire");
        stakingRewards.externalDecreaseUserShare(alice, validPoolID, decreaseAmountWithinShare, true);

        // Warp time to pass cooldown period and decrease share
        uint256 cooldownPeriod = stakingConfig.modificationCooldown();
        vm.warp(block.timestamp + cooldownPeriod);
        stakingRewards.externalDecreaseUserShare(alice, validPoolID, decreaseAmountWithinShare, true);

        // Check if the share has decreased correctly
        uint256 aliceShareAfterDecrease = stakingRewards.userShareForPool(alice, validPoolID);
        uint256 expectedShareAfterDecrease = increaseAmount - decreaseAmountWithinShare;
        assertEq(aliceShareAfterDecrease, expectedShareAfterDecrease, "Alice's share did not decrease correctly");

        vm.stopPrank();
    }


	// From: https://github.com/code-423n4/2024-01-zeroy-findings/issues/341
    function testUserCanBrickRewards() public {
            vm.startPrank(DEPLOYER);
            // Alice is the first depositor to poolIDs[1] and she deposited the minimum amounts 101 and 101 of both tokens.
            // Hence, alice will get 202 shares.
            stakingRewards.externalIncreaseUserShare(alice, poolIDs[1], 202, true);
            assertEq(stakingRewards.userShareForPool(alice, poolIDs[1]), 202);
            vm.stopPrank();

            // Alice adds 100 ZERO as rewards to the pool.
            AddedReward[] memory addedRewards = new AddedReward[](1);
            addedRewards[0] = AddedReward(poolIDs[1], 100 ether);
            stakingRewards.addZERORewards(addedRewards);


            // Bob deposits 100 DAI and 100 USDS he will receive (202 * 100e8) / 101 = 200e18 shares.
            vm.startPrank(DEPLOYER);
            stakingRewards.externalIncreaseUserShare(bob, poolIDs[1], 200e18, true);
            assertEq(stakingRewards.userShareForPool(bob, poolIDs[1]), 200e18);
            vm.stopPrank();

            // Charlie deposits 10000 DAI and 10000 USDS he will receive (202 * 10000e8) / 101 = 20000e18 shares.
            vm.startPrank(DEPLOYER);
            stakingRewards.externalIncreaseUserShare(charlie, poolIDs[1], 20000e18, true);
            assertEq(stakingRewards.userShareForPool(charlie, poolIDs[1]), 20000e18);
            vm.stopPrank();

            // Observe how virtual rewards are broken.
            uint256 virtualRewardsAlice = stakingRewards.userVirtualRewardsForPool(alice, poolIDs[1]);
            uint256 virtualRewardsBob = stakingRewards.userVirtualRewardsForPool(bob, poolIDs[1]);
            uint256 virtualRewardsCharlie = stakingRewards.userVirtualRewardsForPool(charlie, poolIDs[1]);

            console.log("Alice virtual rewards %s", virtualRewardsAlice);
            console.log("Bob virtual rewards %s", virtualRewardsBob);
            console.log("Charlie virtual rewards %s", virtualRewardsCharlie);

            // Observe the amount of claimable rewards.
            uint256 aliceRewardAfter = stakingRewards.userRewardForPool(alice, poolIDs[1]);
            uint256 bobRewardAfter = stakingRewards.userRewardForPool(bob, poolIDs[1]);
            uint256 charlieRewardAfter = stakingRewards.userRewardForPool(charlie, poolIDs[1]);

            console.log("Alice rewards %s", aliceRewardAfter);
            console.log("Bob rewards %s", bobRewardAfter);
            console.log("Charlie rewards %s", charlieRewardAfter);

            // The sum of claimable rewards is greater than 1000e18 ZERO.
            uint256 sumOfRewards = aliceRewardAfter + bobRewardAfter + charlieRewardAfter;
            console.log("All rewards &s", sumOfRewards);

            bytes32[] memory poolIDs2;

            poolIDs2 = new bytes32[](1);

            poolIDs2[0] = poolIDs[1];

            // Fixed in: https://github.com/othernet-global/zeroy-io/commit/0bb763cc67e6a30a97d8b157f7e5954692b3dd68
//            vm.expectRevert("ERC20: transfer amount exceeds balance");
            vm.startPrank(charlie);
            stakingRewards.claimAllRewards(poolIDs2);
            vm.stopPrank();
                           }
	}
