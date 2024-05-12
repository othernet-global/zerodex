// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../rewards/interfaces/IRewardsConfig.sol";
import "../interfaces/IExchangeConfig.sol";
import "./interfaces/IEmissions.sol";
import "../interfaces/IZero.sol";


// Responsible for storing the ZERO token emissions at launch and then distributing them over time.
// The emissions are gradually distributed to the stakingRewardsEmitter and liquidityRewardsEmitter on performUpkeep (via the ZeroRewards contract).
// Default rate of emissions is 0.50% of the remaining ZERO token balance per week (interpolated based on the time elapsed since the last performUpkeep call).

contract Emissions is IEmissions
    {
	using SafeERC20 for IZero;

    uint256 constant public MAX_TIME_SINCE_LAST_UPKEEP = 1 weeks;

    IZeroRewards immutable public zeroRewards;
	IExchangeConfig immutable public exchangeConfig;
	IRewardsConfig immutable public rewardsConfig;
	IZero immutable public zero;


    constructor( IZeroRewards _zeroRewards, IExchangeConfig _exchangeConfig, IRewardsConfig _rewardsConfig )
		{
		zeroRewards = _zeroRewards;
		exchangeConfig = _exchangeConfig;
		rewardsConfig = _rewardsConfig;

		// Cached for efficiency
		zero = _exchangeConfig.zero();
		}


	// Transfer a percent (default 0.50% per week) of the currently held ZERO tokens to the stakingRewardsEmitter and liquidityRewardsEmitter (via ZeroRewards).
	// The percentage to transfer is interpolated from how long it's been since the last performUpkeep() call.
	function performUpkeep(uint256 timeSinceLastUpkeep) external
		{
		require( msg.sender == address(exchangeConfig.upkeep()), "Emissions.performUpkeep is only callable from the Upkeep contract" );

		if ( timeSinceLastUpkeep == 0 )
			return;

		// Cap the timeSinceLastUpkeep at one week (if for some reason it has been longer).
		// This will cap the emitted rewards at a default of 0.50% in this transaction.
		if ( timeSinceLastUpkeep >= MAX_TIME_SINCE_LAST_UPKEEP )
			timeSinceLastUpkeep = MAX_TIME_SINCE_LAST_UPKEEP;

		uint256 zeroBalance = zero.balanceOf( address( this ) );

		// Target a certain percentage of rewards per week and base what we need to distribute now on how long it has been since the last distribution
		uint256 zeroToSend = ( zeroBalance * timeSinceLastUpkeep * rewardsConfig.emissionsWeeklyPercentTimes1000() ) / ( 100 * 1000 weeks );
		if ( zeroToSend == 0 )
			return;

		// Send the emissions to zeroRewards
		zero.safeTransfer(address(zeroRewards), zeroToSend);
		}
	}
