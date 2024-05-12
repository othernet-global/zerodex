// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../dev/Deployment.sol";

contract TestRewardsEmitter is Deployment
	{
    bytes32[] public poolIDs;

    IERC20 public token1;
    IERC20 public token2;
    IERC20 public token3;

    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);
    address public constant charlie = address(0x3333);


    function setUp() public
    	{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			initializeContracts();

		grantAccessAlice();
		grantAccessBob();
		grantAccessCharlie();
		grantAccessDeployer();
		grantAccessDefault();

		finalizeBootstrap();

		vm.prank(address(daoVestingWallet));
		zero.transfer(DEPLOYER, 1000000 ether);

    	token1 = new TestERC20("TEST", 18);
		token2 = new TestERC20("TEST", 18);
		token3 = new TestERC20("TEST", 18);

        bytes32 pool1 = PoolUtils._poolID(token1, token2);
        bytes32 pool2 = PoolUtils._poolID(token2, token3);

        poolIDs = new bytes32[](2);
        poolIDs[0] = pool1;
        poolIDs[1] = pool2;

        // Whitelist
        vm.startPrank(address(dao));
        poolsConfig.whitelistPool(  token1, token2);
        poolsConfig.whitelistPool(  token2, token3);
        vm.stopPrank();

        vm.startPrank(DEPLOYER);
        zero.transfer(address(this), 100000 ether);
        zero.approve(address(liquidityRewardsEmitter), type(uint256).max);
        vm.stopPrank();

        // This contract approves max to staking so that ZERO rewards can be added
        zero.approve(address(liquidityRewardsEmitter), type(uint256).max);

        // Alice gets some zero and tokens
        zero.transfer(alice, 1000 ether);
        token1.transfer(alice, 1000 ether);
        token2.transfer(alice, 1000 ether);
        token3.transfer(alice, 1000 ether);

        vm.startPrank(alice);
        zero.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token1.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token2.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token3.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token1.approve(address(liquidity), type(uint256).max);
        token2.approve(address(liquidity), type(uint256).max);
        token3.approve(address(liquidity), type(uint256).max);
		vm.stopPrank();

        // Bob gets some zero and tokens
        zero.transfer(bob, 1000 ether);
        token1.transfer(bob, 1000 ether);
        token2.transfer(bob, 1000 ether);
        token3.transfer(bob, 1000 ether);

        vm.startPrank(bob);
        zero.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token1.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token2.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token3.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token1.approve(address(liquidity), type(uint256).max);
        token2.approve(address(liquidity), type(uint256).max);
        token3.approve(address(liquidity), type(uint256).max);
		vm.stopPrank();

        // Charlie gets some zero and tokens
        zero.transfer(charlie, 1000 ether);
        token1.transfer(charlie, 1000 ether);
        token2.transfer(charlie, 1000 ether);
        token3.transfer(charlie, 1000 ether);

        vm.startPrank(charlie);
        zero.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token1.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token2.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token3.approve(address(liquidityRewardsEmitter), type(uint256).max);
        token1.approve(address(liquidity), type(uint256).max);
        token2.approve(address(liquidity), type(uint256).max);
        token3.approve(address(liquidity), type(uint256).max);
		vm.stopPrank();

		// Increase rewardsEmitterDailyPercent to 2.5% for testing
		vm.startPrank(address(dao));
		for ( uint256 i = 0; i < 7; i++ )
			rewardsConfig.changeRewardsEmitterDailyPercent(true);
		vm.stopPrank();
    	}


	function pendingLiquidityRewardsForPool( bytes32 pool ) public view returns (uint256)
		{
		bytes32[] memory _pools = new bytes32[](1);
		_pools[0] = pool;

		return liquidityRewardsEmitter.pendingRewardsForPools( _pools )[0];
		}


	function totalRewardsForPools( bytes32 pool ) public view returns (uint256)
		{
		bytes32[] memory _pools = new bytes32[](1);
		_pools[0] = pool;

		return liquidity.totalRewardsForPools( _pools )[0];
		}



	// A unit test in which multiple users try to add ZERO rewards to multiple valid pools. Test that the total amount of ZERO transferred from the senders to the contract is correct and that pending rewards for each pool is correctly incremented.
	function testAddZERORewards() public {
        // Define rewards to be added
        AddedReward[] memory addedRewards = new AddedReward[](4);
        addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 50 ether});
        addedRewards[1] = AddedReward({poolID: poolIDs[0], amountToAdd: 50 ether});
        addedRewards[2] = AddedReward({poolID: poolIDs[1], amountToAdd: 25 ether});
        addedRewards[3] = AddedReward({poolID: poolIDs[1], amountToAdd: 75 ether});

		uint256 startingA = zero.balanceOf(alice);
		uint256 startingB = zero.balanceOf(bob);
		uint256 startingC = zero.balanceOf(charlie);

        // Record initial contract balance
        uint256 initialContractBalance = zero.balanceOf(address(liquidityRewardsEmitter));

        // Alice, Bob and Charlie each add rewards
        vm.prank(alice);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        vm.prank(bob);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        vm.prank(charlie);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Verify contract balance increased by total added rewards
        uint256 finalContractBalance = zero.balanceOf(address(liquidityRewardsEmitter));
        assertEq(finalContractBalance, initialContractBalance + 600 ether);

        // Verify pending rewards for each pool is correctly incremented
        uint256[] memory poolsPendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
        assertEq(poolsPendingRewards[0], 300 ether);
        assertEq(poolsPendingRewards[1], 300 ether);

        assertEq( startingA - zero.balanceOf(alice), 200 ether );
		assertEq( startingB - zero.balanceOf(bob), 200 ether );
		assertEq( startingC - zero.balanceOf(charlie), 200 ether );
    }


	// A unit test in which a user tries to add ZERO rewards but does not have enough ZERO in their account. Test that the transaction reverts as expected.
	function testAddZERORewardsWithInsufficientZERO() public {
	AddedReward[] memory addedRewards = new AddedReward[](1);
	addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 5000 ether});

    vm.expectRevert("ERC20: transfer amount exceeds balance");
	vm.prank(alice);
	liquidityRewardsEmitter.addZERORewards(addedRewards);
    }


	// A unit test in which a user tries to add ZERO rewards to an invalid pool. Test that the transaction reverts as expected.
	function testAddZERORewardsToInvalidPool() public {
        // Invalid pool
        bytes32 invalidPool = bytes32(uint256(0xDEAD));

        // Define reward to be added
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward(invalidPool, 10 ether);

        // Try to add ZERO reward to invalid pool, expect a revert
        vm.expectRevert("Invalid pool");
        liquidityRewardsEmitter.addZERORewards(addedRewards);
    }


	// A unit test where pending rewards are added to multiple pools, then performUpkeep is called. Test that the correct amount of rewards are deducted from each pool's pending rewards.
	function testPerformUpkeepWithMultiplePools() public {

        // Add some pending rewards to the pools
        AddedReward[] memory addedRewards = new AddedReward[](2);
        addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 10 ether});
        addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 10 ether});
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Verify that the rewards were added
        assertEq(pendingLiquidityRewardsForPool(poolIDs[0]), 10 ether);
        assertEq(pendingLiquidityRewardsForPool(poolIDs[1]), 10 ether);

        // Call performUpkeep
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(1 days);

        // Verify that the correct amount of rewards were deducted from each pool's pending rewards
        // With the adjustment in the constructor, 2.5% of the rewards should be deducted per day
        assertEq(pendingLiquidityRewardsForPool(poolIDs[0]), 9.75 ether); // 10 ether - 2.5%
        assertEq(pendingLiquidityRewardsForPool(poolIDs[1]), 9.75 ether); // 10 ether - 2.5%

        // Rewards transferred to the liquidity contract (including from the bootstrapping rewards)
        assertEq(zero.balanceOf(address(liquidity)), 125000499999999999999999);
    }


	// A unit test where rewards are added for the stakingRewardsEmitter
	function testPerformUpkeepForStakingRewardsEmitter() public {

		bytes32[] memory _poolIDs = new bytes32[](1);
		_poolIDs[0] = PoolUtils.STAKED_ZERO;

		uint256 startingRewards = stakingRewardsEmitter.pendingRewardsForPools( _poolIDs )[0];

        // Add some pending rewards to the pools
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward({poolID: PoolUtils.STAKED_ZERO, amountToAdd: 10 ether});

        zero.approve(address(stakingRewardsEmitter), type(uint256).max);
        stakingRewardsEmitter.addZERORewards(addedRewards);

        // Verify that the rewards were added
        assertEq(stakingRewardsEmitter.pendingRewardsForPools( _poolIDs )[0], startingRewards + 10 ether);

        // Call performUpkeep
        vm.prank(address(upkeep));
        stakingRewardsEmitter.performUpkeep(1 days);

        // Verify that the correct amount of rewards were deducted from each pool's pending rewards
        // With the adjustment in the constructor, 2.5% of the rewards should be deducted per day
        assertEq(stakingRewardsEmitter.pendingRewardsForPools( _poolIDs )[0], 2925009750000000000000005); // (startingRewards + 10 ether) - 2.5%

        // Rewards transferred to the staking contract
        assertEq(zero.balanceOf(address(staking)), 75000250000000000000000);
    }


	// A unit test where the performUpkeep function is called for multiple pools. Test that the correct amount of rewards is transferred for each pool.
	function testPerformUpkeep() public {
        // Alice, Bob, and Charlie deposit their LP tokens into pool[1]
        vm.prank(alice);
        liquidity.depositLiquidityAndIncreaseShare(token1, token2, 100 ether, 100 ether, 0, 0, 0, block.timestamp, false);

        vm.prank(bob);
        liquidity.depositLiquidityAndIncreaseShare(token1, token2, 100 ether, 100 ether, 0, 0, 0, block.timestamp, false);

        vm.prank(charlie);
        liquidity.depositLiquidityAndIncreaseShare(token1, token2, 100 ether, 100 ether, 0, 0, 0, block.timestamp, false);

        // Adding rewards to the pools
        AddedReward[] memory addedRewards = new AddedReward[](2);
        addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 100 ether});
        addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 100 ether});
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Before upkeep, rewards should be 100 ether for each pool
        assertEq(pendingLiquidityRewardsForPool(poolIDs[0]), 100 ether);
        assertEq(pendingLiquidityRewardsForPool(poolIDs[1]), 100 ether);

        // Perform upkeep after 1 day for poolIDs[0] and poolIDs[1]
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(1 days);

        // After upkeep, rewards should be reduced by 2.5% (increased from default) for each pool
        assertEq(pendingLiquidityRewardsForPool(poolIDs[0]), 97.5 ether );
        assertEq(pendingLiquidityRewardsForPool(poolIDs[1]), 97.5 ether );

		// Make sure the correct amount of rewards have been emitted to the pools
		assertEq( totalRewardsForPools(poolIDs[0]), 2.5 ether, "Incorrect total rewards in pool[0]" );
		assertEq( totalRewardsForPools(poolIDs[1]), 2.5 ether, "Incorrect total rewards in pool[1]" );

        // Check if the correct amount of rewards was transferred to each user
        assertEq(liquidity.userRewardForPool(alice, poolIDs[0]), 0.833333333333333333 ether); // 2.5% of 100 ether divided by 3 users
        assertEq(liquidity.userRewardForPool(bob, poolIDs[0]), 0.833333333333333333 ether);
        assertEq(liquidity.userRewardForPool(charlie, poolIDs[0]), 0.833333333333333333 ether);
    }


	// A unit test where the pendingRewardsForPools function is called for multiple pools. Test that it correctly returns the amount of pending rewards for each pool.
	function testPendingRewardsForPools() public {
        // Alice stakes in both pools
        vm.startPrank(alice);
        liquidity.depositLiquidityAndIncreaseShare(token1, token2, 50 ether, 50 ether, 0, 0, 0, block.timestamp, false);
        liquidity.depositLiquidityAndIncreaseShare(token2, token3, 50 ether, 50 ether, 0, 0, 0, block.timestamp, false);
        vm.stopPrank();

        // Bob stakes in both pools
        vm.startPrank(bob);
        liquidity.depositLiquidityAndIncreaseShare(token1, token2, 30 ether, 30 ether, 0, 0, 0, block.timestamp, false);
        liquidity.depositLiquidityAndIncreaseShare(token2, token3, 70 ether, 70 ether, 0, 0, 0, block.timestamp, false);
        vm.stopPrank();

        // Charlie stakes in both pools
        vm.startPrank(charlie);
        liquidity.depositLiquidityAndIncreaseShare(token1, token2, 20 ether, 20 ether, 0, 0, 0, block.timestamp, false);
        liquidity.depositLiquidityAndIncreaseShare(token2, token3, 80 ether, 80 ether, 0, 0, 0, block.timestamp, false);
        vm.stopPrank();

        // Advance the time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Add rewards to the pools
        AddedReward[] memory addedRewards = new AddedReward[](2);
        addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 10 ether});
        addedRewards[1] = AddedReward({poolID: poolIDs[1], amountToAdd: 20 ether});
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Check pending rewards
        uint256[] memory rewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);

        assertEq(rewards[0], 10 ether, "Incorrect pending rewards for pool 1");
        assertEq(rewards[1], 20 ether, "Incorrect pending rewards for pool 2");
    }


	// A unit test that attempts to add ZERO rewards to a pool when the contract does not have approval to transfer ZERO. Test that the transaction reverts as expected.
	function testAddZERORewardsWithoutApproval() public {
        zero.approve(address(liquidityRewardsEmitter), 0); // Removing approval for ZERO transfer

        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward(poolIDs[0], 10 ether);

        vm.expectRevert("ERC20: insufficient allowance");
        liquidityRewardsEmitter.addZERORewards(addedRewards);
    }


	// A stress test in which a high volume of ZERO rewards is added and distributed across multiple pools. Test that the contract can handle the high volume of transactions and that the balances and distributions remain accurate.
	function testHighVolumeStress() public {
        // Array to store added rewards
        AddedReward[] memory addedRewards = new AddedReward[](2);
        addedRewards[0] = AddedReward(poolIDs[0], 100000 ether);
        addedRewards[1] = AddedReward(poolIDs[1], 100000 ether);

		vm.prank(DEPLOYER);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Verify that the pending rewards for each pool match the added amounts
        uint256[] memory pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
        assertEq(pendingRewards[0], 100000 ether);
        assertEq(pendingRewards[1], 100000 ether);

        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(2 weeks);

        // Verify that the rewards have been distributed
        pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
        assertEq(pendingRewards[0], 97500 ether);  // 100000 ether - 2.5%
        assertEq(pendingRewards[1], 97500 ether);  // 100000 ether - 2.5%
    }


	// A unit test where a user tries to perform upkeep without any rewards added. Test that the function performs as expected and does not revert.
	function testPerformUpkeepNoRewards() public {
        // Perform initial upkeep without any rewards added
        vm.prank(alice);

        // Verify that no ZERO rewards are distributed for both pools
        uint256[] memory pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
        assertEq( pendingRewards[0], 0);
        assertEq( pendingRewards[1], 0);

        // Perform upkeep again
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(2 weeks);

        // Verify that no ZERO rewards are distributed for both pools, even after 1 day
        pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
        assertEq( pendingRewards[0], 0);
        assertEq( pendingRewards[1], 0);
    }


	// An edge case unit test where the amount to add for ZERO rewards is 0. Test that the function behaves as expected and does not revert or misbehave.
	function testAddZeroZERORewards() public
    {
        // Alice tries to add 0 ZERO rewards for pool[1]
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward({poolID: poolIDs[1], amountToAdd: 0 ether});
        vm.prank(alice);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Ensure that the function did not revert and that the pending rewards for pool[1] is still 0
        assertEq(pendingLiquidityRewardsForPool(poolIDs[1]), 0 ether);

        // Perform upkeep
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(1 days);

        // Ensure that the function did not revert and that the pending rewards for pool[1] is still 0
        assertEq(pendingLiquidityRewardsForPool(poolIDs[1]), 0 ether);

        // Ensure that Alice's balance did not change
        assertEq(zero.balanceOf(alice), 1000 ether);
    }


	// A test that emits rewards amounts with delay between performUpkeep calls of 1 hour, 12 hours, 24 hours, and 48 hours.
	function testEmittingRewardsWithDifferentDelays() public {

        // Add some ZERO rewards to the pool
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward(poolIDs[1], 1000 ether);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

		uint256 denominatorMult = 100 days * 1000;

        // Perform upkeep after 1 hour
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(1 hours);

        // Check rewards
        uint256 pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1];
		uint256 numeratorMult = 1 hours * rewardsConfig.rewardsEmitterDailyPercentTimes1000();

		uint256 expectedPendingRewards = 1000 ether  - ( 1000 ether * numeratorMult ) / denominatorMult;
        assertEq(pendingRewards, expectedPendingRewards, "Incorrect pending rewards after 1 hour" );


        // Perform upkeep after 12 more hours
		vm.prank(address(upkeep));
		liquidityRewardsEmitter.performUpkeep(12 hours);

        // Check rewards
        pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1];
		numeratorMult = 12 hours * rewardsConfig.rewardsEmitterDailyPercentTimes1000();

		expectedPendingRewards = expectedPendingRewards  - ( expectedPendingRewards * numeratorMult ) / denominatorMult;
        assertEq(pendingRewards, expectedPendingRewards, "Incorrect pending rewards after 12 hours" );


        // Perform upkeep after 24 more hours
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(24 hours);

        // Check rewards
        pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1];
		numeratorMult = 24 hours * rewardsConfig.rewardsEmitterDailyPercentTimes1000();

		expectedPendingRewards = expectedPendingRewards  - ( expectedPendingRewards * numeratorMult ) / denominatorMult;
        assertEq(pendingRewards, expectedPendingRewards, "Incorrect pending rewards after 24 hours" );


        // Perform upkeep after 48 more hours
		vm.prank(address(upkeep));
		liquidityRewardsEmitter.performUpkeep(48 hours);

        // Check rewards - will be capped at 24 hours of delay
        pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1];
		numeratorMult = 24 hours * rewardsConfig.rewardsEmitterDailyPercentTimes1000();

		expectedPendingRewards = expectedPendingRewards  - ( expectedPendingRewards * numeratorMult ) / denominatorMult;
        assertEq(pendingRewards, expectedPendingRewards, "Incorrect pending rewards after 48 hours" );
    }


    // A unit test that verifies that the RewardsEmitter contract properly handles scenarios where the daily rewards percentage is changed.
    function testChangeRewardsEmitterDailyPercent() public
    {
        // Lower the daily percent to 1%
        vm.startPrank(address(dao));
        for( uint256 i = 0; i < 6; i++ )
	        rewardsConfig.changeRewardsEmitterDailyPercent(false);
        vm.stopPrank();


        // Add some ZERO rewards to the pool
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward(poolIDs[0], 1000 ether);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Perform upkeep to distribute rewards
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(1 days);

		uint256 rewards0 = pendingLiquidityRewardsForPool(poolIDs[0]);

        // Setup
        uint256 oldDailyPercent = rewardsConfig.rewardsEmitterDailyPercentTimes1000();

        // Change daily rewards percent
        vm.startPrank(address(dao));
        for( uint256 i = 0; i < 6; i++ )
	        rewardsConfig.changeRewardsEmitterDailyPercent(true);
        vm.stopPrank();

        uint256 newDailyPercent = rewardsConfig.rewardsEmitterDailyPercentTimes1000();
        assertTrue(newDailyPercent > oldDailyPercent, "New daily percent should be greater than old daily percent");

        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(1 days);

		uint256 rewards1 = pendingLiquidityRewardsForPool(poolIDs[0]);

//		console.log( " (rewards0 - 1000 ether): ",  1000 ether - rewards0 );
//		console.log( " (rewards1 - rewards0): ",  rewards0 - rewards1 );

		assertTrue( (rewards0 - rewards1) > (1000 ether - rewards0), "Distributed rewards should have increased" );
    }


	function testPerformUpkeepOnlyCallableFromDAO() public
		{
		vm.expectRevert( "RewardsEmitter.performUpkeep is only callable from the Upkeep contract" );
        liquidityRewardsEmitter.performUpkeep(2 weeks);

		vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(2 weeks);
		}


	// A unit test that verifies whether the RewardsEmitter correctly handles scenarios where addZERORewards is called for a pool that has been withdrawn from whitelisting.
	function testWithdrawnPoolAddZERORewards() public {
        // Alice deposits some liquidity to the pool1
        vm.prank(alice);
        liquidity.depositLiquidityAndIncreaseShare(token1, token2, 500 ether, 500 ether, 0, 0, 0, block.timestamp, true );

        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward({poolID: poolIDs[0], amountToAdd: 100 ether});

        vm.prank(alice);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        assertEq(liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[0], 100 ether);
        assertEq(liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1], 0);

        // Whitelist is withdrawn for pool1
        vm.prank(address(dao));
        poolsConfig.unwhitelistPool(token1, token2);

        // Alice tries to add rewards to pool1 that has been withdrawn from whitelisting
        // Expect it to revert
        vm.expectRevert("Invalid pool");
        liquidityRewardsEmitter.addZERORewards(addedRewards);

		// Verify that rewards are still the same
        assertEq(liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[0], 100 ether);
        assertEq(liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1], 0);
    }


    // A unit test that verifies if RewardsEmitter correctly handles a case where addZERORewards is called with an empty array.
    function testAddZERORewardsEmptyArray() public {
            // Define rewards to be added as an empty array
            AddedReward[] memory addedRewards = new AddedReward[](0);

            uint256 initialContractBalance = zero.balanceOf(address(liquidityRewardsEmitter));

            // Alice adds rewards using an empty array
            vm.prank(alice);
            liquidityRewardsEmitter.addZERORewards(addedRewards);

            // Contract balance should remain the same as no rewards were added
            uint256 finalContractBalance = zero.balanceOf(address(liquidityRewardsEmitter));
            assertEq(finalContractBalance, initialContractBalance);

            // Pending rewards for each pool should remain the same as no rewards were added
            uint256[] memory poolsPendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
            for (uint256 i = 0; i < poolIDs.length; i++) {
                assertEq(poolsPendingRewards[i], 0);
            }
        }


    // A unit test that verifies whether the RewardsEmitter correctly handles the situation if a pool is whitelisted after rewards were added.
	function testPoolWhitelistedAfterRewardsAdded() public {
		IERC20 tokenA = new TestERC20( "TEST", 18 );
		IERC20 tokenB = new TestERC20( "TEST", 18 );

        bytes32 unlistedPoolID;
        unlistedPoolID = PoolUtils._poolID(tokenA, tokenB);
        uint256 addedReward = 100 ether;

        // Record initial balance of the contract
        uint256 initialContractBalance = zero.balanceOf(address(liquidityRewardsEmitter));

        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward({poolID: unlistedPoolID, amountToAdd: addedReward});

        // Add rewards to an unlisted pool
        vm.startPrank(address(alice));
        vm.expectRevert("Invalid pool");
        liquidityRewardsEmitter.addZERORewards(addedRewards);
        vm.stopPrank();

        // Ensure that the rewards in the contract have not changed
        assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), initialContractBalance);

        // Whitelist the previously unlisted pool and add rewards again
        vm.prank(address(dao));
        poolsConfig.whitelistPool(  tokenA, tokenB);

        // Add rewards to the now whitelisted pool
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Ensure that the rewards in the contract have been increased by the added amount
        assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), initialContractBalance + addedReward);

        // Ensure that the pending rewards for the whitelisted pool have been correctly incremented
        assertEq(pendingLiquidityRewardsForPool(unlistedPoolID), addedReward);
    }


    // A unit test that checks if ZERO transfer fails, addZERORewards reverts appropriately
    function testAddZERORewardsTransferFail() public {
        // The test uses Alice to perform the transaction.
        vm.prank(alice);

        // We expect the ZERO transfer to fail. No specific revert reason is provided here, so we simulate a generic transfer failure.
        vm.expectRevert();

        // We call addZERORewards with an arbitrary pool ID and an amount that we assume will fail to transfer due to lack of funds or other reasons.
        // This would need to be a valid Pool ID normally, but since transfer will fail, it's largely irrelevant for this test.
        bytes32 arbitraryPoolID = poolIDs[0]; // Assuming poolIDs[0] is a valid Pool ID already set up in the test environment.
        uint256 amountThatWillFail = 1001 ether; // Assuming Alice has less than this amount, the transfer will fail.

        // Create the AddedReward struct with the arbitrary pool and amount.
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward({poolID: arbitraryPoolID, amountToAdd: amountThatWillFail});

        // Attempt to add ZERO rewards, should revert due to failed transfer.
        stakingRewardsEmitter.addZERORewards(addedRewards);
    }


    // A unit test that verifies performUpkeep's behavior with a non-zero starting balance of the contract
	function testPerformUpkeepWithNonZeroStartingBalance() public {
        // Assumptions:
        // - non-zero starting balance means the contract already has ZERO tokens before performUpkeep is called.
        // - performUpkeep is already correctly implemented to handle distributions.
        // - rewardsConfig.rewardsEmitterDailyPercentTimes1000() is available and returns the daily percent times 1000.
        // - We are testing liquidityRewardsEmitter which directly calls performUpkeep.

        // Arrange
        uint256 startingBalance = zero.balanceOf(address(liquidityRewardsEmitter));
        require(startingBalance > 0, "Precondition: non-zero starting balance required");

        uint256 timeSinceLastUpkeep = 1 hours; // 1 hour since last upkeep for the test.
        uint256 dailyPercent1000x = rewardsConfig.rewardsEmitterDailyPercentTimes1000();

        // Calculate expected total emitted rewards
        uint256 expectedEmittedRewards = startingBalance * timeSinceLastUpkeep * dailyPercent1000x / (24 hours * 100000);

        // Perform upkeep
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(timeSinceLastUpkeep); // External call to performUpkeep

        // After the performUpkeep call, we expect the balance of liquidityRewardsEmitter to decrease
        // by the amount of rewards emitted during the upkeep
        // Assert
        uint256 endingBalance = zero.balanceOf(address(liquidityRewardsEmitter));
        uint256 emittedRewards = startingBalance - endingBalance;

        assertEq(emittedRewards, expectedEmittedRewards, "Incorrect emitted rewards after performUpkeep");
    }


    // A unit test that simulate performUpkeep being called successively without any time gap
    function testPerformUpkeepSuccessivelyWithoutTimeGap() public {
        // Arrange
        uint256 startingBalance = zero.balanceOf(address(liquidityRewardsEmitter));
        require(startingBalance > 0, "Precondition: non-zero starting balance required");

        uint256 timeSinceLastUpkeep = 1 hours; // 1 hour since last upkeep for the test.
        uint256 dailyPercent1000x = rewardsConfig.rewardsEmitterDailyPercentTimes1000();

        // Calculate expected total emitted rewards
        uint256 expectedEmittedRewards = startingBalance * timeSinceLastUpkeep * dailyPercent1000x / (24 hours * 100000);

        // Perform upkeep
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(timeSinceLastUpkeep); // External call to performUpkeep

        // After the performUpkeep call, we expect the balance of liquidityRewardsEmitter to decrease
        // by the amount of rewards emitted during the upkeep
        // Assert
        uint256 endingBalance = zero.balanceOf(address(liquidityRewardsEmitter));
        uint256 emittedRewards = startingBalance - endingBalance;

        assertEq(emittedRewards, expectedEmittedRewards, "Incorrect emitted rewards after performUpkeep");


        uint256 startingBalance2 = zero.balanceOf(address(liquidityRewardsEmitter));
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(0); // External call to performUpkeep

        // After the performUpkeep call, we expect the balance of liquidityRewardsEmitter to decrease
        // by the amount of rewards emitted during the upkeep
        // Assert
        uint256 endingBalance2 = zero.balanceOf(address(liquidityRewardsEmitter));
        uint256 emittedRewards2 = startingBalance2 - endingBalance2;

        assertEq(emittedRewards2, 0, "Incorrect emitted rewards after performUpkeep");
    }


    // A unit test that confirms performUpkeep does not revert when called immediately after deployment with no pendingRewards
    function testPerformUpkeepDoesNotRevertOnEmptyPendingRewards() public {
        // Simulate deployment conditions where no rewards have been added yet
        // Expect performUpkeep to not revert despite having no rewards pending
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(0);
    }


    // A unit test that confirms correct handling of rounding for very small reward amounts in performUpkeep
    function testPerformUpkeepRoundingRewards() public {
        // Add a very small reward amount to a test pool
        bytes32 testPoolID = poolIDs[0];
        uint256 smallRewardAmount = 0.0001 ether;
        AddedReward[] memory addedRewards = new AddedReward[](1);
        addedRewards[0] = AddedReward({poolID: testPoolID, amountToAdd: smallRewardAmount});
        vm.prank(DEPLOYER);
        liquidityRewardsEmitter.addZERORewards(addedRewards);

        // Check initial pending rewards
        uint256 initialPendingRewards = pendingLiquidityRewardsForPool(testPoolID);
        assertEq(initialPendingRewards, smallRewardAmount, "Initial rewards incorrect");

        // Perform upkeep with a 1 second delay
        vm.prank(address(upkeep));
        liquidityRewardsEmitter.performUpkeep(1);

        // Expected pending rewards should be rounded down to the nearest wei after subtracting the upkeep percentage
        uint256 expectedPendingRewards = initialPendingRewards - (initialPendingRewards * rewardsConfig.rewardsEmitterDailyPercentTimes1000() / (1 days * 100000));
        uint256 finalPendingRewards = pendingLiquidityRewardsForPool(testPoolID);

        // We expect some level of rounding error, but it should not be more than 1 wei
        // Check with assert to confirm the subtraction is indeed rounded correctly
        assertTrue(finalPendingRewards >= expectedPendingRewards && finalPendingRewards <= expectedPendingRewards + 1, "Final pending rewards rounding incorrect");
    }
	}

