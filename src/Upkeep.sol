// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/finance/VestingWallet.sol";
import "./rewards/interfaces/IEmissions.sol";
import "./pools/interfaces/IPoolsConfig.sol";
import "./interfaces/IExchangeConfig.sol";
import "./dao/interfaces/IDAOConfig.sol";
import "./pools/interfaces/IPools.sol";
import "./dao/interfaces/IDAO.sol";


// Performs the following upkeep for each call to performUpkeep():
// (Uses a maximum of 1.1 million gas with 100 whitelisted pools according to UpkeepGasUsage.t.sol)

// 1. Withdraws deposited ZERO token arbitrage profits from the Pools contract and rewards the caller of performUpkeep() with 5% of the withdrawn ZERO tokens
// 2. Burns 10% of the remaining withdrawn ZERO tokens and sends 10% to the DAO's reserve.
// 3. Sends the remaining ZERO tokens to ZeroRewards.

// 4. Sends ZERO token Emissions to the ZeroRewards contract.
// 5. Distributes ZERO tokens from ZeroRewards to the stakingRewardsEmitter and liquidityRewardsEmitter.
// 6. Distributes ZERO token rewards from the stakingRewardsEmitter and liquidityRewardsEmitter.

// 7. Sends ZERO tokens from the DAO vesting wallet to the DAO (linear distribution over 10 years).
// 8. Sends ZERO tokens from the team vesting wallet to the team (linear distribution over 10 years).

