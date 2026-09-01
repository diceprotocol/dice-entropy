// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IEntropyConsumer} from "@diceprotocol/sdk/solidity/IEntropyConsumer.sol";
import {IEntropy} from "@diceprotocol/sdk/solidity/IEntropy.sol";

/// @title CoinFlip
/// @notice NON-PRODUCTION example of a Dice Protocol consumer.
/// @dev Player pays `oracleFee + wager`. Only the oracle fee is forwarded to Dice.
///      The wager is escrowed here. Wins credit a pull-payment of 2 * wager.
///      This is not a deployed product and must not be treated as a live casino.
contract CoinFlip is IEntropyConsumer {
    uint32 public constant CALLBACK_GAS = 200_000;

    IEntropy public immutable dice;
    address public immutable provider;
    address public owner;

    enum Side {
        Heads,
        Tails
    }

    enum GameState {
        Pending,
        Won,
        Lost
    }

    struct Game {
        address player;
        Side guess;
        uint256 wager;
        GameState state;
        bytes32 randomNumber;
    }

    mapping(uint64 => Game) public games;
    mapping(address => uint256) public pendingPayouts;

    uint256 public lockedWagers;
    uint256 public totalPending;

    uint256 private _guard = 1;

    event Flipped(
        uint64 indexed sequence,
        address indexed player,
        Side guess,
        uint256 wager,
        uint256 fee
    );
    event Resolved(
        uint64 indexed sequence,
        address indexed player,
        Side result,
        GameState state,
        bytes32 randomNumber
    );
    event Withdrawal(address indexed player, uint256 amount);
    event BankrollDeposited(address indexed from, uint256 amount);
    event BankrollWithdrawn(address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error BetRequired();
    error InvalidGuess();
    error ExactFeePlusWagerRequired(uint256 expected, uint256 actual);
    error InsufficientBankroll();
    error GameAlreadyResolved();
    error NoPayout();
    error WithdrawFailed();
    error Unauthorized();
    error ReserveViolation();
    error Reentrant();
    error ZeroAddress();
    error GameNotResolved();

    modifier nonReentrant() {
        if (_guard != 1) revert Reentrant();
        _guard = 2;
        _;
        _guard = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _dice, address _provider) {
        if (_dice == address(0) || _provider == address(0)) revert ZeroAddress();
        dice = IEntropy(_dice);
        provider = _provider;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    receive() external payable {
        emit BankrollDeposited(msg.sender, msg.value);
    }

    /// @notice Oracle fee and total msg.value required for a wager.
    function quote(uint256 wager) public view returns (uint256 fee, uint256 total) {
        fee = uint256(dice.getFeeV2(provider, CALLBACK_GAS));
        total = fee + wager;
    }

    /// @notice ETH not needed to pay every pending game as a win (2x wager) plus unpaid pulls.
    function houseReserve() public view returns (uint256) {
        uint256 reserved = (2 * lockedWagers) + totalPending;
        uint256 bal = address(this).balance;
        if (bal <= reserved) return 0;
        return bal - reserved;
    }

    /// @notice Flip. Send exactly oracleFee + wager. Wager stays here; fee goes to Dice.
    function flip(Side guess, bytes32 userRandom, uint256 wager)
        external
        payable
        nonReentrant
        returns (uint64 seq)
    {
        if (wager == 0) revert BetRequired();
        if (guess != Side.Heads && guess != Side.Tails) revert InvalidGuess();

        (uint256 fee, uint256 total) = quote(wager);
        if (msg.value != total) revert ExactFeePlusWagerRequired(total, msg.value);

        // After forwarding the fee the house must still cover 2x every locked wager
        // (including this one) plus unpaid pulls, so simultaneous wins stay solvent.
        if (address(this).balance < (2 * (lockedWagers + wager)) + totalPending + fee) {
            revert InsufficientBankroll();
        }

        seq = dice.requestV2{value: fee}(provider, userRandom, CALLBACK_GAS);

        lockedWagers += wager;
        games[seq] = Game({
            player: msg.sender,
            guess: guess,
            wager: wager,
            state: GameState.Pending,
            randomNumber: bytes32(0)
        });

        emit Flipped(seq, msg.sender, guess, wager, fee);
    }

    function entropyCallback(uint64 sequence, address, bytes32 randomNumber) internal override {
        Game storage game = games[sequence];
        if (game.player == address(0) || game.state != GameState.Pending) {
            revert GameAlreadyResolved();
        }

        game.randomNumber = randomNumber;
        Side result = (uint256(randomNumber) & 1 == 1) ? Side.Tails : Side.Heads;

        lockedWagers -= game.wager;

        if (game.guess == result) {
            game.state = GameState.Won;
            uint256 payout = game.wager * 2;
            pendingPayouts[game.player] += payout;
            totalPending += payout;
        } else {
            game.state = GameState.Lost;
        }

        emit Resolved(sequence, game.player, result, game.state, randomNumber);
    }

    function getEntropy() internal view override returns (address) {
        return address(dice);
    }

    /// @notice Pull unpaid winnings. Never called from the Dice callback.
    function withdraw() external nonReentrant {
        uint256 amount = pendingPayouts[msg.sender];
        if (amount == 0) revert NoPayout();
        pendingPayouts[msg.sender] = 0;
        totalPending -= amount;
        (bool sent,) = msg.sender.call{value: amount}("");
        if (!sent) revert WithdrawFailed();
        emit Withdrawal(msg.sender, amount);
    }

    function withdrawBankroll(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert BetRequired();
        uint256 reserved = (2 * lockedWagers) + totalPending;
        if (address(this).balance < reserved + amount) revert ReserveViolation();
        (bool sent,) = owner.call{value: amount}("");
        if (!sent) revert WithdrawFailed();
        emit BankrollWithdrawn(owner, amount);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getGame(uint64 seq)
        external
        view
        returns (address player, Side guess, uint256 wager, GameState state, bytes32 randomNumber)
    {
        Game memory g = games[seq];
        return (g.player, g.guess, g.wager, g.state, g.randomNumber);
    }

    function verifyRandomness(uint64 seq) external view returns (bytes32 randomNumber, Side result) {
        Game memory g = games[seq];
        if (g.state == GameState.Pending) revert GameNotResolved();
        return (g.randomNumber, (uint256(g.randomNumber) & 1 == 1) ? Side.Tails : Side.Heads);
    }
}
