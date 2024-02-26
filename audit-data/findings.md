# Code Hawks First Flight One Shot🔫🎶 Audit

## Description

Let's go!!!!!!

## HIGHS

### [H-01] `RapBattle::_battle` function never updates the RapperStats of any `OneShot` NFT resulting in misinformation for `RapperStats.battlesWon` field of every `address`

**Description:**

In the function execution of `RapBattle::_battle`, no update is made to increase by 1 the `RapperStats.battlesWon` field belonging to the winner's `address`.

**`RapBattle::_battle`** code with missing update ⬇

<details>

<summary>Code</summary>

```js
function _battle(uint256 _tokenId, uint256 _credBet) internal {
    address _defender = defender;
    require(defenderBet == _credBet, "RapBattle: Bet amounts do not match");
    uint256 defenderRapperSkill = getRapperSkill(defenderTokenId);
    uint256 challengerRapperSkill = getRapperSkill(_tokenId);
    uint256 totalBattleSkill = defenderRapperSkill + challengerRapperSkill;
    uint256 totalPrize = defenderBet + _credBet;

    uint256 random =
        uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % totalBattleSkill;

    // Reset the defender
    defender = address(0);
    emit Battle(msg.sender, _tokenId, random < defenderRapperSkill ? _defender : msg.sender);

    // If random <= defenderRapperSkill -> defenderRapperSkill wins, otherwise they lose
    if (random <= defenderRapperSkill) {
        // We give them the money the defender deposited, and the challenger's bet
        credToken.transfer(_defender, defenderBet);
        credToken.transferFrom(msg.sender, _defender, _credBet);
    } else {
        // Otherwise, since the challenger never sent us the money, we just give the money in the contract
        credToken.transfer(msg.sender, _credBet);
    }
    totalPrize = 0;
    // Return the defender's NFT
    oneShotNft.transferFrom(address(this), _defender, defenderTokenId);
}
```

</details>

**Impact:**

Calling `OneShot::getRapperStats(uint256 tokenId)` with any `uint256` value would return a `RapperStats` with a `uint256 battlesWon` field that is always **ZERO** `0`.

**Proof of Concept:** Proof of Code

On a foundry installed machine,

- setup a foundry test suite contract as below:

<details>

<summary>Code</summary>

```js
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

        assertGt(credTokenContract.balanceOf(defender), previousDefenderBal);

        // check defender's battlesWon
        IOneShot.RapperStats memory currentDefenderRapStats = oneShotTokenContract.getRapperStats(defenderTokenId);

        console.log("currentDefenderRapStats.battlesWon = ", currentDefenderRapStats.battlesWon);
        console.log("previousDefenderRapStats.battlesWon ", previousDefenderRapStats.battlesWon);

        assertGt(currentDefenderRapStats.battlesWon, previousDefenderRapStats.battlesWon);
    }
}
```

</details>

- on your terminal, run the command:

```shell
forge test --mt testRapperBattlesWonNeverUpdates -vvvvv
```

- results below shows that there's no increment in the `IOneShot.RapperStats.battlesWon` field of the winner `defender`

<details>

<summary><b>RESULT</b></summary>

```js
Running 1 test for test/FindingsTest.t.sol:FindingsTest
[FAIL. Reason: assertion failed] testRapperBattlesWonNeverUpdates() (gas: 663653)
Logs:
  currentDefenderRapStats.battlesWon =  0
  previousDefenderRapStats.battlesWon  0
  Error: a > b not satisfied [uint]
    Value a: 0
    Value b: 0
```

</details>

**Recommended Mitigation:**

- Refactor the `OneShot::onlyStreetContract` modifier as follows:

```diff
-   modifier onlyStreetContract() {
+   modifier onlyStreetOrRapBattleContract() {
-       require(msg.sender == address(_streetsContract), "Not the streets contract");
+       require(msg.sender == address(_streetsContract) || msg.sender == address(_rapBattleContract), "Not the streets or rapBattle contract");
        _;
    }
```

