// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../rewards/interfaces/IZeroRewards.sol";
import "../../pools/interfaces/IPools.sol";
import "../../interfaces/IZero.sol";

interface IDAO
	{
	function finalizeBallot( uint256 ballotID ) external;
	function manuallyRemoveBallot( uint256 ballotID ) external;

	function withdrawFromDAO( IERC20 token ) external returns (uint256 withdrawnAmount);

	// Views
	function pools() external view returns (IPools);
	function websiteURL() external view returns (string memory);
	function countryIsExcluded( string calldata country ) external view returns (bool);
	}