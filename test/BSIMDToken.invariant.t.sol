// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BSIMDToken} from "../src/BSIMDToken.sol";
import {BSIMDTestBase} from "./helpers/BSIMDTestBase.sol";

/// @notice An independent ledger for the entire supply and every actor/spender pair.
/// @dev Amount bounds come from the model, never the token's reported state. Failed calls leave
/// the model untouched, so the invariant also checks rollback of balances and approvals.
contract BSIMDHandler is BSIMDTestBase {
    BSIMDToken public immutable token;
    address[6] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new BSIMDToken();
        actors = [address(this), ALICE, BOB, SPENDER, MANAGER, ATTACKER];
        expectedBalance[address(this)] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        bool succeeds = amount <= expectedBalance[from];
        _invoke(from, abi.encodeCall(token.transfer, (to, amount)), succeeds);
        if (succeeds) _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 choice = amountSeed % 6;
        uint256 amount = choice == 0
            ? 0
            : choice == 1
                ? 1
                : choice == 2
                    ? SUPPLY
                    : choice == 3 ? type(uint256).max : choice == 4 ? type(uint256).max - 1 : amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        _spend(spender, from, _actor(toSeed), _amount(amountSeed, allowed < balance ? allowed : balance));
    }

    // Ensure sequences contain successful positive delegated transfers as well as denial paths.
    // Independent approve/transferFrom actions above can later replace, revoke or reuse this grant.
    function approveThenSpend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool infinite)
        external
    {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = amountSeed % (expectedBalance[from] + 1);
        _approve(from, spender, infinite ? type(uint256).max : amount);
        _spend(spender, from, _actor(toSeed), amount);
    }

    function rejectZeroAddress(uint256 actorSeed, uint256 spenderSeed, uint256 amountSeed, uint8 choice) external {
        address from = _actor(actorSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = amountSeed % (SUPPLY + 1);
        if (choice % 4 == 0) {
            _invoke(from, abi.encodeCall(token.transfer, (address(0), amount)), false);
        } else if (choice % 4 == 1) {
            _invoke(from, abi.encodeCall(token.approve, (address(0), amountSeed)), false);
        } else if (choice % 4 == 2) {
            _approve(from, spender, amount);
            _invoke(spender, abi.encodeCall(token.transferFrom, (from, address(0), amount)), false);
        } else {
            _invoke(spender, abi.encodeCall(token.transferFrom, (address(0), from, 0)), false);
        }
    }

    function rejectPrivilegedCall(uint256 callerSeed, uint256 holderSeed, uint256 amount, uint8 choice) external {
        address holder = _actor(holderSeed);
        bytes memory data;
        if (choice % 6 == 0) data = abi.encodeWithSignature("mint(address,uint256)", holder, amount);
        else if (choice % 6 == 1) data = abi.encodeWithSignature("burn(uint256)", amount);
        else if (choice % 6 == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amount);
        else if (choice % 6 == 3) data = abi.encodeWithSignature("pause()");
        else if (choice % 6 == 4) data = abi.encodeWithSignature("blacklist(address)", holder);
        else data = abi.encodeWithSignature("upgradeTo(address)", holder);
        _invoke(_actor(callerSeed), data, false);
    }

    function advanceTime(uint256 secondsSeed, uint256 blocksSeed) external {
        vm.warp(block.timestamp + secondsSeed % 365 days);
        vm.roll(block.number + blocksSeed % 1_000_000);
    }

    function checkModel() external view {
        require(token.totalSupply() == SUPPLY, "supply changed");
        require(token.balanceOf(address(0)) == 0, "zero address received supply");
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address owner = actors[i];
            uint256 balance = token.balanceOf(owner);
            require(balance == expectedBalance[owner], "balance differs from independent ledger");
            sum += balance;
            require(token.allowance(owner, address(0)) == 0, "zero spender gained allowance");
            require(token.allowance(address(0), owner) == 0, "zero owner gained allowance");
            for (uint256 j; j < actors.length; ++j) {
                address spender = actors[j];
                require(
                    token.allowance(owner, spender) == expectedAllowance[owner][spender],
                    "allowance differs from independent ledger"
                );
            }
        }
        require(sum == SUPPLY, "sum of all balances changed");
    }

    // Called only by afterInvariant, not included among the random action selectors.
    function returnAllToDeployer() external {
        for (uint256 i = 1; i < actors.length; ++i) {
            address holder = actors[i];
            uint256 amount = expectedBalance[holder];
            _invoke(holder, abi.encodeCall(token.transfer, (address(this), amount)), true);
            _move(holder, address(this), amount);
        }
        require(token.balanceOf(address(this)) == SUPPLY, "a holder could not return its whole balance");
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        uint256 choice = seed % 6;
        if (choice == 0) return 0;
        if (choice == 1) return 1;
        if (choice == 2) return limit;
        if (choice == 3) return limit + 1;
        if (choice == 4) return type(uint256).max;
        return seed % (limit + 1);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        _invoke(owner, abi.encodeCall(token.approve, (spender, amount)), true);
        expectedAllowance[owner][spender] = amount;
    }

    function _spend(address spender, address from, address to, uint256 amount) private {
        uint256 allowed = expectedAllowance[from][spender];
        bool succeeds = amount <= allowed && amount <= expectedBalance[from];
        _invoke(spender, abi.encodeCall(token.transferFrom, (from, to, amount)), succeeds);
        if (succeeds) {
            if (allowed != type(uint256).max) expectedAllowance[from][spender] = allowed - amount;
            _move(from, to, amount);
        }
    }

    function _move(address from, address to, uint256 amount) private {
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function _invoke(address caller, bytes memory data, bool expectedSuccess) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        require(success == expectedSuccess, "unexpected call success/revert");
        if (expectedSuccess) require(result.length == 32 && abi.decode(result, (bool)), "ERC20 returned false");
    }
}

contract BSIMDTokenInvariantTest is BSIMDTestBase {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    BSIMDHandler private handler;

    function setUp() public {
        vm.chainId(1);
        handler = new BSIMDHandler();
        // Start with the exact constructor allocation. The handler explores distribution itself.
        handler.checkModel();
    }

    // Foundry's invariant discovery ABI, without introducing a forge-std dependency.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = BSIMDHandler.transfer.selector;
        selectors[1] = BSIMDHandler.approve.selector;
        selectors[2] = BSIMDHandler.transferFrom.selector;
        selectors[3] = BSIMDHandler.approveThenSpend.selector;
        selectors[4] = BSIMDHandler.rejectZeroAddress.selector;
        selectors[5] = BSIMDHandler.rejectPrivilegedCall.selector;
        selectors[6] = BSIMDHandler.advanceTime.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_FixedSupplyBalancesAndAllowancesMatchLedger() public view {
        handler.checkModel();
    }

    function afterInvariant() public {
        handler.returnAllToDeployer();
        handler.checkModel();
    }
}
