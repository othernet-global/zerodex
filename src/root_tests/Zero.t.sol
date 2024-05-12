// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "forge-std/Test.sol";
import "../dev/Deployment.sol";
import "../Zero.sol";


contract TestZero is Deployment
	{
	uint256 constant public MILLION_ETHER = 1000000 ether;

    address public constant alice = address(0x1111);


	constructor()
		{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			initializeContracts();
		}


	// A unit test to check the burnTokensInContract function when there are no tokens in the contract. Verify that the function returns zero.
	function test_burnTokensInContract_noTokens() public {

		uint256 totalSupply0 = zero.totalSupply();

    	// Assert that the contract's balance is initially 0
    	assertEq(zero.balanceOf(address(zero)), 0);

    	// Assert that the burned amount is 0 because the contract initially has no tokens
    	assertEq(totalSupply0, zero.totalSupply());
    }


    // A unit test to check the burnTokensInContract function when there are some tokens that have been sent to the contract. Ensure that these tokens are correctly burned and the function returns the amount of tokens burnt.
    function test_burnTokensInContract() public
        {
        uint preBurnContractBalance = zero.balanceOf(address(zero));
        uint preBurnTotalSupply = zero.totalSupply();
        assertEq(preBurnContractBalance, 0); // Asserting that the balance is 0 before any burn.

		vm.prank(address(initialDistribution));
        zero.transfer(address(zero), 100 ether); // Transferring 100 ether to the contract.

        uint transferredAmount = zero.balanceOf(address(zero));
        assertEq(transferredAmount, 100 ether); // Asserting that the contract received the transferred amount.

		zero.burnTokensInContract();

        uint postBurnContractBalance = zero.balanceOf(address(zero));
        assertEq(postBurnContractBalance, 0); // Asserting that the balance is 0 after the burn.

        uint postBurnTotalSupply = zero.totalSupply();
        assertEq(preBurnTotalSupply - 100 ether, postBurnTotalSupply); // Asserting that the total supply is decreased by the burnt amount.
        }


    // A unit test to check the totalBurned function immediately after the contract's deployment, expecting the returned result to be zero as no tokens should have been burned yet.
    function test_totalBurnedAfterDeployment() public {
        // Assert that the total burned is initially 0
        assertEq(zero.totalBurned(), 0);
    }


    // A unit test to check the totalBurned function after some tokens have been burned via the burnTokensInContract function. Ensure that the function correctly reports the total amount of tokens that have been burned.
    function test_totalBurned_after_burnTokensInContract() public {
        uint preBurnTotalSupply = zero.totalSupply();

        assertEq(preBurnTotalSupply, 100 * MILLION_ETHER); // Assert that total supply is equal to INITIAL_SUPPLY.

    	vm.prank(address(initialDistribution));
        zero.transfer(address(zero), 5 ether); // Sending 5 ether to the contract.

        zero.burnTokensInContract(); // Burning the tokens.

        uint postBurnTotalSupply = zero.totalSupply();

        assertEq(postBurnTotalSupply, preBurnTotalSupply - 5 ether); // Asserting that the total supply has decreased by the amount of tokens burned.

        uint totalBurned = zero.totalBurned();

        assertEq(totalBurned, 5 ether); // Asserting that the totalBurned reporting correctly.
    }


    // A unit test to check the constructor to ensure that it correctly mints the initial supply of tokens to the deployer of the contract.
	function test_initialSupply() public
        {
        zero = new Zero();

        uint preBurnTotalSupply = zero.totalSupply();
        assertEq(preBurnTotalSupply, 100 * MILLION_ETHER); // Assert that total supply is equal to INITIAL_SUPPLY.

        uint deployerBalance = zero.balanceOf(address(this));
        assertEq(deployerBalance, 100 * MILLION_ETHER);
        }


    // A unit test to check the constructor to ensure it correctly sets the name and symbol of the token.
    function test_zeroConstructor() public {

		ERC20 zeroToken = ERC20(address(zero));

    	assertEq(zeroToken.name(), "Zero Token");
		assertEq(zeroToken.symbol(), "ZERO");
    }
	}
