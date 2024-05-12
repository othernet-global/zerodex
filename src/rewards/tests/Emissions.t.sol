	// SPDX-License-Identifier: BUSL 1.1
	pragma solidity =0.8.22;

	import "forge-std/Test.sol";
	import "../../dev/Deployment.sol";
	import "../../root_tests/TestERC20.sol";
	import "../../pools/PoolUtils.sol";
	import "../Emissions.sol";


	contract TestEmissions is Deployment
		{
		address public alice = address(0x1111);
		address public bob = address(0x2222);

		bytes32 public pool1;
		bytes32 public pool2;


		function setUp() public
			{
			// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
			// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
			if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
				{
				vm.prank(DEPLOYER);
				emissions = new Emissions( zeroRewards, exchangeConfig, rewardsConfig );
				}

			vm.prank(address(initialDistribution));
			zero.transfer(DEPLOYER, 100000000 ether);

			vm.startPrank( DEPLOYER );
			IERC20 token1 = new TestERC20("TEST", 18);
			IERC20 token2 = new TestERC20("TEST", 18);
			IERC20 token3 = new TestERC20("TEST", 18);

			pool1 = PoolUtils._poolID(token1, token2);
			pool2 = PoolUtils._poolID(token2, token3);
			vm.stopPrank();

			// Whitelist pools
			vm.startPrank( address(dao) );
			poolsConfig.whitelistPool(  token1, token2);
			poolsConfig.whitelistPool(  token2, token3);
			vm.stopPrank();

			// Start with some ZERO in the Emissions contract
			vm.startPrank( DEPLOYER );
			zero.transfer(address(emissions), 1000 ether);

			// Send some ZERO to alice and bob
			zero.transfer(alice, 100 ether);
			zero.transfer(bob, 100 ether);
			vm.stopPrank();

			vm.prank(alice);
			zero.approve( address(staking), type(uint256).max );

			vm.prank(bob);
			zero.approve( address(staking), type(uint256).max );
			}


		function testPerformUpkeepOnlyCallableFromUpkeep() public
			{
			vm.expectRevert( "Emissions.performUpkeep is only callable from the Upkeep contract" );
			emissions.performUpkeep(2 weeks);

			vm.prank(address(upkeep));
			emissions.performUpkeep(2 weeks);
			}


		// A unit test to check the _performUpkeep function when the timeSinceLastUpkeep is zero. Verify that the function does not perform any actions.
		function testPerformUpkeepWithZeroTimeSinceLastUpkeep() public {

			// Call performUpkeep function
			uint256 initialZeroBalance = zero.balanceOf(address(emissions));

			vm.prank(address(upkeep));
			emissions.performUpkeep(0);

			// Since the calculated zeroToSend was zero, no actions should be taken
			// Therefore, the ZERO balance should be the same
			uint256 finalZeroBalance = zero.balanceOf(address(emissions));
			assertEq(initialZeroBalance, finalZeroBalance);
		}





		// A unit test to check the performUpkeep function when the remaining ZERO balance is zero.
		function testPerformUpkeepWithZeroZeroBalance() public
			{
			// Transfer all remaining ZERO
			vm.startPrank(address(emissions));
			zero.transfer(address(alice), zero.balanceOf(address(emissions)));
			vm.stopPrank();

			// Ensure all ZERO is transferred
			assertEq(zero.balanceOf(address(emissions)), 0);

			// Call performUpkeep function
			vm.prank(address(upkeep));
			emissions.performUpkeep(2 weeks);

			// Since ZERO balance was zero, no actions should be taken
			// Therefore, the initial and final ZERO balances should be the same
			assertEq(zero.balanceOf(address(emissions)), 0);
			}


		// A unit test to verify ZERO approval to zeroRewards in the performUpkeep function.
		function testPerformUpkeepApprovesZERORewards() public {

			uint256 startingEmissionsBalance = zero.balanceOf(address(emissions));

			// Perform upkeep as if 1 week has passed
			vm.prank(address(upkeep));
			emissions.performUpkeep(1 weeks);

			// Expected sent rewards to zeroRewads should be .5% of 1000 ether (both set in the constructor)
			uint256 expectedRewards = 1000 ether * 5 / 1000;
			assertEq( zero.balanceOf(address(zeroRewards)), expectedRewards);

			// All of the allowance should have been sent
			uint256 allowance = zero.allowance(address(emissions), address(zeroRewards));

			assertEq( allowance, 0);
			assertEq( zero.balanceOf(address(emissions)), startingEmissionsBalance - expectedRewards);
		}


		// A unit test to test that increasing emissionsWeeklyPercentTimes1000 to 1% has the desired effect
		function testEmissionsWeeklyPercentTimes1000() public
			{
			uint256 startingEmissionsBalance = zero.balanceOf(address(emissions));

			// Increase emissionsWeeklyPercent to 1% weekly for testing (.50% default + 2x 0.25% increment)
			vm.startPrank( address(dao) );
			rewardsConfig.changeEmissionsWeeklyPercent(true);
			rewardsConfig.changeEmissionsWeeklyPercent(true);
			vm.stopPrank();

			// Perform upkeep as if 1 week has passed
			vm.prank(address(upkeep));
			emissions.performUpkeep(1 weeks);

			// Expected sent rewards to zeroRewads should be 1% of 1000 ether (both set in the constructor)
			uint256 expectedRewards = 1000 ether * 1 / 100;
			assertEq( zero.balanceOf(address(zeroRewards)), expectedRewards);

			assertEq( zero.balanceOf(address(emissions)), startingEmissionsBalance - expectedRewards);
			}


		uint256 constant public MAX_TIME_SINCE_LAST_UPKEEP = 1 weeks;

		// A unit test to check the amount of ZERO rewards sent in performUpkeep when timeSinceLastUpkeep is greater than MAX_TIME_SINCE_LAST_UPKEEP.
		function testPerformUpkeepMaxTimeSinceLastUpkeep() public
			{
			uint256 initialZeroBalance = zero.balanceOf(address(emissions));

			// Perform upkeep with a time greater than MAX_TIME_SINCE_LAST_UPKEEP
			vm.prank(address(upkeep));
			emissions.performUpkeep(MAX_TIME_SINCE_LAST_UPKEEP + 1);

			// Despite providing a time greater than MAX_TIME_SINCE_LAST_UPKEEP, only MAX_TIME_SINCE_LAST_UPKEEP should be considered
			// Weekly emission rate is .50%, so the expected zero sent is .50% of the initial balance
			uint256 expectedZeroSent = initialZeroBalance * 5 / 1000;
			uint256 finalZeroBalance = zero.balanceOf(address(emissions));
			assertEq(initialZeroBalance - finalZeroBalance, expectedZeroSent);
			}


		// A unit test that checks the ZERO transfer from the Emissions contract to the StakingRewardsEmitter and LiquidityRewardsEmitter through the ZeroRewards contract.
		function testZEROTransferFromEmissionsToEmitters() public {

			uint256 timeSinceLastUpkeep = 1 weeks;
			uint256 initialEmissionsZEROBalance = zero.balanceOf(address(emissions));
			uint256 initialZeroRewardsBalance = zero.balanceOf(address(zeroRewards));

			uint256 expectedZeroToSend = (initialEmissionsZEROBalance * timeSinceLastUpkeep * rewardsConfig.emissionsWeeklyPercentTimes1000()) / (100 * 1000 * 1 weeks);

			// Perform upkeep via external call.
			vm.prank(address(upkeep));
			emissions.performUpkeep(timeSinceLastUpkeep);

			uint256 finalEmissionsZEROBalance = zero.balanceOf(address(emissions));
			uint256 finalZeroRewardsBalance = zero.balanceOf(address(zeroRewards));

			// Check the balance of ZERO in the Emissions contract has decreased by the expected amount.
			assertEq( finalEmissionsZEROBalance, initialEmissionsZEROBalance - expectedZeroToSend);

			// Check that ZERO was sent to zeroRewards
			assertEq(finalZeroRewardsBalance, initialZeroRewardsBalance + expectedZeroToSend);
		}


		// A unit test that checks the calculation of zeroToSend is correct by comparing expected vs actual values.
		function testCalculateZeroToSendIsCorrect() public {

			uint256 timeSinceLastUpkeep = 1 days;
			uint256 emissionsWeeklyPercent = rewardsConfig.emissionsWeeklyPercentTimes1000();
			uint256 zeroBalance = zero.balanceOf(address(emissions));
			uint256 expectedZeroToSend = (zeroBalance * timeSinceLastUpkeep * emissionsWeeklyPercent) / (100 * 1000 weeks);

			// Perform upkeep
			vm.prank(address(upkeep));
			emissions.performUpkeep(timeSinceLastUpkeep);

			// Check the amount of zero transferred to zeroRewards
			uint256 actualZeroSent = zero.balanceOf(address(zeroRewards));
			assertEq(expectedZeroToSend, actualZeroSent, "Incorrect amount of ZERO sent to rewards");
		}


		// A unit test that verifies if the cap on the timeSinceLastUpkeep works correctly and the ZERO sent does not exceed the capped percentage.
		function testCapOnTimeSinceLastUpkeep() public {
			uint256 initialZeroBalance = zero.balanceOf(address(emissions));
			uint256 timeSinceLastUpkeep = 2 weeks; // More than the capped MAX_TIME_SINCE_LAST_UPKEEP

			// Pre-approval for transaction
			zero.approve(address(this), type(uint256).max);

			// Assuming weekly percentage is 0.50%, calculate the expected amount of ZERO to be sent
			uint256 expectedZeroToSend = (initialZeroBalance * MAX_TIME_SINCE_LAST_UPKEEP * rewardsConfig.emissionsWeeklyPercentTimes1000()) / (100 * 1000 weeks);

			// Warp to the future by 2 weeks to simulate time passing
			vm.warp(block.timestamp + timeSinceLastUpkeep);

			// Perform the upkeep with the time since last upkeep as 2 weeks
			vm.prank(address(upkeep));
			emissions.performUpkeep(timeSinceLastUpkeep);

			uint256 finalZeroBalance = zero.balanceOf(address(emissions));

			// Check if only the capped percentage of ZERO was sent
			assertEq(initialZeroBalance - finalZeroBalance, expectedZeroToSend, "ZERO sent exceeds capped percentage");
		}
		}
