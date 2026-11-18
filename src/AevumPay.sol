// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AevumPay
/// @notice Capped payment allowances in tUSD8 for AI agents and services on QDay Aevum testnet.
/// @dev A user deposits tUSD8 into an allowance for a designated spender. The spender draws
///      small payments up to a per-draw cap and a total cap, before an expiry. The owner can
///      top up or revoke at any time and reclaim the remainder. No admin, no backdoors.
contract AevumPay is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The stablecoin used for allowances (tUSD8 on Aevum testnet).
    IERC20 public immutable token;

    enum Status {
        Active,
        Revoked,
        Expired
    }

    struct Allowance {
        address owner;
        address spender;
        uint256 perDrawCap;
        uint256 totalCap;
        uint256 spent;
        uint256 expiry;
        Status status;
    }

    uint256 public nextAllowanceId;
    mapping(uint256 => Allowance) public allowances;

    event AllowanceCreated(
        uint256 indexed id,
        address indexed owner,
        address indexed spender,
        uint256 perDrawCap,
        uint256 totalCap,
        uint256 expiry
    );
    event Drawn(uint256 indexed id, address indexed spender, uint256 amount, string memo);
    event ToppedUp(uint256 indexed id, uint256 amount, uint256 newTotalCap);
    event Revoked(uint256 indexed id, uint256 refunded);
    event ExpiredClaimed(uint256 indexed id, uint256 refunded);

    constructor(address _token) {
        require(_token != address(0), "token is zero address");
        token = IERC20(_token);
    }

    /// @notice Create an allowance and fund it with totalCap of tUSD8.
    function createAllowance(
        address spender,
        uint256 perDrawCap,
        uint256 totalCap,
        uint256 expiry
    ) external nonReentrant returns (uint256 id) {
        require(spender != address(0), "spender is zero address");
        require(spender != msg.sender, "spender must differ from owner");
        require(perDrawCap > 0, "per-draw cap is zero");
        require(totalCap >= perDrawCap, "total cap below per-draw cap");
        require(expiry > block.timestamp, "expiry is in the past");

        id = nextAllowanceId++;
        allowances[id] = Allowance({
            owner: msg.sender,
            spender: spender,
            perDrawCap: perDrawCap,
            totalCap: totalCap,
            spent: 0,
            expiry: expiry,
            status: Status.Active
        });

        token.safeTransferFrom(msg.sender, address(this), totalCap);
        emit AllowanceCreated(id, msg.sender, spender, perDrawCap, totalCap, expiry);
    }

    /// @notice Draw a payment from an allowance. Only the designated spender.
    function draw(uint256 id, uint256 amount, string calldata memo) external nonReentrant {
        Allowance storage a = allowances[id];
        require(a.owner != address(0), "allowance does not exist");
        require(a.status == Status.Active, "allowance not active");
        require(msg.sender == a.spender, "caller is not the spender");
        require(block.timestamp < a.expiry, "allowance expired");
        require(amount > 0, "amount is zero");
        require(amount <= a.perDrawCap, "amount over per-draw cap");
        require(a.spent + amount <= a.totalCap, "amount over total cap");

        a.spent += amount;
        token.safeTransfer(a.spender, amount);
        emit Drawn(id, a.spender, amount, memo);
    }

    /// @notice Add funds to an allowance and raise its total cap.
    function topUp(uint256 id, uint256 amount) external nonReentrant {
        Allowance storage a = allowances[id];
        require(a.owner != address(0), "allowance does not exist");
        require(a.status == Status.Active, "allowance not active");
        require(msg.sender == a.owner, "caller is not the owner");
        require(block.timestamp < a.expiry, "allowance expired");
        require(amount > 0, "amount is zero");

        a.totalCap += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit ToppedUp(id, amount, a.totalCap);
    }

    /// @notice Cancel an allowance and refund the remaining balance to the owner.
    function revoke(uint256 id) external nonReentrant {
        Allowance storage a = allowances[id];
        require(a.owner != address(0), "allowance does not exist");
        require(a.status == Status.Active, "allowance not active");
        require(msg.sender == a.owner, "caller is not the owner");

        uint256 remaining = a.totalCap - a.spent;
        a.status = Status.Revoked;
        if (remaining > 0) {
            token.safeTransfer(a.owner, remaining);
        }
        emit Revoked(id, remaining);
    }

    /// @notice After expiry, the owner reclaims whatever was not spent.
    function claimExpired(uint256 id) external nonReentrant {
        Allowance storage a = allowances[id];
        require(a.owner != address(0), "allowance does not exist");
        require(a.status == Status.Active, "allowance not active");
        require(msg.sender == a.owner, "caller is not the owner");
        require(block.timestamp >= a.expiry, "allowance not expired");

        uint256 remaining = a.totalCap - a.spent;
        a.status = Status.Expired;
        if (remaining > 0) {
            token.safeTransfer(a.owner, remaining);
        }
        emit ExpiredClaimed(id, remaining);
    }

    function getAllowance(uint256 id) external view returns (Allowance memory) {
        return allowances[id];
    }

    function remaining(uint256 id) external view returns (uint256) {
        Allowance storage a = allowances[id];
        return a.totalCap - a.spent;
    }
}
