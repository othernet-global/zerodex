// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../dev/Deployment.sol";
import "../PoolUtils.sol";


contract TestPools2 is Deployment
	{
	TestERC20[] private tokens = new TestERC20[](10);

	address public alice = address(0x1111);
	address public bob = address(0x2222);
	address public charlie = address(0x3333);


	constructor()
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

		vm.startPrank(address(daoVestingWallet));
		zero.transfer(DEPLOYER, 1000000 ether);
		zero.transfer(address(liquidity), 1000000 ether);
		vm.stopPrank();

		vm.startPrank( DEPLOYER );
		for( uint256 i = 0; i < 10; i++ )
			{
			tokens[i] = new TestERC20("TEST", 18);
        	tokens[i].approve( address(pools), type(uint256).max );
        	tokens[i].approve( address(liquidity), type(uint256).max );

        	tokens[i].transfer(address(this), 100000 ether );
        	tokens[i].transfer(address(dao), 100000 ether );
        	tokens[i].transfer(address(liquidity), 100000 ether );
			}
		vm.stopPrank();

		for( uint256 i = 0; i < 9; i++ )
			{
			vm.prank(address(dao));
			poolsConfig.whitelistPool(   tokens[i], tokens[i + 1] );

			vm.prank(DEPLOYER);
			liquidity.depositLiquidityAndIncreaseShare( tokens[i], tokens[i + 1], 500 ether, 500 ether, 0, 0, 0, block.timestamp, false );
			}

		vm.prank(address(dao));
		poolsConfig.whitelistPool(   tokens[5], tokens[7] );
		vm.prank(address(dao));
		poolsConfig.whitelistPool(   tokens[0], tokens[9] );

		vm.startPrank( DEPLOYER );
		liquidity.depositLiquidityAndIncreaseShare( tokens[5], tokens[7], 1000 ether, 1000 ether, 0, 0, 0, block.timestamp, false );

		pools.deposit( tokens[5], 1000 ether );
		pools.deposit( tokens[6], 1000 ether );
		pools.deposit( tokens[7], 1000 ether );
		pools.deposit( tokens[8], 1000 ether );

		liquidity.depositLiquidityAndIncreaseShare( tokens[0], tokens[9], 1000000000 ether, 2000000000 ether, 0, 0, 0, block.timestamp, false );
		vm.stopPrank();

		for( uint256 i = 0; i < 10; i++ )
			{
        	tokens[i].approve( address(pools), type(uint256).max );
        	tokens[i].approve( address(liquidity), type(uint256).max );
        	}

		for( uint256 i = 0; i < 9; i++ )
			{
			pools.deposit( tokens[i], 1000 ether );
			liquidity.depositLiquidityAndIncreaseShare( tokens[i], tokens[i + 1], 500 ether, 500 ether, 0, 0, 0, block.timestamp, false );
        	}

		vm.startPrank(address(liquidity));
		for( uint256 i = 0; i < 10; i++ )
			{
        	tokens[i].approve( address(pools), type(uint256).max );
//			pools.deposit( tokens[i], 1000 ether );
        	}
		tokens[5].approve(address(pools), type(uint256).max );
    	vm.stopPrank();

		vm.startPrank(address(dao));
		tokens[5].approve(address(pools), type(uint256).max );
		pools.deposit(tokens[5], 1 ether);
		vm.stopPrank();

		tokens[5].approve(address(pools), type(uint256).max );
		pools.deposit(tokens[5], 1 ether);
		}



	function testGasAddLiquidity() public
		{
		vm.startPrank(address(liquidity));
		pools.addLiquidity( tokens[0], tokens[1], 1000 ether, 1000 ether, 0, 0, liquidity.totalShares( PoolUtils._poolID(tokens[0], tokens[1])));
		}


	function testEmpty() public
		{
		}


	function testEmptyPrank() public
		{
		vm.startPrank(address(liquidity));
		vm.stopPrank();
		}


	// A unit test that ensures adding/removing liquidity fails when token0 and token1 are identical.
	function testAddRemoveLiquidityIdenticalTokens() public
    	{
		vm.startPrank(address(liquidity));

        // Test that adding liquidity fails when token0 and token1 are the same.
        vm.expectRevert("Cannot add liquidity for duplicate tokens");
        pools.addLiquidity( tokens[0],  tokens[0], 100 ether, 100 ether, 0, 0, 0);

        // Test that removing liquidity fails when token0 and token1 are the same.
        vm.expectRevert();
        pools.removeLiquidity( tokens[0],  tokens[0], 50 ether, 0 ether, 0 ether, 0);
	    }


	// A unit test that handles a scenario where maxAmount0 exceeds the pool reserve ratio. The test should confirm that the function uss maxAmount1 and a proportional amoutn of maxAmount0, updates the reserves, and adjusts user's token balance
	function testAddLiquidityWithExceededMaxAmount0() public {
		vm.startPrank(address(liquidity));

        // Define tokens for the test
		uint256 userBalance0 = tokens[0].balanceOf( address(liquidity) );
        uint256 userBalance1 = tokens[1].balanceOf( address(liquidity) );

        // Define maxAmount0 and maxAmount1
        uint256 maxAmount0 = 1500 ether;
        uint256 maxAmount1 = 1000 ether;

        // Get the current reserves before adding liquidity
        (uint256 reserve0Before, uint256 reserve1Before) = pools.getPoolReserves(tokens[0], tokens[1]);

        // Calculate expected proportional maxAmount0
        uint256 expectedProportionalAmount0 = (maxAmount1 * reserve0Before) / reserve1Before;

        // Add liquidity
        pools.addLiquidity(tokens[0], tokens[1], maxAmount0, maxAmount1, 0, 0, liquidity.totalShares( PoolUtils._poolID(tokens[0], tokens[1])));

        // Get the reserves after adding liquidity
        (uint256 reserve0After, uint256 reserve1After) = pools.getPoolReserves(tokens[0], tokens[1]);

        // Assert that the reserves have been updated correctly
        assertEq(reserve0After, reserve0Before + expectedProportionalAmount0);
        assertEq(reserve1After, reserve1Before + maxAmount1);

        assertEq( tokens[0].balanceOf(address(liquidity)), userBalance0 - expectedProportionalAmount0);
        assertEq( tokens[1].balanceOf(address(liquidity)), userBalance1 - maxAmount1);
    }


	// A unit test that handles a scenario where maxAmount1 exceeds the pool reserve ratio. The test should confirm that the function uss maxAmount1 and a proportional amoutn of maxAmount1, updates the reserves, and adjusts user's token balance
	function testAddLiquidityWithExceededMaxAmount1() public {
		vm.startPrank(address(liquidity));

		// Define tokens for the test
        TestERC20 token0 = tokens[0];
        TestERC20 token1 = tokens[1];

		uint256 userBalance0 = token0.balanceOf( address(liquidity) );
        uint256 userBalance1 = token1.balanceOf( address(liquidity) );

        // Define maxAmount0 and maxAmount1
        uint256 maxAmount0 = 1000 ether;
        uint256 maxAmount1 = 1500 ether;

        // Get the current reserves before adding liquidity
        (uint256 reserve0Before, uint256 reserve1Before) = pools.getPoolReserves(token0, token1);

        // Calculate expected proportional maxAmount1
        uint256 expectedProportionalAmount1 = (maxAmount0 * reserve1Before) / reserve0Before;

        // Add liquidity
        pools.addLiquidity(token0, token1, maxAmount0, maxAmount1, 0, 0, liquidity.totalShares( PoolUtils._poolID(tokens[0], tokens[1])));

        // Get the reserves after adding liquidity
        (uint256 reserve0After, uint256 reserve1After) = pools.getPoolReserves(token0, token1);

        // Assert that the reserves have been updated correctly
        assertEq(reserve0After, reserve0Before + maxAmount0);
        assertEq(reserve1After, reserve1Before + expectedProportionalAmount1);

        assertEq( token0.balanceOf(address(liquidity)), userBalance0 - maxAmount0);
        assertEq( token1.balanceOf(address(liquidity)), userBalance1 - expectedProportionalAmount1);
    }


	// A unit test that verifies a token swap fails when the tokens array contains fewer than two tokens or more than two tokens, but the user hasn't deposited enough of the original token in the swap chain
	function testSwapFailures() public {
		vm.startPrank(address(liquidity));

		uint256 amountIn = 300 ether;

        // Deposit an insufficient balance of the initial token
        pools.deposit( tokens[0], amountIn - 1);

        vm.expectRevert("Insufficient deposited token balance of initial token");
        pools.swap(tokens[0], tokens[1], amountIn, 1 ether, block.timestamp);
    }


	// A unit test that handles scenarios related to exceeding pool reserve ratio, updating reserves, and adjusting user's token balance though deposits and withdrawals.
	function testReserveAndBalanceManagement() public
    	{
    	(uint256 token5PoolReserve, uint256 token7PoolReserve) = pools.getPoolReserves(tokens[5], tokens[7]);

    	// Scenario: Add liquidity and update pool reserves
    	vm.prank( address(dao));
    	poolsConfig.whitelistPool(  tokens[5], tokens[7] );

		vm.startPrank(address(liquidity));
    	pools.addLiquidity(tokens[5], tokens[7], 1 ether, 1 ether, 0, 0, liquidity.totalShares( PoolUtils._poolID(tokens[5], tokens[7])));

    	(uint256 token5PoolReserves2, uint256 token7PoolReserves2) = pools.getPoolReserves(tokens[5], tokens[7]);

    	assertEq(token5PoolReserve + 1 ether, token5PoolReserves2, "Pool reserve for token5 not updated correctly");
    	assertEq(token7PoolReserve + 1 ether, token7PoolReserves2, "Pool reserve for token7 not updated correctly");

    	// Scenario: Adjust user's token balance by depositing and withdrawing token
    	uint256 initialToken5Balance = tokens[5].balanceOf(address(liquidity));
    	uint256 initialToken7Balance = tokens[7].balanceOf(address(liquidity));

    	pools.deposit(tokens[5], 1 ether);
    	pools.deposit(tokens[7], 1 ether);

    	assertEq(initialToken5Balance - 1 ether, tokens[5].balanceOf(address(liquidity)), "Token5 balance not reduced after deposit");
    	assertEq(initialToken7Balance - 1 ether, tokens[7].balanceOf(address(liquidity)), "Token7 balance not reduced after deposit");

    	pools.withdraw(tokens[5], 1 ether);
    	pools.withdraw(tokens[7], 1 ether);

    	assertEq(initialToken5Balance, tokens[5].balanceOf(address(liquidity)), "Token5 balance not restored after withdrawal");
    	assertEq(initialToken7Balance, tokens[7].balanceOf(address(liquidity)), "Token7 balance not restored after withdrawal");
    	}


	// Test a token swap and check that k = reserve0 * reserve1 remains constant
	function _checkSwapK( uint256 added0, uint256 added1, uint256 added1b, uint256 added2, uint256 amountIn ) internal
		{
		vm.startPrank(address(liquidity));

		IERC20 token0 = new TestERC20("TEST", 6);
		IERC20 token1 = new TestERC20("TEST", 18);
		IERC20 token2 = new TestERC20("TEST", 6);

			{
			vm.stopPrank();

			vm.startPrank(address(dao));
			poolsConfig.whitelistPool(  token0, token1);
			poolsConfig.whitelistPool(  token1, token2);
			vm.stopPrank();

			vm.startPrank(address(liquidity));
			token0.approve( address(pools), type(uint256).max );
			token1.approve( address(pools), type(uint256).max );
			token2.approve( address(pools), type(uint256).max );

			pools.addLiquidity(token0, token1, added0, added1, 0, 0, liquidity.totalShares( PoolUtils._poolID(token0, token1)) );
			pools.addLiquidity(token1, token2, added1b, added2, 0, 0, liquidity.totalShares( PoolUtils._poolID(token1, token2)) );

			uint256 amountOut = pools.depositSwapWithdraw(token0, token1, amountIn, 0, block.timestamp);
			rollToNextBlock();
			pools.depositSwapWithdraw(token1, token2, amountOut, 0, block.timestamp);
			rollToNextBlock();
			}

		// Check that k is still the same
		(uint256 reserves0, uint256 reserves1) = pools.getPoolReserves(token0, token1);
		(uint256 reserves1b, uint256 reserves2) = pools.getPoolReserves(token1, token2);

		assertEq( ( reserves0 * reserves1 + 5*10**21 ) / 10**22, added0 * added1 / 10**22, "k(0-1) not equal" );
		assertEq( ( reserves1b * reserves2 + 5*10**21 ) / 10**22, added1b * added2 / 10**22, "k(1-2) not equal" );

		vm.stopPrank();
		}


	function testCheckSwapK() public
		{
		_checkSwapK( 1000 * 10**6, 2000 ether, 3000 ether, 4000 * 10**6, 500 * 10**6 );
		_checkSwapK( 4000 * 10**6, 3000 ether, 3000 ether, 1000 * 10**6, 500 * 10**6 );
		_checkSwapK( 1000 * 10**6, 2000 ether, 500 ether, 1000 * 10**6, 500 * 10**6 );
		_checkSwapK( 2000 * 10**6, 1000 ether, 2000 ether, 1000 * 10**6, 500 * 10**6 );
		}


	// A unit test that verifies token swap succeeds when the tokens array is adequate and user possesses all tokens.
	function testSuccessfulTokenSwap() public
    {
   		vm.startPrank(address(liquidity));

		// Make sure the user starts with zero deposited tokens[4]
		assertEq( pools.depositedUserBalance( address(liquidity), tokens[4] ), 0, "tokenOut should initial have zero deposits" );

        // Define the amount of the initial token to be used in the swap
        uint256 amountIn = 100 ether;

        // Define the minimum amount of the final token to be received from the swap
        uint256 minAmountOut = 1 ether;

        // Current timestamp plus 5 minutes
        uint256 deadline = block.timestamp + 5 minutes;

		pools.deposit(tokens[2], amountIn - 101 );

        // Call the swap function on the pools contract
		vm.expectRevert( "Insufficient deposited token balance of initial token" );
        pools.swap(tokens[2], tokens[3], amountIn, minAmountOut, deadline);
		rollToNextBlock();

		pools.deposit(tokens[2], 101 );
        uint256 amountOut = pools.swap(tokens[2], tokens[3], amountIn, 0, deadline);
		rollToNextBlock();
        pools.swap(tokens[3], tokens[4], amountOut, minAmountOut, deadline);
		rollToNextBlock();

		// Check that the user's deposited amount of tokens[2] is zero
		assertEq( pools.depositedUserBalance( address(liquidity), tokens[2] ), 0, "tokenIn deposited balance should now be zero" );

        // Check that the deposited balance of token is correct
        // the reserves for all pools in the transfer will initially be 1000 for each token
        assertEq(pools.depositedUserBalance( address(liquidity), tokens[4] ), 83.333333333333333332 ether , "Incorrect amountOut for final token in chain");
    }


	// A unit test that checks depositSwapWithdraw fails under various conditions, such as insufficient balance or allowance and verifies its correct operation under valid conditions.
	function testDepositSwapWithdraw() public {

        uint256 amountIn = 200 ether;

		vm.startPrank( alice );
		IERC20 tokenIn = new TestERC20("TEST", 18);
		IERC20 tokenOut = new TestERC20("TEST", 18);
		tokenIn.transfer( address(liquidity), amountIn - 1 );
		vm.stopPrank();


  		vm.startPrank(address(dao));
        poolsConfig.whitelistPool(  tokenIn, tokenOut);
		vm.stopPrank();

  		vm.startPrank(address(liquidity));
        uint256 minAmountOut = 1 ether;

		// Insufficient allowance?
		vm.expectRevert( "ERC20: insufficient allowance" );
        pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);

       	tokenIn.approve( address(pools), type(uint256).max );

        // Test for insufficient tokenIn balance
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);

        vm.stopPrank();

        // Provide necessary balance
		vm.prank( alice );
        tokenIn.transfer(address(liquidity), 1);

        // Test for low reserves
        vm.warp(block.timestamp + 1 hours);

  		vm.startPrank(address(liquidity));
        vm.expectRevert("Insufficient reserves before swap");
        pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);
		vm.stopPrank();

        // Add enough liquidity
        vm.startPrank( address(liquidity) );
		tokenIn.approve( address(pools), type(uint256).max );
		tokenOut.approve( address(pools), type(uint256).max );

		uint256 totalShares = liquidity.totalShares(PoolUtils._poolID(tokenIn, tokenOut));
		vm.expectRevert( "ERC20: transfer amount exceeds balance" );
        pools.addLiquidity(tokenIn, tokenOut, 1000 ether, 1000 ether, 0, 0, totalShares);
        vm.stopPrank();

  		vm.prank(alice);
        tokenIn.transfer(address(liquidity), 1000 ether );

  		vm.prank(alice);
        tokenOut.transfer(address(liquidity), 1000 ether );

		vm.startPrank( address(liquidity) );
        pools.addLiquidity(tokenIn, tokenOut, 1000 ether, 1000 ether, 0, 0, totalShares);

        // Test for correct operation under valid conditions
        assertEq( tokenOut.balanceOf( address(liquidity) ), 0, "Test wallet shoudl start with zero tokenOut" );
        uint256 amountOut = pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);

        assertEq(amountOut, 166.666666666666666666 ether, "Unexpected amountOut");

        assertEq( tokenOut.balanceOf( address(liquidity) ), amountOut, "Test wallet tokenOut balance is not amountOut" );
        vm.stopPrank();
    }


	// A unit test that tests all functions with invalid user addresses, non-existent tokens, or a token that has not been deposited, and returns zero for all such cases. This test also includes calls from the contract's owner.
	function testInvalidInputs() public {
   		vm.startPrank(address(liquidity));

        // Invalid user addresses and non-existent tokens
        IERC20 nonExistentToken = IERC20(address(0));

        // Test with invalid user address and non-existent token
        assertEq(0, pools.depositedUserBalance(address(0), nonExistentToken));

//        assertEq(0, pools.getTotalReserveForToken(nonExistentToken)); // will fail on nonExistentToken.balanceOf

        bytes32 poolID = PoolUtils._poolID(tokens[0], nonExistentToken);
        assertEq(0, liquidity.userShareForPool(address(0), poolID));
        assertEq(0, liquidity.totalShares(poolID));

		// Will fail due to reliance on balance of
//        vm.expectRevert("Insufficient allowance to deposit");
//        pools.deposit(nonExistentToken, 1000 ether);
//        vm.expectRevert("Insufficient balance to withdraw specified amount");
//        pools.withdraw(nonExistentToken, 1000 ether);

        // Test with token that has not been deposited
        IERC20 undepositedToken = new TestERC20("TEST", 18);
        vm.stopPrank();

        vm.prank(address(dao));
        poolsConfig.whitelistPool(  tokens[0], undepositedToken);

   		vm.startPrank(address(liquidity));
        assertEq(0, pools.depositedUserBalance(address(liquidity), undepositedToken));
        poolID = PoolUtils._poolID(tokens[0], undepositedToken);
        assertEq(0, liquidity.userShareForPool(DEPLOYER, poolID));
        assertEq(0, liquidity.totalShares(poolID));

        vm.expectRevert("ERC20: insufficient allowance");
        pools.addLiquidity(tokens[0], undepositedToken, 1000 ether, 1000 ether, 0, 0, 0);

        undepositedToken.approve( address(pools), type(uint256).max );

		vm.expectRevert( "The amount of liquidityToRemove cannot be zero" );
        pools.removeLiquidity(tokens[0], undepositedToken, 0, 1000 ether, 1000 ether, 0);

        vm.expectRevert("Insufficient balance to withdraw specified amount");
        pools.withdraw(undepositedToken, 1000 ether);

        vm.expectRevert("Insufficient deposited token balance of initial token");
        pools.swap(undepositedToken, tokens[0], 1000 ether, 1 ether, block.timestamp);

        vm.expectRevert("Insufficient reserves before swap");
        pools.depositSwapWithdraw(undepositedToken, tokens[0], 1000 ether, 1 ether,  block.timestamp);
    }


	// A unit test that ensures addLiquidity fails under various conditions and validates its correct initialization and operation under valid conditions.
	function testAddLiquidity() public
    {
        vm.startPrank(address(liquidity));
        IERC20 tokenA = new TestERC20("TEST", 18);
        IERC20 tokenB = new TestERC20("TEST", 18);
		vm.stopPrank();

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  tokenA, tokenB);

        vm.startPrank(address(liquidity));

		// Check that adding liquidity with the same token fails
        vm.expectRevert("Cannot add liquidity for duplicate tokens");
        pools.addLiquidity(tokenA, tokenA, 10 ether, 10 ether, 0, 0, 0);

        // Check that adding liquidity with insufficient allowance fails
        vm.expectRevert("ERC20: insufficient allowance");
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, 0, 0);

        // Check that adding liquidity with insufficient balance fails
        tokenA.approve(address(pools), 5 ether);
        tokenB.approve(address(pools), 5 ether);
        vm.expectRevert("ERC20: insufficient allowance");
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, 0, 0);

		// Send all of token A elsewhere
		tokenA.transfer( address(0x1111), tokenA.balanceOf(address(liquidity)));

        tokenA.approve(address(pools), 10 ether);
        tokenB.approve(address(pools), 10 ether);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, 0, 0);
		vm.stopPrank();

		vm.startPrank( address(0x1111) );
		tokenA.transfer( address(liquidity), tokenA.balanceOf(address(0x1111)));
		vm.stopPrank();

   		vm.startPrank(address(liquidity));

        // Now add valid liquidity and confirm it has been added
        uint256 initialA = tokenA.balanceOf(address(liquidity));
        uint256 initialB = tokenB.balanceOf(address(liquidity));
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, 0, 0);
        assertEq(initialA - 10 ether, tokenA.balanceOf(address(liquidity)));
        assertEq(initialB - 10 ether, tokenB.balanceOf(address(liquidity)));

        // Check liquidity pool state
        (uint256 poolA, uint256 poolB) = pools.getPoolReserves(tokenA, tokenB);
        assertEq(poolA, 10 ether);
        assertEq(poolB, 10 ether);
    }


	// A unit test that checks removeLiquidity failure conditions and confirms its correct operation when the user has enough liquidity.
	function _testRemoveLiquidity() public
    {
   		vm.startPrank(address(liquidity));
        IERC20 token0 = new TestERC20("TEST", 18);
        IERC20 token1 = new TestERC20("TEST", 6);
		vm.stopPrank();

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token0, token1);

   		vm.startPrank(address(liquidity));
        token0.approve(address(pools), type(uint256).max);
        token1.approve(address(pools), type(uint256).max);

		uint256 added0 = 2000 ether;
		uint256 added1 = 1000 * 10 ** 6;
		uint256 liquidityAdded;

        (added0, added1, liquidityAdded) = pools.addLiquidity(token0, token1, added0, added1, 0, 0, 0 );

        // Test failure when liquidityToRemove is too small
        vm.expectRevert("Insufficient underlying tokens returned");
        pools.removeLiquidity(token0, token1, 10, added0, added1, liquidityAdded);

        // Test failure when user doesn't have enough liquidity
        vm.expectRevert();
        pools.removeLiquidity(token0, token1, liquidityAdded + 1, added0, added1, liquidityAdded);

        // Test failure when minReclaimed0 is not met
        vm.expectRevert("Insufficient underlying tokens returned");
        pools.removeLiquidity(token0, token1, liquidityAdded / 2, added0 / 2 + 1, added1 / 2, liquidityAdded);

        // Test failure when minReclaimed1 is not met
        vm.expectRevert("Insufficient underlying tokens returned");
        pools.removeLiquidity(token0, token1, liquidityAdded / 2, added0 / 2, added1 / 2 + 1, liquidityAdded);

		// Can't remove all the liquidity
		vm.expectRevert( "Insufficient reserves after liquidity removal" );
        (uint256 reclaimed0, uint256 reclaimed1) = pools.removeLiquidity(token0, token1, liquidityAdded, 0, 0, liquidityAdded);

        // Test successful operation
        (reclaimed0, reclaimed1) = pools.removeLiquidity(token0, token1, liquidityAdded * ( added1 - PoolUtils.DUST ) / added1, 0, 0, liquidityAdded);

		(uint256 reserves0, uint256 reserves1) = pools.getPoolReserves(token0, token1);

		assertEq( reserves0, 200000000000000 );
		assertEq( reserves1, 100 );
    }

	function testRemoveLiquidity() public
		{
		// Run the test multiple times to allow different reserve token order for the tokens
		for( uint256 i = 0; i < 20; i++ )
			_testRemoveLiquidity();
		}


	// A unit test that tests depositing and withdrawing tokens, both under failure conditions (insufficient balance, allowance, or deposited tokens) and correct operations.
	function testDepositWithdraw() public {
   		vm.startPrank(address(liquidity));

        TestERC20 token = new TestERC20("TEST", 18);

        uint256 initialBalance = token.balanceOf(address(liquidity));

        // Test deposit
        uint256 depositAmount = 500 ether;
        vm.expectRevert( "ERC20: insufficient allowance" );
        pools.deposit(token, depositAmount);

        token.approve(address(pools), 1000 ether);
        pools.deposit(token, depositAmount);

        assertEq(token.balanceOf(address(liquidity)), initialBalance - depositAmount);
        assertEq(pools.depositedUserBalance(address(liquidity), token), depositAmount);

        // Test failure when trying to withdraw more than the deposited amount
        vm.expectRevert("Insufficient balance to withdraw specified amount");
        pools.withdraw(token, depositAmount + 1);

        pools.withdraw(token, depositAmount/2);
        pools.withdraw(token, depositAmount/2);

        // Test failure when trying to withdraw without having any remaining tokens
        vm.expectRevert("Insufficient balance to withdraw specified amount");
        pools.withdraw(token, 1);

        // Test depositing more tokens and then withdrawing
        depositAmount = 250 ether;

        pools.deposit(token, depositAmount);
        assertEq(token.balanceOf(address(liquidity)), initialBalance - depositAmount);
        assertEq(pools.depositedUserBalance(address(liquidity), token), depositAmount);

        uint256 withdrawAmount = 100 ether;
        pools.withdraw(token, withdrawAmount);
        assertEq(token.balanceOf(address(liquidity)), initialBalance - depositAmount + withdrawAmount);
        assertEq(pools.depositedUserBalance(address(liquidity), token), depositAmount - withdrawAmount);

        // Test withdrawing all remaining deposited tokens
        pools.withdraw(token, depositAmount - withdrawAmount);
        assertEq(token.balanceOf(address(liquidity)), initialBalance);
        assertEq(pools.depositedUserBalance(address(liquidity), token), 0);
    }


	// A unit test that verifies a token swap fails under various conditions and checks a valid token swap with multiple tokens in the path.
	function testTokenSwap() public
    {
   		vm.startPrank(address(liquidity));

   		pools.deposit(tokens[5], 1000 ether);

        // Test that swap fails with insufficient balance
        vm.expectRevert("Insufficient deposited token balance of initial token");
        pools.swap(tokens[5], tokens[6], 1500 ether, 1 ether, block.timestamp + 60);

        vm.expectRevert("Insufficient resulting token amount");
        pools.swap(tokens[5], tokens[6], 500 ether, 1500 ether, block.timestamp + 60);

        // Test valid swap with two tokens
        pools.swap(tokens[5], tokens[6], 250 ether, 1 ether, block.timestamp + 60);
        assertEq(pools.depositedUserBalance(address(liquidity), tokens[5]), 750 ether);
    }


	// A unit test that validates view functions (getUserLiquidity, getTotalLiquidity, getPoolReserves) with valid data.
	function testViewFunctions() public
    	{
   		vm.startPrank(address(liquidity));

    	IERC20 token0 = tokens[5];
    	IERC20 token1 = tokens[6];

    	// User liquidity is sqrt(amount0 * amount1) and 500 ether of each token were initially deposited
    	bytes32 poolID = PoolUtils._poolID(token0, token1);
    	uint256 userLiquidity = liquidity.userShareForPool(DEPLOYER, poolID);
    	assertEq(userLiquidity, 1000 ether, "User liquidity mismatch");

    	// View total liquidity
    	uint256 totalLiquidity = liquidity.totalShares(poolID);
    	assertEq(totalLiquidity, 2000 ether, "Total liquidity mismatch");

    	// View pool reserves
    	(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);
    	assertEq(reserve0, 1000 ether, "Reserve0 mismatch");
    	assertEq(reserve1, 1000 ether, "Reserve1 mismatch");
    	}


	// A unit test that checks function failures (addLiquidity, removeLiquidity, swap, depositSwapWithdraw) when the deadline has expired.
	function testExpiredDeadline() public
        {
   		vm.startPrank(address(liquidity));

        uint256 deadline = block.timestamp - 1; // Set deadline in the past

        // Swap
        vm.expectRevert("TX EXPIRED");
        pools.swap(tokens[0], tokens[1], 1000 ether, 1 ether, deadline);

        // Deposit Swap Withdraw
        vm.expectRevert("TX EXPIRED");
        pools.depositSwapWithdraw(tokens[0], tokens[1], 1000 ether, 1 ether, deadline);
        }


	// A unit test that verifies correct return values from functions like PoolUtils._poolID, getTotalLiquidity, getPoolReserves, getUserLiquidity after successful operations.
	function testReturnValues() public
        {
   		vm.startPrank(address(liquidity));

        IERC20 token0 = tokens[0];
        IERC20 token1 = tokens[1];

        bytes32 poolID;
        bool flipped;

        (poolID, flipped) = PoolUtils._poolIDAndFlipped(IERC20(address(0x111)), IERC20(address(0x222)));
        assertFalse(flipped, "Expected PoolUtils._poolID to return flipped as false");

        (poolID, flipped) = PoolUtils._poolIDAndFlipped(IERC20(address(0x222)), IERC20(address(0x111)));
        assertTrue(flipped, "Expected PoolUtils._poolID to return flipped as true");

    	poolID = PoolUtils._poolID(token0, token1);
        uint256 totalLiquidity = liquidity.totalShares(poolID);
        assertEq(totalLiquidity, 2000 ether, "Expected totalLiquidity to return 1000 ether");

        uint256 reserve0;
        uint256 reserve1;
        (reserve0, reserve1) = pools.getPoolReserves(token0, token1);
        assertEq(reserve0, 1000 ether, "Expected reserve0 to return 1000 ether");
        assertEq(reserve1, 1000 ether, "Expected reserve1 to return 1000 ether");

        uint256 userLiquidity = liquidity.userShareForPool(DEPLOYER, PoolUtils._poolID(token0, token1));
        assertEq(userLiquidity, 1000 ether, "Expected getUserLiquidity to return 500 ether");

        pools.addLiquidity(token0, token1, 500 ether, 500 ether, 0, 0, liquidity.totalShares(poolID));
        vm.warp(block.timestamp + 15 minutes);


        (reserve0, reserve1) = pools.getPoolReserves(token0, token1);
        assertEq(reserve0, 1500 ether, "Expected reserve0 to return 1500 ether");
        assertEq(reserve1, 1500 ether, "Expected reserve1 to return 1500 ether");
        }


	// A unit test that ensures function failures when trying to operate (removeLiquidity, swap, depositSwapWithdraw) with pools that have no liquidity.
	function testFailNoLiquidityOperations() public {
   		vm.startPrank(address(liquidity));

    	IERC20 tokenA = tokens[9]; // The 10th token in your array which has no liquidity in the pool
    	IERC20 tokenB = tokens[0]; // The first token in your array which has liquidity in the pool

    	// Expect revert on removeLiquidity operation with a pool that has no liquidity
    	vm.expectRevert("Insufficient balance to remove more liquidity than the current balance");
    	pools.removeLiquidity(tokenA, tokenB, 1000 ether, 0, 0, 0);

    	// Expect revert on swap operation with a pool that has no liquidity
    	vm.expectRevert("Insufficient deposited token balance of initial token");
    	pools.depositSwapWithdraw(tokenA, tokenB, 1000 ether, 0, 0);
    }


	// Chop off the last two digits of 18 decimal numbers and compare
	function _assertAlmostEqual( uint256 a, uint256 b ) public
		{
		assertEq( a / 100, b / 100 );
		}


	// A unit test that tests addLiquidity return values
	function testAddLiquidityReturnValues() public {
   		vm.startPrank(address(liquidity));
       	IERC20 token0 = new TestERC20("TEST", 18);
       	IERC20 token1 = new TestERC20("TEST", 18);
       	vm.stopPrank();

       	vm.prank(address(dao));
       	poolsConfig.whitelistPool(  token0, token1);

   		vm.startPrank(address(liquidity));
    	token0.transfer(alice, 1000 ether);
		token0.transfer(bob, 1000 ether);
    	token1.transfer(alice, 1000 ether);
		token1.transfer(bob, 1000 ether);
		vm.stopPrank();

		vm.startPrank(address(liquidity));
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		// Alice adds some liquidity
		uint256 userToken0 = token0.balanceOf( address(liquidity) );
        uint256 userToken1 = token1.balanceOf( address(liquidity) );

		vm.prank(address(liquidity));
		(uint256 added0, uint256 added1, uint256 addedLiquidity) = pools.addLiquidity( token0, token1, 200 ether, 100 ether, 0, 0, 0 );
		assertEq( 200 ether + 100 ether, addedLiquidity );

		uint256 aliceAdded0 = userToken0 - token0.balanceOf( address(liquidity) );
        uint256 aliceAdded1 = userToken1 - token1.balanceOf( address(liquidity) );
        assertEq( aliceAdded0, added0 );
        assertEq( aliceAdded1, added1 );

		userToken0 = token0.balanceOf( address(liquidity) );
        userToken1 = token1.balanceOf( address(liquidity) );

		vm.prank(address(liquidity));
		(added0, added1, addedLiquidity) = pools.addLiquidity( token0, token1, 250 ether, 100 ether, 0, 0, addedLiquidity );

		uint256 bobAdded0 = userToken0 - token0.balanceOf( address(liquidity) );
        uint256 bobAdded1 = userToken1 - token1.balanceOf( address(liquidity) );
        assertEq( bobAdded0, added0 );
        assertEq( bobAdded1, added1 );

//		uint256 bobLiquidity1 = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
//		assertEq( addedLiquidity, bobLiquidity1 );

//
//		userToken0 = token0.balanceOf( bob );
//        userToken1 = token1.balanceOf( bob );
//
//		vm.prank(address(liquidity));
//		(added0, added1, addedLiquidity) = pools.addLiquidity( token0, token1, 200 ether, 150 ether, 0, liquidity.totalSharesForPool(PoolUtils._poolID(token0, token1)) );
//
//		bobAdded0 = userToken0 - token0.balanceOf( bob );
//        bobAdded1 = userToken1 - token1.balanceOf( bob );
//        assertEq( bobAdded0, added0 );
//        assertEq( bobAdded1, added1 );

//		uint256 bobLiquidity2 = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
//		assertEq( addedLiquidity, bobLiquidity2 - bobLiquidity1 );
		}


	// A unit test with interleaved liquidity adds, swaps, and liquidity removals from multiple users
	function testMultipleInteractions() public {
   		vm.startPrank(address(liquidity));

       	IERC20 token0 = new TestERC20("TEST", 18);
       	IERC20 token1 = new TestERC20("TEST", 18);
       	vm.stopPrank();

		vm.prank(address(dao));
       	poolsConfig.whitelistPool(  token0, token1);

   		vm.startPrank(address(liquidity));
    	token0.transfer(alice, 1000 ether);
		token0.transfer(bob, 1000 ether);
		token0.transfer(charlie, 1000 ether);
    	token1.transfer(alice, 1000 ether);
		token1.transfer(bob, 1000 ether);
		token1.transfer(charlie, 1000 ether);
		vm.stopPrank();

		vm.startPrank(alice);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(charlie);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		// Alice adds some liquidity
		vm.prank(alice);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 200 ether, 100 ether, 0, 0, 0, block.timestamp, false );
		vm.warp( block.timestamp + 1 hours );
		rollToNextBlock();

		// Bob depositSwapWithdraws 10 ether token0 for token1
		vm.prank(bob);
		uint256 amountOut = pools.depositSwapWithdraw(token0, token1, 10 ether, 1 ether, block.timestamp);
		_assertAlmostEqual( amountOut, 4761904761904761905 );
		rollToNextBlock();

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0,token1);
		_assertAlmostEqual( reserve0, 210000000000000000000 );
		_assertAlmostEqual( reserve1, 95238095238095238095 );

		// Charlie deposits 20 ether token1
		vm.startPrank(charlie);
		pools.deposit(token1, 20 ether);

		// Charlie swaps 20 ether token1 for token0
		uint256 charlieToken0 = pools.swap(token1, token0, 20 ether, 1 ether, block.timestamp);
		_assertAlmostEqual( charlieToken0, 36446280991735537191 );
		vm.stopPrank();
		rollToNextBlock();

			{
			(uint256 aliceReserve0, uint256 aliceReserve1) = pools.getPoolReserves(token0,token1);
			_assertAlmostEqual( aliceReserve0, 173553719008264462809 );
			_assertAlmostEqual( aliceReserve1, 115238095238095238095 );
	//		console.log( "aliceReserve0: ", aliceReserve0 );
	//		console.log( "aliceReserve1: ", aliceReserve1 );


			// Bob adds an extra half of the current liquidity
			vm.prank(bob);
			liquidity.depositLiquidityAndIncreaseShare(token0, token1, 86776859504132231404, 57619047619047619047, 0, 0, 0, block.timestamp, true);
		vm.warp( block.timestamp + 1 hours );

			(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
			_assertAlmostEqual( reserve0, 260330578512396694213 );
			_assertAlmostEqual( reserve1, 172857142857142857142 );
	//		console.log( "reserve0: ", reserve0 );
	//		console.log( "reserve1: ", reserve1 );

			// Charlie adds an extra 25% of the current liquidity
			vm.prank(charlie);
			liquidity.depositLiquidityAndIncreaseShare(token0, token1, 65082644628099173553, 43214285714285714285, 0, 0, 0, block.timestamp, true);
		vm.warp( block.timestamp + 1 hours );

			(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
			_assertAlmostEqual( reserve0, 325413223140495867766 );
			_assertAlmostEqual( reserve1, 216071428571428571427 );
	//		console.log( "reserve0: ", reserve0 );
	//		console.log( "reserve1: ", reserve1 );


			// Alice removes her liquidity
			uint256 aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
			_assertAlmostEqual( aliceLiquidity, 300 ether );
			bytes32 poolID = PoolUtils._poolID(token0, token1);
			_assertAlmostEqual( liquidity.totalShares(poolID), 562499999999999999999);
	//		console.log( "aliceLiquidity: ", aliceLiquidity );
	//		console.log( "totalLiquidity: ", pools.getTotalLiquidity(token0,token1) );

			vm.prank(alice);
			(uint256 reclaimed0, uint256 reclaimed1) = liquidity.withdrawLiquidityAndClaim(token0, token1, 300 ether, 0, 0, block.timestamp);
		vm.warp( block.timestamp + 1 hours );

			// Alice should have reclaimed the liquidity that was there before bob and charlie added theirs
			_assertAlmostEqual( reclaimed0, aliceReserve0 );
			_assertAlmostEqual( reclaimed1, aliceReserve1 );
			}
//		console.log( "reclaimed0: ", reclaimed0 );
//		console.log( "reclaimed1: ", reclaimed1 );


		// Charlie swaps all his deposited token0 for token 1
		vm.prank(charlie);
		amountOut = pools.swap(token0, token1, charlieToken0, 1 ether, block.timestamp);
		_assertAlmostEqual( amountOut, 19516129032258064517 );
		rollToNextBlock();

		(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
		_assertAlmostEqual( reserve0, 188305785123966942148 );
		_assertAlmostEqual( reserve1, 81317204301075268815 );


		// Bob swaps 10 ether token0 for token1
//		vm.prank(bob);
//		amountOut = pools.depositSwapWithdraw(token0, token1, 10 ether, 1 ether, block.timestamp);
//		_assertAlmostEqual( amountOut, 4100596674486396136 );
//
//		(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
//		_assertAlmostEqual( reserve0, 188305785123966942148 + 10 ether );
//		_assertAlmostEqual( reserve1, 81317204301075268815 - 4100596674486396136 );
	    }


	// A unit test in which alice, bob and charlie interleave multiple add liquidity and remove liquidity calls.
	// No swaps are done, but at the end all liquidity is remove and the users should ensure that they have reclaimed what they originally added.
	function testMultiAddRemoveLiquidity() public {
   		vm.startPrank(address(liquidity));
       	IERC20 token0 = new TestERC20("TEST", 18);
       	IERC20 token1 = new TestERC20("TEST", 18);
       	vm.stopPrank();

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token0, token1);

   		vm.startPrank(address(liquidity));
		bytes32 poolID = PoolUtils._poolID(token0, token1);

		// alice, bob and charlie initially have 1000 of each token
    	token0.transfer(alice, 1000 ether);
		token0.transfer(bob, 1000 ether);
		token0.transfer(charlie, 1000 ether);
    	token1.transfer(alice, 1000 ether);
		token1.transfer(bob, 1000 ether);
		token1.transfer(charlie, 1000 ether);
		vm.stopPrank();

		// Approvals for adding liquidity
		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(charlie);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		vm.stopPrank();

		// Multiple liquidity adds and removals
		vm.prank(alice);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 200 ether, 100 ether, 0, 0, 0, block.timestamp, false );

		vm.prank(bob);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 400 ether, 200 ether, 0, 0, 0, block.timestamp, false );

		vm.prank(charlie);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 100 ether, 50 ether, 0, 0, 0, block.timestamp, false );

		vm.warp( block.timestamp + 1 hours);

		uint256 aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		uint256 bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		uint256 charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));

		vm.prank(alice);
		liquidity.withdrawLiquidityAndClaim( token0, token1, aliceLiquidity / 2, 0, 0, block.timestamp );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		vm.prank(bob);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 600 ether, 300 ether, 0, 0, 0, block.timestamp, false );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		vm.prank(charlie);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 100 ether, 50 ether, 0, 0, 0, block.timestamp, false );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		vm.warp( block.timestamp + 1 hours );

		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		vm.prank(bob);
		liquidity.withdrawLiquidityAndClaim( token0, token1, bobLiquidity, 0, 0, block.timestamp );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		vm.prank(alice);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 100 ether, 100 ether, 0, 0, 0, block.timestamp, false );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		vm.warp( block.timestamp + 1 hours );

		vm.prank(bob);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 100 ether, 100 ether, 0, 0, 0, block.timestamp, false );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		vm.prank(charlie);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 100 ether, 50 ether, 0, 0, 0, block.timestamp, false );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		// Remove all liquidity
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		vm.prank(alice);
		liquidity.withdrawLiquidityAndClaim( token0, token1, aliceLiquidity, 0, 0, block.timestamp );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		vm.warp( block.timestamp + 1 hours );

		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		vm.prank(bob);
		liquidity.withdrawLiquidityAndClaim( token0, token1, bobLiquidity, 0, 0, block.timestamp );
		aliceLiquidity = liquidity.userShareForPool(alice, PoolUtils._poolID(token0, token1));
		bobLiquidity = liquidity.userShareForPool(bob, PoolUtils._poolID(token0, token1));
		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		assertEq( liquidity.totalShares(poolID), aliceLiquidity + bobLiquidity + charlieLiquidity );

		charlieLiquidity = liquidity.userShareForPool(charlie, PoolUtils._poolID(token0, token1));
		vm.prank(charlie);
		liquidity.withdrawLiquidityAndClaim( token0, token1, charlieLiquidity * ( 100 ether - PoolUtils.DUST ) / 100 ether, 0, 0, block.timestamp );

		// As there were no swaps the pulled liquidity should result in the original balances
		assertEq( token0.balanceOf(alice), 1000 ether );
		assertEq( token0.balanceOf(bob), 1000 ether );
		assertEq( token0.balanceOf(charlie), 1000 ether - 300 );

		assertEq( token1.balanceOf(alice), 1000 ether );
		assertEq( token1.balanceOf(bob), 1000 ether );
		assertEq( token1.balanceOf(charlie), 1000 ether - 150 );
	    }


	// Function to check that with multiple users and multiple swaps the total number of tokens on the exchange remains constant and correct addLiquidity values are returned
	function _checkMultipleSwaps( uint8 decimals0, uint8 decimals1, uint256 units0, uint256 units1 ) internal {

   		vm.startPrank(address(liquidity));
       	IERC20 token0 = new TestERC20("TEST", decimals0);
       	IERC20 token1 = new TestERC20("TEST", decimals1);

		// alice, bob and charlie initially have 1000 of each token
    	token0.transfer(alice, 10000 * units0);
		token0.transfer(bob, 10000 * units0);
		token0.transfer(charlie, 10000 * units0);
    	token1.transfer(alice, 10000 * units1);
		token1.transfer(bob, 10000 * units1);
		token1.transfer(charlie, 10000 * units1);
		vm.stopPrank();

		// Approvals for adding liquidity
		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(charlie);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		vm.stopPrank();

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token0, token1);

		// Add the initial liquidity
		vm.startPrank(alice);

		uint256 balanceA = token0.balanceOf(alice);
		uint256 balanceB = token1.balanceOf(alice);
   		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 1000 * units0, 500 * units1, 0, 0, 0, block.timestamp, false );
		uint256 added0 = balanceA - token0.balanceOf(alice);
		uint256 added1 = balanceB - token1.balanceOf(alice);

		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);

		vm.warp( block.timestamp + 1 hours );

		balanceA = token0.balanceOf(alice);
		balanceB = token1.balanceOf(alice);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 1000 * units0, 500 * units1, 0, 0, 0, block.timestamp, false );
		added0 = balanceA - token0.balanceOf(alice);
		added1 = balanceB - token1.balanceOf(alice);

		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);
		vm.stopPrank();


		balanceA = token0.balanceOf(bob);
		balanceB = token1.balanceOf(bob);
		vm.prank(bob);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 1000 * units0, 500 * units1, 0, 0, 0, block.timestamp, false );
		added0 = balanceA - token0.balanceOf(bob);
		added1 = balanceB - token1.balanceOf(bob);

		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);

		balanceA = token0.balanceOf(charlie);
		balanceB = token1.balanceOf(charlie);
		vm.prank(charlie);
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 1000 * units0, 500 * units1, 0, 0, 0, block.timestamp, false );
		added0 = balanceA - token0.balanceOf(charlie);
		added1 = balanceB - token1.balanceOf(charlie);

		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);

		vm.warp( block.timestamp + 1 hours );

		vm.prank(alice);
		pools.deposit( token0, 500 * units0 );


		// Multiple swaps
		{
		vm.prank(alice);
		pools.swap( token0, token1, 500 * units0, 0 ether, block.timestamp );
		rollToNextBlock();

		vm.prank(bob);
		pools.depositSwapWithdraw(token1, token0, 500 * units1, 0 ether, block.timestamp );

		vm.prank(charlie);
		pools.depositSwapWithdraw(token1, token0, 500 * units1, 0 ether, block.timestamp );

		vm.prank(alice);
		pools.swap( token1, token0, 100 * units1, 0 ether, block.timestamp );
		rollToNextBlock();

		vm.prank(bob);
		pools.depositSwapWithdraw(token0, token1, 100 * units0, 0 * units1, block.timestamp );

		vm.prank(charlie);
		pools.depositSwapWithdraw(token0, token1, 100 * units0, 0 * units1, block.timestamp );

		vm.prank(alice);
		pools.swap( token0, token1, 10 * units0, 0 * units1, block.timestamp );
		rollToNextBlock();

		vm.prank(bob);
		pools.depositSwapWithdraw(token1, token0, 10 * units1, 0 * units0, block.timestamp );

		vm.prank(charlie);
		pools.depositSwapWithdraw(token1, token0, 10 * units1, 0 * units0, block.timestamp );
		}

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);

		// After all of the swaps, the amount of each token should be the starting liquidity
		assertEq( reserve0 + pools.depositedUserBalance( alice, token0 ) + token0.balanceOf(alice) + token0.balanceOf(bob) + token0.balanceOf(charlie), 30000 * units0 );
		assertEq( reserve1 + pools.depositedUserBalance( alice, token1 ) + token1.balanceOf(alice) + token1.balanceOf(bob) + token1.balanceOf(charlie), 30000 * units1 );
	    }


	// Unit test to check that with multiple users and multiple swaps the total number of tokens on the exchange remains constant.
	// Check various decimals to make sure every works as expected
	function testMultipleSwaps() public
		{
		_checkMultipleSwaps( 18, 18, 10**18, 10**18 );
		_checkMultipleSwaps( 6, 18, 10**6, 10**18 );
		_checkMultipleSwaps( 18, 6, 10**18, 10**6 );
		_checkMultipleSwaps( 6, 12, 10**6, 10**12 );
		_checkMultipleSwaps( 12, 6, 10**12, 10**6 );
		}


	function _checkReserves( uint256 a, uint256 b, uint256 c, uint256 d ) public
		{
		vm.startPrank(address(liquidity));

        // Define the array of tokens to be used in the swap operation
        IERC20[] memory chain = new IERC20[](3);
        chain[0] = new TestERC20("TEST", 18);
        chain[1] = new TestERC20("TEST", 18);
        chain[2] = new TestERC20("TEST", 18);

		chain[0].approve(address(pools),type(uint256).max);
		chain[1].approve(address(pools),type(uint256).max);
		chain[2].approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(address(dao));
		poolsConfig.whitelistPool(  chain[0], chain[1]);
		poolsConfig.whitelistPool(  chain[1], chain[2]);
		vm.stopPrank();

		vm.startPrank(address(liquidity));
		pools.addLiquidity( chain[0], chain[1], a, b, 0, 0, 0 );
		pools.addLiquidity( chain[1], chain[2], c, d, 0, 0, 0 );

		(uint256 reserves0, uint256 reserves1) = pools.getPoolReserves( chain[0], chain[1] );
		(uint256 reserves1b, uint256 reserves2) = pools.getPoolReserves( chain[1], chain[2] );

		assertEq( reserves0, a, "incorrect checkReserves a" );
		assertEq( reserves1, b, "incorrect checkReserves b" );
		assertEq( reserves1b, c, "incorrect checkReserves c" );
		assertEq( reserves2, d, "incorrect checkReserves d" );

		vm.stopPrank();
		}

	function testCheckReserves() public
		{
		_checkReserves( 1000 ether, 100 ether, 200 ether, 2000 ether );
		_checkReserves( 1000 ether, 100 ether, 2000 ether, 200 ether );
		_checkReserves( 100 ether, 1000 ether, 200 ether, 2000 ether );
		_checkReserves( 100 ether, 1000 ether, 2000 ether, 200 ether );
		}


	function _checkNumbersClose( uint256 x, uint256 y ) public pure returns (bool)
		{
		if ( x > y )
			return ( x * 999999 / 1000000 ) < y;

		if ( x < y )
			return ( y * 999999 / 1000000 ) < x;

		return true;
		}


	// A unit test that checks the addition of dust liquidity
	function testAddingDustLiquidity() public
		{
		vm.warp( block.timestamp + 1 hours );
		liquidity.depositLiquidityAndIncreaseShare( tokens[0], tokens[1], 101, 101, 0, 0, 0, block.timestamp, false );

		vm.warp( block.timestamp + 1 hours );

		vm.expectRevert( "The amount of tokenA to add is too small" );
		liquidity.depositLiquidityAndIncreaseShare( tokens[0], tokens[1], 99, 101, 0, 0, 0, block.timestamp, false );
		}