- Refactor `OneShot` contract as follows:

```diff
    ...
+   RapBattle private _rapBattleContract;

+   function setRapBattleContract(address rapBattleContract) public onlyOwner {
+   _rapBattleContract = RapBattle(rapBattleContract);
+   }
    ...
```

- Refactor `OneShot::updateRapperStats` as follows:

```diff
   function updateRapperStats(
       uint256 tokenId,
       bool weakKnees,
       bool heavyArms,
       bool spaghettiSweater,
       bool calmAndReady,
       uint256 battlesWon
-  ) public onlyStreetContract {
+  ) public onlyStreetOrRapBattleContract {
    ...
```

### [H-02] An attacker can cheat `RapBattle::_battle` by not approving `RapBattle` contract address to spend their `CredToken` if they loose bet

**Description:**

An attacker can check if a `defender` exists therefore, decide not to approve `RapBattle` contract to spend their `CredToken` because the **else block** gets called in `goOnStageOrBattle` thereby not transferring any tokens and code execution moves to `_battle` function.

Within the `_battle` function, `RapBattle` transfers only the `defender` `CredToken` to a winning `challenger` and for the case where a `challenger` looses, within the **if block**, the `RapBattle` contract tries to transfer `challenger`'s `CredToken` to `defender` but it gets reverted hence, `challenger` knows they lost bet but retained their `CredToken`

**Impact:**

An attacker leverages the misplaced code logic to ensure they never loose bet even when their **rapper skills** is below that of `defender`

**Proof of Concept:** Proof of Code

Within your foundry test suite, include the code below ⬇️:

<details>

<summary>Code</summary>

```js
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
```

</details>

On your terminal, run the command below:

```shell
forge test --mt testChallengerCanChooseNotApproveRapBattleToBet -vvvvv
```

<details>

<summary><b>RESULT</b></summary>

```js
Running 1 test for test/FindingsTest.t.sol:FindingsTest
[PASS] testChallengerCanChooseNotApproveRapBattleToBet() (gas: 584792)
...
    ├─ [28309] RapBattle::goOnStageOrBattle(1, 3)
    │   ├─ [1183] OneShot::getRapperStats(0) [staticcall]
    │   │   └─ ← RapperStats({ weakKnees: false, heavyArms: false, spaghettiSweater: false, calmAndReady: false, battlesWon: 0 })
    │   ├─ [1183] OneShot::getRapperStats(1) [staticcall]
    │   │   └─ ← RapperStats({ weakKnees: false, heavyArms: false, spaghettiSweater: false, calmAndReady: false, battlesWon: 0 })
    │   ├─ emit Battle(challenger: Challenger: [0x846F7fB58d70E74E7663287da63f88E9F8dD8fdf], tokenId: 1, winner: Challenger: [0x846F7fB58d70E74E7663287da63f88E9F8dD8fdf])
    │   ├─ [18516] Credibility::transfer(Defender: [0x7E6A50Ec13a3762C32fffEb425B71Bf40668dC46], 3)
    │   │   ├─ emit Transfer(from: RapBattle: [0xF62849F9A0B5Bf2913b396098F7c7019b51A820a], to: Defender: [0x7E6A50Ec13a3762C32fffEb425B71Bf40668dC46], value: 3)
    │   │   └─ ← true
    │   ├─ [2926] Credibility::transferFrom(Challenger: [0x846F7fB58d70E74E7663287da63f88E9F8dD8fdf], Defender: [0x7E6A50Ec13a3762C32fffEb425B71Bf40668dC46], 3)
    │   │   └─ ← ERC20InsufficientAllowance(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a, 0, 3)
    │   └─ ← ERC20InsufficientAllowance(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a, 0, 3)
    └─ ← ()
```

</details>

**Recommended Mitigation:**

Refactor `goOnStageOrBattle` function as follows:

