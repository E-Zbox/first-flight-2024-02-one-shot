// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOneShot} from "./interfaces/IOneShot.sol";
import {Credibility} from "./CredToken.sol";
import {ICredToken} from "./interfaces/ICredToken.sol";

contract RapBattle {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IOneShot public oneShotNft;
    ICredToken public credToken;

    // If someone is waiting to battle, the defender will be populated, otherwise address 0
    address public defender;
    uint256 public defenderBet;
    uint256 public defenderTokenId;

    // @written BASE_SKILL is different from what the Documentation specified
    uint256 public constant BASE_SKILL = 65; // The starting base skill of a rapper
    uint256 public constant VICE_DECREMENT = 5; // -5 for each vice the rapper has
    uint256 public constant VIRTUE_INCREMENT = 10; // +10 for each virtue the rapper has

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event OnStage(address indexed defender, uint256 tokenId, uint256 credBet);
    event Battle(address indexed challenger, uint256 tokenId, address indexed winner);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address _oneShot, address _credibilityContract) {
        oneShotNft = IOneShot(_oneShot);
        credToken = ICredToken(_credibilityContract);
    }

    function goOnStageOrBattle(uint256 _tokenId, uint256 _credBet) external {
        if (defender == address(0)) {
            defender = msg.sender;
            defenderBet = _credBet;
            defenderTokenId = _tokenId;

            emit OnStage(msg.sender, _tokenId, _credBet);

            // ?question what's the point of staking challenger's OneShot NFT
            /**
                answered✅ staking challenger's NFT shows that we have the
                right to transfer it since only ERC721 owner can approve 
                another address to transfer it, 
                it proves _tokenId belongs to msg.sender✅
             */
            // ?question missing `onERC721Received` to accept ERC721 tokens seems not to be a problem
            oneShotNft.transferFrom(msg.sender, address(this), _tokenId);
            credToken.transferFrom(msg.sender, address(this), _credBet);
        } else {
            // credToken.transferFrom(msg.sender, address(this), _credBet);
            // ?question why are there no token transfers
            _battle(_tokenId, _credBet);
        }
    }

    function _battle(uint256 _tokenId, uint256 _credBet) internal {
        address _defender = defender;
        require(defenderBet == _credBet, "RapBattle: Bet amounts do not match");
        uint256 defenderRapperSkill = getRapperSkill(defenderTokenId);
        uint256 challengerRapperSkill = getRapperSkill(_tokenId);
        uint256 totalBattleSkill = defenderRapperSkill + challengerRapperSkill;
        // ?question totalPrize does not serve any purpose
        uint256 totalPrize = defenderBet + _credBet;

        // ?question what is block.prevrandao
        uint256 random =
            uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % totalBattleSkill;

        // Reset the defender
        defender = address(0);
        // @written✅ possible wrong event gets emitted when random == defenderRapperSkill hence, causing emitting msg.sender as the winner
        emit Battle(msg.sender, _tokenId, random < defenderRapperSkill ? _defender : msg.sender);

        // If random <= defenderRapperSkill -> defenderRapperSkill wins, otherwise they lose
        if (random <= defenderRapperSkill) {
            // We give winner the money the defender deposited, and the challenger's bet
            credToken.transfer(_defender, defenderBet);
            // @written✅ challenger can choose not to approve address(this) to spend their token
            // so that if they loose, the tx reverts😎
            credToken.transferFrom(msg.sender, _defender, _credBet);
        } else {
            // Otherwise, since the challenger never sent us the money, we just give the money in the contract
            credToken.transfer(msg.sender, _credBet);
        }
        totalPrize = 0;
        // Return the defender's NFT
        oneShotNft.transferFrom(address(this), _defender, defenderTokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getRapperSkill(uint256 _tokenId) public view returns (uint256 finalSkill) {
        IOneShot.RapperStats memory stats = oneShotNft.getRapperStats(_tokenId);
        finalSkill = BASE_SKILL;
        if (stats.weakKnees) {
            finalSkill -= VICE_DECREMENT;
        }
        if (stats.heavyArms) {
            finalSkill -= VICE_DECREMENT;
        }
        if (stats.spaghettiSweater) {
            finalSkill -= VICE_DECREMENT;
        }
        if (stats.calmAndReady) {
            finalSkill += VIRTUE_INCREMENT;
        }
    }
}