// A unit test that tests that minLiquidityReceived, minReclaimedA and minReclaimedB cause correct reversions if they are not satisfied on an addLiquidity or removeLiquidity call.
function testMinLiquidityAndReclaimedAmounts() public {
    vm.startPrank(address(liquidity));

    // Define tokens for the test
    TestERC20 token0 = tokens[0];
    TestERC20 token1 = tokens[1];

    // Define an excessive minLiquidityReceived
    uint256 excessiveMinLiquidityReceived = 300000 ether;

    // Test that adding liquidity fails when minLiquidityReceived is excessive
    uint256 totalShares = liquidity.totalShares(PoolUtils._poolID(token0, token1));

    vm.expectRevert("Insufficient tokenA added to liquidity");
    pools.addLiquidity(token0, token1, 1000 ether, 1000 ether, excessiveMinLiquidityReceived, 0, totalShares );

    vm.expectRevert("Insufficient tokenB added to liquidity");
    pools.addLiquidity(token0, token1, 1000 ether, 1000 ether, 0, excessiveMinLiquidityReceived, totalShares );

    // Get the current user's liquidity before removing liquidity
    uint256 liquidityBefore = liquidity.userShareForPool(DEPLOYER, PoolUtils._poolID(token0, token1));

    // Define an excessive minReclaimedA and minReclaimedB
    uint256 excessiveMinReclaimedA = 1500000 ether;
    uint256 excessiveMinReclaimedB = 1500000 ether;

    // Test that removing liquidity fails when minReclaimedA and minReclaimedB are excessive
  	totalShares = liquidity.totalShares(PoolUtils._poolID(token0, token1));

    vm.expectRevert("Insufficient underlying tokens returned");
	pools.removeLiquidity(token0, token1, liquidityBefore, excessiveMinReclaimedA, excessiveMinReclaimedB, totalShares );
}



	// A unit test that checks deposit function when the deposit amount is exactly equal to the user balance
	function testDepositFullBalance() public {

		vm.prank(DEPLOYER);
		tokens[5].transfer(alice, 1000 ether);

        uint256 userBalance = tokens[5].balanceOf(alice);

        vm.startPrank(alice);

        // Deposit the whole balance
        tokens[5].approve(address(pools), userBalance);
        pools.deposit(tokens[5], userBalance);

        // Assert that the deposited amount is reflected correctly
        assertEq(pools.depositedUserBalance(alice, tokens[5]), userBalance);

        // Assert user token balance is now zero
        assertEq(tokens[5].balanceOf(alice), 0);
    }


	// A unit test that checks that "setContracts" can only be called once
	function testSetContracts() public {
		pools = new Pools(exchangeConfig, poolsConfig);

        // Set the DAO for the first time
        pools.setContracts(dao, liquidity);

        // Try to set the DAO again and expect a revert
        vm.expectRevert("Ownable: caller is not the owner");
        pools.setContracts(dao, liquidity);
    }


	// A unit test that verifies that the startExchangeApproved can only be called from the BootstrapBallot contract.
	function testStartExchangeApprovedOnlyCallableFromBootstrapBallot() public {

        vm.startPrank(bob);

        vm.expectRevert("Pools.startExchangeApproved can only be called from the BootstrapBallot contract");
        pools.startExchangeApproved();
        }


	// A unit test that verifies that Pools.addLiquidity is only callable from the Liquidity contract
	function testAddLiquidityOnlyCallableFromLiquidity() public {
        vm.startPrank(bob);

        vm.expectRevert("Pools.addLiquidity is only callable from the Liquidity contract");
        pools.addLiquidity( tokens[0], tokens[1], 100 ether, 100 ether, 0, 0, 0 );
        }


	// A unit test that verifies that Pools.removeLiquidity is only callable from the Liquidity contract
	function testRemoveLiquidityOnlyCallableFromLiquidity() public {
        vm.startPrank(bob);

        vm.expectRevert("Pools.removeLiquidity is only callable from the Liquidity contract");
        pools.removeLiquidity( tokens[0], tokens[1], 100 ether, 0, 0, 0 );
        }


	// A unit test that checks that swaps must result in reserves being above DUST
	function testSwapDustRestriction() public {

		vm.startPrank(address(liquidity));
        IERC20 token0 = new TestERC20("TEST", 18);
        IERC20 token1 = new TestERC20("TEST", 18);
        vm.stopPrank();

        vm.prank(address(dao));
        poolsConfig.whitelistPool(  token0, token1);

		vm.startPrank(address(liquidity));
		token0.approve( address(pools), type(uint256).max );
		token1.approve( address(pools), type(uint256).max );
        pools.addLiquidity(token0, token1, PoolUtils.DUST + 1, PoolUtils.DUST + 1, 0, 0, liquidity.totalShares(PoolUtils._poolID(token0, token1)));

		vm.expectRevert( "Insufficient reserves after swap" );
		pools.depositSwapWithdraw(token0, token1, PoolUtils.DUST + 1, 0, block.timestamp);
    }


	function _checkZapping( uint8 decimals0, uint8 decimals1, uint256 initialLiquidity0, uint256 initialLiquidity1, uint256 zapAmount0, uint256 zapAmount1 ) internal
		{
		vm.startPrank(DEPLOYER);
        IERC20 token0 = new TestERC20("TEST", decimals0);
        IERC20 token1 = new TestERC20("TEST", decimals1);

		token0.transfer(alice, (initialLiquidity0 + zapAmount0)  * 10 ** decimals0 );
		token1.transfer(alice, (initialLiquidity1 + zapAmount1) * 10 ** decimals1 );
		vm.stopPrank();

		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),(initialLiquidity0 + zapAmount0)* 10 ** decimals0);
		token1.approve(address(liquidity),(initialLiquidity1 + zapAmount1)* 10 ** decimals1);
		vm.stopPrank();

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token0, token1);

		vm.startPrank(address(alice));
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, initialLiquidity0 * 10 ** decimals0, initialLiquidity1 * 10 ** decimals1, 0, 0, 0, block.timestamp, false );


