// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "forge-std/Test.sol";
import "../../dev/Deployment.sol";
import "../../root_tests/TestERC20.sol";
import "../../ExchangeConfig.sol";
import "../../pools/Pools.sol";
import "../../staking/Liquidity.sol";
import "../../staking/Staking.sol";
import "../../staking/Liquidity.sol";
import "../../rewards/RewardsEmitter.sol";
import "../../pools/PoolsConfig.sol";
import "../../AccessManager.sol";
import "../InitialDistribution.sol";
import "../../Upkeep.sol";
import "../../dao/Proposals.sol";
import "../../dao/DAO.sol";


contract TestInitialDistribution is Deployment
	{
	uint256 constant public MILLION_ETHER = 1000000 ether;


	// User wallets for testing
    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);


	constructor()
		{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			{
			// Transfer the zero from the original initialDistribution to the DEPLOYER
			vm.prank(address(initialDistribution));
			zero.transfer(DEPLOYER, 100 * MILLION_ETHER);

			vm.startPrank(DEPLOYER);

			poolsConfig = new PoolsConfig();

			exchangeConfig = new ExchangeConfig(zero, wbtc, weth, usdc, usdt, teamWallet );

		pools = new Pools(exchangeConfig, poolsConfig);
		staking = new Staking( exchangeConfig, poolsConfig, stakingConfig );
		liquidity = new Liquidity(pools, exchangeConfig, poolsConfig, stakingConfig);

			stakingRewardsEmitter = new RewardsEmitter( staking, exchangeConfig, poolsConfig, rewardsConfig, false );
			liquidityRewardsEmitter = new RewardsEmitter( liquidity, exchangeConfig, poolsConfig, rewardsConfig, true );

			emissions = new Emissions( zeroRewards, exchangeConfig, rewardsConfig );

		// Whitelist the pools
		poolsConfig.whitelistPool(zero, usdc);
		poolsConfig.whitelistPool(zero, weth);
		poolsConfig.whitelistPool(weth, usdc);
		poolsConfig.whitelistPool(weth, usdt);
		poolsConfig.whitelistPool(wbtc, usdc);
		poolsConfig.whitelistPool(wbtc, weth);
		poolsConfig.whitelistPool(usdc, usdt);

			proposals = new Proposals( staking, exchangeConfig, poolsConfig, daoConfig );

			address oldDAO = address(dao);
			dao = new DAO( pools, proposals, exchangeConfig, poolsConfig, stakingConfig, rewardsConfig, daoConfig, liquidityRewardsEmitter);

			airdrop1 = new Airdrop(exchangeConfig);
			airdrop2 = new Airdrop(exchangeConfig);

			accessManager = new AccessManager(dao);

			zeroRewards = new ZeroRewards(stakingRewardsEmitter, liquidityRewardsEmitter, exchangeConfig, rewardsConfig);

			upkeep = new Upkeep(pools, exchangeConfig, poolsConfig, daoConfig, zeroRewards, emissions, dao);

			initialDistribution = new InitialDistribution(zero, poolsConfig, emissions, bootstrapBallot, dao, daoVestingWallet, teamVestingWallet, zeroRewards);

			pools.setContracts(dao, liquidity);

			exchangeConfig.setContracts(dao, upkeep, initialDistribution, teamVestingWallet, daoVestingWallet );
			exchangeConfig.setAccessManager(accessManager);

			// Transfer ownership of the newly created config files to the DAO
			Ownable(address(exchangeConfig)).transferOwnership( address(dao) );
			Ownable(address(poolsConfig)).transferOwnership( address(dao) );
			vm.stopPrank();

			vm.startPrank(address(oldDAO));
			Ownable(address(stakingConfig)).transferOwnership( address(dao) );
			Ownable(address(rewardsConfig)).transferOwnership( address(dao) );
			Ownable(address(daoConfig)).transferOwnership( address(dao) );
			vm.stopPrank();

			// Transfer ZERO to the new InitialDistribution contract
			vm.startPrank(DEPLOYER);
			zero.transfer(address(initialDistribution), 100 * MILLION_ETHER);
			vm.stopPrank();
			}

		whitelistAlice();
		}


	// A unit test to ensure the constructor has correctly set the input parameters.
	function testInitial_distribution_constructor() public
    {
    	InitialDistribution initialDistribution = new InitialDistribution(zero, poolsConfig, emissions, bootstrapBallot, dao, daoVestingWallet, teamVestingWallet, zeroRewards);

    	assertEq(address(initialDistribution.zero()), address(zero), "error in initialDistribution.zero()");
    	assertEq(address(initialDistribution.poolsConfig()), address(poolsConfig), "error in initialDistribution.poolsConfig()");
    	assertEq(address(initialDistribution.emissions()), address(emissions), "error in initialDistribution.emissions()");
    	assertEq(address(initialDistribution.bootstrapBallot()), address(bootstrapBallot), "error in initialDistribution.bootstrapBallot()");
    	assertEq(address(initialDistribution.dao()), address(dao), "error in initialDistribution.dao()");
    	assertEq(address(initialDistribution.daoVestingWallet()), address(daoVestingWallet), "error in initialDistribution.daoVestingWallet()");
    	assertEq(address(initialDistribution.teamVestingWallet()), address(teamVestingWallet), "error in initialDistribution.teamVestingWallet()");
    	assertEq(address(initialDistribution.zeroRewards()), address(zeroRewards), "error in initialDistribution.zeroRewards()");
    }


	// A unit test to verify that the `distributionApproved` function can only be called from the BootstrapBallot contract.
	function testCannotCallDistributionApprovedFromInvalidAddress() public {
        InitialDistribution id = new InitialDistribution( zero, poolsConfig, emissions, bootstrapBallot, dao, daoVestingWallet, teamVestingWallet, zeroRewards );

        vm.expectRevert("InitialDistribution.distributionApproved can only be called from the BootstrapBallot contract");
        id.distributionApproved(airdrop1, airdrop2);
    }


	// A unit test to ensure ZERO has not already been sent from the contract when `distributionApproved` is called. If ZERO has already been sent, calling `distributionApproved` should fail.
	function testDistributionApprovedWithAlreadySentZero() public {

		// Transfer ZERO from the InitialDistribution contract
		uint256 zeroBalance = zero.balanceOf(address(initialDistribution));

		vm.prank(address(initialDistribution));
		zero.transfer(DEPLOYER, zeroBalance);

    	// Attempting to call distributionApproved should revert due to ZERO already being sent
    	vm.prank(address(bootstrapBallot));

    	vm.expectRevert("ZERO tokens have already been sent from the contract");
    	initialDistribution.distributionApproved(airdrop1, airdrop2);
    }


	// A unit test to check that correct amounts of ZERO have been distributed and initial liquidity formed on a call to distributionApproved()
	function testZeroTransferOnDistributionApproved() public {

		assertEq(zero.balanceOf(address(emissions)), 0);
		assertEq(zero.balanceOf(address(daoVestingWallet)), 0);
		assertEq(zero.balanceOf(address(teamVestingWallet)), 0);
		assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), 0);
		assertEq(zero.balanceOf(address(stakingRewardsEmitter)), 0);

		vm.prank(address(bootstrapBallot));
		initialDistribution.distributionApproved(airdrop1, airdrop2);

		assertEq(zero.balanceOf(address(emissions)), 50 * MILLION_ETHER);
		assertEq(zero.balanceOf(address(daoVestingWallet)), 25 * MILLION_ETHER);
		assertEq(zero.balanceOf(address(teamVestingWallet)), 10 * MILLION_ETHER);
		assertEq(zero.balanceOf(address(airdrop1)), 4 * MILLION_ETHER);
		assertEq(zero.balanceOf(address(airdrop2)), 3 * MILLION_ETHER);
		assertEq(zero.balanceOf(address(liquidityRewardsEmitter)), 4999999999999999999999995);
		assertEq(zero.balanceOf(address(stakingRewardsEmitter)), 3000000000000000000000005);

		assertEq( zero.balanceOf(address(initialDistribution)), 0 );
	}



	// A unit test to ensure the `distributionApproved` function can only be called once and subsequent calls fail.
	function testDistributionApproved_callTwice() public {
		vm.prank(DEPLOYER);
		weth.transfer(address(dao), 1000 ether);

        // First call should succeed
        vm.prank(address(bootstrapBallot));
        initialDistribution.distributionApproved(airdrop1, airdrop2);

        // Verify the balance of ZERO contract is zero after distribution
        assertEq(zero.balanceOf(address(initialDistribution)), 0);

        // Second call should revert
        vm.expectRevert("ZERO tokens have already been sent from the contract");
        vm.prank(address(bootstrapBallot));
        initialDistribution.distributionApproved(airdrop1, airdrop2);
    }


	// A unit test to check that the Airdrop contract has been setup correctly on a call to distributionApproved()
	function testAirdropSetupOnDistributionApproved() public {

		vm.prank(address(bootstrapBallot));
		initialDistribution.distributionApproved(airdrop1, airdrop2);

		assertEq( zero.balanceOf(address(airdrop1)), 4 * MILLION_ETHER );
		assertEq( zero.balanceOf(address(airdrop2)), 3 * MILLION_ETHER );
	}
    }

