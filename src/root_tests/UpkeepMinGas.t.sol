// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../dev/Deployment.sol";
import "./ITestUpkeep.sol";


contract TestMinUpkeep is Deployment
	{
	constructor()
		{
		initializeContracts();

		finalizeBootstrap();

		grantAccessDeployer();
		}


	function _setupPools() public
		{
		vm.prank(address(daoVestingWallet));
		zero.transfer(DEPLOYER, 1000000 ether);

		vm.startPrank(DEPLOYER);
    	bytes32[] memory poolIDs = poolsConfig.whitelistedPools();

    	// Add liquidity to all the pools
    	for( uint256 i = 0; i < poolIDs.length; i++ )
    		{
    		(IERC20 tokenA, IERC20 tokenB) = poolsConfig.underlyingTokenPair(poolIDs[i]);

			tokenA.approve(address(liquidity), type(uint256).max);
			tokenB.approve(address(liquidity), type(uint256).max);
			tokenA.approve(address(pools), type(uint256).max);
			tokenB.approve(address(pools), type(uint256).max);

			liquidity.depositLiquidityAndIncreaseShare(tokenA, tokenB, 100 * 10**ERC20(address(tokenA)).decimals(), 100 * 10**ERC20(address(tokenB)).decimals(), 0, 0, 0, block.timestamp, false);
    		}
    	vm.stopPrank();
		}

	// Place trades on all of the pools
    function _placeTrades() public
    	{
		vm.startPrank(DEPLOYER);
    	bytes32[] memory poolIDs = poolsConfig.whitelistedPools();

    	// Performs swaps on all of the pools so that arbitrage profits exist everywhere
    	for( uint256 i = 0; i < poolIDs.length; i++ )
    		{
    		(IERC20 tokenA, IERC20 tokenB) = poolsConfig.underlyingTokenPair(poolIDs[i]);

            pools.depositSwapWithdraw(tokenA, tokenB, 10 * 10**ERC20(address(tokenA)).decimals(), 0, block.timestamp);
            rollToNextBlock();
    		}
    	vm.stopPrank();
    	}


	// Set the initial storage write baseline for performUpkeep()
    function _createActivity() internal
    	{
    	_placeTrades();

    	// Mimic arbitrage profits deposited as WETH for the DAO
    	vm.prank(DEPLOYER);
    	weth.transfer(address(dao), 100 ether);

    	vm.startPrank(address(dao));
    	weth.approve(address(pools), 100 ether);
    	pools.deposit(weth, 100 ether);
    	vm.stopPrank();
       	}



	// A unit test to verify all expected outcomes of a performUpkeep call with the maximum amount of pools and gas usage
	function testPerformUpkeepMaxGas() public
		{
		_setupPools();
		_createActivity();

		vm.warp(block.timestamp + 1 hours );

		// === Perform upkeep ===
		address upkeepCaller = address(0x9999);

		vm.prank(upkeepCaller);
		upkeep.performUpkeep();
		// ==================

		vm.warp(block.timestamp + 1 hours );

		_createActivity();

		uint256 gas0 = gasleft();
		upkeep.performUpkeep();
		console.log( "MIN UPKEEP GAS: ", gas0 - gasleft() );
		}
	}
