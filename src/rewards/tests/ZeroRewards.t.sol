// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../dev/Deployment.sol";
import "./TestZeroRewards.sol";


contract TestZeroRewards2 is Deployment
	{
    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);
    address public constant charlie = address(0x3333);



    function setUp() public
    	{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			initializeContracts();

		// Transfer the zero from the original initialDistribution to the DEPLOYER
		vm.prank(address(initialDistribution));
		zero.transfer(DEPLOYER, 100000000 ether);
    	}


    // A unit test to ensure that the _sendStakingRewards function correctly transfers the pendingStakingRewards to the stakingRewardsEmitter and resets the pendingStakingRewards to zero.
 function testSendStakingRewards() public {
 		TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

		vm.prank(DEPLOYER);
		zero.transfer(address(_zeroRewards), 10 ether);

         // Initializing the pending staking rewards
         uint256 initialPendingStakingRewards = 10 ether;

         // Initializing the balance of contract before running the function
     	uint256 initialZeroContractBalance = zero.balanceOf(address(_zeroRewards));

         // Set the initial balance of stakingRewardsEmitter
         uint256 initialStakingRewardsEmitterBalance = zero.balanceOf(address(stakingRewardsEmitter));

         // Running _sendStakingRewards function
         _zeroRewards.sendStakingRewards(initialPendingStakingRewards);

         // Expectations after running the function
         uint256 expectedStakingRewardsEmitterBalance = initialPendingStakingRewards + initialStakingRewardsEmitterBalance;
         uint256 expectedZeroContractBalance = initialZeroContractBalance - initialPendingStakingRewards;

         // Verifying the changes in the balances and the pending staking rewards
         assertEq(zero.balanceOf(address(stakingRewardsEmitter)), expectedStakingRewardsEmitterBalance, "StakingRewardsEmitter hasn't received the correct amount of Zero");
         assertEq(zero.balanceOf(address(_zeroRewards)), expectedZeroContractBalance, "_sendStakingRewards hasn't deducted the correct amount of Zero from the contract balance");
     }


    // A unit test to verify the _sendLiquidityRewards function with a non-zero total profits and non-zero pending rewards, ensuring that the correct amount is transferred each pool's liquidityRewardsEmitter and the pendingLiquidityRewards
    function testSendLiquidityRewards() public {
        TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

    	vm.prank(DEPLOYER);
        zero.transfer(address(_zeroRewards), 50 ether);

		IERC20 token1 = new TestERC20( "TEST", 18 );
		IERC20 token2 = new TestERC20( "TEST", 18 );

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token1, token2);

        bytes32[] memory poolIDs = new bytes32[](2);
        poolIDs[0] = PoolUtils._poolID(zero,usdc);
		poolIDs[1] = PoolUtils._poolID(token1, token2);

        uint256[] memory profitsForPools = new uint256[](2);
        profitsForPools[0] = 10 ether;
        profitsForPools[1] = 20 ether;

        // Initializing the pending rewards
        uint256 initialPendingLiquidityRewards = 40 ether; // for other pools

        // Balance of contract before running sendLiquidityRewards
        uint256 initialZeroContractBalance = zero.balanceOf(address(_zeroRewards));

    	// Balance of liquidityRewardsEmitter before running sendLiquidityRewards
        uint256 initialLiquidityRewardsEmitterBalance = zero.balanceOf(address(liquidityRewardsEmitter));

        // Run _sendLiquidityRewards function
        _zeroRewards.sendLiquidityRewards(initialPendingLiquidityRewards, poolIDs, profitsForPools);

        // Expectations after running the function
        uint256 expectedLiquidityRewardsEmitterBalance = initialLiquidityRewardsEmitterBalance + initialPendingLiquidityRewards;
        uint256 expectedZeroContractBalance = initialZeroContractBalance - initialPendingLiquidityRewards;

        // Verifying the changes in the balances and the pending rewards
        assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), expectedLiquidityRewardsEmitterBalance - 1, "LiquidityRewardsEmitter hasn't received the correct amount of Zero");
        assertEq(zero.balanceOf(address(_zeroRewards)), expectedZeroContractBalance + 1, "_sendLiquidityRewards hasn't deducted the correct amount of Zero from the contract balance");

        // Should set  pendingRewardsZeroUSDC to the remaining ZERO that wasn't sent
        assertEq(zero.balanceOf(address(_zeroRewards)), 10000000000000000001, "_zeroRewards balance incorrect");

        uint256[] memory pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
        assertEq( pendingRewards[0], initialPendingLiquidityRewards * 1 / 3 );
        assertEq( pendingRewards[1], initialPendingLiquidityRewards * 2 / 3 );
    }


    // A unit test to ensure that _sendLiquidityRewards function does not transfer any rewards when total profits are zero.
    function testSendLiquidityRewardsZeroProfits() public {
    	TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

    	vm.prank(DEPLOYER);
    	zero.transfer(address(_zeroRewards), 10 ether);

    	// Initializing the pending liquidity rewards
    	uint256 initialPendingLiquidityRewards = 10 ether;

    	// Running _sendLiquidityRewards function with zero total profits
    	bytes32[] memory poolIDs = new bytes32[](0);
    	uint256[] memory profitsForPools = new uint256[](0);
    	_zeroRewards.sendLiquidityRewards(initialPendingLiquidityRewards, poolIDs, profitsForPools);

    	// Since total profits are zero, no rewards should be transferred
    	assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), 0, "No liquidity rewards should be transferred for zero profits");
    	assertEq(zero.balanceOf(address(_zeroRewards)), 10 ether, "No liquidity rewards should be deducted for zero profits");
    }


    // A unit test to ensure that the _sendInitialLiquidityRewards function correctly divides the liquidityBootstrapAmount amongst the initial pools and sends the amount to liquidityRewardsEmitter.
        function testSendInitialLiquidityRewards() public {
            TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

            bytes32[] memory poolIDs = new bytes32[](3);
            poolIDs[0] = PoolUtils._poolID(zero, usdc);
            poolIDs[1] = PoolUtils._poolID(wbtc, weth);
            poolIDs[2] = PoolUtils._poolID(weth, usdc);

            uint256 liquidityBootstrapAmount = 900 ether;

            // move tokens to rewards contract
            vm.prank(DEPLOYER);
            zero.transfer(address(_zeroRewards), liquidityBootstrapAmount);

            uint256 initialLiquidityEmitterBalance = zero.balanceOf(address(liquidityRewardsEmitter));

            // run `_sendInitialLiquidityRewards` function
            _zeroRewards.sendInitialLiquidityRewards(liquidityBootstrapAmount, poolIDs);

            // verify the correct amount was transferred to liquidityRewardsEmitter
            uint256 expectedLiquidityEmitterBalance = initialLiquidityEmitterBalance + liquidityBootstrapAmount;
            assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), expectedLiquidityEmitterBalance, "LiquidityRewardsEmitter hasn't received the correct amount of Zero");

            uint256 expectedPerPool = liquidityBootstrapAmount / 3;
            uint256[] memory pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);

            assertEq( pendingRewards[0], expectedPerPool );
            assertEq( pendingRewards[1], expectedPerPool );
            assertEq( pendingRewards[2], expectedPerPool );
        }


    // A unit test to check the _sendInitialStakingRewards function ensuring that the stakingBootstrapAmount is correctly transferred to the stakingRewardsEmitter.
    function testSendInitialStakingRewards() public {
    	TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

    	vm.prank(DEPLOYER);
    	zero.transfer(address(_zeroRewards), 10 ether);

    	// Initializing the staking bootstrap amount
    	uint256 stakingBootstrapAmount = 10 ether;

    	// Initializing the balance of contract before running the function
    	uint256 initialZeroContractBalance = zero.balanceOf(address(_zeroRewards));

    	// Initialize the initial balance of stakingRewardsEmitter
    	uint256 initialStakingRewardsEmitterBalance = zero.balanceOf(address(stakingRewardsEmitter));

    	// Running _sendInitialStakingRewards function
    	_zeroRewards.sendInitialStakingRewards(stakingBootstrapAmount);

    	// Expectations after running the function
    	uint256 expectedStakingRewardsEmitterBalance = stakingBootstrapAmount + initialStakingRewardsEmitterBalance;
    	uint256 expectedZeroContractBalance = initialZeroContractBalance - stakingBootstrapAmount;

    	// Verifying the changes in the balances after running the function
    	assertEq(zero.balanceOf(address(stakingRewardsEmitter)), expectedStakingRewardsEmitterBalance, "StakingRewardsEmitter hasn't received the correct amount of Zero");
    	assertEq(zero.balanceOf(address(_zeroRewards)), expectedZeroContractBalance, "_sendInitialStakingRewards hasn't deducted the correct amount of Zero from the contract balance");
    }


    // A unit test to check the sendInitialZeroRewards function ensuring that it cannot be called by any other address other than the initialDistribution address set in the constructor.
    function testSendInitialZeroRewards_onlyCallableByInitialDistribution() public {
        TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

        vm.prank(DEPLOYER);
        zero.transfer(address(_zeroRewards), 8 ether);

        uint256 liquidityBootstrapAmount = 5 ether;

        bytes32[] memory poolIDs = new bytes32[](1);
        poolIDs[0] = PoolUtils._poolID(zero, usdc);

        // Expect revert because the caller is not the initialDistribution
        vm.expectRevert("ZeroRewards.sendInitialRewards is only callable from the InitialDistribution contract");
        _zeroRewards.sendInitialZERORewards(liquidityBootstrapAmount, poolIDs);

        // Change the caller to the initialDistribution
        vm.prank(address(initialDistribution));
        _zeroRewards.sendInitialZERORewards(liquidityBootstrapAmount, poolIDs);
    }


    // A unit test to validate that the performUpkeep function works correctly when called by the upkeep address and the pendingStakingRewards and pendingLiquidityRewards fields are non-zero and check if the balance of contract is decreased by the sent amount.
    function testPerformUpkeepSuccess() public
    {
        TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

		uint256 zeroRewards = 30 ether;
        vm.prank(DEPLOYER);
        zero.transfer(address(_zeroRewards), zeroRewards);


        // Create dummy poolIds and profitsForPools arrays
		IERC20 token1 = new TestERC20( "TEST", 18 );
		IERC20 token2 = new TestERC20( "TEST", 18 );

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token1, token2);

        bytes32[] memory poolIDs = new bytes32[](2);
        poolIDs[0] = PoolUtils._poolID(zero,usdc);
		poolIDs[1] = PoolUtils._poolID(token1, token2);

        uint256[] memory profitsForPools = new uint256[](2);
        profitsForPools[0] = 10 ether;
        profitsForPools[1] = 20 ether;


        // Running performUpkeep function
        vm.prank(address(exchangeConfig.upkeep()));
        _zeroRewards.performUpkeep(poolIDs, profitsForPools);

        // Expectations after running the function
        uint256 expectedStakingRewardsEmitterBalance = zeroRewards / 2;
        uint256 expectedLiquidityRewardsEmitterBalance = zeroRewards / 2;

        // Verifying the changes in the balances, pending staking rewards and pending liquidity rewards
        assertEq(zero.balanceOf(address(_zeroRewards)), 0, "performUpkeep hasn't deducted the correct amount of Zero from the contract balance");
        assertEq(zero.balanceOf(address(stakingRewardsEmitter)), expectedStakingRewardsEmitterBalance, "StakingRewardsEmitter hasn't received the correct amount of Zero");
        assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), expectedLiquidityRewardsEmitterBalance, "LiquidityRewardsEmitter hasn't received the correct amount of Zero");
    }



    // A unit test to check the performUpkeep function when it's called by an address other than the upkeep address, ensuring that it reverts with the correct error message.
    function testPerformUpkeep_NotUpkeepAddress() public
    {
        TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

        vm.prank(charlie); // Assuming charlie is not an upkeep address

        bytes32[] memory poolIDs = new bytes32[](0);
        uint256[] memory profitsForPools = new uint256[](0);

        // Expect the performUpkeep to revert because it's called by an address other than the upkeep address
        vm.expectRevert("ZeroRewards.performUpkeep is only callable from the Upkeep contract");
        _zeroRewards.performUpkeep(poolIDs, profitsForPools);
    }


    // A unit test to check that the performUpkeep function does not perform any actions when the pendingStakingRewards or pendingLiquidityRewards are zero.
    function testPerformUpkeepWithZeroRewards() public
    	{
    	TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);
    	vm.prank(DEPLOYER);

    	// No rewards are transferred to _zeroRewards


    	// Initial balances to be compared with final balances
    	uint256 initialContractBalance = zero.balanceOf(address(_zeroRewards));
    	uint256 initialStakingRewardsEmitterBalance = zero.balanceOf(address(stakingRewardsEmitter));
    	uint256 initialLiquidityRewardsEmitterBalance = zero.balanceOf(address(liquidityRewardsEmitter));


        // Create dummy poolIds and profitsForPools arrays
		IERC20 token1 = new TestERC20( "TEST", 18 );
		IERC20 token2 = new TestERC20( "TEST", 18 );

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token1, token2);

        bytes32[] memory poolIDs = new bytes32[](2);
        poolIDs[0] = PoolUtils._poolID(zero,usdc);
		poolIDs[1] = PoolUtils._poolID(token1, token2);

        uint256[] memory profitsForPools = new uint256[](2);
        profitsForPools[0] = 10 ether;
        profitsForPools[1] = 20 ether;


    	// Perform upkeep
    	vm.prank(address(upkeep));
    	_zeroRewards.performUpkeep(poolIDs, profitsForPools);

    	// Final balances
    	uint256 finalContractBalance = zero.balanceOf(address(_zeroRewards));
    	uint256 finalStakingRewardsEmitterBalance = zero.balanceOf(address(stakingRewardsEmitter));
    	uint256 finalLiquidityRewardsEmitterBalance = zero.balanceOf(address(liquidityRewardsEmitter));

    	// Asserts
    	assertEq(finalContractBalance, initialContractBalance, "The contracts balance was changed, but it shouldn't have!");
    	assertEq(finalStakingRewardsEmitterBalance, initialStakingRewardsEmitterBalance, "The Staking Rewards Emitter's balance was changed, but it shouldn't have!");
    	assertEq(finalLiquidityRewardsEmitterBalance, initialLiquidityRewardsEmitterBalance, "The Liquidity Rewards Emitter's balance was changed, but it shouldn't have!");
    	}


    // A unit test that checks if rewards are proportionally distributed to each pool according to their profits in _sendLiquidityRewards()
	function testRewardDistributionProportionalToProfits() public {
            TestZeroRewards zeroRewards = new TestZeroRewards(
                stakingRewardsEmitter,
                liquidityRewardsEmitter,
                exchangeConfig,
                rewardsConfig
            );

            vm.prank(DEPLOYER);
            zero.transfer(address(zeroRewards), 30 ether);

            IERC20 tokenA = new TestERC20("TESTA", 18);
            IERC20 tokenB = new TestERC20("TESTB", 18);

            vm.prank(address(dao));
            poolsConfig.whitelistPool(tokenA, tokenB);

            bytes32 poolIdA = PoolUtils._poolID(zero,usdc);
            bytes32 poolIdB = PoolUtils._poolID(tokenA, tokenB);
            bytes32[] memory poolIDs = new bytes32[](2);
            poolIDs[0] = poolIdA;
            poolIDs[1] = poolIdB;

            uint256 profitA = 15 ether;
            uint256 profitB = 5 ether;
            uint256 totalProfits = profitA + profitB;
            uint256[] memory profitsForPools = new uint256[](2);
            profitsForPools[0] = profitA;
            profitsForPools[1] = profitB;

            uint256 liquidityRewardsAmount = 10 ether; // total rewards to be distributed
            uint256 expectedRewardsForPoolA = (liquidityRewardsAmount * profitA / totalProfits);
            uint256 expectedRewardsForPoolB = (liquidityRewardsAmount * profitB / totalProfits);

            // Both pools should now have a pending reward that's directly proportional to their profits contribution
            uint256 initialPendingRewardsA = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[0];
            uint256 initialPendingRewardsB = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1];

            zeroRewards.sendLiquidityRewards(
                liquidityRewardsAmount,
                poolIDs,
                profitsForPools
            );

            uint256 finalPendingRewardsA = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[0];
            uint256 finalPendingRewardsB = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs)[1];

            assertEq(finalPendingRewardsA, initialPendingRewardsA + expectedRewardsForPoolA, "Pool A did not receive correct rewards based on profits");
            assertEq(finalPendingRewardsB, initialPendingRewardsB + expectedRewardsForPoolB, "Pool B did not receive correct rewards based on profits");
        }


    // A unit test that validates that the staking rewards are sent to the stakingRewardsEmitter correctly
	function testStakingRewardsSentToStakingRewardsEmitter() public {
		TestZeroRewards zeroRewards = new TestZeroRewards(
			stakingRewardsEmitter,
			liquidityRewardsEmitter,
			exchangeConfig,
			rewardsConfig
		);

		// Arrange
        uint256 stakingRewardsAmount = 5 ether;

        vm.startPrank(DEPLOYER);
        zero.transfer(address(zeroRewards), stakingRewardsAmount);
        vm.stopPrank();

        uint256 initialStakingRewardsEmitterBalance = zero.balanceOf(address(stakingRewardsEmitter));

        // Act
        zeroRewards.sendStakingRewards(stakingRewardsAmount);

        // Assert
        uint256 expectedStakingRewardsEmitterBalance = initialStakingRewardsEmitterBalance + stakingRewardsAmount;
        uint256 contractBalanceAfterTransfer = zero.balanceOf(address(this));
        uint256 stakingRewardsEmitterBalanceAfterTransfer = zero.balanceOf(address(stakingRewardsEmitter));

        assertEq(contractBalanceAfterTransfer, 0, "Contract balance should be 0 after sending rewards");
        assertEq(stakingRewardsEmitterBalanceAfterTransfer, expectedStakingRewardsEmitterBalance, "stakingRewardsEmitter balance should be increased by stakingRewardsAmount");
    }


    // A unit test that verifies if _sendInitialLiquidityRewards evenly divides the bootstrap amount across all initial pools
	function testSendInitialLiquidityRewardsEvenDivision() public {
        TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

        uint256 initialPoolsCount = 4;
        bytes32[] memory poolIDs = new bytes32[](initialPoolsCount);
        poolIDs[0] = PoolUtils._poolID(zero, usdc);
        poolIDs[1] = PoolUtils._poolID(wbtc, weth);
        poolIDs[2] = PoolUtils._poolID(weth, usdc);
        poolIDs[3] = PoolUtils._poolID(wbtc, usdc);

        uint256 liquidityBootstrapAmount = 1000 ether;

        // move tokens to rewards contract
        vm.prank(DEPLOYER);
        zero.transfer(address(_zeroRewards), liquidityBootstrapAmount);

        uint256 initialLiquidityEmitterBalance = zero.balanceOf(address(liquidityRewardsEmitter));

        // run `_sendInitialLiquidityRewards` function
        _zeroRewards.sendInitialLiquidityRewards(liquidityBootstrapAmount, poolIDs);

        // verify the correct amount was transferred to liquidityRewardsEmitter
        uint256 expectedLiquidityEmitterBalance = initialLiquidityEmitterBalance + liquidityBootstrapAmount;
        assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), expectedLiquidityEmitterBalance, "LiquidityRewardsEmitter hasn't received the correct amount of Zero");

        uint256 expectedPerPoolAmount = liquidityBootstrapAmount / initialPoolsCount;
        uint256[] memory pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);

        for (uint256 i = 0; i < initialPoolsCount; i++) {
            assertEq(pendingRewards[i], expectedPerPoolAmount, "Pool did not receive the expected amount of initial liquidity rewards");
        }
    }


    // A unit test that _sendInitialStakingRewards sends the correct staking bootstrap amount to the stakingRewardsEmitter
	function testSendInitialStakingRewardsTransfersCorrectAmount() public {
        TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

        vm.prank(DEPLOYER);
        zero.transfer(address(_zeroRewards), 5 ether);

        uint256 stakingBootstrapAmount = 5 ether;

        uint256 initialStakingRewardsEmitterBalance = zero.balanceOf(address(stakingRewardsEmitter));

        vm.prank(DEPLOYER);
        _zeroRewards.sendInitialStakingRewards(stakingBootstrapAmount);

        uint256 finalStakingRewardsEmitterBalance = zero.balanceOf(address(stakingRewardsEmitter));
        uint256 expectedStakingRewardsEmitterBalance = initialStakingRewardsEmitterBalance + stakingBootstrapAmount;

        assertEq(finalStakingRewardsEmitterBalance, expectedStakingRewardsEmitterBalance, "StakingRewardsEmitter did not receive the correct bootstrap amount");
    }


    // A unit test that confirms no action is taken in performUpkeep when zeroRewardsToDistribute is zero
    function testPerformUpkeep_NoActionWhenZeroRewardsToDistributeIsZero() public {

        TestZeroRewards testZeroRewards2 = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);


        // Arrange: We will not transfer any ZERO to the ZeroRewards contract,
        // so the balance should be zero.

        // Act: Call the performUpkeep function
        bytes32[] memory poolIDs = new bytes32[](0);
        uint256[] memory profitsForPools = new uint256[](0);
        vm.prank(address(exchangeConfig.upkeep()));
        testZeroRewards2.performUpkeep(poolIDs, profitsForPools);

        // Assert: Since there is 0 ZERO to distribute, no action should be taken,
        // and balances should remain unchanged.
        assertEq(zero.balanceOf(address(stakingRewardsEmitter)), 0, "No ZERO should have been distributed to the stakingRewardsEmitter");
        assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), 0, "No ZERO should have been distributed to the liquidityRewardsEmitter");
        assertEq(zero.balanceOf(address(testZeroRewards2)), 0, "No ZERO should have been distributed at all");
    }


    // A unit test for _sendLiquidityRewards to ensure directRewardsForZeroUSDC is not included for other pool IDs except zeroUSDCPoolID
    function testSendLiquidityRewardsExcludesDirectRewardsForNonZeroUSDCPools() public {
        TestZeroRewards _zeroRewards = new TestZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

        vm.prank(DEPLOYER);
        zero.transfer(address(_zeroRewards), 100 ether);

		IERC20 newToken = new TestERC20( "TEST", 18 );

        bytes32 zeroUSDCPoolIDTest = PoolUtils._poolID(zero, usdc);
        bytes32 otherPoolIDTest = PoolUtils._poolID(newToken, usdc);

		vm.prank(address(dao));
		poolsConfig.whitelistPool(newToken, usdc);

        // Set pool IDs and profits with one pool being the zeroUSDCPoolID and another being any other pool
        bytes32[] memory poolIDs = new bytes32[](2);
        poolIDs[0] = zeroUSDCPoolIDTest;
        poolIDs[1] = otherPoolIDTest;

        uint256[] memory profitsForPools = new uint256[](2);
        profitsForPools[0] = 10 ether; // Profits for zeroUSDCPoolID
        profitsForPools[1] = 20 ether; // Profits for otherPoolIDTest

        // Balance of contract before running sendLiquidityRewards
        uint256 initialZeroContractBalance = zero.balanceOf(address(_zeroRewards));

        // Call sendLiquidityRewards, which should include directRewardsForZeroUSDCPoolID only for zeroUSDCPoolID
        _zeroRewards.sendLiquidityRewards(40 ether, poolIDs, profitsForPools);

        // There should be no revert, but let's calculate the rewards we expect to be sent
        uint256 totalProfits = profitsForPools[0] + profitsForPools[1];
        uint256 otherPoolRewards = (40 ether * profitsForPools[1]) / totalProfits;

        // Retrieve pending rewards from emitter to check correct distribution
        uint256[] memory pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);

        // Expectations after running the function.
        assertEq(zero.balanceOf(address(_zeroRewards)), initialZeroContractBalance - 40 ether + 1, "SendLiquidityRewards did not emit correct ZERO from contract balance.");
        assertEq(pendingRewards[1], otherPoolRewards, "SendLiquidityRewards incorrectly allocated direct ZERO rewards to pools");
    }
	}