//		console.log( "token0: ", token0.balanceOf(alice ) / 10**18);
//		console.log( "token1: ", token1.balanceOf(alice ) / 10**18);


		uint256 reclaimedA;
		uint256 reclaimedB;

		vm.warp( block.timestamp + 1 hours );

		// Avoid stack too deep
			{
			uint256 addedLiquidity = liquidity.depositLiquidityAndIncreaseShare( token0, token1, zapAmount0 * 10 ** decimals0, zapAmount1 * 10 ** decimals1, 0, 0, 0, block.timestamp, true );

			console.log( "token0: ", token0.balanceOf(alice ));
			console.log( "token1: ", token1.balanceOf(alice ));

			// Expect that we would have used close to all our tokens for zapping
			assertTrue( token0.balanceOf(alice) < PoolUtils.DUST, "Alice should have close to zero token0" );
			assertTrue( token1.balanceOf(alice) < PoolUtils.DUST, "Alice should have close to zero token1" );

			vm.warp( block.timestamp + 1 hours );

			// Remove liquidity
			(reclaimedA, reclaimedB) = liquidity.withdrawLiquidityAndClaim(token0, token1, addedLiquidity, 0, 0, block.timestamp);
			}


		// Swap back and see if things are where we started
		if ( reclaimedA > zapAmount0 * 10**decimals0 )
			pools.depositSwapWithdraw(token0, token1, reclaimedA - zapAmount0 * 10**decimals0, 0, block.timestamp);
		rollToNextBlock();

		if ( reclaimedB > zapAmount1 * 10**decimals1 )
			pools.depositSwapWithdraw(token1, token0, reclaimedB - zapAmount1 * 10**decimals1, 0, block.timestamp);
		rollToNextBlock();

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);

		assertTrue( _checkNumbersClose( reserve0, initialLiquidity0 * 10**decimals0), "reconstructed initialLiquidity0 incorrect" );
		assertTrue( _checkNumbersClose( reserve1, initialLiquidity1 * 10**decimals1), "reconstructed initialLiquidity1 incorrect" );

		assertTrue( _checkNumbersClose( token0.balanceOf(alice), zapAmount0 * 10**decimals0), "reconstructed zapAmount0 incorrect" );
		assertTrue( _checkNumbersClose( token1.balanceOf(alice), zapAmount1 * 10**decimals1), "reconstructed zapAmount1 incorrect" );


