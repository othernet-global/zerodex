pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


library PoolUtils
	{
	// Token reserves less than dust are treated as if they don't exist at all.
	// With the 18 decimals that are used for most tokens, DUST has a value of 0.0000000000000001
	uint256 constant public DUST = 100;

	// A special pool that represents staked ZERO tokens that are not associated with any actual liquidity pool.
    bytes32 constant public STAKED_ZERO = bytes32(0);


    // Return the unique poolID for the given two tokens.
    // Tokens are sorted before being hashed to make reversed pairs equivalent.
    function _poolID( IERC20 tokenA, IERC20 tokenB ) internal pure returns (bytes32 poolID)
    	{
        // See if the token orders are flipped
        if ( uint160(address(tokenB)) < uint160(address(tokenA)) )
            return keccak256(abi.encodePacked(address(tokenB), address(tokenA)));

        return keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
    	}


    // Return the unique poolID and whether or not it is flipped
    function _poolIDAndFlipped( IERC20 tokenA, IERC20 tokenB ) internal pure returns (bytes32 poolID, bool flipped)
    	{
        // See if the token orders are flipped
        if ( uint160(address(tokenB)) < uint160(address(tokenA)) )
            return (keccak256(abi.encodePacked(address(tokenB), address(tokenA))), true);

        return (keccak256(abi.encodePacked(address(tokenA), address(tokenB))), false);
    	}
	}