```diff
    function goOnStageOrBattle(uint256 _tokenId, uint256 _credBet) external {
        if (defender == address(0)) {
            defender = msg.sender;
            defenderBet = _credBet;
            defenderTokenId = _tokenId;

            emit OnStage(msg.sender, _tokenId, _credBet);

            oneShotNft.transferFrom(msg.sender, address(this), _tokenId);
            credToken.transferFrom(msg.sender, address(this), _credBet);
        } else {
            credToken.transferFrom(msg.sender, address(this), _credBet);
            _battle(_tokenId, _credBet);
        }
    }
```

Refactor `RapBattle::_battle` function as follows:

```diff
    function _battle(uint256 _tokenId, uint256 _credBet) internal {
        address _defender = defender;
        require(defenderBet == _credBet, "RapBattle: Bet amounts do not match");
        uint256 defenderRapperSkill = getRapperSkill(defenderTokenId);
        uint256 challengerRapperSkill = getRapperSkill(_tokenId);
        uint256 totalBattleSkill = defenderRapperSkill + challengerRapperSkill;
        uint256 totalPrize = defenderBet + _credBet;

        uint256 random =
            uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % totalBattleSkill;

        // Reset the defender
        defender = address(0);
        emit Battle(msg.sender, _tokenId, random < defenderRapperSkill ? _defender : msg.sender);

        // If random <= defenderRapperSkill -> defenderRapperSkill wins, otherwise they lose
        if (random <= defenderRapperSkill) {
            // We give them the money the defender deposited, and the challenger's bet
-           credToken.transfer(_defender, defenderBet);
-           credToken.transferFrom(msg.sender, _defender, _credBet);
+           credToken.transfer(_defender, (defenderBet + _credBet));
        } else {
-           // Otherwise, since the challenger never sent us the money, we just give the money in the contract
+           // we give them the money the defender deposited, and the challenger's bet
-           credToken.transfer(msg.sender, _credBet);
+           credToken.transfer(msg.sender, (defenderBet + _credBet));
        }
        totalPrize = 0;
        // Return the defender's NFT
        oneShotNft.transferFrom(address(this), _defender, defenderTokenId);
    }
```

## MEDIUMS

### [M-01] `Streets::unstake` uses `oneShotContract::transferFrom` instead of `safeTransferFrom` which could lead to a permanent loss of tokens

**Description:**

Within the `Streets::unstake` function scope, the transfer of user staked tokens using `oneShotContract.transferFrom` possesses a loss of token threat for the sake of saving gas.

**Impact:**

Possible loss of `ERC721` tokens that were staked.

**Proof of Concept:**

<details>

<summary>Code</summary>

```js
    function unstake(uint256 tokenId) external {
        require(stakes[tokenId].owner == msg.sender, "Not the token owner");
        uint256 stakedDuration = block.timestamp - stakes[tokenId].startTime;
        uint256 daysStaked = stakedDuration / 1 days;

        // Assuming RapBattle contract has a function to update metadata properties
        IOneShot.RapperStats memory stakedRapperStats = oneShotContract.getRapperStats(tokenId);

        emit Unstaked(msg.sender, tokenId, stakedDuration);
        delete stakes[tokenId]; // Clear staking info

        // Apply changes based on the days staked
        if (daysStaked >= 1) {
            stakedRapperStats.weakKnees = false;
            credContract.mint(msg.sender, 1);
        }
        if (daysStaked >= 2) {
            stakedRapperStats.heavyArms = false;
            credContract.mint(msg.sender, 1);
        }
        if (daysStaked >= 3) {
            stakedRapperStats.spaghettiSweater = false;
            credContract.mint(msg.sender, 1);
        }
        if (daysStaked >= 4) {
            stakedRapperStats.calmAndReady = true;
            credContract.mint(msg.sender, 1);
        }

        // Only call the update function if the token was staked for at least one day
        if (daysStaked >= 1) {
            oneShotContract.updateRapperStats(
                tokenId,
                stakedRapperStats.weakKnees,
                stakedRapperStats.heavyArms,
                stakedRapperStats.spaghettiSweater,
                stakedRapperStats.calmAndReady,
                stakedRapperStats.battlesWon
            );
        }

        // Continue with unstaking logic (e.g., transferring the token back to the owner)
        oneShotContract.transferFrom(address(this), msg.sender, tokenId);
    }
```