//		console.log( "---------------------------------" );
//		console.log( "zapAmount0: ", zapAmount0 * 10**decimals0 );
//		console.log( "zapAmount1: ", zapAmount1 * 10**decimals1 );
//
//		console.log( "reclaimedA: ", reclaimedA );
//		console.log( "reclaimedB: ", reclaimedB );
//
//		console.log( "initialLiquidity0: ", initialLiquidity0 * 10**decimals0 );
//		console.log( "initialLiquidity1: ", initialLiquidity1 * 10**decimals1 );
//
//		console.log( "reserve0: ", reserve0 );
//		console.log( "reserve1: ", reserve1 );
//
//		console.log( "token0: ", token0.balanceOf(alice) );
//		console.log( "token1: ", token1.balanceOf(alice) );

		vm.stopPrank();
		}

	// A unit test that checks the zapping functionality
	function testZapping() public
		{
		// 800 trillion and 500 trillion reserves with 1 trillion of each token added
//		_checkZapping( 6, 18, 800000000000000, 500000000000000, 1000000000000, 1000000000000 );
		_checkZapping( 18, 6, 800000000000000, 500000000000000, 1000000000000, 1000000000000 );
		_checkZapping( 18, 18, 800000000000000, 500000000000000, 1000000000000, 1000000000000 );
		_checkZapping( 18, 18, 80000000000000, 50000000000000, 1000000000000, 1000000000000 );
//		_checkZapping( 18, 18, 8000000000000, 5000000000000, 1000000000000, 1000000000000 );
//		_checkZapping( 18, 18, 8000000000000, 5000000000000, 100000000000, 100000000000 );
//		_checkZapping( 6, 18, 800000000000, 500000000000, 100000000000, 100000000000 );
//		_checkZapping( 18, 6, 800000000000, 500000000000, 100000000000, 100000000000 );
//		_checkZapping( 18, 6, 800000000000, 500000000000, 100000, 100000000000 );
		_checkZapping( 18, 18, 800000000000, 500000000000, 100000, 100000 );
		_checkZapping( 18, 18, 800000, 5000, 1000, 0 );
		_checkZapping( 18, 18, 800000, 50000, 0, 500 );
//		_checkZapping( 18, 18, 8000, 50, 0, 1000 );
		_checkZapping( 18, 18, 1000000, 1000000, 1000, 0 );
		_checkZapping( 18, 18, 1000000, 1000000, 0, 1000 );
		_checkZapping( 18, 18, 10000000, 10000000, 2000, 1000 );
		}


	function _checkZappingDust( uint8 decimals0, uint8 decimals1, uint256 initialLiquidity0, uint256 initialLiquidity1, uint256 zapAmount0, uint256 zapAmount1 ) internal
		{
		vm.startPrank(address(liquidity));
        IERC20 token0 = new TestERC20("TEST", decimals0);
        IERC20 token1 = new TestERC20("TEST", decimals1);

		token0.transfer(alice,initialLiquidity0+zapAmount0);
		token1.transfer(alice,initialLiquidity1+zapAmount1);
		vm.stopPrank();

		vm.prank(address(dao));
		poolsConfig.whitelistPool(  token0, token1);

		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		token0.approve(address(liquidity),(initialLiquidity0 + zapAmount0)* 10 ** decimals0);
		token1.approve(address(liquidity),(initialLiquidity1 + zapAmount1)* 10 ** decimals1);

		liquidity.depositLiquidityAndIncreaseShare( token0, token1, initialLiquidity0, initialLiquidity1, 0, 0, 0, block.timestamp, false );
		vm.warp( block.timestamp + 1 hours );

//		console.log( "token0: ", token0.balanceOf(alice ));
//		console.log( "token1: ", token1.balanceOf(alice ));


		uint256 reclaimedA;
		uint256 reclaimedB;

		// Avoid stack too deep
			{
			uint256 addedLiquidity = liquidity.depositLiquidityAndIncreaseShare( token0, token1, zapAmount0, zapAmount1, 0, 0, 0, block.timestamp, true );

//			console.log( "addedLiquidity: ", addedLiquidity);
			console.log( "token0: ", token0.balanceOf(alice ));
			console.log( "token1: ", token1.balanceOf(alice ));

			// Expect that we would have used all our tokens for zapping
//			assertTrue( _checkNumbersClose( token0.balanceOf(alice), 0, decimals0), "Alice should have zero token0" );
//			assertTrue( _checkNumbersClose( token1.balanceOf(alice), 0, decimals1), "Alice should have zero token1" );

			// Expect that we would have used close to all our tokens for zapping
			assertTrue( token0.balanceOf(alice) < PoolUtils.DUST, "Alice should have close to zero token0" );
			assertTrue( token1.balanceOf(alice) < PoolUtils.DUST, "Alice should have close to zero token1" );

			vm.warp( block.timestamp + 1 hours );

			// Remove liquidity
			(reclaimedA, reclaimedB) = liquidity.withdrawLiquidityAndClaim(token0, token1, addedLiquidity, 0, 0, block.timestamp);
			}


		// Swap back and see if things are where we started
		if ( reclaimedA > zapAmount0 )
			pools.depositSwapWithdraw(token0, token1, reclaimedA - zapAmount0, 0, block.timestamp);
		rollToNextBlock();

		if ( reclaimedB > zapAmount1 )
			pools.depositSwapWithdraw(token1, token0, reclaimedB - zapAmount1, 0, block.timestamp);
		rollToNextBlock();

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);

		assertTrue( _checkNumbersClose( reserve0, initialLiquidity0), "reconstructed initialLiquidity0 incorrect" );
		assertTrue( _checkNumbersClose( reserve1, initialLiquidity1), "reconstructed initialLiquidity1 incorrect" );

		assertTrue( _checkNumbersClose( token0.balanceOf(alice), zapAmount0), "reconstructed zapAmount0 incorrect" );
		assertTrue( _checkNumbersClose( token1.balanceOf(alice), zapAmount1), "reconstructed zapAmount1 incorrect" );

