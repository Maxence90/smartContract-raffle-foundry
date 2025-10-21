//SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AddConsumer} from "../../script/Interactions.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelpConfig} from "../../script/HelpConfig.s.sol";
import {VRFCoordinatorV2Mock} from "lib/chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract intergrationsTest is Test {
    uint256 public constant STAING_USER_BALANCE = 10 ether;

    Raffle private raffle;
    HelpConfig private helpConfig;
    address private PLAYER = makeAddr("player");
    address private vrfCoordinator;
    uint64 private subId;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helpConfig) = deployRaffle.run();

        vrfCoordinator = helpConfig.getConfig().vrfCoordinator;
        subId = raffle.getsubId();
        vm.deal(PLAYER, STAING_USER_BALANCE);
    }

    function testAddConsumerRunSuccessful() public {
        (,,, address[] memory consumers) = VRFCoordinatorV2Mock(vrfCoordinator).getSubscription(subId);

        bool found = false;
        for (uint256 i = 0; i < consumers.length; i++) {
            if (consumers[i] == address(raffle)) {
                found = true;
                break;
            }
        }

        assertTrue(found, "Raffle contract should be added as consumer");
    }
}
