// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {HelpConfig} from "./HelpConfig.s.sol";
import {VRFCoordinatorV2Mock} from "lib/chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {VRFCoordinatorV2Interface} from "lib/chainlink-evm/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {Raffle} from "../src/Raffle.sol";

/**
 * @dev 创建chainlink订阅
 */
contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelpConfig helpConfig = new HelpConfig();
        (, , address vrfCoordinator, , , , , uint256 deployerKey) = helpConfig
            .activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 deployerKey
    ) public returns (uint64) {
        vm.startBroadcast(deployerKey);
        uint64 subId = VRFCoordinatorV2Interface(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("your sub Id is", subId);
        return subId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_ACOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelpConfig helpConfig = new HelpConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subId,
            ,
            address link,
            uint256 deployerKey
        ) = helpConfig.activeNetworkConfig();
        fundSubscription(vrfCoordinator, subId, link, deployerKey);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint64 subId,
        address link,
        uint256 deployerKey
    ) public {
        console.log("Funding subscription: ", subId);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("on chainId", block.chainid);
        if (block.chainid == 31337) {
            //本地开发网
            vm.startBroadcast();
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subId,
                FUND_ACOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_ACOUNT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsume(
        address raffle,
        address vrfCoordinator,
        uint64 subId,
        uint256 deployerKey
    ) public {
        console.log("Adding consumer contract: ", raffle);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("On chainId", block.chainid);
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, raffle);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address raffle) public {
        HelpConfig helpConfig = new HelpConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            ,
            uint64 subId,
            ,
            uint256 deployerKey
        ) = helpConfig.activeNetworkConfig();
        addConsume(raffle, vrfCoordinator, subId, deployerKey);
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        ); //动态查找最近部署的合约地址
        addConsumerUsingConfig(raffle);
    }
}
