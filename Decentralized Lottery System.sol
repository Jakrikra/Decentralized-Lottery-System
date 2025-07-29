// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Decentralized Lottery System
 * @dev A simple lottery system with Chainlink VRF integration
 * @author Your Name
 */
contract Project is VRFConsumerBaseV2, ReentrancyGuard {
    
    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable vrfCoord;
    uint64 private immutable subscriptionId;
    bytes32 private immutable gasLane;
    uint32 private constant CALLBACK_GAS_LIMIT = 100000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    
    // Lottery Variables
    uint256 public constant TICKET_PRICE = 0.01 ether;
    uint256 public constant LOTTERY_DURATION = 1 hours;
    
    address[] public players;
    address public recentWinner;
    uint256 public lotteryEndTime;
    uint256 public prizePool;
    
    enum LotteryState { OPEN, CALCULATING, CLOSED }
    LotteryState public lotteryState;
    
    mapping(uint256 => uint256) private requestToRandomness;
    
    // Events
    event PlayerEntered(address indexed player, uint256 ticketCount);
    event WinnerPicked(address indexed winner, uint256 prize);
    event LotteryStarted(uint256 endTime);
    
    // Errors
    error InsufficientPayment();
    error LotteryNotOpen();
    error LotteryNotEnded();
    error NoPlayers();
    error TransferFailed();
    
    constructor(
        address vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _gasLane
    ) VRFConsumerBaseV2(vrfCoordinator) {
        vrfCoord = VRFCoordinatorV2Interface(vrfCoordinator);
        subscriptionId = _subscriptionId;
        gasLane = _gasLane;
        
        // Start first lottery
        startLottery();
    }
    
    /**
     * @dev Core Function 1: Enter the lottery by buying tickets
     * @param ticketCount Number of tickets to purchase
     */
    function enterLottery(uint256 ticketCount) external payable nonReentrant {
        if (lotteryState != LotteryState.OPEN) revert LotteryNotOpen();
        if (block.timestamp >= lotteryEndTime) revert LotteryNotEnded();
        if (msg.value < TICKET_PRICE * ticketCount) revert InsufficientPayment();
        
        // Add player tickets to the lottery
        for (uint256 i = 0; i < ticketCount; i++) {
            players.push(msg.sender);
        }
        
        prizePool += msg.value;
        
        // Refund excess payment
        if (msg.value > TICKET_PRICE * ticketCount) {
            uint256 refund = msg.value - (TICKET_PRICE * ticketCount);
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            if (!success) revert TransferFailed();
            prizePool -= refund;
        }
        
        emit PlayerEntered(msg.sender, ticketCount);
    }
    
    /**
     * @dev Core Function 2: Pick winner using Chainlink VRF
     */
    function pickWinner() external {
        if (lotteryState != LotteryState.OPEN) revert LotteryNotOpen();
        if (block.timestamp < lotteryEndTime) revert LotteryNotEnded();
        if (players.length == 0) revert NoPlayers();
        
        lotteryState = LotteryState.CALCULATING;
        
        // Request random number from Chainlink VRF
        uint256 requestId = vrfCoord.requestRandomWords(
            gasLane,
            subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            1
        );
        
        requestToRandomness[requestId] = block.timestamp;
    }
    
    /**
     * @dev Core Function 3: Distribute prizes and start new lottery
     */
    function distributePrizes() internal {
        uint256 totalPrize = prizePool;
        
        // Prize distribution: 80% to winner, 20% kept for next round
        uint256 winnerPrize = (totalPrize * 80) / 100;
        uint256 nextRoundSeed = totalPrize - winnerPrize;
        
        // Transfer prize to winner
        (bool success, ) = payable(recentWinner).call{value: winnerPrize}("");
        if (!success) revert TransferFailed();
        
        emit WinnerPicked(recentWinner, winnerPrize);
        
        // Reset for next round
        players = new address[](0);
        prizePool = nextRoundSeed;
        
        // Start new lottery
        startLottery();
    }
    
    /**
     * @dev Chainlink VRF callback function
     */
    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % players.length;
        recentWinner = players[indexOfWinner];
        lotteryState = LotteryState.CLOSED;
        
        distributePrizes();
    }
    
    /**
     * @dev Start a new lottery round
     */
    function startLottery() internal {
        lotteryState = LotteryState.OPEN;
        lotteryEndTime = block.timestamp + LOTTERY_DURATION;
        emit LotteryStarted(lotteryEndTime);
    }
    
    // View Functions
    function getPlayers() external view returns (address[] memory) {
        return players;
    }
    
    function getPlayerCount() external view returns (uint256) {
        return players.length;
    }
    
    function getTimeRemaining() external view returns (uint256) {
        if (block.timestamp >= lotteryEndTime) return 0;
        return lotteryEndTime - block.timestamp;
    }
    
    function getLotteryState() external view returns (LotteryState) {
        return lotteryState;
    }
}