</details>

**Recommended Mitigation:**

The [OpenZeppelin's documentation](https://docs.openzeppelin.com/contracts/4.x/api/token/erc721#IERC721-transferFrom-address-address-uint256-) encourages the use of `safeTransferFrom` so that the receiving address if a contract must be `ERC721TokenReceiver` compliant to receive `ERC721`

## LOWS

### [L-1] Wrong event data gets emitted from `emit Battle` in `RapBattle::_battle`

**Description:**

In cases where `random == defenderRapperSkill`, the ternary operation `random < defenderRapperSkill ? _defender : msg.sender` passed to the `address indexed winner` params in `event Battle` causes wrong event data to be emitted. As a result, the emitted winner is not the actual winner as actual winner as determined in the **if condition** block scope is `random <= defenderRapperSkill`

**Impact:**

Incorrect event data can mislead developers, users, or other contracts about the state of the contract, leading to incorrect assumptions.

**Proof of Concept:**

Within your foundry test suite, include the below function:

<details>

<summary>Code</summary>

```js
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
```

</details>

On your terminal, paste the command below:

```shell
forge test --mt testWrongBattleEventGetsEmitted -vvvvv
```

<details>

<summary><b>RESULT</b></summary>
```js
Running 1 test for test/FindingsTest.t.sol:FindingsTest
[FAIL. Reason: assertion failed] testWrongBattleEventGetsEmitted() (gas: 666550)
Logs:
  Error: a == b not satisfied [address]
        Left: 0x7E6A50Ec13a3762C32fffEb425B71Bf40668dC46
       Right: 0x846F7fB58d70E74E7663287da63f88E9F8dD8fdf
  defender =>  0x7E6A50Ec13a3762C32fffEb425B71Bf40668dC46
  address(uint160(uint256(topics[2]))) =>  0x846F7fB58d70E74E7663287da63f88E9F8dD8fdf
```

</details>

**Recommended Mitigation:**

Refactor the `RapBattle::_battle` function as follows:

```diff
-       emit Battle(msg.sender, _tokenId, random < defenderRapperSkill ? _defender : msg.sender);
+       emit Battle(msg.sender, _tokenId, random <= defenderRapperSkill ? _defender : msg.sender);
```

## INFORMATIONALS

### [I-1] `OneShot::mintRapper` not returning minted `tokenId` causes difficulty in tracking users' tokens

**Description:**

**Impact:**

**Proof of Concept:** Proof of Code

```js
    function mintRapper() public {
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        // Initialize metadata for the minted token
        rapperStats[tokenId] =
            RapperStats({weakKnees: true, heavyArms: true, spaghettiSweater: true, calmAndReady: false, battlesWon: 0});
    }
```

**Recommended Mitigation:**

Refactor `OneShot::mintRapper` as below:

```diff
-   function mintRapper() public {
+   function mintRapper() public returns(uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        // Initialize metadata for the minted token
        rapperStats[tokenId] =
            RapperStats({weakKnees: true, heavyArms: true, spaghettiSweater: true, calmAndReady: false, battlesWon: 0});

        return tokenId;
    }
```

### [I-2] `RapBattle::BASE_SKILL` value differs from the starting base skill of a rapper defined in documentation as `50`

**Description:**

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

Refactor `RapBattle` as follows:

```diff
-   uint256 public constant BASE_SKILL = 65; // The starting base skill of a rapper
+   uint256 public constant BASE_SKILL = 50; // The starting base skill of a rapper
```
