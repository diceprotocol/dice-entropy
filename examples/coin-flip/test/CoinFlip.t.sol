// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoinFlip} from "../contracts/CoinFlip.sol";
import {MockEntropy} from "./MockEntropy.sol";
import {DiceErrors} from "@diceprotocol/sdk/solidity/DiceErrors.sol";

contract RejectingReceiver {
    CoinFlip public flip;
    uint256 public wager;
    bytes32 public userRandom;

    constructor(CoinFlip flip_) {
        flip = flip_;
    }

    receive() external payable {
        revert("no eth");
    }

    function play(uint256 wager_, uint256 total) external payable {
        wager = wager_;
        userRandom = keccak256("reject");
        flip.flip{value: total}(CoinFlip.Side.Heads, userRandom, wager_);
    }
}

contract ReenteringWithdrawer {
    CoinFlip public flip;
    bool public attack;

    constructor(CoinFlip flip_) {
        flip = flip_;
    }

    function enableAttack() external {
        attack = true;
    }

    receive() external payable {
        if (attack) {
            attack = false;
            flip.withdraw();
        }
    }

    function play(uint256 wager, uint256 total) external payable {
        flip.flip{value: total}(CoinFlip.Side.Heads, keccak256("reenter"), wager);
    }

    function pull() external {
        flip.withdraw();
    }
}

