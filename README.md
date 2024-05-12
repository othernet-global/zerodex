# Technical Overview
\
The Zero DEX codebase is divided up into the following folders:


**/arbitrage** - handles creating governance proposals, voting, and acting on successful proposals. DAO adjustable parameters are stored in ~Config.sol contracts and are stored on a per folder basis.

**/dao** - handles creating governance proposals, voting, acting on successful proposals and managing POL (Protocol Owned Liquidity). DAO adjustable parameters are stored in ~Config.sol contracts and are stored on a per folder basis.

**/launch** - handles the initial airdrop, initial distribution, and bootstrapping ballot (a decentralized vote by the airdrop recipients to start up the DEX and distribute ZERO tokens).

**/pools** - a core part of the exchange which handles liquidity pools, swaps, arbitrage, and user token deposits (which reduces gas costs for multiple trades) and pools contribution to recent arbitrage trades (for proportional rewards distribution).

**/rewards** - handles global ZERO token emissions, ZERO token rewards (which are sent to liquidity providers and stakers), and includes a rewards emitter mechanism (which emits a percentage of rewards over time to reduce rewards volatility).

**/staking** - implements a staking rewards mechanism which handles users receiving rewards proportional to some "userShare".  What the userShare actually represents is dependent on the contract that derives from StakingRewards.sol (namely Staking.sol which handles users staking ZERO tokens, and Liquidity.sol which handles users depositing liquidity).

**/** - includes the ZERO token, the default AccessManager (which allows for DAO controlled geo-restriction) and the Upkeep contract (which contains a user callable performUpkeep() function that ensures proper functionality of ecosystem rewards, emissions, etc).

\
**Codebase**

*Based on the audited [Salty.IO contracts](https://github.com/othernet-global/salty-io)*

\
**Dependencies**

*openzeppelin/openzeppelin-contracts@v4.9.3*

\
**Build Instructions**

forge build\
\
**To run unit tests**\
Note - the RPC URL needs to be a Sepolia RPC (e.g. https://rpc.sepolia.org) \
COVERAGE="yes" NETWORK="sep" forge test -vv --rpc-url https://x.x.x.x:yyy

\
**Additional Resources**

[Documentation](https://docs.zerodex.org) \

\
**Audits**

[ABDK](https://github.com/abdk-consulting/audits/blob/main/othernet_global_pte_ltd/ABDK_OthernetGlobalPTELTD_SaltyIO_v_2_0.pdf) \
[Trail of Bits](https://github.com/trailofbits/publications/blob/master/reviews/2023-10-saltyio-securityreview.pdf) \
[Code4rena](https://code4rena.com/reports/2024-01-salty)
