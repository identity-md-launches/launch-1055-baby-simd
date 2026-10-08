// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BSIMDToken} from "../src/BSIMDToken.sol";
import {BSIMDTestBase, BSIMDVm} from "./helpers/BSIMDTestBase.sol";

contract BSIMDTokenAdversarialTest is BSIMDTestBase {
    BSIMDToken private token;

    function setUp() public {
        vm.chainId(1);
        token = new BSIMDToken();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AnyNonzeroRecipientReceivesExactAmount(address recipient, uint256 amount) public {
        // Include arbitrary wallets/contracts and the token itself, with no allowlist assumption.
        if (recipient == address(0)) recipient = address(token);
        amount %= SUPPLY + 1;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), recipient, amount);
        require(token.transfer(recipient, amount), "transfer return");
        if (recipient == address(this)) {
            require(token.balanceOf(address(this)) == SUPPLY, "self transfer changed balance");
        } else {
            require(token.balanceOf(recipient) == amount, "recipient taxed or limited");
            require(token.balanceOf(address(this)) == SUPPLY - amount, "sender debited incorrectly");
        }
        require(token.totalSupply() == SUPPLY, "transfer changed supply");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApprovalCannotBeUsedByAnotherSpenderOrOwner(uint256 amount) public {
        amount = 1 + amount % SUPPLY;
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);
        // Neither a self-granted allowance nor an allowance from a different holder helps.
        vm.prank(ATTACKER);
        token.approve(ATTACKER, type(uint256).max);
        vm.prank(BOB);
        token.approve(ATTACKER, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientAllowance.selector, ATTACKER, 0, amount));
        vm.prank(ATTACKER);
        token.transferFrom(ALICE, ATTACKER, amount);
        require(token.balanceOf(ALICE) == amount && token.balanceOf(ATTACKER) == 0, "unauthorized movement");
        require(token.allowance(ALICE, SPENDER) == amount, "another spender consumed the grant");

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, amount);
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, amount), "authorized spend return");
        require(token.balanceOf(BOB) == amount && token.balanceOf(ALICE) == 0, "authorized spend amount");
        require(token.allowance(ALICE, SPENDER) == 0, "finite grant not exhausted");
        require(token.allowance(BOB, ATTACKER) == type(uint256).max, "unrelated owner's grant changed");
        require(token.allowance(ATTACKER, ATTACKER) == type(uint256).max, "unrelated spender's grant changed");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_OverdrawRollsBackFiniteAllowance(uint256 held, uint256 excess, bool selfTransfer) public {
        held %= SUPPLY + 1;
        // Exercise values up to max-1, keeping the allowance finite, including values above supply.
        uint256 requested = held + 1 + excess % (type(uint256).max - held - 1);
        address recipient = selfTransfer ? ALICE : BOB;
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(SPENDER, requested);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientBalance.selector, ALICE, held, requested));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, recipient, requested);
        BSIMDVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 0, "failed spend emitted a log");
        require(token.allowance(ALICE, SPENDER) == requested, "failed spend consumed allowance");
        require(token.balanceOf(ALICE) == held && token.balanceOf(BOB) == 0, "failed spend changed holders");
        require(token.balanceOf(address(this)) == SUPPLY - held, "failed spend changed deployer");
        require(token.totalSupply() == SUPPLY, "failed spend changed supply");

        // The same approval remains usable after the failed call.
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, held), "valid retry failed");
        require(token.allowance(ALICE, SPENDER) == requested - held, "retry allowance mismatch");
        require(token.balanceOf(BOB) == held && token.balanceOf(ALICE) == 0, "retry delivery mismatch");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_InfiniteApprovalCanBeSpentRepeatedlyThenRevoked(uint256 amount) public {
        amount = 1 + amount % SUPPLY;
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientBalance.selector, ALICE, 0, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        require(token.allowance(ALICE, SPENDER) == type(uint256).max, "failed infinite spend changed grant");

        token.transfer(ALICE, amount);
        for (uint256 i; i < 2; ++i) {
            vm.prank(SPENDER);
            require(token.transferFrom(ALICE, BOB, amount), "infinite spend failed");
            require(token.balanceOf(BOB) == amount && token.balanceOf(ALICE) == 0, "infinite spend amount");
            require(token.allowance(ALICE, SPENDER) == type(uint256).max, "infinite allowance consumed");
            vm.prank(BOB);
            token.transfer(ALICE, amount);
        }

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(ALICE, SPENDER, 0);
        vm.prank(ALICE);
        require(token.approve(SPENDER, 0), "revoke return");
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        require(token.balanceOf(ALICE) == amount && token.balanceOf(BOB) == 0, "revocation bypassed");
        require(token.allowance(ALICE, SPENDER) == 0, "revoked grant restored");
    }

    function test_MaxMinusOneAllowanceIsFinite() public {
        uint256 grant = type(uint256).max - 1;
        token.approve(SPENDER, grant);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, SUPPLY), "large finite grant rejected");
        require(token.allowance(address(this), SPENDER) == grant - SUPPLY, "max-1 treated as infinite");
        require(token.balanceOf(BOB) == SUPPLY && token.balanceOf(address(this)) == 0, "full supply spend");
    }

    function test_ZeroTransferFromWithoutApprovalEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0), "empty holder zero transferFrom");
        require(token.allowance(ALICE, SPENDER) == 0, "zero spend changed allowance");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "zero spend changed balances");
        require(token.balanceOf(address(this)) == SUPPLY && token.totalSupply() == SUPPLY, "zero spend minted");
    }

    function test_SelfTransferCannotOverdrawWithInfiniteApproval() public {
        token.transfer(ALICE, 1);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 2);
        require(token.balanceOf(ALICE) == 1, "self overdraw changed balance");
        require(token.allowance(ALICE, SPENDER) == type(uint256).max, "self overdraw changed allowance");
    }

    function test_HolderTransferFromStillNeedsSelfApproval() public {
        token.transfer(ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1);
        vm.prank(ALICE);
        token.approve(ALICE, 1);
        vm.prank(ALICE);
        require(token.transferFrom(ALICE, BOB, 1), "self-approved transfer failed");
        require(token.balanceOf(BOB) == 1 && token.allowance(ALICE, ALICE) == 0, "self grant not consumed");
    }

    function test_ZeroRecipientRollbackWithInfiniteApproval() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), SUPPLY);
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "invalid receiver consumed grant");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(address(0)) == 0, "invalid burn");
        require(token.totalSupply() == SUPPLY, "supply shrank");
    }
}
