// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../rewards/interfaces/IRewardsEmitter.sol";
import "../rewards/interfaces/IRewardsConfig.sol";
import "../interfaces/IExchangeConfig.sol";
import "./interfaces/IZeroRewards.sol";
import "../interfaces/IZero.sol";
import "../pools/PoolUtils.sol";


// A utility contract that temporarily holds ZERO token rewards from emissions and arbitrage profits during performUpkeep().
// Sends ZERO token rewards to the stakingRewardsEmitter and liquidityRewardsEmitter (with proportions for the latter based on each pool's share in generating recent arbitrage profits).
contract ZeroRewards is IZeroRewards
    {
	IRewardsEmitter immutable public stakingRewardsEmitter;
	IRewardsEmitter immutable public liquidityRewardsEmitter;
	IExchangeConfig immutable public exchangeConfig;
	IRewardsConfig immutable public rewardsConfig;
	IZero immutable public zero;


    constructor( IRewardsEmitter _stakingRewardsEmitter, IRewardsEmitter _liquidityRewardsEmitter, IExchangeConfig _exchangeConfig, IRewardsConfig _rewardsConfig )
		{
		stakingRewardsEmitter = _stakingRewardsEmitter;
		liquidityRewardsEmitter = _liquidityRewardsEmitter;
		exchangeConfig = _exchangeConfig;
		rewardsConfig = _rewardsConfig;

		// Cached for efficiency
		zero = _exchangeConfig.zero();

		// Gas saving approval for rewards distribution on performUpkeep().
		// This contract only has a temporary ZERO token balance during the performUpkeep transaction.
		zero.approve( address(stakingRewardsEmitter), type(uint256).max );
		zero.approve( address(liquidityRewardsEmitter), type(uint256).max );
		}


	// Send the pending ZERO token rewards to the stakingRewardsEmitter
	function _sendStakingRewards(uint256 stakingRewardsAmount) internal
		{
		AddedReward[] memory addedRewards = new AddedReward[](1);
		addedRewards[0] = AddedReward( PoolUtils.STAKED_ZERO, stakingRewardsAmount );

		stakingRewardsEmitter.addZERORewards(addedRewards);
		}


	// Transfer ZERO token rewards to pools in the liquidityRewardsEmitter proportional to each pool's share in generating recent arbitrage profits.
	function _sendLiquidityRewards( uint256 liquidityRewardsAmount, bytes32[] memory poolIDs, uint256[] memory profitsForPools, uint256 totalProfits ) internal
		{
		require( poolIDs.length == profitsForPools.length, "Incompatible array lengths" );

		// Send ZERO token rewards (with an amount of pendingLiquidityRewards) proportional to the profits generated by each pool
		AddedReward[] memory addedRewards = new AddedReward[]( poolIDs.length );
		for( uint256 i = 0; i < addedRewards.length; i++ )
			{
			bytes32 poolID = poolIDs[i];
			uint256 rewardsForPool = ( liquidityRewardsAmount * profitsForPools[i] ) / totalProfits;

			addedRewards[i] = AddedReward( poolID, rewardsForPool );
			}

		// Send the ZERO token rewards to the LiquidityRewardsEmitter
		liquidityRewardsEmitter.addZERORewards( addedRewards );
		}


	function _sendInitialLiquidityRewards( uint256 liquidityBootstrapAmount, bytes32[] memory poolIDs ) internal
		{
		// Divide the liquidityBootstrapAmount evenly across all the initial pools
		uint256 amountPerPool = liquidityBootstrapAmount / poolIDs.length; // poolIDs.length is guaranteed to not be zero

		AddedReward[] memory addedRewards = new AddedReward[]( poolIDs.length );
		for( uint256 i = 0; i < addedRewards.length; i++ )
			addedRewards[i] = AddedReward( poolIDs[i], amountPerPool );

		// Send the liquidity bootstrap rewards to the liquidityRewardsEmitter
		liquidityRewardsEmitter.addZERORewards( addedRewards );
		}


	function _sendInitialStakingRewards( uint256 stakingBootstrapAmount ) internal
		{
		// Send the stakingBootstrapAmount to the stakingRewardsEmitter
		AddedReward[] memory addedRewards = new AddedReward[](1);
		addedRewards[0] = AddedReward( PoolUtils.STAKED_ZERO, stakingBootstrapAmount );

		stakingRewardsEmitter.addZERORewards( addedRewards );
		}


    // Sends an expected 5 million ZERO tokens to the liquidityRewardsEmitter (evenly divided amongst the pools) and 3 million ZERO tokens to the stakingRewardsEmitter.
	function sendInitialZERORewards( uint256 liquidityBootstrapAmount, bytes32[] calldata poolIDs ) external
		{
		require( msg.sender == address(exchangeConfig.initialDistribution()), "ZeroRewards.sendInitialRewards is only callable from the InitialDistribution contract" );

		_sendInitialLiquidityRewards(liquidityBootstrapAmount, poolIDs);

		// Remaining ZERO token balance goes to stakingRewardsEmitter
		_sendInitialStakingRewards( zero.balanceOf(address(this)) );
		}


	function performUpkeep( bytes32[] calldata poolIDs, uint256[] calldata profitsForPools ) external
		{
		require( msg.sender == address(exchangeConfig.upkeep()), "ZeroRewards.performUpkeep is only callable from the Upkeep contract" );
		require( poolIDs.length == profitsForPools.length, "Incompatible array lengths" );

		// Distribute all ZERO tokens currently in the contract.
		uint256 zeroRewardsToDistribute = zero.balanceOf(address(this));
		if ( zeroRewardsToDistribute == 0 )
			return;

		// Determine the total profits so we can calculate proportional share for the liquidity rewards
		uint256 totalProfits = 0;
		for( uint256 i = 0; i < poolIDs.length; i++ )
			totalProfits += profitsForPools[i];

		// Make sure that there are some profits to determine the proportional liquidity rewards.
		// Otherwise just handle the ZERO token balance later so it can be divided between stakingRewardsEmitter and liquidityRewardsEmitter without further accounting.
		if ( totalProfits == 0 )
			return;

		// Divide up the remaining rewards between ZERO token stakers and liquidity providers
		uint256 stakingRewardsAmount = ( zeroRewardsToDistribute * rewardsConfig.stakingRewardsPercent() ) / 100;
		uint256 liquidityRewardsAmount = zeroRewardsToDistribute - stakingRewardsAmount;

		_sendStakingRewards(stakingRewardsAmount);
		_sendLiquidityRewards(liquidityRewardsAmount, poolIDs, profitsForPools, totalProfits);
		}
	}
