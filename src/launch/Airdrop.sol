// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IExchangeConfig.sol";
import "./interfaces/IAirdrop.sol";


// The Airdrop contract keeps track of users who qualify for the Zero DEX Airdrop.
// The amount of awarded ZERO tokens for each user will be claimable over 52 weeks (starting from when allowClaiming() is called)

contract Airdrop is IAirdrop, ReentrancyGuard
    {
	using SafeERC20 for IZero;

    uint256 constant VESTING_PERIOD = 52 weeks;

	IExchangeConfig immutable public exchangeConfig;
    IZero immutable public zero;

	// The timestamp when allowClaiming() was called
	uint256 public claimingStartTimestamp;

	// The claimable airdrop amount for each user
	mapping (address=>uint256) _airdropPerUser;

	// The amount already claimed by each user
	mapping (address=>uint256) claimedPerUser;


	constructor( IExchangeConfig _exchangeConfig )
		{
		exchangeConfig = _exchangeConfig;

		zero = _exchangeConfig.zero();
		}


	// Authorize the wallet as being able to claim a specific amount of the airdrop.
	// The BootstrapBallot would have already confirmed the user is authorized to receive the specified zeroAmount.
    function authorizeWallet( address wallet, uint256 zeroAmount ) external
    	{
    	require( msg.sender == address(exchangeConfig.initialDistribution().bootstrapBallot()), "Only the BootstrapBallot can call Airdrop.authorizeWallet" );
    	require( claimingStartTimestamp == 0, "Cannot authorize after claiming is allowed" );
    	require( _airdropPerUser[wallet] == 0, "Wallet already authorized" );

		_airdropPerUser[wallet] = zeroAmount;
    	}


	// Called to signify that users are able to start claiming their airdrop
    function allowClaiming() external
    	{
    	require( msg.sender == address(exchangeConfig.initialDistribution().bootstrapBallot()), "Only the BootstrapBallot can call Airdrop.allowClaiming" );
    	require( claimingStartTimestamp == 0, "Claiming is already allowed" );

		claimingStartTimestamp = block.timestamp;
    	}


	// Allow the user to claim up to the vested amount they are entitled to
    function claim() external nonReentrant
    	{
  		uint256 claimableZERO = claimableAmount(msg.sender);
    	require( claimableZERO != 0, "User has no claimable airdrop at this time" );

		// Send ZERO tokens to the user
		zero.safeTransfer( msg.sender, claimableZERO);

		// Remember the amount that was claimed by the user
		claimedPerUser[msg.sender] += claimableZERO;
    	}


    // === VIEWS ===

	// Whether or not claiming is allowed
	function claimingAllowed() public view returns (bool)
		{
		return claimingStartTimestamp != 0;
		}


	// The amount that the user has already claimed
	function claimedByUser( address wallet) public view returns (uint256)
		{
		return claimedPerUser[wallet];
		}


	// The amount of ZERO tokens that is currently claimable for the user
    function claimableAmount(address wallet) public view returns (uint256)
    	{
    	// Claiming not allowed yet?
    	if ( claimingStartTimestamp == 0 )
    		return 0;

    	// Look up the airdrop amount for the user
		uint256 airdropAmount = airdropForUser(wallet);
		if ( airdropAmount == 0 )
			return 0;

		uint256 timeElapsed = block.timestamp - claimingStartTimestamp;
		uint256 vestedAmount = ( airdropAmount * timeElapsed) / VESTING_PERIOD;

		// Don't exceed the airdropAmount
		if ( vestedAmount > airdropAmount )
			vestedAmount = airdropAmount;

		// Users can claim the vested amount they are entitled to minus the amount they have already claimed
		return vestedAmount - claimedPerUser[wallet];
    	}


    // The total airdrop that the user will receive
    function airdropForUser( address wallet ) public view returns (uint256)
    	{
    	return _airdropPerUser[wallet];
    	}
	}