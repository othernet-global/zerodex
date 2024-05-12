// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../dev/Deployment.sol";
import "../dev/Utils.sol";


contract TestUtils is Deployment
	{
	function testUtils() public view
		{
		uint256 usdcPrice;
		uint256 wethPrice;
		uint256 zeroPrice;

//		Utils utils = new Utils();

		IPriceFeed priceFeed = IPriceFeed(0x4303c5471A4F68e1DEeAf06cc73e8d190Ed7bcf7);

		usdcPrice = priceFeed.getPriceUSDC();

		IERC20 weth = exchangeConfig.weth();
		IERC20 usdc = exchangeConfig.usdc();
		IZero zero = exchangeConfig.zero();


		// USDC has 6 decimals, usdcPrice has 8
		// Convert to 18 decimals

		(uint256 reserves1, uint256 reserves2) = pools.getPoolReserves(weth, usdc);
		if ( reserves1 > PoolUtils.DUST )
		if ( reserves2 > PoolUtils.DUST )
			wethPrice = (reserves2 * usdcPrice * 10**12 ) / (reserves1/10**10);

		(reserves1, reserves2) = pools.getPoolReserves(zero, usdc);
		if ( reserves1 > PoolUtils.DUST )
		if ( reserves2 > PoolUtils.DUST )
			{
			uint256 zeroPriceUSDC = (reserves2 * usdcPrice * 10**12) / (reserves1/10**10);

			(uint256 reserves1b, uint256 reserves2b) = pools.getPoolReserves(zero, weth);
			if ( reserves1b > PoolUtils.DUST )
			if ( reserves2b > PoolUtils.DUST )
				{
				uint256 zeroPriceWETH = (reserves2b * wethPrice) / reserves1b;

				zeroPrice = ( zeroPriceUSDC * reserves1 + zeroPriceWETH * reserves1b ) / ( reserves1 + reserves1b );
				}
			}

		// Convert to 18 decimals
		usdcPrice = usdcPrice * 10**10;



//		utils.corePrices(pools, exchangeConfig, priceFeed);
		}
	}
