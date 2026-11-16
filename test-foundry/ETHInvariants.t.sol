// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "forge-std/Vm.sol";

import "../contracts/reference/ERC8060NativeETHReference.sol";
import "../contracts/reference/ReservableConditionalETHReference.sol";

/// @notice Ghost ledgers are maintained by independent fuzz handlers, not
///         derived from the contracts under test.
abstract contract FuzzActors {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address[2] internal actors = [address(0xA11CE), address(0xB0B)];
    address[2] internal spenders = [address(0xCAFE), address(0xBABE)];

    constructor() {
        for (uint256 i = 0; i < actors.length; i++) vm.deal(actors[i], 100 ether);
    }

    function _cap(uint256 seed, uint256 max) internal pure returns (uint256) {
        return (seed % max) + 1;
    }
}

/// @notice Fuzzer selects among mint, transfer and owner redemption. The
///         contract's balance is NEVER used as the source of ghost truth.
contract StrictETHHandler is FuzzActors {
    ERC8060NativeETHReference public immutable target;
    struct Token { bool live; address owner; uint256 value; }
    mapping(uint256 => Token) public token;
    uint256 public minted;
    uint256 public ghostOutstanding;
    uint256 public successfulCalls;

    constructor(ERC8060NativeETHReference t) { target = t; }

    function _active(uint256 raw) internal view returns (uint256) {
        uint256 count;
        for (uint256 id = 1; id <= minted; id++) if (token[id].live) count++;
        if (count == 0) return 0;
        uint256 nth = raw % count;
        for (uint256 id = 1; id <= minted; id++) {
            if (!token[id].live) continue;
            if (nth == 0) return id;
            nth--;
        }
        revert("unreachable");
    }

    function mint(uint256 ownerSeed, uint256 amountSeed) external {
        if (minted >= 6) return;
        address who = actors[ownerSeed % 2];
        uint256 amount = _cap(amountSeed, 1e16);
        vm.prank(who);
        uint256 id = target.mint{value: amount}();
        minted++;
        require(id == minted, "wrong mint ID");
        token[id] = Token(true, who, amount);
        ghostOutstanding += amount;
        successfulCalls++;
    }

    function transfer(uint256 tokenSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        address destination = t.owner == actors[0] ? actors[1] : actors[0];
        vm.prank(t.owner);
        target.transferFrom(t.owner, destination, id);
        t.owner = destination;
        successfulCalls++;
    }

    function burn(uint256 tokenSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        address owner = t.owner;
        uint256 amount = t.value;
        uint256 balanceBefore = owner.balance;
        vm.prank(owner);
        target.burn(id);
        require(owner.balance == balanceBefore + amount, "strict payout mismatch");
        t.live = false;
        ghostOutstanding -= amount;
        successfulCalls++;
    }
}

