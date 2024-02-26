// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
// local imports
import {IOneShot} from "../src/interfaces/IOneShot.sol";
import {Credibility} from "../src/CredToken.sol";
import {OneShot} from "../src/OneShot.sol";
import {RapBattle} from "../src/RapBattle.sol";
import {Streets} from "../src/Streets.sol";

contract FindingsTest is Test {
    Credibility credTokenContract;
    OneShot oneShotTokenContract;
    RapBattle rapBattleContract;
    Streets streetsContract;

    address defender;
    address challenger;

    function setUp() public {
        credTokenContract = new Credibility();
        oneShotTokenContract = new OneShot();
        rapBattleContract = new RapBattle(address(oneShotTokenContract), address(credTokenContract));
        streetsContract = new Streets(address(oneShotTokenContract), address(credTokenContract));

        defender = makeAddr("Defender");
        challenger = makeAddr("Challenger");

        // configure CredToken.setStreetsContract
        credTokenContract.setStreetsContract(address(streetsContract));

        // configure OneShot.setStreetsContract
        oneShotTokenContract.setStreetsContract(address(streetsContract));
    }

    function readyPlayersForBattle() internal returns(uint256 defenderTokenId, uint256 challengerTokenId) {
        vm.startPrank(defender);
        defenderTokenId = oneShotTokenContract.getNextTokenId();
        oneShotTokenContract.mintRapper();
        oneShotTokenContract.approve(address(streetsContract), defenderTokenId);
        // let's stake Rapper NFT for defender for 4 days duration
        streetsContract.stake(defenderTokenId);
        vm.stopPrank();

        vm.startPrank(challenger);
        challengerTokenId = oneShotTokenContract.getNextTokenId();
        oneShotTokenContract.mintRapper();
        oneShotTokenContract.approve(address(streetsContract), challengerTokenId);
        // let's stake Rapper NFT for challenger for 4 days duration
        streetsContract.stake(challengerTokenId);
        vm.stopPrank();

        vm.warp(4 days);

        vm.prank(defender);
        streetsContract.unstake(defenderTokenId);

        vm.prank(challenger);
        streetsContract.unstake(challengerTokenId);
    }

    function testRapperBattlesWonNeverUpdates() public {
        (uint256 defenderTokenId, uint256 challengerTokenId) = readyPlayersForBattle();
        uint256 _credBet = 3;

        IOneShot.RapperStats memory previousDefenderRapStats = oneShotTokenContract.getRapperStats(challengerTokenId) ;

        // let's battle ⚔️

        vm.startPrank(defender);
        credTokenContract.approve(address(rapBattleContract), _credBet);
        oneShotTokenContract.approve(address(rapBattleContract), defenderTokenId);
        rapBattleContract.goOnStageOrBattle(defenderTokenId, _credBet);
        vm.stopPrank();

        uint256 previousDefenderBal = credTokenContract.balanceOf(defender);

        vm.startPrank(challenger);
        credTokenContract.approve(address(rapBattleContract), _credBet);
        oneShotTokenContract.approve(address(rapBattleContract), challengerTokenId);
        vm.recordLogs();
        rapBattleContract.goOnStageOrBattle(challengerTokenId, _credBet);
        vm.stopPrank();

        // expecting defender to win and get their RapperStats.battlesWon increase by one
        /*
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32[] memory topics = entries[0].topics;

        assertEq(defender, address(uint160(uint256(topics[2]))));
        */

        assertGt(credTokenContract.balanceOf(defender), previousDefenderBal);

        // check defender's battlesWon
        IOneShot.RapperStats memory currentDefenderRapStats = oneShotTokenContract.getRapperStats(defenderTokenId);

        console.log("currentDefenderRapStats.battlesWon = ", currentDefenderRapStats.battlesWon);
        console.log("previousDefenderRapStats.battlesWon ", previousDefenderRapStats.battlesWon);

        assertGt(currentDefenderRapStats.battlesWon, previousDefenderRapStats.battlesWon);
    }

    function testChallengerCanChooseNotApproveRapBattleToBet() public {
        (uint256 defenderTokenId, uint256 challengerTokenId) = readyPlayersForBattle();
        uint256 _credBet = 3;

        // let's battle ⚔️

        vm.startPrank(defender);
        oneShotTokenContract.approve(address(rapBattleContract), defenderTokenId);
        credTokenContract.approve(address(rapBattleContract), _credBet);
        rapBattleContract.goOnStageOrBattle(defenderTokenId, _credBet);
        vm.stopPrank();

        vm.prank(challenger);
        vm.expectRevert();
        rapBattleContract.goOnStageOrBattle(challengerTokenId, _credBet);
    }

    function testWrongBattleEventGetsEmitted() public {
        (uint256 defenderTokenId, uint256 challengerTokenId) = readyPlayersForBattle();
        uint256 _credBet = 3;

        // let's battle ⚔️

        vm.startPrank(defender);
        credTokenContract.approve(address(rapBattleContract), _credBet);
        oneShotTokenContract.approve(address(rapBattleContract), defenderTokenId);
        rapBattleContract.goOnStageOrBattle(defenderTokenId, _credBet);
        vm.stopPrank();

        uint256 previousDefenderBal = credTokenContract.balanceOf(defender);

        vm.startPrank(challenger);
        credTokenContract.approve(address(rapBattleContract), _credBet);
        oneShotTokenContract.approve(address(rapBattleContract), challengerTokenId);
        vm.recordLogs();
        rapBattleContract.goOnStageOrBattle(challengerTokenId, _credBet);
        vm.stopPrank();

        // expecting defender to win and get their RapperStats.battlesWon increase by one
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32[] memory topics = entries[0].topics;

        assertEq(defender, address(uint160(uint256(topics[2]))));

        console.log("defender => ", defender);
        console.log("address(uint160(uint256(topics[2]))) => ", address(uint160(uint256(topics[2]))));

        assertGt(credTokenContract.balanceOf(defender), previousDefenderBal);
    }
}