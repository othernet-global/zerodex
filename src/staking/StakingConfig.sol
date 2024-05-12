// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./interfaces/IStakingConfig.sol";


// Contract owned by the DAO with parameters modifiable only by the DAO
contract StakingConfig is IStakingConfig, Ownable
    {
    event MinUnstakeWeeksChanged(uint256 newMinUnstakeWeeks);
    event MaxUnstakeWeeksChanged(uint256 newMaxUnstakeWeeks);
    event MinUnstakePercentChanged(uint256 newMinUnstakePercent);
    event ModificationCooldownChanged(uint256 newModificationCooldown);

    // The minimum number of weeks for an unstake request at which point minUnstakePercent of the original staked ZERO tokens is reclaimable.
	// Range: 2 to 12 with an adjustment of 1
	uint256 public minUnstakeWeeks = 2;  // minUnstakePercent returned for unstaking this number of weeks

	// The maximum number of weeks for an unstake request at which point 100% of the original staked ZERO tokens is reclaimable.
	// Range: 20 to 108 with an adjustment of 8
	uint256 public maxUnstakeWeeks = 52;

	// The percentage of the original staked ZERO tokens that is reclaimable when unstaking the minimum number of weeks.
	// Range: 10 to 50 with an adjustment of 5
	uint256 public minUnstakePercent = 20;

	// Minimum time between increasing and decreasing user share in SharedRewards contracts.
	// Prevents reward hunting where users could frontrun reward distributions and then immediately withdraw.
	// Range: 15 minutes to 6 hours with an adjustment of 15 minutes
	uint256 public modificationCooldown = 15 minutes;


	function changeMinUnstakeWeeks(bool increase) external onlyOwner
        {
        if (increase)
            {
            if (minUnstakeWeeks < 12)
                minUnstakeWeeks += 1;
            }
        else
            {
            if (minUnstakeWeeks > 2)
                minUnstakeWeeks -= 2;
            }

		emit MinUnstakeWeeksChanged(minUnstakeWeeks);
        }


	function changeMaxUnstakeWeeks(bool increase) external onlyOwner
        {
        if (increase)
            {
            if (maxUnstakeWeeks < 108)
                maxUnstakeWeeks += 8;
            }
        else
            {
            if (maxUnstakeWeeks > 20)
                maxUnstakeWeeks -= 8;
            }

		emit MaxUnstakeWeeksChanged(maxUnstakeWeeks);
        }


	function changeMinUnstakePercent(bool increase) external onlyOwner
        {
        if (increase)
            {
            if (minUnstakePercent < 50)
                minUnstakePercent += 5;
            }
        else
            {
            if (minUnstakePercent > 10)
                minUnstakePercent -= 5;
            }

		emit MinUnstakePercentChanged(minUnstakePercent);
        }


	function changeModificationCooldown(bool increase) external onlyOwner
        {
        if (increase)
            {
            if (modificationCooldown < 6 hours)
                modificationCooldown += 15 minutes;
            }
        else
            {
            if (modificationCooldown > 15 minutes)
                modificationCooldown -= 15 minutes;
            }

		emit ModificationCooldownChanged(modificationCooldown);
        }
    }