contract ConditionalETHHandler is FuzzActors {
    ReservableConditionalETHReference public immutable target;
    address internal constant ETH = address(0);

    struct Token {
        bool live;
        uint256 backing;
        uint8 ownerIndex;
        uint256 epoch;
    }
    struct Grant {
        uint256 approved;
        uint256 locked;
        uint256 epoch;
    }

    mapping(uint256 => Token) public token;
    mapping(uint256 => mapping(uint256 => Grant)) public grants;
    uint256 public minted;
    uint256 public ghostOutstanding;
    uint256 public successfulCalls;

    constructor(ReservableConditionalETHReference t) { target = t; }

    function actor(uint256 index) external view returns (address) { return actors[index]; }
    function spender(uint256 index) external view returns (address) { return spenders[index]; }

    function _active(uint256 raw) internal view returns (uint256) {
        uint256 count;
        for (uint256 id = 1; id <= minted; id++) if (token[id].live) count++;
        if (count == 0) return 0;
        uint256 nth = raw % count;
        for (uint256 id = 1; id <= minted; id++) {
            if (!token[id].live) continue;
            if (nth == 0) return id;
            nth--;
        }
        revert("unreachable");
    }

    function ghostLocked(uint256 id) public view returns (uint256) {
        return grants[id][0].locked + grants[id][1].locked;
    }

    function mint(uint256 ownerSeed, uint256 amountSeed) external {
        if (minted >= 6) return;
        uint8 index = uint8(ownerSeed % 2);
        uint256 amount = _cap(amountSeed, 1e16);
        vm.prank(actors[index]);
        uint256 id = target.mint{value: amount}();
        minted++;
        require(id == minted, "wrong mint ID");
        token[id] = Token(true, amount, index, 0);
        ghostOutstanding += amount;
        successfulCalls++;
    }

    function deposit(uint256 tokenSeed, uint256 amountSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        uint256 amount = _cap(amountSeed, 1e15);
        vm.prank(actors[t.ownerIndex]);
        target.deposit{value: amount}(id);
        t.backing += amount;
        ghostOutstanding += amount;
        successfulCalls++;
    }

    function approve(uint256 tokenSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        uint256 k = spenderSeed % 2;
        // Set to zero, below current lock, or above current backing.
        uint256 amount = amountSeed % (2e16);
        vm.prank(actors[t.ownerIndex]);
        target.approveReserve(id, spenders[k], ETH, amount);
        grants[id][k].approved = amount;
        grants[id][k].epoch = t.epoch;
        successfulCalls++;
    }

    function reserve(uint256 tokenSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        uint256 k = spenderSeed % 2;
        Grant storage g = grants[id][k];
        uint256 room = g.epoch == t.epoch && g.approved > g.locked ? g.approved - g.locked : 0;
        uint256 free = t.backing - ghostLocked(id);
        if (room == 0 || free == 0) return;
        uint256 limit = room < free ? room : free;
        uint256 amount = _cap(amountSeed, limit);
        vm.prank(spenders[k]);
        target.reserveValue(id, ETH, amount);
        g.locked += amount;
        successfulCalls++;
    }

    function release(uint256 tokenSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        uint256 k = spenderSeed % 2;
        Grant storage g = grants[id][k];
        if (g.locked == 0) return;
        uint256 amount = _cap(amountSeed, g.locked);
        vm.prank(spenders[k]);
        target.releaseValue(id, ETH, amount);
        g.locked -= amount;
        successfulCalls++;
    }

    function withdraw(uint256 tokenSeed, uint256 amountSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        uint256 free = t.backing - ghostLocked(id);
        if (free == 0) return;
        uint256 amount = _cap(amountSeed, free);
        address owner = actors[t.ownerIndex];
        uint256 beforeBalance = owner.balance;
        vm.prank(owner);
        target.withdrawAvailable(id, amount);
        require(owner.balance == beforeBalance + amount, "withdraw payout mismatch");
        t.backing -= amount;
        ghostOutstanding -= amount;
        successfulCalls++;
    }

    function transfer(uint256 tokenSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        address from = actors[t.ownerIndex];
        t.ownerIndex = t.ownerIndex == 0 ? 1 : 0;
        address to = actors[t.ownerIndex];
        vm.prank(from);
        target.transferFrom(from, to, id);
        t.epoch++;
        successfulCalls++;
    }

    function redeem(uint256 tokenSeed) external {
        uint256 id = _active(tokenSeed);
        if (id == 0) return;
        Token storage t = token[id];
        if (ghostLocked(id) != 0) return; // locked ETH must remain encumbered
        address owner = actors[t.ownerIndex];
        uint256 amount = t.backing;
        uint256 beforeBalance = owner.balance;
        vm.prank(owner);
        target.redeemWhenUnlocked(id);
        require(owner.balance == beforeBalance + amount, "redemption payout mismatch");
        t.live = false;
        ghostOutstanding -= amount;
        successfulCalls++;
    }
}

contract StrictETHInvariant is StdInvariant, Test {
    ERC8060NativeETHReference internal reference;
    StrictETHHandler internal handler;

    function setUp() public {
        reference = new ERC8060NativeETHReference();
        handler = new StrictETHHandler(reference);
        handler.mint(0, 1000); // seed a real ETH liability
        targetContract(address(handler));
    }

    function invariant_strictSolvencyAndGhostLedger() public view {
        uint256 sum;
        for (uint256 id = 1; id <= handler.minted(); id++) {
            (bool live, address owner, uint256 value) = handler.token(id);
            if (!live) continue;
            assertEq(reference.ownerOf(id), owner, "strict owner");
            assertEq(reference.valueOf(id), value, "strict per-NFT backing");
            sum += value;
        }
        assertEq(sum, handler.ghostOutstanding(), "strict ghost obligations");
        assertEq(reference.totalRedeemableValue(), sum, "strict onchain liabilities");
        assertEq(address(reference).balance, sum, "strict actual ETH");
        assertTrue(reference.isSolvent(), "strict undercollateralization");
    }

    function invariant_strictIDsAndExercise() public view {
        assertEq(reference.nextTokenId(), handler.minted() + 1, "strict IDs");
        assertGe(handler.successfulCalls(), 1, "handler seeded transaction");
    }
}

