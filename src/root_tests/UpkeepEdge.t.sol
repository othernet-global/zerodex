// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "forge-std/Test.sol";
import "../dev/Deployment.sol";
import "./ITestUpkeep.sol";


contract TestUpkeepEdge is Deployment
	{
    address public constant alice = address(0x1111);


	constructor()
		{
		initializeContracts();

		finalizeBootstrap();

		grantAccessAlice();
		grantAccessBob();
		grantAccessCharlie();
		grantAccessDeployer();
		grantAccessDefault();
		}


	function _setupLiquidity() internal
		{
		vm.prank(address(teamVestingWallet));
		zero.transfer(DEPLOYER, 100000 ether );

		vm.startPrank(DEPLOYER);
		weth.approve( address(liquidity), 300000 ether);
		usdc.approve( address(liquidity), 100000 ether);
		zero.approve( address(liquidity), 100000 ether);

		liquidity.depositLiquidityAndIncreaseShare(weth, usdc, 100000 ether, 100000 * 10**6, 0, 0, 0, block.timestamp, false);
		liquidity.depositLiquidityAndIncreaseShare(weth, zero, 100000 ether, 100000 ether, 0, 0, 0, block.timestamp, false);

		vm.stopPrank();
		}


	function _swapToGenerateProfits() internal
		{
		vm.startPrank(DEPLOYER);
		pools.depositSwapWithdraw(zero, weth, 1 ether, 0, block.timestamp);
		rollToNextBlock();
		pools.depositSwapWithdraw(zero, usdc, 1 ether, 0, block.timestamp);
		rollToNextBlock();
		pools.depositSwapWithdraw(weth, usdc, 1 ether, 0, block.timestamp);
		rollToNextBlock();
		vm.stopPrank();
		}


	function _generateArbitrageProfits( bool despositZeroUSDC ) internal
		{
		/// Pull some ZERO from the daoVestingWallet
    	vm.prank(address(daoVestingWallet));
    	zero.transfer(DEPLOYER, 100000 ether);

		vm.startPrank(DEPLOYER);
		zero.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);

		if ( despositZeroUSDC )
			liquidity.depositLiquidityAndIncreaseShare( zero, weth, 1000 ether, 1000 ether, 0, 0, 0, block.timestamp, false );

		liquidity.depositLiquidityAndIncreaseShare( usdc, zero, 1000 * 10**8, 1000 ether, 0, 0, 0, block.timestamp, false );
		liquidity.depositLiquidityAndIncreaseShare( usdc, weth, 1000 * 10**8, 1000 ether, 0, 0, 0, block.timestamp, false );

		zero.approve(address(pools), type(uint256).max);
		wbtc.approve(address(pools), type(uint256).max);
		weth.approve(address(pools), type(uint256).max);
		vm.stopPrank();

		// Place some sample trades to create arbitrage profits
		_swapToGenerateProfits();
		}


    // A unit test to verify the step1 function when the DAO's WETH balance is zero.
	function testStep1() public
		{
		// Step 1. Withdraws existing WETH arbitrage profits from the Pools contract and rewards the caller of performUpkeep() with default 5% of the withdrawn amount.
    	vm.prank(address(upkeep));
    	ITestUpkeep(address(upkeep)).step1(alice);

    	assertEq( weth.balanceOf(alice), 0 ether );
		}


    // A unit test to verify the steps 2-3 function when the remaining WETH balance in the contract is zero.
	function testStep2Through3() public
		{
		vm.startPrank(address(upkeep));
		ITestUpkeep(address(upkeep)).step2();
		ITestUpkeep(address(upkeep)).step3();
		vm.stopPrank();

		assertEq( liquidity.userShareForPool(address(dao), PoolUtils._poolID(zero, usdc)), 0 );
		}


    // A unit test to verify the step4 function when the Emissions' performUpkeep function does not emit any ZERO. Ensure that it does not perform any emission actions.
	function testStep4() public
		{
		assertEq( zero.balanceOf(address(emissions)), 50 * 1000000 ether );

		vm.warp( upkeep.lastUpkeepTimeEmissions() );

		// Step 4. Sends ZERO Emissions to the ZeroRewards contract.
		vm.prank(address(upkeep));
		ITestUpkeep(address(upkeep)).step4();

		// Emissions initial distribution of 50 million tokens stored in the contract is a default .50% per week.
		assertEq( zero.balanceOf(address(zeroRewards)), 0 );
		}


    // A unit test to verify the step7 function when the profits for pools are zero. Ensure that the function does not perform any actions.
    function testStep7() public
    	{
		bytes32[] memory poolIDs = new bytes32[](4);
		poolIDs[0] = PoolUtils._poolID(zero,weth);
		poolIDs[1] = PoolUtils._poolID(zero,wbtc);
		poolIDs[2] = PoolUtils._poolID(wbtc,weth);
		poolIDs[3] = PoolUtils._poolID(zero,usdc);

		uint256 initialSupply = zero.totalSupply();

		// Step 7. Collects ZERO rewards from the DAO's Protocol Owned Liquidity (ZERO/USDC from formed POL), sends 10% to the initial dev team and burns a default 50% of the remaining - the rest stays in the DAO.
    	vm.prank(address(upkeep));
    	ITestUpkeep(address(upkeep)).step7();

		// Check teamWallet transfer
		assertEq( zero.balanceOf(teamWallet), 0 ether);

		// Check the amount burned
		uint256 amountBurned = initialSupply - zero.totalSupply();
		uint256 expectedAmountBurned = 0;
		assertEq( amountBurned, expectedAmountBurned );
	  	}


    // A unit test to verify the step8 function when the dao's vesting wallet has no elapsed time
	function testSuccessStep8() public
		{
		// Warp to the start of when the teamVestingWallet starts to emit
		vm.warp( VestingWallet(payable(daoVestingWallet)).start() );

		assertEq( zero.balanceOf(address(dao)), 0 );

		// Step 8. Sends ZERO from the DAO vesting wallet to the DAO (linear distribution over 10 years).
		vm.prank(address(upkeep));
		ITestUpkeep(address(upkeep)).step8();

		// Check that ZERO has been sent to DAO.
		assertEq( zero.balanceOf(address(dao)), 0 );
		}
	}




