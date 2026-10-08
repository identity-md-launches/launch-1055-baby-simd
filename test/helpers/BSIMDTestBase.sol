// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BSIMDToken} from "../../src/BSIMDToken.sol";

// Keep the suite dependency-free, as in the existing tests. These are Foundry cheatcodes,
// not a substitute token implementation or an external protocol dependency.
interface BSIMDVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address sender) external;
    function expectRevert(bytes calldata data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function chainId(uint256 newChainId) external;
    function warp(uint256 timestamp) external;
    function roll(uint256 height) external;
}

abstract contract BSIMDTestBase {
    BSIMDVm internal constant vm = BSIMDVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1e27;
    // Local test actors; no requester-owned address or production configuration is inferred.
    address internal constant ALICE = address(uint160(uint256(keccak256("BSIMD test Alice"))));
    address internal constant BOB = address(uint160(uint256(keccak256("BSIMD test Bob"))));
    address internal constant SPENDER = address(uint160(uint256(keccak256("BSIMD test spender"))));
    address internal constant ATTACKER = address(uint160(uint256(keccak256("BSIMD test attacker"))));
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
