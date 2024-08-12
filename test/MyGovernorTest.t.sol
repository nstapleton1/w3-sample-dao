// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {Timelock} from "../src/Timelock.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    GovToken govToken;
    Timelock timelock;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;
    uint256 public constant MIN_DELAY = 3600; // 1 hour - after a vote passes
    uint256 public constant VOTING_DELAY = 1; // how many blocks until a vote is active
    uint256 public constant VOTING_PERIOD = 50400; // a week

    address[] proposers;
    address[] executors;

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startBroadcast(USER);
        govToken.delegate(USER);
        timelock = new Timelock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timelock);

        // grant roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER); // remove yourself as admin

        vm.stopBroadcast();

        box = new Box();
        box.transferOwnership(address(timelock)); // caution: to timelock common mistake is to transfer to Governor
    }

    function testCannotUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 1 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uiint256)", valueToStore);

        // 1. prepare Proposal

        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the state
        console.log("Proposal State: ", uint256(governor.state(proposalId))); // (from enum)

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State: ", uint256(governor.state(proposalId))); // should be active now (from enum)

        // 2. Vote
        string memory reason = "cos blue frog is cool :)";
        uint8 wayToVote = 1; // i.e. voting yes (from enum)
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, wayToVote, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Q the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box Value: ", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }
}
