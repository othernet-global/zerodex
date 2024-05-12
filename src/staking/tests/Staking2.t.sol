// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../dev/Deployment.sol";
import "../interfaces/IStaking.sol";


contract StakingTest is Deployment
	{
    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);


	constructor()
		{
		initializeContracts();

		grantAccessAlice();
		grantAccessBob();
		}


	function testLiveBalanceCheck() public
    	{
    	address wallet1 = alice;
    	address wallet2 = bob;

		// Create a new Staking contract for testing
		staking = new Staking( exchangeConfig, poolsConfig, stakingConfig );

		// Initial approvals
		vm.prank(wallet1);
		zero.approve(address(staking), type(uint256).max);
		vm.prank(wallet2);
		zero.approve(address(staking), type(uint256).max);


		// Transfer ZERO to the two test wallets
		vm.startPrank(address(initialDistribution));
		zero.transfer(wallet1, 1401054000000000000000000 );
		zero.transfer(wallet1, 54000000000000000000 );
		zero.transfer(wallet2, 2401234000000000000000000 );
		vm.stopPrank();

		// wallet1 stakes 1401054 ZERO
		vm.prank(wallet1);
		staking.stakeZERO(1401054000000000000000000);

		// wallet2 stakes 2401234 ZERO
		vm.prank(wallet2);
		staking.stakeZERO(2401234000000000000000000);

		// Add 30000 rewards
    	bytes32[] memory poolIDs = new bytes32[](1);
    	poolIDs[0] = PoolUtils.STAKED_ZERO;

		AddedReward[] memory addedRewards = new AddedReward[](1);
		addedRewards[0] = AddedReward( PoolUtils.STAKED_ZERO, 30000 ether );

		vm.startPrank(address(initialDistribution));
		zero.approve( address(staking), type(uint256).max );
		staking.addZERORewards(addedRewards);
		vm.stopPrank();

		uint256 totalRewards = staking.totalRewardsForPools(poolIDs)[0];
		uint256 userShare = staking.userShareForPool(wallet1, PoolUtils.STAKED_ZERO);
		uint256 totalShares = staking.totalShares(PoolUtils.STAKED_ZERO);
		uint256 rewardsShare = ( totalRewards * userShare ) / totalShares;
//		console.log( "REWARDS SHARE0: ", rewardsShare );
//		console.log( "VIRTUAL REWARDS0: ", staking.userVirtualRewardsForPool(wallet1, PoolUtils.STAKED_ZERO));

		console.log( "" );
		// wallet1 claims all
		vm.prank(wallet1);
//		uint256 amountClaimed = staking.claimAllRewards(poolIDs);
//		console.log( "AMOUNT CLAIMED: ", amountClaimed );

		totalRewards = staking.totalRewardsForPools(poolIDs)[0];
		userShare = staking.userShareForPool(wallet1, PoolUtils.STAKED_ZERO);
		totalShares = staking.totalShares(PoolUtils.STAKED_ZERO);
		rewardsShare = ( totalRewards * userShare ) / totalShares;
//		console.log( "REWARDS SHARE1: ", rewardsShare );
//		console.log( "VIRTUAL REWARDS1: ", staking.userVirtualRewardsForPool(wallet1, PoolUtils.STAKED_ZERO));

		vm.prank(wallet1);
		staking.stakeZERO(54000000000000000000);

		totalRewards = staking.totalRewardsForPools(poolIDs)[0];
		userShare = staking.userShareForPool(wallet1, PoolUtils.STAKED_ZERO);
		totalShares = staking.totalShares(PoolUtils.STAKED_ZERO);
		rewardsShare = ( totalRewards * userShare ) / totalShares;
//		console.log( "REWARDS SHARE2: ", rewardsShare );
//		console.log( "VIRTUAL REWARDS2: ", staking.userVirtualRewardsForPool(wallet1, PoolUtils.STAKED_ZERO));


//		uint256 reward = staking.userRewardForPool( wallet1, PoolUtils.STAKED_ZERO );
//		console.log( "REWARD: ", reward );

    	}
	}
