// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/finance/VestingWallet.sol";
import "../rewards/interfaces/IZeroRewards.sol";
import "../rewards/interfaces/IEmissions.sol";
import "../pools/interfaces/IPoolsConfig.sol";
import "./interfaces/IInitialDistribution.sol";
import "./interfaces/IBootstrapBallot.sol";
import "./interfaces/IAirdrop.sol";
import "../interfaces/IZero.sol";


contract InitialDistribution is IInitialDistribution
    {
	using SafeERC20 for IZero;

	uint256 constant public MILLION_ETHER = 1000000 ether;

   	IZero immutable public zero;
	IPoolsConfig immutable public poolsConfig;
   	IEmissions immutable public emissions;
   	IBootstrapBallot immutable public bootstrapBallot;
	IDAO immutable public dao;
	VestingWallet immutable public daoVestingWallet;
	VestingWallet immutable public teamVestingWallet;
	IZeroRewards immutable public zeroRewards;


	constructor( IZero _zero, IPoolsConfig _poolsConfig, IEmissions _emissions, IBootstrapBallot _bootstrapBallot, IDAO _dao, VestingWallet _daoVestingWallet, VestingWallet _teamVestingWallet, IZeroRewards _zeroRewards  )
		{
		zero = _zero;
		poolsConfig = _poolsConfig;
		emissions = _emissions;
		bootstrapBallot = _bootstrapBallot;
		dao = _dao;
		daoVestingWallet = _daoVestingWallet;
		teamVestingWallet = _teamVestingWallet;
		zeroRewards = _zeroRewards;
        }


    // Called when the BootstrapBallot is approved by the initial airdrop recipients.
    function distributionApproved( IAirdrop airdrop1, IAirdrop airdrop2 ) external
    	{
    	require( msg.sender == address(bootstrapBallot), "InitialDistribution.distributionApproved can only be called from the BootstrapBallot contract" );
		require( zero.balanceOf(address(this)) == 100 * MILLION_ETHER, "ZERO tokens have already been sent from the contract" );

    	// 50 million		Emissions
		zero.safeTransfer( address(emissions), 50 * MILLION_ETHER );

	    // 25 million		DAO Reserve Vesting Wallet
		zero.safeTransfer( address(daoVestingWallet), 25 * MILLION_ETHER );

	    // 10 million		Initial Development Team Vesting Wallet
		zero.safeTransfer( address(teamVestingWallet), 10 * MILLION_ETHER );

	    // 4 million		Airdrop Phase I
		zero.safeTransfer( address(airdrop1), 4 * MILLION_ETHER );

	    // 3 million		Airdrop Phase II
		zero.safeTransfer( address(airdrop2), 3 * MILLION_ETHER );

		bytes32[] memory poolIDs = poolsConfig.whitelistedPools();

	    // 5 million		Liquidity Bootstrapping
	    // 3 million		Staking Bootstrapping
		zero.safeTransfer( address(zeroRewards), 8 * MILLION_ETHER );
		zeroRewards.sendInitialZERORewards(5 * MILLION_ETHER, poolIDs );
    	}
	}