contract ConditionalETHInvariant is StdInvariant, Test {
    ReservableConditionalETHReference internal reference;
    ConditionalETHHandler internal handler;
    address internal constant ETH = address(0);

    function setUp() public {
        reference = new ReservableConditionalETHReference();
        handler = new ConditionalETHHandler(reference);
        handler.mint(0, 10000);
        handler.approve(0, 0, 1e15);
        handler.reserve(0, 0, 1e14);
        targetContract(address(handler));
    }

    function invariant_conditionalSolvencyAndLockIsolation() public view {
        uint256 sum;
        for (uint256 id = 1; id <= handler.minted(); id++) {
            (bool live, uint256 backing, uint8 ownerIndex, uint256 epoch) = handler.token(id);
            if (!live) continue;
            uint256 locked;
            for (uint256 k = 0; k < 2; k++) {
                (uint256 approved, uint256 individualLock, uint256 grantEpoch) = handler.grants(id, k);
                locked += individualLock;
                uint256 room = epoch == grantEpoch && approved > individualLock
                    ? approved - individualLock : 0;
                assertEq(reference.reserveAllowance(id, handler.spender(k), ETH), room, "spender allowance");
            }
            assertLe(locked, backing, "overreserved backing");
            assertEq(reference.ownerOf(id), handler.actor(ownerIndex), "conditional owner");
            assertEq(reference.backingOf(id), backing, "conditional backing");
            assertEq(reference.lockedValue(id, ETH), locked, "aggregate lock");
            assertEq(reference.availableValue(id, ETH), backing - locked, "unreserved backing");
            sum += backing;
        }
        assertEq(sum, handler.ghostOutstanding(), "conditional ghost liabilities");
        assertEq(reference.totalBacked(), sum, "conditional onchain liabilities");
        assertEq(address(reference).balance, sum, "conditional actual ETH");
        assertTrue(reference.isSolvent(), "conditional undercollateralization");
    }

    function invariant_conditionalMonotoneIDs() public view {
        assertEq(reference.nextTokenId(), handler.minted() + 1, "no ID reuse");
        assertGe(handler.successfulCalls(), 3, "handler must exercise mint/approval/reserve");
    }

    /// @notice Deliberately demonstrates an availability risk, not theft:
    /// a reserved NFT can be transferred, but its new owner cannot cancel
    /// an existing spender lock. Uncooperative spender => unbounded lock.
    function test_UncooperativeSpenderLocksRemain(uint96 seed) public {
        uint256 amount = (uint256(seed) % 1e16) + 1;
        address seller = address(0xA11CE);
        address buyer = address(0xB0B);
        address spender = address(0xCAFE);
        vm.deal(seller, 100 ether);
        vm.prank(seller);
        uint256 id = reference.mint{value: amount}();
        vm.prank(seller);
        reference.approveReserve(id, spender, ETH, amount);
        vm.prank(spender);
        reference.reserveValue(id, ETH, amount);
        vm.prank(seller);
        reference.transferFrom(seller, buyer, id);
        vm.prank(buyer);
        reference.approveReserve(id, spender, ETH, 0);
        vm.expectRevert(bytes("active reservation blocks redemption"));
        vm.prank(buyer);
        reference.redeemWhenUnlocked(id);
        vm.expectRevert(bytes("release exceeds allocation"));
        vm.prank(buyer);
        reference.releaseValue(id, ETH, amount);
        assertEq(reference.lockedValue(id, ETH), amount, "lock not silently bypassed");
        assertEq(address(reference).balance, amount + 10001, "backing remains present");
    }
}
