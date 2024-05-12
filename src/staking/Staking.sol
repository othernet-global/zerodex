// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "./interfaces/IStaking.sol";
import "../interfaces/IZero.sol";
import "./StakingRewards.sol";
import "../pools/PoolUtils.sol";


// Staking ZERO tokens provides veZERO at a 1:1 ratio.
// Unstaking veZERO to reclaim ZERO tokens has a default unstake duration of 52 weeks and a minimum duration of two weeks.
// Expedited unstaking for two weeks allows a default 20% of the ZERO tokens to be reclaimed, while unstaking for a full year allows the full 100% to be reclaimed.

contract Staking is IStaking, StakingRewards
    {
	event ZEROStaked(address indexed user, uint256 amountStaked);
	event UnstakeInitiated(address indexed user, uint256 indexed unstakeID, uint256 amountUnstaked, uint256 claimableZERO, uint256 numWeeks);
	event UnstakeCancelled(address indexed user, uint256 indexed unstakeID);
	event ZERORecovered(address indexed user, uint256 indexed unstakeID, uint256 zeroRecovered, uint256 expeditedUnstakeFee);
	event veZEROTransferredFromAirdrop(address indexed toUser, uint256 amountTransferred);

	using SafeERC20 for IZero;

	// The unstakeIDs for each user - including completed and cancelled unstakes.
	mapping(address => uint256[]) private _userUnstakeIDs;

	// Mapping of unstake IDs to their corresponding Unstake data.
    mapping(uint256=>Unstake) private _unstakesByID;
	uint256 public nextUnstakeID;


	constructor( IExchangeConfig _exchangeConfig, IPoolsConfig _poolsConfig, IStakingConfig _stakingConfig )
		StakingRewards( _exchangeConfig, _poolsConfig, _stakingConfig )
		{
		}


	// Stake a given amount of ZERO tokens and immediately receive the same amount of veZERO.
	// Requires exchange access for the sending wallet.
	function stakeZERO( uint256 amountToStake ) external nonReentrant
		{
		require( exchangeConfig.walletHasAccess(msg.sender), "Sender does not have exchange access" );

		// Increase the user's staking share so that they will receive more future ZERO token rewards.
		// No cooldown as it takes default 52 weeks to unstake the veZERO to receive the full amount of staked ZERO tokens back.
		_increaseUserShare( msg.sender, PoolUtils.STAKED_ZERO, amountToStake, false );

		// Transfer the ZERO tokens from the user's wallet
		zero.safeTransferFrom( msg.sender, address(this), amountToStake );

		emit ZEROStaked(msg.sender, amountToStake);
		}


	// Unstake a given amount of veZERO over a certain duration.
	// Unstaking immediately reduces the user's veZERO balance even though there will be the specified delay to convert it back to ZERO
	// With a full unstake duration the user receives 100% of their staked amount.
	// With expedited unstaking the user receives less.
	function unstake( uint256 amountUnstaked, uint256 numWeeks ) external nonReentrant returns (uint256 unstakeID)
		{
		require( userShareForPool(msg.sender, PoolUtils.STAKED_ZERO) >= amountUnstaked, "Cannot unstake more than the amount staked" );

		uint256 claimableZERO = calculateUnstake( amountUnstaked, numWeeks );
		uint256 completionTime = block.timestamp + numWeeks * ( 1 weeks );

		unstakeID = nextUnstakeID++;
		Unstake memory u = Unstake( UnstakeState.PENDING, msg.sender, amountUnstaked, claimableZERO, completionTime, unstakeID );

		_unstakesByID[unstakeID] = u;
		_userUnstakeIDs[msg.sender].push( unstakeID );

		// Decrease the user's staking share so that they will receive less future ZERO token rewards
		// This call will send any pending ZERO token rewards to msg.sender as well.
		// Note: _decreaseUserShare checks to make sure that the user has the specified staking share balance.
		_decreaseUserShare( msg.sender, PoolUtils.STAKED_ZERO, amountUnstaked, false );

		emit UnstakeInitiated(msg.sender, unstakeID, amountUnstaked, claimableZERO, numWeeks);
		}


	// Cancel a pending unstake.
	// Caller will be able to use the veZERO again immediately
	function cancelUnstake( uint256 unstakeID ) external nonReentrant
		{
		Unstake storage u = _unstakesByID[unstakeID];

		require( u.status == UnstakeState.PENDING, "Only PENDING unstakes can be cancelled" );
		require( block.timestamp < u.completionTime, "Unstakes that have already completed cannot be cancelled" );
		require( msg.sender == u.wallet, "Sender is not the original staker" );

		// Update the user's share of the rewards for staked ZERO tokens
		_increaseUserShare( msg.sender, PoolUtils.STAKED_ZERO, u.unstakedVeZERO, false );

		u.status = UnstakeState.CANCELLED;
		emit UnstakeCancelled(msg.sender, unstakeID);
		}


	// Recover claimable ZERO tokens from a completed unstake
	function recoverZERO( uint256 unstakeID ) external nonReentrant
		{
		Unstake storage u = _unstakesByID[unstakeID];
		require( u.status == UnstakeState.PENDING, "Only PENDING unstakes can be claimed" );
		require( block.timestamp >= u.completionTime, "Unstake has not completed yet" );
		require( msg.sender == u.wallet, "Sender is not the original staker" );

		u.status = UnstakeState.CLAIMED;

		// See if the user unstaked early and received only a portion of their original stake.
		// The portion they did not receive will be considered the expeditedUnstakeFee.
		uint256 expeditedUnstakeFee = u.unstakedVeZERO - u.claimableZERO;

		// Burn 100% of the expeditedUnstakeFee
		if ( expeditedUnstakeFee > 0 )
			{
			// Send the expeditedUnstakeFee to the ZERO contract and burn it
			zero.safeTransfer( address(zero), expeditedUnstakeFee );
            zero.burnTokensInContract();
            }

		// Send the reclaimed ZERO tokens back to the user
		zero.safeTransfer( msg.sender, u.claimableZERO );

		emit ZERORecovered(msg.sender, unstakeID, u.claimableZERO, expeditedUnstakeFee);
		}


	// === VIEWS ===

	function userVeZERO( address wallet ) external view returns (uint256)
		{
		return userShareForPool(wallet, PoolUtils.STAKED_ZERO);
		}


	// Retrieve all unstakes associated with a user within a specific range.
	function unstakesForUser( address user, uint256 start, uint256 end ) public view returns (Unstake[] memory)
		{
        // Check if start and end are within the bounds of the array
        require(end >= start, "Invalid range: end cannot be less than start");

        uint256[] memory userUnstakes = _userUnstakeIDs[user];

        require(userUnstakes.length > end, "Invalid range: end is out of bounds");
        require(start < userUnstakes.length, "Invalid range: start is out of bounds");

        Unstake[] memory unstakes = new Unstake[](end - start + 1);

        uint256 index;
        for(uint256 i = start; i <= end; i++)
            unstakes[index++] = _unstakesByID[ userUnstakes[i]];

        return unstakes;
    }


	// Retrieve all unstakes associated with a user.
	function unstakesForUser( address user ) external view returns (Unstake[] memory)
		{
		// Check to see how many unstakes the user has
		uint256[] memory unstakeIDs = _userUnstakeIDs[user];
		if ( unstakeIDs.length == 0 )
			return new Unstake[](0);

		// Return them all
		return unstakesForUser( user, 0, unstakeIDs.length - 1 );
		}


	// Returns the unstakeIDs for the user
	function userUnstakeIDs( address user ) external view returns (uint256[] memory)
		{
		return _userUnstakeIDs[user];
		}


	function unstakeByID(uint256 id) external view returns (Unstake memory)
		{
		return _unstakesByID[id];
		}


	// Calculate the reclaimable amount of ZERO tokens based on the amount of unstaked veZERO and unstake duration
	// By default, unstaking for two weeks allows 20% of the ZERO tokens to be reclaimed, while unstaking for a full year allows the full 100% to be reclaimed.
	function calculateUnstake( uint256 unstakedVeZERO, uint256 numWeeks ) public view returns (uint256)
		{
		uint256 minUnstakeWeeks = stakingConfig.minUnstakeWeeks();
        uint256 maxUnstakeWeeks = stakingConfig.maxUnstakeWeeks();
        uint256 minUnstakePercent = stakingConfig.minUnstakePercent();

		require( numWeeks >= minUnstakeWeeks, "Unstaking duration too short" );
		require( numWeeks <= maxUnstakeWeeks, "Unstaking duration too long" );

		uint256 percentAboveMinimum = 100 - minUnstakePercent;
		uint256 unstakeRange = maxUnstakeWeeks - minUnstakeWeeks;

		uint256 numerator = unstakedVeZERO * ( minUnstakePercent * unstakeRange + percentAboveMinimum * ( numWeeks - minUnstakeWeeks ) );
    	return numerator / ( 100 * unstakeRange );
		}
	}