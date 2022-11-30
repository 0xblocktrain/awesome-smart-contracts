// FRs: ====================================================
// 1. Stake : lock tokens into our smart contract ✅
// 2. Withdraw : unlock tokens and pull out of the contract ✅
// 3. claimReward : users get their reward tokens
// Design Questions ============================================
//     * what's a good reward mechanism?
//     * What's some good reward maths?

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//custom errors here - gas efficient way of sending failures
//      when used with 'revert' (e.g. `revert Staking_TransferFailed();`) :
//              -> they revert everything that happend before in the function call
error Staking_TransferFailed();
error Staking_NeedsMoreThanZero();

contract Staking is ReentrancyGuard {
  IERC20 public s_stakingToken; // storage variable - expensive to read & write
  IERC20 public s_rewardsToken;

  // someone's address -> how much have they staked
  mapping(address => uint256) public s_balances;

  uint256 public s_totalSupply;

  // This is the reward token per second
  // Which will be multiplied by the tokens the user staked divided by the total
  // This ensures a steady reward rate of the platform
  // So the more users stake, the less for everyone who is staking.
  uint256 public constant REWARD_RATE = 100;
  uint256 public s_lastUpdateTime;
  uint256 public s_rewardPerTokenStored;

  //a mapping of how much reward tokens each account has been paid
  mapping(address => uint256) public s_userRewardPerTokenPaid;
  //a mapping of how much rewards each user has
  mapping(address => uint256) public s_rewards;

  constructor(address stakingToken, address rewardToken) {
    s_stakingToken = IERC20(stakingToken); //wrap the address to IERC20 token
    s_rewardsToken = IERC20(rewardToken);
  }

  // do we allow any tokens ? - no, not for this simple app ❌
  //      NOTE: to allow this; we have to do some Chainlink stuff to convert prices b/w tokens
  // or just a specific toekn? ✅
  function stake(uint256 amount)
    external
    updateReward(msg.sender)
    nonReentrant
    moreThanZero(amount)
  {
    // 1. keep track how much this user has staked ( to be useful when they are withdrawing it)
    s_balances[msg.sender] += amount;

    // 2. keep track of how much token we have total
    s_totalSupply += amount;

    //TODO: emit event

    // 3. transfer the toekns to this contract
    //     transferFrom() -> is from openzeppelin's IERC20 interface
    ///                   -> is different from transfer() ; as it needs approval
    bool suceess = s_stakingToken.transferFrom(
      msg.sender,
      address(this),
      amount
    );
    // require(success, "failed"); -> better handle d with custom error in below line(as sending this string "failed" is gas-expensive)
    if (!suceess) {
      revert Staking_TransferFailed();
    }
  }

  // just do the opposites of stake()
  function withdraw(uint256 amount)
    external
    updateReward(msg.sender)
    moreThanZero(amount)
    nonReentrant
  {
    s_balances[msg.sender] -= amount;
    s_totalSupply += amount;
    //TODO: emit event

    // transfer()
    //          -> is also from openzeppelin's IERC20 interface
    //          -> is different from transferFrom() ; as we(the contract) already has these tokens; so we dont need approval again; just make the transfer
    bool suceess = s_stakingToken.transfer(msg.sender, amount);
    if (!suceess) {
      revert Staking_TransferFailed();
    }
  }

  function claimReward() external updateReward(msg.sender) nonReentrant {
    uint256 reward = s_rewards[msg.sender];
    s_rewards[msg.sender] = 0;
    //emit RewardsClaimed(msg.sender, reward);
    bool success = s_rewardsToken.transfer(msg.sender, reward);
    if (!success) {
      revert Staking_TransferFailed();
    }
    // How much reward do they get?
    // => The contract is going to emit X tokens per second
    //    And disperse them to all token stakers in the
    //    ratio of their staked coins
    // e.g
    //   ======================================================================
    //   lets say the contract emtis 100 reward tokens per second
    //   State1: 3 people have below stakes at t=0 seconds
    //         person:     p1        p2         p3
    //         STAKED:    50 tokens  20 tokens  30 tokens  (total:100)
    //        REWARDS:    50 tokens  20 tokens  30 tokens  (total:100)
    //   --------------------------------------------------------------
    //   State1: 3 people have below stakes at t=1 second. Another person stakes 50 tokens in contract
    //         person:     p1        p2         p3        p4
    //         STAKED:    50 tokens  20 tokens  30 tokens 50 tokens  (total:200)
    //        REWARDS:    25 tokens  10 tokens  15 tokens 25 tokens  (total:100)
    //   ======================================================================
    //
    // Why not reward 1 token for every staked token? -> bankrupt your protocol
    //
    // till 5 seconds: only 1 person had 100 tokens staked => reward 500 tokens
    //   at 6 seconds: another person deposits 100 tokens
    //                 - now we ahve 2 persons having 100 staked each
    //                 - rewards:
    //                     - Person 1: 550
    //                     - Person 2:  50
    //
    // We need a a timestamp mechanism to have these calculations:
    //     - ok between seconds 1 and 5, person 1 got 500 tokens
    //     - ok at second 6 on, person 1 gets 50 tokens now
  }

  /**
   * @notice How much reward a token gets based on how long it's been in and during which "snapshots"
   */
  function rewardPerToken() public view returns (uint256) {
    if (s_totalSupply == 0) {
      return s_rewardPerTokenStored;
    }
    return
      s_rewardPerTokenStored +
      (((block.timestamp - s_lastUpdateTime) * REWARD_RATE * 1e18) /
        s_totalSupply);
  }

  /**
   * @notice How much reward a user has earned
   */
  function earned(address account) public view returns (uint256) {
    uint256 currentBalance = s_balances[account];
    uint256 amountAlreadyPaid = s_userRewardPerTokenPaid[account];
    uint256 currentRewardPerToken = rewardPerToken();
    uint256 pastRewards = s_rewards[account];
    return
      ((currentBalance * (currentRewardPerToken - amountAlreadyPaid)) / 1e18) *
      pastRewards;

    // one-liner implementation
    // return
    //   ((s_balances[account] *
    //     (rewardPerToken() - s_userRewardPerTokenPaid[account])) / 1e18) +
    //   s_rewards[account];
  }

  /********************/
  /* Modifiers Functions */
  /********************/
  //NOTE: to be called everytime the user does - skate, withdraw, claimReward
  modifier updateReward(address account) {
    // 1. find how much reward per token?
    // 2. get last timestamp
    // 3.
    s_rewardPerTokenStored = rewardPerToken();
    s_lastUpdateTime = block.timestamp;
    s_rewards[account] = earned(account);
    s_userRewardPerTokenPaid[account] = s_rewardPerTokenStored;
    _;
  }

  modifier moreThanZero(uint256 amount) {
    if (amount == 0) {
      revert Staking_NeedsMoreThanZero();
    }
    _;
  }
}