contract Upkeep is IUpkeep, ReentrancyGuard
    {
	using SafeERC20 for IZero;
	using SafeERC20 for IERC20;

    event UpkeepError(string description, bytes error);

	IPools immutable public pools;
	IExchangeConfig  immutable public exchangeConfig;
	IPoolsConfig immutable public poolsConfig;
	IDAOConfig immutable public daoConfig;
	IZeroRewards immutable public zeroRewards;
	IEmissions immutable public emissions;
	IDAO immutable public dao;

	IZero  immutable public zero;

	uint256 public lastUpkeepTimeEmissions;
	uint256 public lastUpkeepTimeRewardsEmitters;


    constructor( IPools _pools, IExchangeConfig _exchangeConfig, IPoolsConfig _poolsConfig, IDAOConfig _daoConfig, IZeroRewards _zeroRewards, IEmissions _emissions, IDAO _dao )
		{
		pools = _pools;
		exchangeConfig = _exchangeConfig;
		poolsConfig = _poolsConfig;
		daoConfig = _daoConfig;
		zeroRewards = _zeroRewards;
		emissions = _emissions;
		dao = _dao;

		// Cached for efficiency
		zero = _exchangeConfig.zero();

		lastUpkeepTimeEmissions = block.timestamp;
		lastUpkeepTimeRewardsEmitters = block.timestamp;
		}


	modifier onlySameContract()
		{
    	require(msg.sender == address(this), "Only callable from within the same contract");
    	_;
		}


	// Note - while the following steps are public so that they can be wrapped in a try/catch, they are all still only callable from this same contract.

	// 1. Withdraw deposited ZERO token arbitrage profits from the Pools contract and reward the caller of performUpkeep() with 5% of the withdrawn ZERO tokens
	function step1(address receiver) public onlySameContract
		{
		uint256 withdrawnZERO = dao.withdrawFromDAO(zero);
		if ( withdrawnZERO == 0 )
			return;

		// Default 5% of the original ZERO token arbitrage profits should be rewarded to the caller of performUpkeep.
		uint256 rewardAmount = withdrawnZERO * daoConfig.upkeepRewardPercent() / 100;

		// Send the reward
		zero.safeTransfer(receiver, rewardAmount);
		}


	// 2. Burn 10% of the remaining withdrawn ZERO tokens and send 10% to the DAO's reserve.
	function step2() public onlySameContract
		{
		uint256 zeroBalance = zero.balanceOf( address(this) );
		if ( zeroBalance == 0 )
			return;

		// Default 10% of the remaining ZERO token profits should be burned
		uint256 burnAmount = zeroBalance * daoConfig.percentRewardsBurned() / 100;
		zero.transfer( address(zero), burnAmount);
		zero.burnTokensInContract();

		// Default 10% of the remaining ZERO token profits should be sent to the DAO's reserve
		uint256 reserveAmount = zeroBalance * daoConfig.percentRewardsForReserve() / 100;
		zero.transfer( address(dao), reserveAmount);
		}


	// 3. Send the remaining ZERO tokens to ZeroRewards
	function step3() public onlySameContract
		{
		uint256 zeroBalance = zero.balanceOf( address(this) );
		if ( zeroBalance == 0 )
			return;

		zero.safeTransfer(address(zeroRewards), zeroBalance);
		}


	// 4. Send ZERO token Emissions to the ZeroRewards contract.
	function step4() public onlySameContract
		{
		uint256 timeSinceLastUpkeep = block.timestamp - lastUpkeepTimeEmissions;
		emissions.performUpkeep(timeSinceLastUpkeep);

		lastUpkeepTimeEmissions = block.timestamp;
		}


	// 5. Distribute ZERO tokens from ZeroRewards to the stakingRewardsEmitter and liquidityRewardsEmitter.
	function step5() public onlySameContract
		{
		uint256[] memory profitsForPools = pools.profitsForWhitelistedPools();
		bytes32[] memory poolIDs = poolsConfig.whitelistedPools();

		zeroRewards.performUpkeep(poolIDs, profitsForPools );
		pools.clearProfitsForPools();
		}


	// 6. Distribute ZERO tokens rewards from the stakingRewardsEmitter and liquidityRewardsEmitter.
	function step6() public onlySameContract
		{
		uint256 timeSinceLastUpkeep = block.timestamp - lastUpkeepTimeRewardsEmitters;

		zeroRewards.stakingRewardsEmitter().performUpkeep(timeSinceLastUpkeep);
		zeroRewards.liquidityRewardsEmitter().performUpkeep(timeSinceLastUpkeep);

		lastUpkeepTimeRewardsEmitters = block.timestamp;
		}


	// 7. Send ZERO tokens from the DAO vesting wallet to the DAO (linear distribution over 10 years).
	function step7() public onlySameContract
		{
		exchangeConfig.daoVestingWallet().release(address(zero));
		}


	// 8. Sends ZERO tokens from the team vesting wallet to the team (linear distribution over 10 years).
	function step8() public onlySameContract
		{
		exchangeConfig.teamVestingWallet().release(address(zero));
		}


	// Perform the various steps of performUpkeep as outlined at the top of the contract.
	// Each step is wrapped in a try/catch to prevent reversions from cascading through the performUpkeep.
	function performUpkeep() public nonReentrant
		{
		require(lastUpkeepTimeEmissions != block.timestamp, "No time since elapsed since last upkeep");

		// Perform the multiple steps of performUpkeep()
 		try this.step1(msg.sender) {}
		catch (bytes memory error) { emit UpkeepError("Step 1", error); }

 		try this.step2() {}
		catch (bytes memory error) { emit UpkeepError("Step 2", error); }

 		try this.step3() {}
		catch (bytes memory error) { emit UpkeepError("Step 3", error); }

 		try this.step4() {}
		catch (bytes memory error) { emit UpkeepError("Step 4", error); }

 		try this.step5() {}
		catch (bytes memory error) { emit UpkeepError("Step 5", error); }

 		try this.step6() {}
		catch (bytes memory error) { emit UpkeepError("Step 6", error); }

 		try this.step7() {}
		catch (bytes memory error) { emit UpkeepError("Step 7", error); }

 		try this.step8() {}
		catch (bytes memory error) { emit UpkeepError("Step 8", error); }
		}


	// ==== VIEWS ====
	// Returns the amount of WETH that will currently be rewarded for calling performUpkeep().
	// Useful for potential callers to know if calling the function will be profitable in comparison to current gas costs.
	function currentRewardsForCallingPerformUpkeep() public view returns (uint256)
		{
		uint256 depositedZERO = pools.depositedUserBalance(address(dao), zero);

		// Default 5% of the original ZERO token arbitrage profits should be rewarded to the caller of performUpkeep.
		return depositedZERO * daoConfig.upkeepRewardPercent() / 100;
		}
	}
