// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelpConfig} from "../../script/HelpConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "lib/chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle private raffle;
    HelpConfig private helpConfig;
    address private PLAYER = makeAddr("player");

    uint256 public entranceFee = 0.01 ether;
    uint256 public interval = 30;
    uint256 public constant STATING_USER_BALANCE = 10 ether;
    address public vrfCoordinator;
    uint256 public constant STARTING_USERING_BALANCE = 10 ether;

    event EnteredRaffle(address indexed player);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helpConfig) = deployRaffle.run();
        HelpConfig.NetworkConfig memory config = helpConfig.getConfig();

        vrfCoordinator = config.vrfCoordinator;
        vm.deal(PLAYER, STATING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ////////////////////
    // enterRafle     //
    ////////////////////
    function testRaffleRevertWhenYouDontPayEnough() public {
        vm.prank(PLAYER);

        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle{value: 0.0001 ether, gas: 1_000_000}();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        assertEq(PLAYER, raffle.getPlayer(0));
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ////////////////////
    // checkUpkeep    //
    ////////////////////
    function testCheckUpkeepReturnsFalseIfIthasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        //Assert
        assert(!upkeepNeeded);
    }

    modifier nextRaffle() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public nextRaffle {
        //Arrange
        raffle.performUpkeep("");

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        assert(upkeepNeeded == false);
    }

    ////////////////////
    // performUpkeep  //
    ////////////////////
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        nextRaffle
    {
        // Arrange

        //Act / assert
        raffle.performUpkeep("");
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        //Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    //获得事件的输出
    function testPerformUpkeepUpdatasRaffleStateAndEmitsRequestId()
        public
        nextRaffle
    {
        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    /////////////////////////
    // fulfillRandomWords  //
    /////////////////////////

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 ramdomRequestId
    ) public nextRaffle skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            ramdomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetAndSendsMoney()
        public
        nextRaffle
        skipFork
    {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_USERING_BALANCE);
            console.log("userBalance", player.balance);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        //假装成Chainlink VRF来获取随机数，然后选出获胜者
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        console.log("WinerBalance", raffle.getRecentWinner().balance);
        console.log("expectWinerBalance", STARTING_USERING_BALANCE + prize);
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USERING_BALANCE + prize - entranceFee
        );
    }
}
