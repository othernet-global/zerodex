// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../rewards/interfaces/IRewardsConfig.sol";
import "../pools/interfaces/IPoolsConfig.sol";
import "../staking/interfaces/IStaking.sol";
import "../staking/interfaces/IStakingConfig.sol";
import "../pools/interfaces/IPools.sol";
import "../interfaces/IUpkeep.sol";
import "../interfaces/IZero.sol";
import "../interfaces/IExchangeConfig.sol";
import "../pools/PoolUtils.sol";
import "../pools/PoolMath.sol";
import "./IPriceFeed.sol";


// Efficiency functions called from the Web3 UI to prevent multiple calls on the RPC server

contract Utils
    {
	function tokenNames( address[] memory tokens ) public view returns (string[] memory)
		{
		string[] memory names = new string[]( tokens.length );

		for( uint256 i = 0; i < tokens.length; i++ )
			names[i] = IERC20Metadata( tokens[i] ).symbol();

		return names;
		}


	function tokenDecimals( address[] memory tokens ) public view returns (uint256[] memory)
		{
		uint256[] memory decimals = new uint256[]( tokens.length );

		for( uint256 i = 0; i < tokens.length; i++ )
			decimals[i] = IERC20Metadata( tokens[i] ).decimals();

		return decimals;
		}


	function tokenSupplies( address[] memory tokens ) public view returns (uint256[] memory)
		{
		uint256[] memory supplies = new uint256[]( tokens.length );

		for( uint256 i = 0; i < tokens.length; i++ )
			{
			IERC20 pair = IERC20( tokens[i] );

			supplies[i] = pair.totalSupply();
			}

		return supplies;
		}


	function underlyingTokens( IPoolsConfig poolsConfig, bytes32[] memory poolIDs ) public view returns (address[] memory)
		{
		address[] memory tokens = new address[]( poolIDs.length * 2 );

		uint256 index;
		for( uint256 i = 0; i < poolIDs.length; i++ )
			{
			(IERC20 token0, IERC20 token1) = poolsConfig.underlyingTokenPair( poolIDs[i] );

			tokens[ index++ ] = address(token0);
			tokens[ index++ ] = address(token1);
			}

		return tokens;
		}


	function poolReserves( IPools pools, IPoolsConfig poolsConfig, bytes32[] memory poolIDs ) public view returns (uint256[] memory)
		{
		uint256[] memory reserves = new uint256[]( poolIDs.length * 2 );

		uint256 index;
		for( uint256 i = 0; i < poolIDs.length; i++ )
			{
			(IERC20 token0, IERC20 token1) = poolsConfig.underlyingTokenPair( poolIDs[i] );
			(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves( token0, token1 );

			reserves[ index++ ] = reserve0;
			reserves[ index++ ] = reserve1;
			}

		return reserves;
		}



	function userBalances( address wallet, address[] memory tokenIDs ) public view returns (uint256[] memory)
		{
		uint256[] memory balances = new uint256[]( tokenIDs.length );

		for( uint256 i = 0; i < tokenIDs.length; i++ )
			{
			IERC20 token = IERC20( tokenIDs[i] );

			balances[i] = token.balanceOf( wallet );
			}

		return balances;
		}


	// The current circulating supply of ZERO tokens
	function circulatingZERO( IERC20 zero, IExchangeConfig exchangeConfig, address emissions, address stakingRewardsEmitter, address liquidityRewardsEmitter, address airdrop1, address airdrop2 ) public view returns (uint256)
		{
		// Don't include balances that still haven't been distributed
		return zero.totalSupply() - zero.balanceOf(emissions) - zero.balanceOf(address(exchangeConfig.daoVestingWallet())) - zero.balanceOf(address(exchangeConfig.teamVestingWallet())) - zero.balanceOf(stakingRewardsEmitter) - zero.balanceOf(liquidityRewardsEmitter) - zero.balanceOf(airdrop1) - zero.balanceOf(airdrop2) - zero.balanceOf(address(exchangeConfig.initialDistribution()));
		}


	// Shortcut for returning the current percentStakedTimes1000 and stakingAPRTimes1000
	function stakingPercentAndAPR(IZero zero, IExchangeConfig exchangeConfig, IStaking staking, IRewardsConfig rewardsConfig, address stakingRewardsEmitter, address liquidityRewardsEmitter, address emissions, address airdrop1, address airdrop2) public view returns (uint256 percentStakedTimes1000, uint256 stakingAPRTimes1000)
		{
		// Make sure that the InitDistribution has already happened
		if ( zero.balanceOf(stakingRewardsEmitter) == 0 )
			return (0, 0);

		uint256 totalCirculating = circulatingZERO(zero, exchangeConfig, emissions, stakingRewardsEmitter, liquidityRewardsEmitter, airdrop1, airdrop2);

		uint256 totalStaked = staking.totalShares(PoolUtils.STAKED_ZERO);
		if ( totalStaked == 0 )
			return (0, 0);

		percentStakedTimes1000 = ( totalStaked * 100 * 1000 ) / totalCirculating;

		uint256 rewardsEmitterBalance = zero.balanceOf(stakingRewardsEmitter);
		uint256 rewardsEmitterDailyPercentTimes1000 = rewardsConfig.rewardsEmitterDailyPercentTimes1000();

		uint256 yearlyStakingRewardsTimes100000 = ( rewardsEmitterBalance * rewardsEmitterDailyPercentTimes1000 * 365 );// / ( 100 * 1000 );

		stakingAPRTimes1000 = yearlyStakingRewardsTimes100000 / totalStaked;
		}


	function poolID(IERC20 tokenA, IERC20 tokenB) public pure returns (bytes32 _poolID)
		{
		return PoolUtils._poolID(tokenA, tokenB);
		}


	function stakingInfo(IStakingConfig stakingConfig) public view returns (uint256 minUnstakePercent, uint256 minUnstakeWeeks, uint256 maxUnstakeWeeks )
		{
		minUnstakePercent = stakingConfig.minUnstakePercent();
		minUnstakeWeeks = stakingConfig.minUnstakeWeeks();
		maxUnstakeWeeks = stakingConfig.maxUnstakeWeeks();
		}


	// Returns prices with 18 decimals
	function corePrices(IPools pools, IExchangeConfig exchangeConfig, IPriceFeed priceFeed) public view returns (uint256 wethPrice, uint256 usdcPrice, uint256 zeroPrice)
		{
		usdcPrice = priceFeed.getPriceUSDC();

		IZero zero = exchangeConfig.zero();
		IERC20 weth = exchangeConfig.weth();
		IERC20 usdc = exchangeConfig.usdc();

		// USDC has 6 decimals, usdcPrice has 8
		// Convert to 18 decimals

		(uint256 reserves1, uint256 reserves2) = pools.getPoolReserves(weth, usdc);
		if ( reserves1 > PoolUtils.DUST )
		if ( reserves2 > PoolUtils.DUST )
			wethPrice = (reserves2 * usdcPrice * 10**12 ) / (reserves1/10**10);

		(reserves1, reserves2) = pools.getPoolReserves(zero, usdc);
		if ( reserves1 > PoolUtils.DUST )
		if ( reserves2 > PoolUtils.DUST )
			{
			uint256 zeroPriceUSDC = (reserves2 * usdcPrice * 10**12) / (reserves1/10**10);

			(uint256 reserves1b, uint256 reserves2b) = pools.getPoolReserves(zero, weth);
			if ( reserves1b > PoolUtils.DUST )
			if ( reserves2b > PoolUtils.DUST )
				{
				uint256 zeroPriceWETH = (reserves2b * wethPrice) / reserves1b;

				zeroPrice = ( zeroPriceUSDC * reserves1 + zeroPriceWETH * reserves1b ) / ( reserves1 + reserves1b );
				}
			}

		// Convert to 18 decimals
		usdcPrice = usdcPrice * 10**10;
		}


	function nonUserPoolInfo(ILiquidity liquidity, IRewardsEmitter liquidityRewardsEmitter, IPools pools, IPoolsConfig poolsConfig, IRewardsConfig rewardsConfig, bytes32[] memory poolIDs) public view returns ( address[] memory tokens, string[] memory names, uint256[] memory decimals, uint256[] memory reserves, uint256[] memory totalShares, uint256[] memory pendingRewards, uint256 rewardsEmitterDailyPercentTimes1000 )
		{
		tokens = underlyingTokens(poolsConfig, poolIDs);
		names = tokenNames(tokens);
		decimals = tokenDecimals(tokens);
		reserves = poolReserves(pools, poolsConfig, poolIDs);
		totalShares = liquidity.totalSharesForPools(poolIDs);
		pendingRewards = liquidityRewardsEmitter.pendingRewardsForPools(poolIDs);
		rewardsEmitterDailyPercentTimes1000 = rewardsConfig.rewardsEmitterDailyPercentTimes1000();
		}


	function userPoolInfo(address wallet, ILiquidity liquidity, bytes32[] memory poolIDs, address[] memory tokens) public view returns ( uint256[] memory userCooldowns, uint256[] memory userPoolShares, uint256[] memory userRewardsForPools, uint256[] memory userTokenBalances )
		{
		userCooldowns = liquidity.userCooldowns( wallet, poolIDs );
		userPoolShares = liquidity.userShareForPools( wallet, poolIDs );
   		userRewardsForPools = liquidity.userRewardsForPools( wallet, poolIDs );
		userTokenBalances = userBalances( wallet, tokens );
		}


	function currentTimestamp() public view returns (uint256 timestamp)
		{
		return block.timestamp;
		}


	function userStakingInfo(address wallet, IZero zero, IStaking staking) public view returns ( uint256 allowance, uint256 zeroBalance, uint256 veZeroBalance, uint256 pendingRewards )
		{
		allowance = zero.allowance( wallet, address(staking) );
		zeroBalance = zero.balanceOf( wallet );
		veZeroBalance = staking.userVeZERO( wallet );

		bytes32[] memory poolIDs = new bytes32[](1);
		poolIDs[0] = PoolUtils.STAKED_ZERO;

		pendingRewards = staking.userRewardsForPools( wallet, poolIDs )[0];
		}


	function determineZapSwapAmount( uint256 reserveA, uint256 reserveB, uint256 zapAmountA, uint256 zapAmountB ) external pure returns (uint256 swapAmountA, uint256 swapAmountB )
		{
		return PoolMath._determineZapSwapAmount( reserveA, reserveB, zapAmountA, zapAmountB );
		}


	// Determine the expected swap result for a given series of swaps and amountIn
	function quoteAmountOut( IPools pools, IERC20[] memory tokens, uint256 amountIn ) external view returns (uint256 amountOut)
		{
		require( tokens.length >= 2, "Must have at least two tokens swapped" );

		IERC20 tokenIn = tokens[0];
		IERC20 tokenOut;

		for( uint256 i = 1; i < tokens.length; i++ )
			{
			tokenOut = tokens[i];

			(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(tokenIn, tokenOut);

			if ( reserve0 <= PoolUtils.DUST || reserve1 <= PoolUtils.DUST || amountIn <= PoolUtils.DUST )
				return 0;

			uint256 k = reserve0 * reserve1;

			// Determine amountOut based on amountIn and the reserves
			amountOut = reserve1 - k / ( reserve0 + amountIn );

			tokenIn = tokenOut;
			amountIn = amountOut;
			}

		return amountOut;
		}


	// For a given desired amountOut and a series of swaps, determine the amountIn that would be required.
	// amountIn is rounded up
	function quoteAmountIn(  IPools pools, IERC20[] memory tokens, uint256 amountOut ) external view returns (uint256 amountIn)
		{
		require( tokens.length >= 2, "Must have at least two tokens swapped" );

		IERC20 tokenOut = tokens[ tokens.length - 1 ];
		IERC20 tokenIn;

		for( uint256 i = 2; i <= tokens.length; i++ )
			{
			tokenIn = tokens[ tokens.length - i];

			(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(tokenIn, tokenOut);

			if ( reserve0 <= PoolUtils.DUST || reserve1 <= PoolUtils.DUST || amountOut >= reserve1 || amountOut < PoolUtils.DUST)
				return 0;

			uint256 k = reserve0 * reserve1;

			// Determine amountIn based on amountOut and the reserves
			// Round up here to err on the side of caution
			amountIn = Math.ceilDiv( k, reserve1 - amountOut ) - reserve0;

			tokenOut = tokenIn;
			amountOut = amountIn;
			}

		return amountIn;
		}


	function estimateAddedLiquidity( uint256 reservesA, uint256 reservesB, uint256 maxAmountA, uint256 maxAmountB, uint256 totalLiquidity ) external pure returns (uint256 addedLiquidity)
		{
		// If either reserve is less than dust then consider the pool to be empty and that the added liquidity will become the initial token ratio
		if ( ( reservesA < PoolUtils.DUST ) || ( reservesB < PoolUtils.DUST ) )
			return maxAmountA + maxAmountB;

		// Add liquidity to the pool proportional to the current existing token reserves in the pool.
		// First, try the proportional amount of tokenB for the given maxAmountA
		uint256 proportionalB = ( reservesB * maxAmountA ) / reservesA;

		uint256 addedAmountA;
		uint256 addedAmountB;

		// proportionalB too large for the specified maxAmountB?
		if ( proportionalB > maxAmountB )
			{
			// Use maxAmountB and a proportional amount for tokenA instead
			addedAmountA = ( reservesA * maxAmountB ) / reservesB;
			addedAmountB = maxAmountB;
			}
		else
			{
			addedAmountA = maxAmountA;
			addedAmountB = proportionalB;
			}

		addedLiquidity = (totalLiquidity * (addedAmountA+addedAmountB) ) / (reservesA+reservesB);
		}


	function statsData(IZero zero, IExchangeConfig exchangeConfig, address emissions, address stakingRewardsEmitter, address liquidityRewardsEmitter, IStaking staking, IRewardsConfig rewardsConfig, address airdrop1, address airdrop2 ) external view returns ( uint256 zeroSupply, uint256 stakedZERO, uint256 burnedZERO, uint256 liquidityRewardsZero, uint256 rewardsEmitterDailyPercentTimes1000 )
		{
		zeroSupply = circulatingZERO(zero, exchangeConfig, emissions, stakingRewardsEmitter, liquidityRewardsEmitter, airdrop1, airdrop2 );
		stakedZERO = staking.totalShares(PoolUtils.STAKED_ZERO );
		burnedZERO = zero.totalBurned();
		liquidityRewardsZero = zero.balanceOf( liquidityRewardsEmitter );
		rewardsEmitterDailyPercentTimes1000 = rewardsConfig.rewardsEmitterDailyPercentTimes1000();
		}


	function secondsSinceLastUpkeep(IUpkeep upkeep) external view returns (uint256 elapsedSeconds)
		{
		return block.timestamp - upkeep.lastUpkeepTimeEmissions();
		}


	function tvl() external view returns (uint256 _tvl)
		{
		 IPoolsConfig poolsConfig = IPoolsConfig(address(0xA6ba8decE812f4663A19960735c0F66560a1D894));
		 IPools pools = IPools(address(0xf5D65d370141f1fff0Db646c9406Ce051354A8a5));
		 IExchangeConfig exchangeConfig = IExchangeConfig(address(0x66DB65306C2dDb7Aa9730e010033eE624ddD7f61));
		 IPriceFeed priceFeed = IPriceFeed(address(0x1D3C3C4C021C63c36369e3A06f8db03BD4A18bEf));

	    (uint256 ethPrice, uint256 usdcPrice, ) = corePrices(pools, exchangeConfig, priceFeed);

		bytes32[] memory allPools = poolsConfig.whitelistedPools();

		for( uint256 i = 0; i < allPools.length; i++ )
			{
			(IERC20 token0, IERC20 token1) = poolsConfig.underlyingTokenPair( allPools[i] );
			(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves( token0, token1 );

			// All pools are pools with either WETH or USDC

			if ( address(token0) == address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) ) // WETH?
				{
				// Consider tvl for this pool to be twice the value of the WETH in the pool (assuming each side of the pool has equal value)
				_tvl += 2 * ( reserve0 * ethPrice ) / ( 10 ** 18 );
				}

			else if ( address(token1) == address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) ) // WETH?
				{
				// Consider tvl for this pool to be twice the value of the WETH in the pool (assuming each side of the pool has equal value)
				_tvl += 2 * ( reserve1 * ethPrice ) / ( 10 ** 18 );
				}

			else if ( address(token0) == address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) ) // USDC?
				{
				// Consider tvl for this pool to be twice the value of the WETH in the pool (assuming each side of the pool has equal value)
				_tvl += 2 * ( reserve0 * usdcPrice ) / ( 10 ** 6 );
				}

			else if ( address(token1) == address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) ) // USDC?
				{
				// Consider tvl for this pool to be twice the value of the WETH in the pool (assuming each side of the pool has equal value)
				_tvl += 2 * ( reserve1 * usdcPrice ) / ( 10 ** 6 );
				}
			}
		}


	// The current circulating supply of ZERO
	function circulatingZERO() public view returns (uint256)
		{
		IZero zero = IZero(address(0x0110B0c3391584Ba24Dbf8017Bf462e9f78A6d9F));
		IExchangeConfig exchangeConfig = IExchangeConfig(address(0x66DB65306C2dDb7Aa9730e010033eE624ddD7f61));
		address emissions = address(0x7647F324e7fDE3aC8c70775988D42F764daf5e8d);
		address stakingRewardsEmitter = address(0x7A48c8936389E50874aDd4987e4D6b0d8248f566);
		address liquidityRewardsEmitter = address(0x5Bb26BFAB9CAF661B2DE03BC286104278FeA65ae);
		address airdrop1 = address(0x3d9a9EDc9880DE24D33B6ca5a59cc91560C3A21e);
		address airdrop2 = address(0x0CF0Ce08acEE57Ba864DD95b036698aADf6503E5);

		return circulatingZERO( zero, exchangeConfig, emissions, stakingRewardsEmitter, liquidityRewardsEmitter, airdrop1, airdrop2 );
		}


	// The current price of ZERO (18 decimals)
	function priceZERO() external view returns (uint256 zeroPrice)
		{
		 IPools pools = IPools(address(0xf5D65d370141f1fff0Db646c9406Ce051354A8a5));
		 IExchangeConfig exchangeConfig = IExchangeConfig(address(0x66DB65306C2dDb7Aa9730e010033eE624ddD7f61));
		 IPriceFeed priceFeed = IPriceFeed(address(0x1D3C3C4C021C63c36369e3A06f8db03BD4A18bEf));

	    (,, zeroPrice) = corePrices(pools, exchangeConfig, priceFeed);
		}


	// The max supply of ZERO
	function maxZERO() external view returns (uint256)
		{
		IZero zero = IZero(address(0x0110B0c3391584Ba24Dbf8017Bf462e9f78A6d9F));

		// Maximum supply is the initial supply of 100 million - amount burned
		return 100000000 ether - zero.totalBurned();
		}
	}

