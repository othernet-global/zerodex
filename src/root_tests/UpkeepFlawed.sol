// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "forge-std/Test.sol";
import "../pools/interfaces/IPools.sol";
import "../pools/interfaces/IPoolsConfig.sol";
import "../interfaces/IExchangeConfig.sol";
import "../dao/interfaces/IDAOConfig.sol";
import "../rewards/interfaces/IEmissions.sol";
import "../pools/interfaces/IPoolStats.sol";
import "openzeppelin-contracts/contracts/finance/VestingWallet.sol";
import "../Upkeep.sol";


contract UpkeepFlawed is Upkeep
    {
	using SafeERC20 for IZero;
	using SafeERC20 for IERC20;

	uint256 public flawedStep;


    constructor( IPools _pools, IExchangeConfig _exchangeConfig, IPoolsConfig _poolsConfig, IDAOConfig _daoConfig, IZeroRewards _zeroRewards, IEmissions _emissions, IDAO _dao, uint256 _flawedStep )
    Upkeep(_pools, _exchangeConfig, _poolsConfig, _daoConfig, _zeroRewards, _emissions, _dao)
		{
		flawedStep = _flawedStep;
		}


	function _step1(address receiver) public onlySameContract
		{
		require( flawedStep != 1, "Step 1 reverts" );
		this.step1(receiver);
		}


	function _step2() public onlySameContract
		{
		require( flawedStep != 2, "Step 2 reverts" );
		this.step2();
		}



	function _step3() public onlySameContract
		{
		require( flawedStep != 3, "Step 3 reverts" );
		this.step3();
		}


	function _step4() public onlySameContract
		{
		require( flawedStep != 4, "Step 4 reverts" );
		this.step4();
		}


	function _step5() public onlySameContract
		{
		require( flawedStep != 5, "Step 5 reverts" );
		this.step5();
		}


	function _step6() public onlySameContract
		{
		require( flawedStep != 6, "Step 6 reverts" );
		this.step6();
		}


	function _step7() public onlySameContract
		{
		require( flawedStep != 7, "Step 7 reverts" );
		this.step7();
		}


	function _step8() public onlySameContract
		{
		require( flawedStep != 8, "Step 8 reverts" );
		this.step8();
		}



	function performFlawedUpkeep() public
		{
		// Perform the multiple steps to perform upkeep.
		// Try/catch blocks are used to prevent any of the steps (which are not independent from previous steps) from reverting the transaction.
 		try this._step1(msg.sender) {}
		catch (bytes memory error) { emit UpkeepError("Step 1", error); }

 		try this._step2() {}
		catch (bytes memory error) { emit UpkeepError("Step 2", error); }

 		try this._step3() {}
		catch (bytes memory error) { emit UpkeepError("Step 3", error); }

 		try this._step4() {}
		catch (bytes memory error) { emit UpkeepError("Step 4", error); }

 		try this._step5() {}
		catch (bytes memory error) { emit UpkeepError("Step 5", error); }

 		try this._step6() {}
		catch (bytes memory error) { emit UpkeepError("Step 6", error); }

 		try this._step7() {}
		catch (bytes memory error) { emit UpkeepError("Step 7", error); }

 		try this._step8() {}
		catch (bytes memory error) { emit UpkeepError("Step 8", error); }
		}
	}
