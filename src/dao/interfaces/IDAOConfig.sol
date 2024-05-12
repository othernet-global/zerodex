// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;


interface IDAOConfig
	{
	function changeBootstrappingRewards(bool increase) external; // onlyOwner
	function changePercentRewardsBurned(bool increase) external; // onlyOwner
	function changeBaseBallotQuorumPercent(bool increase) external; // onlyOwner
	function changeBallotDuration(bool increase) external; // onlyOwner
	function changeBallotMaximumDuration(bool increase) external; // onlyOwner
	function changeRequiredProposalPercentStake(bool increase) external; // onlyOwner
	function changePercentRewardsForReserve(bool increase) external; // onlyOwner
	function changeUpkeepRewardPercent(bool increase) external; // onlyOwner

	// Views
    function bootstrappingRewards() external view returns (uint256);
    function percentRewardsBurned() external view returns (uint256);
    function baseBallotQuorumPercentTimes1000() external view returns (uint256);
    function ballotMinimumDuration() external view returns (uint256);
    function ballotMaximumDuration() external view returns (uint256);
    function requiredProposalPercentStakeTimes1000() external view returns (uint256);
    function percentRewardsForReserve() external view returns (uint256);
    function upkeepRewardPercent() external view returns (uint256);
	}