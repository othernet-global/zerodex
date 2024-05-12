// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../dev/Deployment.sol";


contract TestArbitrage is Deployment
	{
	IERC20 public tokenE;	// similar price to ETH


	constructor()
		{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			initializeContracts();

		grantAccessDefault();

		finalizeBootstrap();

		vm.prank(address(daoVestingWallet));
		zero.transfer(DEPLOYER, 1000000 ether);

		tokenE = new TestERC20("TEST", 18);

        vm.startPrank(address(dao));
        poolsConfig.whitelistPool(  tokenE, zero);
        poolsConfig.whitelistPool(  tokenE, weth);
        vm.stopPrank();

		vm.startPrank(DEPLOYER);
		weth.transfer(address(this), 1000000 ether);
		zero.transfer(address(this), 1000000 ether);
		vm.stopPrank();

		tokenE.approve( address(pools), type(uint256).max );
   		weth.approve( address(pools), type(uint256).max );
   		zero.approve( address(pools), type(uint256).max );

		tokenE.approve( address(liquidity), type(uint256).max );
   		weth.approve( address(liquidity), type(uint256).max );
   		zero.approve( address(liquidity), type(uint256).max );

		liquidity.depositLiquidityAndIncreaseShare( tokenE, zero, 1000 ether, 1000 ether, 0, 0, 0, block.timestamp, false );
		liquidity.depositLiquidityAndIncreaseShare( tokenE, weth, 1000 ether, 1000 ether, 0, 0, 0, block.timestamp, false );
		liquidity.depositLiquidityAndIncreaseShare( weth, zero, 1000 ether, 1000 ether, 0, 0, 0, block.timestamp, false );

		pools.deposit( tokenE, 100 ether );

		// Initial transactions cost more gas so perform the first ones here
		pools.swap( tokenE, zero, 10 ether, 0, block.timestamp );
		rollToNextBlock();

		pools.depositSwapWithdraw( zero, tokenE, 10 ether, 0, block.timestamp );

		rollToNextBlock();
		}


	function testGasDepositSwapWithdrawAndArbitrage() public
		{
		uint256 arbProfits = pools.depositedUserBalance(address(dao), zero);

		uint256 gas0 = gasleft();
		uint256 totalOutput = pools.depositSwapWithdraw( tokenE, zero, 100 ether, 0, block.timestamp );

		arbProfits = pools.depositedUserBalance(address(dao), zero) - arbProfits;

		console.log( "DEPOSIT/SWAP/ARB GAS: ", gas0 - gasleft() );
		console.log( "OUTPUT: ", totalOutput );
		console.log( "ARB PROFITS: ", arbProfits );
		}


	function testGasSwapAndArbitrage() public
		{
		uint256 gas0 = gasleft();
		pools.swap( tokenE, zero, 10 ether, 0, block.timestamp );
		console.log( "SWAP/ARB GAS: ", gas0 - gasleft() );
		}


	function testDepositSwapWithdrawAndArbitrage() public
		{
		uint256 amountOut = pools.depositSwapWithdraw( tokenE, weth, 10 ether, 0, block.timestamp );

//		console.log( "amountOut: ", amountOut );
//		console.log( "ending pools balance: ", pools.depositedUserBalance( address(pools), weth ) );

		assertEq( amountOut, 9900982881233894761 );
		assertEq( pools.depositedUserBalance( address(dao), zero ), 66446611804469303 );
		}
	}

