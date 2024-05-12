// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "../interfaces/IExchangeConfig.sol";
import "../arbitrage/ArbitrageSearch.sol";
import "./interfaces/IPoolsConfig.sol";
import "./interfaces/IPools.sol";
import "./PoolStats.sol";
import "./PoolUtils.sol";


// The Pools contract stores the reserves that are used for swaps within the DEX.
// It handles deposits, arbitrage, and keeps stats for proportional rewards distribution to the liquidity providers.
//
// Only the Liquidity contract can actually call addLiquidity and removeLiquidity.
// User liquidity accounting is done by Liquidity (via its derivation of StakingRewards).

contract Pools is IPools, ReentrancyGuard, PoolStats, ArbitrageSearch, Ownable
	{
	event LiquidityAdded(IERC20 indexed tokenA, IERC20 indexed tokenB, uint256 addedAmountA, uint256 addedAmountB, uint256 addedLiquidity);
	event LiquidityRemoved(IERC20 indexed tokenA, IERC20 indexed tokenB, uint256 reclaimedA, uint256 reclaimedB, uint256 removedLiquidity);
	event TokenDeposit(address indexed user, IERC20 indexed token, uint256 amount);
	event TokenWithdrawal(address indexed user, IERC20 indexed token, uint256 amount);
	event SwapAndArbitrage(address indexed user, IERC20 indexed swapTokenIn, IERC20 indexed swapTokenOut, uint256 swapAmountIn, uint256 swapAmountOut, uint256 arbitrageProfit);

	using SafeERC20 for IERC20;

	struct PoolReserves
		{
		uint128 reserve0;						// The token reserves such that address(token0) < address(token1)
		uint128 reserve1;
		}


	IDAO public dao;
	ILiquidity public liquidity;
	IZero public zero;

	// Set to true when starting the exchange is approved by the bootstrapBallot
	bool public exchangeIsLive;

	// Keeps track of the pool reserves by poolID
	mapping(bytes32=>PoolReserves) private _poolReserves;

	// User token balances for deposited tokens
	mapping(address=>mapping(IERC20=>uint256)) private _userDeposits;

	// Used to prevent splitting large swaps within a single block into smaller ones as doing so allows for greater price manipulation without consequence from the arbitrage rebalancing.
	mapping(address => uint) private lastSwappedBlocks;


	constructor( IExchangeConfig _exchangeConfig, IPoolsConfig _poolsConfig )
	ArbitrageSearch(_exchangeConfig)
	PoolStats(_exchangeConfig, _poolsConfig)
		{
		zero = _exchangeConfig.zero();
		}


	// Allow users to make only one swap per block
	modifier oneUserSwapPerBlock()
		{
		require(lastSwappedBlocks[msg.sender] != block.number, "User already swapped in this block");
        _;
        lastSwappedBlocks[msg.sender] = block.number;
        }


	modifier ensureNotExpired(uint256 deadline)
		{
		require(block.timestamp <= deadline, "TX EXPIRED");
		_;
		}


	// This will be called only once - at deployment time
	function setContracts( IDAO _dao, ILiquidity _liquidity ) external onlyOwner
		{
		dao = _dao;
		liquidity = _liquidity;

		// setContracts can only be called once
		renounceOwnership();
		}


	function startExchangeApproved() external nonReentrant
		{
    	require( msg.sender == address(exchangeConfig.initialDistribution().bootstrapBallot()), "Pools.startExchangeApproved can only be called from the BootstrapBallot contract" );

		// Make sure that the arbitrage indicies for the whitelisted pools are updated before starting the exchange
		updateArbitrageIndicies();

		exchangeIsLive = true;
		}


	// Add the given amount of two tokens to the specified liquidity pool.
	// The maximum amount of tokens is added while having the added amount have the same ratio as the current reserves.
	function _addLiquidity( bytes32 poolID, uint256 maxAmount0, uint256 maxAmount1, uint256 totalLiquidity ) internal returns(uint256 addedAmount0, uint256 addedAmount1, uint256 addedLiquidity)
		{
		PoolReserves storage reserves = _poolReserves[poolID];
		uint256 reserve0 = reserves.reserve0;
		uint256 reserve1 = reserves.reserve1;

		// If either reserve is zero then consider the pool to be empty and that the added liquidity will become the initial token ratio
		if ( ( reserve0 == 0 ) || ( reserve1 == 0 ) )
			{
			// Update the reserves
			reserves.reserve0 += uint128(maxAmount0);
			reserves.reserve1 += uint128(maxAmount1);

			// Default liquidity will be the addition of both maxAmounts in case one of them is much smaller (has smaller decimals)
			return ( maxAmount0, maxAmount1, (maxAmount0 + maxAmount1) );
			}

		// Add liquidity to the pool proportional to the current existing token reserves in the pool.
		// First, try the proportional amount of tokenB for the given maxAmountA
		uint256 proportionalB = ( maxAmount0 * reserve1 ) / reserve0;

		// proportionalB too large for the specified maxAmountB?
		if ( proportionalB > maxAmount1 )
			{
			// Use maxAmountB and a proportional amount for tokenA instead
			addedAmount0 = ( maxAmount1 * reserve0 ) / reserve1;
			addedAmount1 = maxAmount1;
			}
		else
			{
			addedAmount0 = maxAmount0;
			addedAmount1 = proportionalB;
			}

		// Ensure that the added amounts are at least DUST
		require( addedAmount0 > PoolUtils.DUST, "Added liquidity for token 0 less than DUST" );
		require( addedAmount1 > PoolUtils.DUST, "Added liquidity for token 1 less than DUST" );

		// Update the reserves
		reserves.reserve0 += uint128(addedAmount0);
		reserves.reserve1 += uint128(addedAmount1);

		// Determine the amount of liquidity that will be given to the user to reflect their share of the total liquidity.
		addedLiquidity = (totalLiquidity * (addedAmount0+addedAmount1) ) / (reserve0+reserve1);
		}


	// Add liquidity to the specified pool (must be a whitelisted pool)
	// Only callable from the Liquidity contract - so it can specify totalLiquidity with authority
	function addLiquidity( IERC20 tokenA, IERC20 tokenB, uint256 maxAmountA, uint256 maxAmountB, uint256 minAddedAmountA, uint256 minAddedAmountB, uint256 totalLiquidity ) external nonReentrant returns (uint256 addedAmountA, uint256 addedAmountB, uint256 addedLiquidity)
		{
		require( msg.sender == address(liquidity), "Pools.addLiquidity is only callable from the Liquidity contract" );
		require( exchangeIsLive, "The exchange is not yet live" );
		require( address(tokenA) != address(tokenB), "Cannot add liquidity for duplicate tokens" );

		require( maxAmountA > PoolUtils.DUST, "The amount of tokenA to add is too small" );
		require( maxAmountB > PoolUtils.DUST, "The amount of tokenB to add is too small" );

		(bytes32 poolID, bool flipped) = PoolUtils._poolIDAndFlipped(tokenA, tokenB);

		// Flip the users arguments if they are not in reserve token order with address(tokenA) < address(tokenB)
		if ( flipped )
			(addedAmountB, addedAmountA, addedLiquidity) = _addLiquidity( poolID, maxAmountB, maxAmountA, totalLiquidity );
		else
			(addedAmountA, addedAmountB, addedLiquidity) = _addLiquidity( poolID, maxAmountA, maxAmountB, totalLiquidity );

		// Make sure the minimum liquidity has been added
		require( addedAmountA >= minAddedAmountA, "Insufficient tokenA added to liquidity" );
		require( addedAmountB >= minAddedAmountB, "Insufficient tokenB added to liquidity" );

		// Transfer the tokens from the sender - only tokens without fees should be whitelisted on the DEX
		tokenA.safeTransferFrom(msg.sender, address(this), addedAmountA );
		tokenB.safeTransferFrom(msg.sender, address(this), addedAmountB );

		emit LiquidityAdded(tokenA, tokenB, addedAmountA, addedAmountB, addedLiquidity);
		}


	// Remove liquidity for the user and reclaim the underlying tokens
	// Only callable from the Liquidity contract - so it can specify totalLiquidity with authority
	function removeLiquidity( IERC20 tokenA, IERC20 tokenB, uint256 liquidityToRemove, uint256 minReclaimedA, uint256 minReclaimedB, uint256 totalLiquidity ) external nonReentrant returns (uint256 reclaimedA, uint256 reclaimedB)
		{
		require( msg.sender == address(liquidity), "Pools.removeLiquidity is only callable from the Liquidity contract" );
		require( liquidityToRemove > 0, "The amount of liquidityToRemove cannot be zero" );

		(bytes32 poolID, bool flipped) = PoolUtils._poolIDAndFlipped(tokenA, tokenB);

		// Determine how much liquidity is being withdrawn and round down in favor of the protocol
		PoolReserves storage reserves = _poolReserves[poolID];

		if (reserves.reserve0 <= reserves.reserve1 )
			{
			reclaimedA = ( reserves.reserve0 * liquidityToRemove ) / totalLiquidity;
			reclaimedB = ( reserves.reserve1 * reclaimedA ) / reserves.reserve0;
			}
		else
			{
			reclaimedB = ( reserves.reserve1 * liquidityToRemove ) / totalLiquidity;
			reclaimedA = ( reserves.reserve0 * reclaimedB ) / reserves.reserve1;
			}

		reserves.reserve0 -= uint128(reclaimedA);
		reserves.reserve1 -= uint128(reclaimedB);

		// Make sure that removing liquidity doesn't drive either of the reserves below DUST.
		// This is to ensure that ratios remain relatively constant even after a maximum withdrawal.
        require((reserves.reserve0 >= PoolUtils.DUST) && (reserves.reserve1 >= PoolUtils.DUST), "Insufficient reserves after liquidity removal");

		// Switch reclaimed amounts back to the order that was specified in the call arguments so they make sense to the caller
		if (flipped)
			(reclaimedA,reclaimedB) = (reclaimedB,reclaimedA);

		require( (reclaimedA >= minReclaimedA) && (reclaimedB >= minReclaimedB), "Insufficient underlying tokens returned" );

		// Send the reclaimed tokens to the user
		tokenA.safeTransfer( msg.sender, reclaimedA );
		tokenB.safeTransfer( msg.sender, reclaimedB );

		emit LiquidityRemoved(tokenA, tokenB, reclaimedA, reclaimedB, liquidityToRemove);
		}


	// Allow users to deposit tokens into the contract.
	// This is not rewarded or considered staking in any way.  It's simply a way to reduce gas costs by preventing transfers at swap time.
	function deposit( IERC20 token, uint256 amount ) external nonReentrant
		{
        require( amount > PoolUtils.DUST, "Deposit amount too small");

		_userDeposits[msg.sender][token] += amount;

		// Transfer the tokens from the sender - only tokens without fees should be whitelisted on the DEX
		token.safeTransferFrom(msg.sender, address(this), amount );

		emit TokenDeposit(msg.sender, token, amount);
		}


	// Withdraw tokens that were previously deposited
    function withdraw( IERC20 token, uint256 amount ) external nonReentrant
    	{
    	require( _userDeposits[msg.sender][token] >= amount, "Insufficient balance to withdraw specified amount" );
        require( amount > PoolUtils.DUST, "Withdraw amount too small");

		_userDeposits[msg.sender][token] -= amount;

    	// Send the token to the user
    	token.safeTransfer( msg.sender, amount );

    	emit TokenWithdrawal(msg.sender, token, amount);
    	}


	// Swap amountIn tokens for amountOut tokens in the direction specified by flipped and update the reserves.
	// Only the reserves are updated - the function does not adjust deposited user balances or do ERC20 transfers.
	// Assumes that the reserves have already been checked for minimal necessary liquidity.
    function _adjustReservesForSwap( PoolReserves storage reserves, bool flipped, uint256 amountIn ) internal returns (uint256 amountOut)
    	{
		// Constant Product AMM Math
		// k=r0*r1																	• product of reserves is constant k
		// k=(r0+amountIn)*(r1-amountOut)							• add some token0 to r0 and swap it for some token1 which is removed from r1
		// r1-amountOut=k/(r0+amountIn)								• divide by (r0+amountIn) and flip
		// amountOut=r1-k/(r0+amountIn)								• multiply by -1 and isolate amountOut
		// amountOut(r0+amountIn)=r1(r0+amountIn)-k		• multiply by (r0+amountIn)
		// amountOut(r0+amountIn)=r1*r0+r1*amountIn-k	• multiply r1 by (r0+amountIn)
		// amountOut(r0+amountIn)=k+r1*amountIn-k			• r0*r1=k (from above)
		// amountOut(r0+amountIn)=r1*amountIn					• cancel k
		// amountOut=r1*amountIn/(r0+amountIn)				• isolate amountOut

        uint256 reserve0 = reserves.reserve0;
        uint256 reserve1 = reserves.reserve1;

		// See if the reserves should be flipped
        if (flipped)
        	{
			reserve1 += amountIn;
			amountOut = reserve0 * amountIn / reserve1;
			reserve0 -= amountOut;
        	}
        else
        	{
			reserve0 += amountIn;
			amountOut = reserve1 * amountIn / reserve0;
			reserve1 -= amountOut;
        	}

		// Make sure that the reserves after swap are greater than DUST
        require( (reserve0 > PoolUtils.DUST) && (reserve1 > PoolUtils.DUST), "Insufficient reserves after swap");

		// Update the reserves with an overflow check
		require( (reserve0 <= type(uint128).max) && (reserve1 <= type(uint128).max), "Reserves overflow after swap" );

		reserves.reserve0 = uint128(reserve0);
		reserves.reserve1 = uint128(reserve1);
    	}


    // Arbitrage a token to itself along a specified circular path (starting and ending with WETH), taking advantage of imbalances in the exchange pools.
    // Does not require any deposited tokens to make the call, but requires that the resulting amountOut is greater than the specified arbitrageAmountIn.
    // Essentially the caller virtually "borrows" arbitrageAmountIn of the starting token and virtually "repays" it from their received amountOut at the end of the swap chain.
    // The extra amountOut (compared to arbitrageAmountIn) is the arbitrageProfit.
	function _arbitrage(uint256 arbitrageAmountIn, PoolReserves storage reservesA, PoolReserves storage reservesB, PoolReserves storage reservesC, bool flippedA, bool flippedB, bool flippedC ) internal returns (uint256 arbitrageProfit)
		{
		uint256 amountOut = _adjustReservesForSwap( reservesA, flippedA, arbitrageAmountIn );
		amountOut = _adjustReservesForSwap( reservesB, flippedB, amountOut );
		amountOut = _adjustReservesForSwap( reservesC, flippedC, amountOut );

		// Will revert if amountOut < arbitrageAmountIn
		arbitrageProfit = amountOut - arbitrageAmountIn;

		// Immediately swap the generated WETH arbitrage profits to ZERO
		(bytes32 poolID, bool flipped) = PoolUtils._poolIDAndFlipped(weth, zero);
        PoolReserves storage reserves = _poolReserves[poolID];

        // Only swap for ZERO with sufficient reserves
		if ( ( reserves.reserve0 > PoolUtils.DUST ) && ( reserves.reserve1 > PoolUtils.DUST ) )
			{
			uint256 zeroOut = _adjustReservesForSwap(reserves, flipped, arbitrageProfit);

			// Deposit the swapped ZERO for the DAO - to be used later within DAO.performUpkeep
			_userDeposits[address(dao)][zero] += zeroOut;
			}
		}


	// Check to see if profitable arbitrage is possible after the user swap that was just made
	// Check the arbitrage path: WETH->arbToken2->arbToken3->WETH
	function _attemptArbitrage( IERC20 arbToken2, IERC20 arbToken3 ) internal returns (uint256 arbitrageProfit)
		{
		bytes32 poolID;
		bool flippedA;
		bool flippedB;
		bool flippedC;

		PoolReserves storage reservesA;
		PoolReserves storage reservesB;
		PoolReserves storage reservesC;

		// Given the specified arbitrage path, determine the best arbitrageAmountIn to use
		uint256 arbitrageAmountIn;
			{
			(poolID, flippedA) = PoolUtils._poolIDAndFlipped(weth, arbToken2);
			reservesA = _poolReserves[poolID];
			(uint256 a0, uint256 a1) = (reservesA.reserve0, reservesA.reserve1 );
			if (flippedA)
				(a0, a1) = (a1, a0);


			(poolID, flippedB) = PoolUtils._poolIDAndFlipped(arbToken2, arbToken3);
			reservesB = _poolReserves[poolID];
			(uint256 b0, uint256 b1) = (reservesB.reserve0, reservesB.reserve1 );
			if (flippedB)
				(b0, b1) = (b1, b0);


			(poolID, flippedC) = PoolUtils._poolIDAndFlipped(arbToken3, weth);
			reservesC = _poolReserves[poolID];
			(uint256 c0, uint256 c1) = (reservesC.reserve0, reservesC.reserve1 );
			if (flippedC)
				(c0, c1) = (c1, c0);

			// Determine the best amount of WETH to start the arbitrage with
			if ( a0 > PoolUtils.DUST && a1 > PoolUtils.DUST && b0 > PoolUtils.DUST && b1 > PoolUtils.DUST && c0 > PoolUtils.DUST && c1 > PoolUtils.DUST )
				arbitrageAmountIn = _bestArbitrageIn(a0, a1, b0, b1, c0, c1 );
			}

		// If arbitrage is viable, then perform it
		if (arbitrageAmountIn > 0)
			{
			 arbitrageProfit = _arbitrage(arbitrageAmountIn, reservesA, reservesB, reservesC, flippedA, flippedB, flippedC);

			// Update the stats related to the pools that contributed to the arbitrage so they can be rewarded proportionally later.
			// The arbitrage path can be identified by the middle tokens arbToken2 and arbToken3 (with WETH always on both ends)
			_updateProfitsFromArbitrage( arbToken2, arbToken3, arbitrageProfit );
			 }
		}


	// Adjust the reserves for swapping between the two specified tokens and then immediately attempt arbitrage.
	// Does not require exchange access for the sending wallet.
	function _adjustReservesForSwapAndAttemptArbitrage( IERC20 swapTokenIn, IERC20 swapTokenOut, uint256 swapAmountIn, uint256 minAmountOut ) internal returns (uint256 swapAmountOut)
		{
		// Place the user swap first
		(bytes32 poolID, bool flipped) = PoolUtils._poolIDAndFlipped(swapTokenIn, swapTokenOut);
        PoolReserves storage reserves = _poolReserves[poolID];

        // Revert if reserves are insufficient
        require((reserves.reserve0 > PoolUtils.DUST) && (reserves.reserve1 > PoolUtils.DUST), "Insufficient reserves before swap");
		swapAmountOut = _adjustReservesForSwap( reserves, flipped, swapAmountIn );

		// Make sure the swap meets the minimums specified by the user
		require( swapAmountOut >= minAmountOut, "Insufficient resulting token amount" );

		// The user's swap has just been made - attempt atomic arbitrage to rebalance the pool and yield arbitrage profit.

		// Determine the arbitrage path for the given user swap.
		// Arbitrage path returned as: weth->arbToken2->arbToken3->weth
		(IERC20 arbToken2, IERC20 arbToken3) = _arbitragePath( swapTokenIn, swapTokenOut );
		uint256 arbitrageProfit = _attemptArbitrage( arbToken2, arbToken3 );

		emit SwapAndArbitrage(msg.sender, swapTokenIn, swapTokenOut, swapAmountIn, swapAmountOut, arbitrageProfit);
		}


    // Swap one token for another via a direct whitelisted pool.
    // Having simpler swaps without multiple tokens in the swap chain makes it simpler (and less expensive gas wise) to find suitable arbitrage opportunities.
    // Cheap arbitrage gas-wise is important as arbitrage will be atomically attempted with every user swap transaction.
    // Requires that the first token in the chain has already been deposited for the caller.
	function swap( IERC20 swapTokenIn, IERC20 swapTokenOut, uint256 swapAmountIn, uint256 minAmountOut, uint256 deadline ) external oneUserSwapPerBlock nonReentrant ensureNotExpired(deadline) returns (uint256 swapAmountOut)
		{
		// Confirm and adjust user deposits
		mapping(IERC20=>uint256) storage userDeposits = _userDeposits[msg.sender];

    	require( userDeposits[swapTokenIn] >= swapAmountIn, "Insufficient deposited token balance of initial token" );
		userDeposits[swapTokenIn] -= swapAmountIn;

		swapAmountOut = _adjustReservesForSwapAndAttemptArbitrage(swapTokenIn, swapTokenOut, swapAmountIn, minAmountOut );

		// Deposit the final tokenOut for the caller
		userDeposits[swapTokenOut] += swapAmountOut;
		}


	// Deposit tokenIn, swap to tokenOut and then have tokenOut sent to the sender
	function depositSwapWithdraw(IERC20 swapTokenIn, IERC20 swapTokenOut, uint256 swapAmountIn, uint256 minAmountOut, uint256 deadline ) external oneUserSwapPerBlock nonReentrant ensureNotExpired(deadline) returns (uint256 swapAmountOut)
		{
		// Transfer the tokens from the sender - only tokens without fees should be whitelisted on the DEX
		swapTokenIn.safeTransferFrom(msg.sender, address(this), swapAmountIn );

		swapAmountOut = _adjustReservesForSwapAndAttemptArbitrage(swapTokenIn, swapTokenOut, swapAmountIn, minAmountOut );

    	// Send tokenOut to the user
    	swapTokenOut.safeTransfer( msg.sender, swapAmountOut );
		}


	// Deposit tokenIn, swap to tokenOut without arbitrage and then have tokenOut sent to the sender.
	// Only callable by the Liquidity contract
	function depositZapSwapWithdraw(IERC20 zapSwapTokenIn, IERC20 zapSwapTokenOut, uint256 zapSwapAmountIn ) external returns (uint256 zapSwapAmountOut)
		{
		require( msg.sender == address(liquidity), "Pools.depositZapSwapWithdraw is only callable from the Liquidity contract" );

		// Transfer the tokens from the sender - only tokens without fees should be whitelisted on the DEX
		zapSwapTokenIn.safeTransferFrom(msg.sender, address(this), zapSwapAmountIn );

		// Perform the zap swap without arbitrage or minimum checks (as the users final swap will be checked for relevant minimums).
		// PoolMath.determineZapSwapAmount already checked for reservers > DUST as well.
		(bytes32 poolID, bool flipped) = PoolUtils._poolIDAndFlipped(zapSwapTokenIn, zapSwapTokenOut);
        PoolReserves storage reserves = _poolReserves[poolID];

		// Prevent users from zapping too much at once as they may encounter unexpected slippage
		if ( flipped )
			require( zapSwapAmountIn < reserves.reserve1 / 100, "Cannot zap more than 1% of the reserves" );
		else
			require( zapSwapAmountIn < reserves.reserve0 / 100, "Cannot zap more than 1% of the reserves" );

		zapSwapAmountOut = _adjustReservesForSwap( reserves, flipped, zapSwapAmountIn );

    	// Send tokenOut to the user
    	zapSwapTokenOut.safeTransfer( msg.sender, zapSwapAmountOut );
		}


	// A convenience method to perform two swaps in one transaction
	function depositDoubleSwapWithdraw( IERC20 swapTokenIn, IERC20 swapTokenMiddle, IERC20 swapTokenOut, uint256 swapAmountIn, uint256 minAmountOut, uint256 deadline ) external oneUserSwapPerBlock nonReentrant ensureNotExpired(deadline) returns (uint256 swapAmountOut)
		{
		swapTokenIn.safeTransferFrom(msg.sender, address(this), swapAmountIn );

		uint256 middleAmountOut = _adjustReservesForSwapAndAttemptArbitrage(swapTokenIn, swapTokenMiddle, swapAmountIn, 0 );
		swapAmountOut = _adjustReservesForSwapAndAttemptArbitrage(swapTokenMiddle, swapTokenOut, middleAmountOut, minAmountOut );

    	swapTokenOut.safeTransfer( msg.sender, swapAmountOut );
		}


	// === VIEWS ===

	// The pool reserves for two specified tokens - returned in the order specified by the caller
	function getPoolReserves(IERC20 tokenA, IERC20 tokenB) public view returns (uint256 reserveA, uint256 reserveB)
		{
		(bytes32 poolID, bool flipped) = PoolUtils._poolIDAndFlipped(tokenA, tokenB);
		PoolReserves memory reserves = _poolReserves[poolID];
		reserveA = reserves.reserve0;
		reserveB = reserves.reserve1;

		// Return the reserves in the order that they were requested
		if (flipped)
			(reserveA, reserveB) = (reserveB, reserveA);
		}


	// A user's deposited balance for a token
	function depositedUserBalance(address user, IERC20 token) public view returns (uint256)
		{
		return _userDeposits[user][token];
		}
	}