//		console.log( "---------------------------------" );
//		console.log( "zapAmount0: ", zapAmount0 );
//		console.log( "zapAmount1: ", zapAmount1 );
//
//		console.log( "reclaimedA: ", reclaimedA );
//		console.log( "reclaimedB: ", reclaimedB );
//
//		console.log( "initialLiquidity0: ", initialLiquidity0 );
//		console.log( "initialLiquidity1: ", initialLiquidity1 );
//
//		console.log( "reserve0: ", reserve0 );
//		console.log( "reserve1: ", reserve1 );
//
//		console.log( "token0: ", token0.balanceOf(alice) );
//		console.log( "token1: ", token1.balanceOf(alice) );

		vm.stopPrank();
		}


	// A unit test that checks the zapping functionality with dust amounts
	function testZappingDust() public
		{
//		_checkZappingDust( 18, 18,  101 * 10**12,  99 * 10**12, 400*10**12, 200*10**12 );

		// z1 and z2 less than dust
		_checkZappingDust( 18, 18, 2000 ether, 2000 ether, 200 *10**6, 99 *10**6 );

		// This should check the minimum quantity to zap of .000101
		_checkZappingDust( 18, 18, 8000 * 10**6, 2000 * 10**18, 80 * 10 ** 6, 101 * 10 ** 12 );

		// This should check the minimum quantity to zap of .000101
		_checkZappingDust( 18, 18, 800000 ether, 200000 ether, 101 * 10 ** 6, 101 * 10 ** 12 );

//		// z1/z2 = r1/r2
//		_checkZappingDust( 18, 18, 1000, 2000, 200, 400 );

		// smaller decimals
//		_checkZappingDust( 6, 6, 1000, 2000, 200, 500 );
//		_checkZappingDust( 5, 5, 1000, 2000, 200, 500 );
		}



	// A unit test that checks if the dualZapInLiquidity correctly switches to the zapping function bypassing the swap when needed.
	    function testDualZapInLiquidity() public {
            // setup
            TestERC20 tokenA = new TestERC20( "TEST", 18 );
            TestERC20 tokenB = new TestERC20( "TEST", 18 );

            uint256 zapAmountA = 1000 ether;
            uint256 zapAmountB = 1000 ether;

			vm.prank(address(dao));
			poolsConfig.whitelistPool(  tokenA, tokenB);

            // make initial deposits
            tokenA.approve(address(liquidity),type(uint256).max);
            tokenB.approve(address(liquidity),type(uint256).max);
            liquidity.depositLiquidityAndIncreaseShare(tokenA, tokenB, zapAmountA, zapAmountB, 0, 0, 0, block.timestamp, false);
            vm.warp( block.timestamp + 1 hours );

            // get actual reserves
            (uint256 actualAddedAmountA, uint256 actualAddedAmountB) = pools.getPoolReserves(tokenA, tokenB);

            // assert actual result equals expected result
            assertEq(zapAmountA, actualAddedAmountA);
            assertEq(zapAmountB, actualAddedAmountB);


			// Add more liquidity
            liquidity.depositLiquidityAndIncreaseShare(tokenA, tokenB, 500 ether, 2000 ether, 0, 0, 0, block.timestamp, false);
            vm.warp( block.timestamp + 1 hours );

            // get actual reserves
            (uint256 reservesA, uint256 reservesB) = pools.getPoolReserves(tokenA, tokenB);

            // assert actual result equals expected result
            assertEq(reservesA, 1500 ether);
            assertEq(reservesB, 1500 ether);


			uint256 startingBalanceA = tokenA.balanceOf(address(this));
			uint256 startingBalanceB = tokenB.balanceOf(address(this));

			// Add more liquidity
            liquidity.depositLiquidityAndIncreaseShare(tokenA, tokenB, 10 ether, 30 ether, 0, 0, 0, block.timestamp, true);

            // get actual reserves
            (reservesA, reservesB) = pools.getPoolReserves(tokenA, tokenB);

            // assert actual result equals expected result
            assertEq(reservesA, 1510000000000000000000);
            assertEq(reservesB, 1529999999999999999998);

            assertEq(startingBalanceA - tokenA.balanceOf(address(this)), 10000000000000000000);
            assertEq(startingBalanceB - tokenB.balanceOf(address(this)), 29999999999999999998);


			// Check that we hold all the liquidity
			bytes32 poolID = PoolUtils._poolID(tokenA, tokenB);
			assertEq( liquidity.totalShares(poolID), liquidity.userShareForPool(address(this), poolID));
        }


    // A unit test to test addLiquidity with flipped tokens
    function testAddLiquidityWithFlippedTokens() public
    	{
       	IERC20 token0 = new TestERC20("TEST", 18);
       	IERC20 token1 = new TestERC20("TEST", 18);
       	IERC20 token2 = new TestERC20("TEST", 18);

		vm.startPrank(address(dao));
		poolsConfig.whitelistPool(  token0, token1);
		poolsConfig.whitelistPool(  token1, token2);
		vm.stopPrank();

		// Approvals for adding liquidity
		token0.approve(address(liquidity),type(uint256).max);
		token1.approve(address(liquidity),type(uint256).max);
		token2.approve(address(liquidity),type(uint256).max);

		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 100 ether, 200 ether, 0, 0, 0, block.timestamp, false );
		liquidity.depositLiquidityAndIncreaseShare( token1, token2, 100 ether, 200 ether, 0, 0, 0, block.timestamp, false );

		vm.warp( block.timestamp + 1 hours );
		liquidity.depositLiquidityAndIncreaseShare( token0, token1, 100 ether, 200 ether, 0, 0, 0, block.timestamp, false );
		liquidity.depositLiquidityAndIncreaseShare( token2, token1, 200 ether, 100 ether, 0, 0, 0, block.timestamp, false );

		// These reserves should be the same
		(uint256 reservesA0, uint256 reservesA1) = pools.getPoolReserves(token0, token1);
		(uint256 reservesB0, uint256 reservesB1) = pools.getPoolReserves(token1, token2);

		assertEq( reservesA0, reservesB0);
		assertEq( reservesA1, reservesB1);
    	}


	// A unit test to check that depositDoubleSwapWithdraw functions correctly
	function testDepositDoubleSwapWithdraw() public
		{
		vm.startPrank(DEPLOYER);

		IERC20 tokenA = new TestERC20("TEST", 18);
		IERC20 tokenB = new TestERC20("TEST", 18);

		wbtc.approve(address(liquidity), type(uint256).max );
		weth.approve(address(liquidity), type(uint256).max );
		tokenA.approve(address(liquidity), type(uint256).max );
		tokenB.approve(address(liquidity), type(uint256).max );
		tokenA.approve(address(pools), type(uint256).max );

		liquidity.depositLiquidityAndIncreaseShare(wbtc, weth, 1000 * 10**8, 1000 ether, 0, 0, 0, block.timestamp, false);
		vm.stopPrank();

		vm.startPrank(address(dao));
		poolsConfig.whitelistPool(tokenA, wbtc);
		poolsConfig.whitelistPool(tokenA, weth);
		poolsConfig.whitelistPool(tokenB, wbtc);
		poolsConfig.whitelistPool(tokenB, weth);
		vm.stopPrank();

		vm.startPrank(DEPLOYER);
		liquidity.depositLiquidityAndIncreaseShare(tokenA, wbtc, 1000 ether, 1000 * 10**8, 0, 0, 0, block.timestamp, false);
		liquidity.depositLiquidityAndIncreaseShare(tokenB, wbtc, 1000 ether, 1000 * 10**8, 0, 0, 0, block.timestamp, false);
		liquidity.depositLiquidityAndIncreaseShare(tokenA, weth, 1000 ether, 1000 ether, 0, 0, 0, block.timestamp, false);
		liquidity.depositLiquidityAndIncreaseShare(tokenB, weth, 1000 ether, 1000 ether, 0, 0, 0, block.timestamp, false);

		uint256 gas0 = gasleft();
		pools.depositDoubleSwapWithdraw(tokenA, weth, tokenB, 10 ether, 0, block.timestamp);
		console.log( "DOUBLE SWAP GAS: ", gas0 - gasleft() );
		vm.stopPrank();
		}


