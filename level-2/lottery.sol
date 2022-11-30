// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

error Raffle__UpkeepNotNeeded(
  uint256 currentBalance,
  uint256 numPlayers,
  uint256 raffleState
);
error Raffle__TransferFailed();
error Raffle__SendMoreToEnterRaffle();
error Raffle__RaffleNotOpen();

contract Raffle is VRFConsumerBaseV2 {
  /* Type declarations */
  enum RaffleState {
    OPEN,
    CALCULATING
  }
  /* State variables */
  // Chainlink VRF Variables
  VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
  bytes32 private immutable i_gasLane;
  uint64 private immutable i_subscriptionId;
  uint32 private immutable i_callbackGasLimit;
  uint16 private constant REQUEST_CONFIRMATIONS = 3;
  uint32 private constant NUM_WORDS = 1;

  // Lottery Variables
  RaffleState private s_raffleState;
  uint256 private immutable i_entranceFee; //cheap variable immutable
  address payable[] private s_players;
  uint256 private immutable i_interval;
  uint256 private s_lastTimeStamp;
  address private s_recentWinner;

  /* Events */
  event RaffleEnter(address indexed player);
  event RequestedRaffleWinner(uint256 indexed requestId);
  event WinnerPicked(address indexed player);

  constructor(
    uint256 entranceFee,
    uint256 interval,
    address vrfCoordinatorV2,
    bytes32 gasLane, // keyHash
    uint64 subscriptionId,
    uint32 callbackGasLimit
  ) VRFConsumerBaseV2(vrfCoordinatorV2) {
    i_entranceFee = entranceFee;
    s_raffleState = RaffleState.OPEN; //default open
    i_interval = interval;
    s_lastTimeStamp = block.timestamp;
    i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
    i_gasLane = gasLane;
    i_subscriptionId = subscriptionId;
    i_callbackGasLimit = callbackGasLimit;
  }

  function enterRaffle() public payable {
    // require(msg.value >= i_entranceFee, "Not enough value sent");
    // require(s_raffleState == RaffleState.OPEN, "Raffle is not open");
    if (msg.value < i_entranceFee) {
      revert();
    }
    // do not allow players to enter when we are calculating a winner
    if (s_raffleState != RaffleState.OPEN) {
      revert Raffle__RaffleNotOpen();
    }
    s_players.push(payable(msg.sender)); // 'payable' because if they win the lottery; you want to send them money
    // Emit an event when we update a dynamic array or mapping
    // Named events with the function name reversed
    emit RaffleEnter(msg.sender);
  }

  /**
   * @dev This is the function that the Chainlink Keeper nodes call
   * they look for `upkeepNeeded` to return True.
   * the following should be true for this to return true:
   * 1. The time interval has passed between raffle runs.
   * 2. The lottery is open.
   * 3. The contract has ETH.
   * 4. Implicity, your subscription is funded with LINK.
   */

  function checkUpkeep(
    bytes memory /* checkData */
  )
    public
    view
    returns (
      bool upkeepNeeded,
      bytes memory /* performData */
    )
  {
    bool isOpen = RaffleState.OPEN == s_raffleState;
    bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
    bool hasPlayers = s_players.length > 0;
    bool hasBalance = address(this).balance > 0;
    upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
    return (upkeepNeeded, "0x0"); // '0x0' is blank data for now
  }

  /**
   * @dev Once `checkUpkeep` is returning `true`, this function is called
   * and it kicks off a Chainlink VRF call to get a random winner.
   */
  function performUpkeep(
    bytes calldata /* performData */
  ) external {
    (bool upkeepNeeded, ) = checkUpkeep("");
    // require(upkeepNeeded, "Upkeep not needed");
    if (!upkeepNeeded) {
      revert Raffle__UpkeepNotNeeded(
        address(this).balance,
        s_players.length,
        uint256(s_raffleState)
      );
    }
    s_raffleState = RaffleState.CALCULATING;

    // see chainlink docs for making the call here : https://docs.chain.link/docs/get-a-random-number/#analyzing-the-contract
    uint256 requestId = i_vrfCoordinator.requestRandomWords(
      i_gasLane,
      i_subscriptionId,
      REQUEST_CONFIRMATIONS,
      i_callbackGasLimit,
      NUM_WORDS
    );
    // this maybe redundant... as VRF already emits an event
    emit RequestedRaffleWinner(requestId);
  }

  /**
   * @dev This is the function that Chainlink VRF node
   * calls to send the money to the random winner.
   */
  function fulfillRandomWords(
    uint256, /* requestId */
    uint256[] memory randomWords
  ) internal override {
    //override on VRF's fuction
    // s_players size 10
    // randomNumber 202
    // 202 % 10 ? what's doesn't divide evenly into 202?
    // 20 * 10 = 200
    // 2
    // 202 % 10 = 2

    uint256 indexOfWinner = randomWords[0] % s_players.length;
    address payable recentWinner = s_players[indexOfWinner];
    s_recentWinner = recentWinner;
    s_players = new address payable[](0); // reset all the players
    s_raffleState = RaffleState.OPEN;
    s_lastTimeStamp = block.timestamp;
    (bool success, ) = recentWinner.call{ value: address(this).balance }(""); //'call' is the best way to send money
    // require(success, "Transfer failed");
    if (!success) {
      revert Raffle__TransferFailed();
    }
    emit WinnerPicked(recentWinner);
  }
}