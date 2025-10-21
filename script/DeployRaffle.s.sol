//SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelpConfig} from "./HelpConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

pragma solidity ^0.8.30;

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelpConfig) {
        HelpConfig helpConfig = new HelpConfig();
        (
            uint256 entranceFee,
            uint256 interval,
            address vrfCoordinator,
            bytes32 gasLane,
            uint64 subscripitionId,
            uint32 callbackGasLimit,
            address link,
            uint256 deployerKey
        ) = helpConfig.activeNetworkConfig();

        if (subscripitionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscripitionId = createSubscription.createSubscription(vrfCoordinator, deployerKey);

            //Fund it
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(vrfCoordinator, subscripitionId, link, deployerKey);
        }

        vm.startBroadcast();
        Raffle raffle = new Raffle(
            entranceFee, interval, vrfCoordinator, gasLane, subscripitionId, callbackGasLimit, link, deployerKey
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsume(address(raffle), vrfCoordinator, subscripitionId, deployerKey); //将当前raffle的部署地址传入到消费者中，以保证该地址能调用里面的资金

        return (raffle, helpConfig);
    }
}
