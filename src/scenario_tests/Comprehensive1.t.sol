// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "forge-std/Test.sol";
import "../dev/Deployment.sol";
import "../launch/BootstrapBallot.sol";


contract TestComprehensive1 is Deployment
	{
	// User wallets for testing
    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);
    address public constant charlie = address(0x3333);
    address public constant delta = address(0x4444);


    function setUp() public
		{
		initializeContracts();

		grantAccessAlice();
		grantAccessBob();
		grantAccessCharlie();
		grantAccessDeployer();
		grantAccessDefault();


		// Give some WBTC and WETH to Alice, Bob and Charlie
		vm.startPrank(DEPLOYER);
		wbtc.transfer(alice, 1000 * 10**8 );
		wbtc.transfer(bob, 1000 * 10**8 );
		wbtc.transfer(charlie, 1000 * 10**8 );

		weth.transfer(alice, 1000 ether);
		weth.transfer(bob, 1000 ether);
		weth.transfer(charlie, 1000 ether);

		usdc.transfer(alice, 1000 * 10**6 );
		usdc.transfer(bob, 1000 * 10**6 );
		usdc.transfer(charlie, 1000 * 10**6 );
		vm.stopPrank();

		// Everyone approves
		vm.startPrank(alice);
		zero.approve(address(pools), type(uint256).max);
		wbtc.approve(address(pools), type(uint256).max);
		weth.approve(address(pools), type(uint256).max);
		zero.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		zero.approve(address(pools), type(uint256).max);
		wbtc.approve(address(pools), type(uint256).max);
		weth.approve(address(pools), type(uint256).max);
		zero.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);
		vm.stopPrank();

		vm.startPrank(charlie);
		zero.approve(address(pools), type(uint256).max);
		wbtc.approve(address(pools), type(uint256).max);
		weth.approve(address(pools), type(uint256).max);
		zero.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);
		vm.stopPrank();
		}


	function testComprehensive() public
		{
		// Cast votes for the BootstrapBallot so that the initialDistribution can happen
		bytes memory sig = abi.encodePacked(aliceVotingSignature);
		vm.startPrank(alice);
		bootstrapBallot.vote(true, 1000 ether, sig);
		vm.stopPrank();

		sig = abi.encodePacked(bobVotingSignature);
		vm.startPrank(bob);
		bootstrapBallot.vote(true, 1000 ether, sig);
		vm.stopPrank();

		sig = abi.encodePacked(charlieVotingSignature);
		vm.startPrank(charlie);
		bootstrapBallot.vote(false, 1000 ether, sig);
		vm.stopPrank();

		// Finalize the ballot to distribute ZERO to the protocol contracts and start up the exchange
		vm.warp( bootstrapBallot.claimableTimestamp1() );
		bootstrapBallot.finalizeBallot();

		// Wait a day so that alice, bob and charlie receive some ZERO emissions for their xZERO
		vm.warp( block.timestamp + 1 days );

		vm.prank(alice);
		airdrop1.claim();
		vm.prank(bob);
		airdrop1.claim();
		vm.prank(charlie);
		airdrop1.claim();

		assertEq( zero.balanceOf(alice), 2747252747252747252 );
		assertEq( zero.balanceOf(bob), 2747252747252747252 );
		assertEq( zero.balanceOf(charlie), 2747252747252747252 );

		upkeep.performUpkeep();

		// No liquidity exists yet

		// Alice adds some ZERO/WETH, AND ZERO/USDC
		vm.startPrank(alice);
		zero.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		usdc.approve(address(liquidity), type(uint256).max);

		liquidity.depositLiquidityAndIncreaseShare(zero, weth, 1 ether, 10 ether, 0, 0, 0, block.timestamp, false);
		liquidity.depositLiquidityAndIncreaseShare(zero, usdc, 1 ether, 10 * 10**6, 0, 0, 0, block.timestamp, false);
		vm.stopPrank();

		// Bob adds some WBTC/WETH liquidity
		vm.startPrank(bob);
		zero.approve(address(liquidity), type(uint256).max);
		weth.approve(address(liquidity), type(uint256).max);
		wbtc.approve(address(liquidity), type(uint256).max);
		usdc.approve(address(liquidity), type(uint256).max);

    	liquidity.depositLiquidityAndIncreaseShare(usdc, weth, 1000 * 10**6, 1000 ether, 0, 0, 0, block.timestamp, false);
    	vm.stopPrank();

    	console.log( "bob USDC: ", usdc.balanceOf(bob) );

    	// Charlie places some trades
    	vm.startPrank(charlie);
    	uint256 amountOut1 = pools.depositSwapWithdraw(weth, zero, 1 ether, 0, block.timestamp);
    	rollToNextBlock();
    	uint256 amountOut2 = pools.depositSwapWithdraw(weth, zero, 1 ether, 0, block.timestamp);
		rollToNextBlock();
		vm.stopPrank();

		console.log( "ARBITRAGE PROFITS: ", pools.depositedUserBalance( address(dao), zero ) );

    	console.log( "charlie swapped ZERO:", amountOut1 );
    	console.log( "charlie swapped ZERO:", amountOut2 );

		console.log( "CURRENT REWARDS FOR CALLING: ", upkeep.currentRewardsForCallingPerformUpkeep() );

    	vm.warp( block.timestamp + 1 hours );

    	vm.prank(delta);
    	upkeep.performUpkeep();

    	console.log( "delta BALANCE: ", zero.balanceOf(address(delta)) );
    	}
	}