contract CoinFlipTest is Test {
    MockEntropy internal mock;
    CoinFlip internal flip;

    address internal house = address(0xA11CE);
    address internal player = address(0xB0B);
    address internal other = address(0xC0DE);

    uint128 internal constant FEE = 0.000025 ether;
    uint256 internal constant WAGER = 0.001 ether;

    bytes32 internal constant HEADS_RNG = bytes32(uint256(0));
    bytes32 internal constant TAILS_RNG = bytes32(uint256(1));

    function setUp() public {
        mock = new MockEntropy(FEE);
        vm.prank(house);
        flip = new CoinFlip(address(mock), address(0xBEEF1));

        vm.deal(house, 20 ether);
        vm.deal(player, 5 ether);
        vm.deal(other, 5 ether);

        vm.prank(house);
        (bool ok,) = address(flip).call{value: 10 ether}("");
        require(ok, "fund");
    }

    function _total(uint256 wager) internal view returns (uint256) {
        (, uint256 total) = flip.quote(wager);
        return total;
    }

    function test_QuoteSeparatesFeeFromWager() public view {
        (uint256 fee, uint256 total) = flip.quote(WAGER);
        assertEq(fee, FEE);
        assertEq(total, FEE + WAGER);
    }

    function test_FlipStoresWagerNotOracleFee() public {
        uint256 balBefore = address(flip).balance;
        uint256 total = _total(WAGER);
        vm.prank(player);
        uint64 seq = flip.flip{value: total}(CoinFlip.Side.Heads, keccak256("r"), WAGER);

        (address p, CoinFlip.Side guess, uint256 wager, CoinFlip.GameState state, bytes32 rng) =
            flip.getGame(seq);
        assertEq(p, player);
        assertEq(uint256(guess), uint256(CoinFlip.Side.Heads));
        assertEq(wager, WAGER);
        assertTrue(wager != FEE);
        assertEq(uint256(state), uint256(CoinFlip.GameState.Pending));
        assertEq(rng, bytes32(0));
        assertEq(flip.lockedWagers(), WAGER);
        assertEq(address(flip).balance, balBefore + WAGER);
        assertEq(address(mock).balance, FEE);
    }

    function test_WrongMsgValueReverts() public {
        vm.prank(player);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoinFlip.ExactFeePlusWagerRequired.selector, FEE + WAGER, WAGER
            )
        );
        flip.flip{value: WAGER}(CoinFlip.Side.Heads, keccak256("r"), WAGER);
    }

    function test_PublishedOldBetsNeverWorkWithoutFee() public {
        vm.prank(player);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoinFlip.ExactFeePlusWagerRequired.selector, FEE + 0.1 ether, 0.1 ether
            )
        );
        flip.flip{value: 0.1 ether}(CoinFlip.Side.Heads, keccak256("r"), 0.1 ether);
    }

    function test_ZeroWagerReverts() public {
        vm.prank(player);
        vm.expectRevert(CoinFlip.BetRequired.selector);
        flip.flip{value: FEE}(CoinFlip.Side.Heads, keccak256("r"), 0);
    }

    function test_InsufficientBankrollReverts() public {
        CoinFlip poor;
        vm.prank(house);
        poor = new CoinFlip(address(mock), address(0xBEEF1));
        uint256 total = _total(WAGER);
        vm.prank(player);
        vm.expectRevert(CoinFlip.InsufficientBankroll.selector);
        poor.flip{value: total}(CoinFlip.Side.Heads, keccak256("r"), WAGER);
    }

    function test_WinCreditsPullPayoutAndWithdraw() public {
        uint256 playerBefore = player.balance;
        uint256 total = _total(WAGER);
        vm.prank(player);
        uint64 seq = flip.flip{value: total}(CoinFlip.Side.Heads, keccak256("r"), WAGER);

        mock.fulfill(seq, HEADS_RNG);

        (, , , CoinFlip.GameState state,) = flip.getGame(seq);
        assertEq(uint256(state), uint256(CoinFlip.GameState.Won));
        assertEq(flip.pendingPayouts(player), 2 * WAGER);
        assertEq(flip.lockedWagers(), 0);
        assertEq(flip.totalPending(), 2 * WAGER);

        uint256 houseAfterWin = address(flip).balance;
        vm.prank(player);
        flip.withdraw();

        assertEq(flip.pendingPayouts(player), 0);
        assertEq(player.balance, playerBefore - FEE - WAGER + (2 * WAGER));
        assertEq(address(flip).balance, houseAfterWin - (2 * WAGER));
    }

    function test_LoseKeepsWagerOnHouse() public {
        uint256 houseBefore = address(flip).balance;
        uint256 total = _total(WAGER);
        vm.prank(player);
        uint64 seq = flip.flip{value: total}(CoinFlip.Side.Heads, keccak256("r"), WAGER);
        mock.fulfill(seq, TAILS_RNG);

        (, , , CoinFlip.GameState state,) = flip.getGame(seq);
        assertEq(uint256(state), uint256(CoinFlip.GameState.Lost));
        assertEq(flip.pendingPayouts(player), 0);
        assertEq(flip.lockedWagers(), 0);
        assertEq(address(flip).balance, houseBefore + WAGER);

        vm.prank(player);
        vm.expectRevert(CoinFlip.NoPayout.selector);
        flip.withdraw();
    }

    function test_RejectingReceiverStillResolvesOnWin() public {
        RejectingReceiver recv = new RejectingReceiver(flip);
        vm.deal(address(recv), 1 ether);
        uint256 total = _total(WAGER);
        vm.prank(address(recv));
        recv.play{value: total}(WAGER, total);

        uint64 seq = 1;
        mock.fulfill(seq, HEADS_RNG);

        (, , , CoinFlip.GameState state,) = flip.getGame(seq);
        assertEq(uint256(state), uint256(CoinFlip.GameState.Won));
        assertEq(flip.pendingPayouts(address(recv)), 2 * WAGER);

        vm.prank(address(recv));
        vm.expectRevert(CoinFlip.WithdrawFailed.selector);
        flip.withdraw();
        assertEq(flip.pendingPayouts(address(recv)), 2 * WAGER);
    }

    function test_WithdrawReentrancyBlocked() public {
        ReenteringWithdrawer attacker = new ReenteringWithdrawer(flip);
        vm.deal(address(attacker), 1 ether);
        uint256 total = _total(WAGER);
        attacker.play{value: total}(WAGER, total);
        mock.fulfill(1, HEADS_RNG);
        attacker.enableAttack();
        // Inner withdraw hits Reentrant; the ETH call fails; outer withdraw reverts
        // and pending credit is preserved (pull-payment, not push from the callback).
        vm.expectRevert(CoinFlip.WithdrawFailed.selector);
        attacker.pull();
        assertEq(flip.pendingPayouts(address(attacker)), 2 * WAGER);
    }

    function test_DoubleFulfillReverts() public {
        uint256 total = _total(WAGER);
        vm.prank(player);
        uint64 seq = flip.flip{value: total}(CoinFlip.Side.Heads, keccak256("r"), WAGER);
        mock.fulfill(seq, HEADS_RNG);
        vm.expectRevert(CoinFlip.GameAlreadyResolved.selector);
        mock.fulfill(seq, HEADS_RNG);
    }

    function test_CallbackFromNonDiceReverts() public {
        uint256 total = _total(WAGER);
        vm.prank(player);
        uint64 seq = flip.flip{value: total}(CoinFlip.Side.Heads, keccak256("r"), WAGER);
        vm.expectRevert(bytes("Only Entropy can call this function"));
        flip._entropyCallback(seq, address(0xBEEF1), HEADS_RNG);
    }

    function test_OwnerCannotWithdrawLockedOrPending() public {
        uint256 total = _total(WAGER);
        vm.prank(player);
        uint64 seq = flip.flip{value: total}(CoinFlip.Side.Heads, keccak256("r"), WAGER);

        uint256 reserved = (2 * flip.lockedWagers()) + flip.totalPending();
        uint256 excess = address(flip).balance - reserved;
        vm.prank(house);
        vm.expectRevert(CoinFlip.ReserveViolation.selector);
        flip.withdrawBankroll(excess + 1);

        mock.fulfill(seq, HEADS_RNG);
        reserved = (2 * flip.lockedWagers()) + flip.totalPending();
        excess = address(flip).balance - reserved;
        vm.prank(house);
        vm.expectRevert(CoinFlip.ReserveViolation.selector);
        flip.withdrawBankroll(excess + 1);
    }

    function test_OwnerCanWithdrawReserve() public {
        uint256 reserve = flip.houseReserve();
        uint256 ownerBefore = house.balance;
        vm.prank(house);
        flip.withdrawBankroll(1 ether);
        assertEq(house.balance, ownerBefore + 1 ether);
        assertEq(flip.houseReserve(), reserve - 1 ether);
    }

    function test_NonOwnerCannotWithdrawBankroll() public {
        vm.prank(player);
        vm.expectRevert(CoinFlip.Unauthorized.selector);
        flip.withdrawBankroll(1 ether);
    }

    function test_MultipleFlipsLockIndependently() public {
        vm.startPrank(player);
        uint64 s1 = flip.flip{value: _total(WAGER)}(CoinFlip.Side.Heads, keccak256("a"), WAGER);
        uint64 s2 = flip.flip{value: _total(WAGER)}(CoinFlip.Side.Tails, keccak256("b"), WAGER);
        vm.stopPrank();
        assertEq(flip.lockedWagers(), 2 * WAGER);

        mock.fulfill(s1, HEADS_RNG);
        mock.fulfill(s2, HEADS_RNG);

        assertEq(flip.lockedWagers(), 0);
        assertEq(flip.pendingPayouts(player), 2 * WAGER);
        assertEq(flip.totalPending(), 2 * WAGER);
    }

    function test_VerifyRandomnessAfterResolve() public {
        vm.prank(player);
        uint64 seq = flip.flip{value: _total(WAGER)}(CoinFlip.Side.Heads, keccak256("v"), WAGER);
        mock.fulfill(seq, TAILS_RNG);
        (bytes32 rng, CoinFlip.Side result) = flip.verifyRandomness(seq);
        assertEq(rng, TAILS_RNG);
        assertEq(uint256(result), uint256(CoinFlip.Side.Tails));
    }

    function test_FrontendDefaultWagerWorksAtLiveFee() public {
        vm.prank(player);
        uint64 seq = flip.flip{value: FEE + 0.001 ether}(
            CoinFlip.Side.Heads, keccak256("frontend"), 0.001 ether
        );
        (, , uint256 wager,,) = flip.getGame(seq);
        assertEq(wager, 0.001 ether);
    }

    function test_MockForwardsOnlyExactFee() public {
        vm.prank(player);
        vm.expectRevert(DiceErrors.InsufficientFee.selector);
        mock.requestV2{value: FEE + 1}(address(0xBEEF1), keccak256("x"), 200000);
    }
}
