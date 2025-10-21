// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {VRFConsumerBaseV2Plus} from "lib/chainlink-evm/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {
    VRFCoordinatorV2Interface
} from "lib/chainlink-evm/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * @title 一个抽奖合约
 * @author Maxence90
 * @notice 这个合约是为了创建一个抽奖功能
 * @dev 我们将使用 Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2Plus {
    //error
    error Raffle__NotEnoughEthSent();
    error Raffle__NotEnoughtTime();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    //Type declarations
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    //state variables
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable I_ENTRANCE_FEE;
    uint256 private immutable I_INTERVAL;
    bytes32 private immutable I_GAS_LANE;
    uint64 private immutable I_SUBSCRIPTION_ID;
    uint32 private immutable I_CALLBACK_GAS_LIMIT;
    address private immutable I_LINK;
    VRFCoordinatorV2Interface private immutable I_VRF_COORDINATOR;
    uint256 private immutable I_DEPLOYER_KEY;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffState;

    //Event
    event EnteredRaffle(address indexed player);
    event WinnerPicked(address winner);
    event RequestRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator, //通过 VRF Coordinator 请求随机数(不同网络的协调员地址不同)
        bytes32 gasLane, //这个值对应特定的 Gas 价格档次
        uint64 subscripitionId, //订阅ID
        uint32 callbackGasLimit,
        address link,
        uint256 deployerKey
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        I_ENTRANCE_FEE = entranceFee;
        I_INTERVAL = interval;
        I_GAS_LANE = gasLane;
        I_SUBSCRIPTION_ID = subscripitionId;
        I_CALLBACK_GAS_LIMIT = callbackGasLimit;
        I_LINK = link;

        s_raffState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        I_VRF_COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        I_DEPLOYER_KEY = deployerKey;
    }

    function enterRaffle() external payable {
        if (msg.value < I_ENTRANCE_FEE) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev 这是Chainlink自动化节点调用以判断是否执行upkeep的时间的函数
     * 满足以下条件会返回true
     * 1.距离上次抽奖的间隔时间已经到达我们之间设置的间隔
     * 2.抽奖状态s_raffState是OPEN
     * 3.合约拥有ETH(有玩家参与抽奖)
     * 4.订阅已经用LINK资金资助
     */

    function checkUpKeep(
        bytes memory /*checkData*/
    )
        public
        view
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= I_INTERVAL;
        bool isOpen = RaffleState.OPEN == s_raffState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(
        bytes calldata /* performData */
    )
        external
    {
        (bool upkeepNeeded,) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffState));
        }

        s_raffState = RaffleState.CALCULATING;
        uint256 requestId = I_VRF_COORDINATOR.requestRandomWords(
            I_GAS_LANE, I_SUBSCRIPTION_ID, REQUEST_CONFIRMATION, I_CALLBACK_GAS_LIMIT, NUM_WORDS
        );
        emit RequestRaffleWinner(requestId); //是没必要的，因为接口中包含了这个事件
    }

    function fulfillRandomWords(
        uint256,
        /*requestId*/
        uint256[] calldata randomWords
    )
        internal
        override
    {
        // Checks
        // Effects (我们对合约的影响)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffState = RaffleState.OPEN;

        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(winner);
        // Interaction(与其他合约交互)
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // getter function

    function getEntranceFee() external view returns (uint256) {
        return I_ENTRANCE_FEE;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffState;
    }

    function getPlayer(uint256 indexOfPlayers) external view returns (address) {
        return s_players[indexOfPlayers];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getsubId() external view returns (uint64) {
        return I_SUBSCRIPTION_ID;
    }
}
