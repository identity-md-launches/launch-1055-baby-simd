// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BSIMDToken} from "../src/BSIMDToken.sol";

// Only the cheatcodes used here; no external test dependency or environment configuration.
interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes calldata data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

contract FactoryDeploymentProbe {
    function deploy() external returns (BSIMDToken) {
        return new BSIMDToken();
    }
}

contract BSIMDTokenTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant DISTRIBUTOR = address(0xD157);
    address private constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    BSIMDToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new BSIMDToken();
    }

    function test_MetadataAndWholeSupply() public view {
        require(keccak256(bytes(token.name())) == keccak256("Baby SIMD"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("BSIMD"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.totalSupply() == SUPPLY && token.balanceOf(address(this)) == SUPPLY, "full supply");
    }

    function test_ConstructorMintsToFactoryAndEmitsEvent() public {
        FactoryDeploymentProbe factory = new FactoryDeploymentProbe();
        address predicted = address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(factory), hex"01")))));
        vm.expectEmit(true, true, false, true, predicted);
        emit Transfer(address(0), address(factory), SUPPLY);
        BSIMDToken deployed = factory.deploy();
        require(address(deployed) == predicted, "deployment prediction");
        require(deployed.balanceOf(address(factory)) == SUPPLY, "factory must hold everything");
        require(deployed.balanceOf(address(this)) == 0, "not tx.origin");
    }

    function test_TransferEntireSupplyEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, SUPPLY);
        require(token.transfer(ALICE, SUPPLY), "transfer return");
        require(token.balanceOf(ALICE) == SUPPLY && token.balanceOf(address(this)) == 0, "no limit or fee");
    }

    function test_ZeroAndSelfTransfersPreserveBalances() public {
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "empty holder zero transfer");
        require(token.transfer(address(this), SUPPLY), "self transfer");
        require(token.balanceOf(address(this)) == SUPPLY, "self transfer conservation");
    }

    function test_ApproveOverwriteAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        require(token.approve(SPENDER, 100), "approve return");
        token.approve(SPENDER, 50);
        require(token.allowance(address(this), SPENDER) == 50, "overwrite");
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_ExactAllowanceAndNoReplay() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 100), "transferFrom return");
        require(token.balanceOf(ALICE) == 100 && token.allowance(address(this), SPENDER) == 0, "exact spend");
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_InfiniteAllowanceIsNotConsumed() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, SUPPLY);
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "infinite allowance");
        require(token.balanceOf(ALICE) == SUPPLY, "whole supply");
    }

    function test_SelfTransferFromConsumesAllowanceOnly() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), 100);
        require(token.balanceOf(address(this)) == SUPPLY, "self balance");
        require(token.allowance(address(this), SPENDER) == 0, "self allowance");
    }

    function test_RevertInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BSIMDToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "atomic failure");
    }

    function test_FailedTransferFromRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        require(token.allowance(ALICE, SPENDER) == 100 && token.balanceOf(BOB) == 0, "atomic allowance");
    }

    function test_RevertZeroRecipientAndSpender() public {
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        require(token.allowance(address(this), SPENDER) == 100, "zero recipient rollback");
    }

    function test_RevertZeroSender() public {
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_DeployerHasNoUnapprovedTransferAuthority() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(BSIMDToken.ERC20InsufficientAllowance.selector, address(this), 0, 100));
        token.transferFrom(ALICE, BOB, 100);
        vm.prank(ALICE);
        token.transfer(BOB, 100);
        require(token.balanceOf(BOB) == 100, "holder remains free");
    }

    function test_LaunchAndManagerTransferPathsDeliverWhole() public {
        uint256 swarm = SUPPLY / 10;
        token.transfer(DISTRIBUTOR, swarm);
        token.transfer(MANAGER, SUPPLY - swarm);
        require(token.balanceOf(address(this)) == 0, "all allocated");
        require(token.balanceOf(MANAGER) == SUPPLY * 9 / 10, "seed arrived whole");
        vm.prank(DISTRIBUTOR);
        token.transfer(ALICE, swarm);
        require(token.balanceOf(ALICE) == swarm && token.balanceOf(DISTRIBUTOR) == 0, "claim whole");
        vm.prank(MANAGER);
        token.transfer(BOB, 1e18);
        require(token.balanceOf(BOB) == 1e18, "buy delivery whole");
        vm.prank(BOB);
        token.transfer(MANAGER, 1e18);
        require(token.balanceOf(BOB) == 0 && token.balanceOf(MANAGER) == SUPPLY - swarm, "sell whole");
        require(token.totalSupply() == SUPPLY, "supply fixed");
    }

    function test_NoAdminMintBurnOrUpgradeFunctions() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "seize(address)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)",
            "owner()"
        ];
        token.transfer(ALICE, 100);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, 100);
            (bool ok,) = address(token).call(data);
            require(!ok, "deployer reached privileged function");
            vm.prank(BOB);
            (ok,) = address(token).call(data);
            require(!ok, "stranger reached privileged function");
        }
        require(token.totalSupply() == SUPPLY && token.balanceOf(ALICE) == 100, "immutable balances and supply");
        vm.prank(ALICE);
        token.transfer(BOB, 100);
    }

    function test_RuntimeContainsNoForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) i += op - 0x5f;
            else require(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferRoundTrip(uint256 amount) public {
        amount %= SUPPLY + 1;
        token.transfer(ALICE, amount);
        require(token.balanceOf(ALICE) == amount, "exact received");
        vm.prank(ALICE);
        token.transfer(address(this), amount);
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "roundtrip conservation");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AllowanceBoundary(uint256 approved, uint256 spent) public {
        approved %= SUPPLY + 1;
        spent %= SUPPLY + 1;
        token.approve(SPENDER, approved);
        if (spent > approved) {
            vm.expectRevert(
                abi.encodeWithSelector(BSIMDToken.ERC20InsufficientAllowance.selector, SPENDER, approved, spent)
            );
            vm.prank(SPENDER);
            token.transferFrom(address(this), ALICE, spent);
            require(
                token.allowance(address(this), SPENDER) == approved && token.balanceOf(ALICE) == 0,
                "failure conservation"
            );
        } else {
            vm.prank(SPENDER);
            token.transferFrom(address(this), ALICE, spent);
            require(token.allowance(address(this), SPENDER) == approved - spent, "allowance consumption");
            require(
                token.balanceOf(ALICE) == spent && token.balanceOf(address(this)) == SUPPLY - spent,
                "balance conservation"
            );
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_StatefulConservation(bytes32 seed) public {
        address[4] memory actors = [address(this), ALICE, BOB, SPENDER];
        for (uint256 i; i < 64; ++i) {
            seed = keccak256(abi.encode(seed, i));
            uint256 random = uint256(seed);
            address from = actors[random % 4];
            address to = actors[(random >> 8) % 4];
            uint256 amount = (random >> 16) % (token.balanceOf(from) + 1);
            if ((random & 256) == 0) {
                vm.prank(from);
                token.transfer(to, amount);
            } else {
                vm.prank(from);
                token.approve(SPENDER, amount);
                vm.prank(SPENDER);
                token.transferFrom(from, to, amount);
            }
            uint256 sum;
            for (uint256 j; j < actors.length; ++j) {
                sum += token.balanceOf(actors[j]);
            }
            require(sum == SUPPLY && token.totalSupply() == SUPPLY, "stateful supply conservation");
        }
    }
}