// From: https://github.com/code-423n4/2024-01-zeroy-findings/issues/927
function testAdjustReservesForSwap_Overflow_Bug_Audit() public {
    // setup
    vm.startPrank(alice);
    IERC20 tokenIn = new TestERC20('TEST', 18);
    IERC20 tokenOut = new TestERC20('TEST', 18);
    vm.stopPrank();

    vm.startPrank(address(dao));
    poolsConfig.whitelistPool(tokenIn, tokenOut);
    vm.stopPrank();

    uint256 tokenInBalance = type(uint128).max - 1000;
    uint256 tokenOutBalance = type(uint128).max - 1000;

    deal(address(tokenIn), alice, type(uint256).max);
    deal(address(tokenOut), alice, type(uint256).max);

    // Add enough liquidity
    vm.startPrank(alice);
    tokenIn.transfer(address(liquidity), tokenInBalance);
    tokenOut.transfer(address(liquidity), tokenInBalance);
    vm.stopPrank();

    vm.startPrank(address(liquidity));
    tokenIn.approve(address(pools), type(uint256).max);
    tokenOut.approve(address(pools), type(uint256).max);
    uint256 totalShares = liquidity.totalShares(PoolUtils._poolID(tokenIn, tokenOut));

    pools.addLiquidity(tokenIn, tokenOut, tokenInBalance, tokenOutBalance, 0, 0, totalShares);
    vm.stopPrank();

    // get pool reserves before swap
    pools.getPoolReserves(tokenIn, tokenOut);

    uint256 tokenAmountToSwap = 1500;
    uint256 minAmountOut = 1;

    vm.prank(alice);
    tokenIn.transfer(bob, tokenAmountToSwap + 100);

    tokenOut.balanceOf(bob);
    vm.startPrank(bob);
    tokenIn.approve(address(pools), type(uint256).max);

    vm.expectRevert( "Reserves overflow after swap" );
    pools.depositSwapWithdraw(
      tokenIn,
      tokenOut,
      tokenAmountToSwap,
      minAmountOut,
      block.timestamp + 1 minutes
    );
  }
    }