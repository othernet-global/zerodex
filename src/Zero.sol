// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IZero.sol";


contract Zero is IZero, ERC20
    {
    event ZEROBurned(uint256 amount);

	uint256 public constant MILLION_ETHER = 1000000 ether;
	uint256 public constant INITIAL_SUPPLY = 100 * MILLION_ETHER ;


	constructor()
		ERC20( "Zero Token", "ZERO" )
		{
		_mint( msg.sender, INITIAL_SUPPLY );
        }


	// ZERO tokens will need to be sent here before they are burned.
	// There should otherwise be no ZERO token balance in this contract.
    function burnTokensInContract() external
    	{
    	uint256 balance = balanceOf( address(this) );
    	_burn( address(this), balance );

    	emit ZEROBurned(balance);
    	}


    // === VIEWS ===
    function totalBurned() external view returns (uint256)
    	{
    	return INITIAL_SUPPLY - totalSupply();
    	}
	}

