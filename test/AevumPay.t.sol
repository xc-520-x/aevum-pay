// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AevumPay} from "../src/AevumPay.sol";

contract MockUSD is ERC20 {
    constructor() ERC20("Mock tUSD8", "tUSD8") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract AevumPayTest is Test {
    AevumPay public pay;
    MockUSD public token;

    address public owner = address(0x1001);
    address public agent = address(0x2002);
    address public stranger = address(0x3003);

    uint256 constant PER_DRAW = 100e6;
    uint256 constant TOTAL = 500e6;

    function setUp() public {
        token = new MockUSD();
        pay = new AevumPay(address(token));
        token.mint(owner, 10_000e6);
        vm.prank(owner);
        token.approve(address(pay), type(uint256).max);
    }

    function _create() internal returns (uint256 id) {
        vm.prank(owner);
        id = pay.createAllowance(agent, PER_DRAW, TOTAL, block.timestamp + 7 days);
    }

    function testCreateAllowance() public {
        uint256 id = _create();
        AevumPay.Allowance memory a = pay.getAllowance(id);
        assertEq(a.owner, owner);
        assertEq(a.spender, agent);
        assertEq(a.perDrawCap, PER_DRAW);
        assertEq(a.totalCap, TOTAL);
        assertEq(a.spent, 0);
        assertEq(uint256(a.status), 0);
        assertEq(token.balanceOf(address(pay)), TOTAL);
        assertEq(pay.remaining(id), TOTAL);
    }

    function testDraw() public {
        uint256 id = _create();
        vm.prank(agent);
        pay.draw(id, 40e6, "task 1 complete");
        AevumPay.Allowance memory a = pay.getAllowance(id);
        assertEq(a.spent, 40e6);
        assertEq(token.balanceOf(agent), 40e6);
        assertEq(pay.remaining(id), TOTAL - 40e6);
    }

    function testDrawOverPerDrawCap() public {
        uint256 id = _create();
        vm.prank(agent);
        vm.expectRevert("amount over per-draw cap");
        pay.draw(id, PER_DRAW + 1, "too big");
    }

    function testDrawOverTotalCap() public {
        uint256 id = _create();
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(agent);
            pay.draw(id, PER_DRAW, "drain");
        }
        vm.prank(agent);
        vm.expectRevert("amount over total cap");
        pay.draw(id, 1, "one more");
    }

    function testDrawByNonSpender() public {
        uint256 id = _create();
        vm.prank(stranger);
        vm.expectRevert("caller is not the spender");
        pay.draw(id, 10e6, "nope");
    }

    function testDrawAfterExpiry() public {
        uint256 id = _create();
        vm.warp(block.timestamp + 8 days);
        vm.prank(agent);
        vm.expectRevert("allowance expired");
        pay.draw(id, 10e6, "late");
    }

    function testRevoke() public {
        uint256 id = _create();
        vm.prank(agent);
        pay.draw(id, 40e6, "partial work");
        uint256 ownerBefore = token.balanceOf(owner);
        vm.prank(owner);
        pay.revoke(id);
        AevumPay.Allowance memory a = pay.getAllowance(id);
        assertEq(uint256(a.status), 1);
        assertEq(token.balanceOf(owner), ownerBefore + (TOTAL - 40e6));
        assertEq(token.balanceOf(address(pay)), 0);
    }

    function testRevokeByNonOwner() public {
        uint256 id = _create();
        vm.prank(agent);
        vm.expectRevert("caller is not the owner");
        pay.revoke(id);
    }

    function testDrawAfterRevoke() public {
        uint256 id = _create();
        vm.prank(owner);
        pay.revoke(id);
        vm.prank(agent);
        vm.expectRevert("allowance not active");
        pay.draw(id, 10e6, "too late");
    }

    function testClaimExpired() public {
        uint256 id = _create();
        vm.prank(agent);
        pay.draw(id, 40e6, "partial work");
        vm.warp(block.timestamp + 8 days);
        uint256 ownerBefore = token.balanceOf(owner);
        vm.prank(owner);
        pay.claimExpired(id);
        AevumPay.Allowance memory a = pay.getAllowance(id);
        assertEq(uint256(a.status), 2);
        assertEq(token.balanceOf(owner), ownerBefore + (TOTAL - 40e6));
    }

    function testClaimExpiredTooEarly() public {
        uint256 id = _create();
        vm.prank(owner);
        vm.expectRevert("allowance not expired");
        pay.claimExpired(id);
    }

    function testTopUp() public {
        uint256 id = _create();
        vm.prank(owner);
        pay.topUp(id, 500e6);
        AevumPay.Allowance memory a = pay.getAllowance(id);
        assertEq(a.totalCap, TOTAL + 500e6);
        assertEq(token.balanceOf(address(pay)), TOTAL + 500e6);
    }

    function testTopUpByNonOwner() public {
        uint256 id = _create();
        vm.prank(agent);
        vm.expectRevert("caller is not the owner");
        pay.topUp(id, 10e6);
    }

    function testCreateInvalidParams() public {
        vm.startPrank(owner);
        vm.expectRevert("spender is zero address");
        pay.createAllowance(address(0), PER_DRAW, TOTAL, block.timestamp + 1 days);
        vm.expectRevert("spender must differ from owner");
        pay.createAllowance(owner, PER_DRAW, TOTAL, block.timestamp + 1 days);
        vm.expectRevert("per-draw cap is zero");
        pay.createAllowance(agent, 0, TOTAL, block.timestamp + 1 days);
        vm.expectRevert("total cap below per-draw cap");
        pay.createAllowance(agent, PER_DRAW, PER_DRAW - 1, block.timestamp + 1 days);
        vm.expectRevert("expiry is in the past");
        pay.createAllowance(agent, PER_DRAW, TOTAL, block.timestamp);
        vm.stopPrank();
    }

    function testDrawNonexistent() public {
        vm.prank(agent);
        vm.expectRevert("allowance does not exist");
        pay.draw(999, 10e6, "ghost");
    }
}
