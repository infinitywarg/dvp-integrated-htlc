// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleDVP {
    enum Status {
        PENDING,
        SETTLED,
        ABORTED
    }

    struct Instruction {
        address seller;
        address buyer;
        uint256 assetAmount;
        uint256 cashAmount;
        bytes32 hashlock;
        bytes32 secret;
        Status status;
    }

    address immutable asset;
    address immutable cash;

    mapping(bytes32 => Instruction) public instruction;

    constructor(address asset_, address cash_) {
        require(asset_ != address(0) && cash_ != address(0), "zero address");
        asset = asset_;
        cash = cash_;
    }

    event InstructionCreated(bytes32 indexed id, address indexed seller, address indexed buyer);

    event InstructionSettled(bytes32 indexed id, address indexed seller, address indexed buyer);

    event InstructionAborted(bytes32 indexed id, address indexed seller, address indexed buyer);

    function createSettlement(
        address buyer,
        uint256 assetAmount,
        uint256 cashAmount,
        bytes32 hashlock
    ) public returns (bytes32 id) {
        require(assetAmount != 0 && cashAmount != 0, "zero amount");
        // create settlement instruction
        Instruction memory i = Instruction(msg.sender, buyer, assetAmount, cashAmount, hashlock, 0x00, Status.PENDING);
        id = keccak256(abi.encode(i));
        require(instruction[id].seller == address(0), "settlement id exists");
        instruction[id] = i;
        emit InstructionCreated(id, i.seller, buyer);
        // deposit asset tokens into this contract
        if (!IERC20(asset).transferFrom(msg.sender, address(this), assetAmount)) {
            revert("asset deposit failed");
        }
    }

    function executeSettlement(bytes32 id, bytes32 secret) external {
        Instruction memory i = instruction[id];
        require(i.seller != address(0), "settlement id doesnt exist");
        require(i.hashlock == keccak256(abi.encode(secret)), "hashlock invalid");
        require(i.buyer == msg.sender, "sender not buyer");
        require(i.status == Status.PENDING, "settlement not pending");
        // update settlement instruction
        i.secret = secret;
        i.status = Status.SETTLED;
        instruction[id] = i;
        emit InstructionSettled(id, i.seller, i.buyer);
        // deposit cash tokens into this contract
        if (!IERC20(cash).transferFrom(msg.sender, address(this), i.cashAmount)) {
            revert("cash deposit failed");
        }

        // execute delivery vs payment transfers
        if (!IERC20(cash).transfer(i.seller, i.cashAmount)) {
            revert("DvP cash transfer to seller failed");
        }
        if (!IERC20(asset).transfer(msg.sender, i.assetAmount)) {
            revert("DvP asset transfer to buyer failed");
        }
    }

    function abortSettlement(bytes32 id) external {
        Instruction memory i = instruction[id];
        require(i.seller != address(0), "settlement id doesnt exist");
        require(i.seller == msg.sender, "sender not seller");
        require(i.status != Status.SETTLED && i.status != Status.ABORTED, "already settled or aborted");

        i.status = Status.ABORTED;
        instruction[id] = i;
        emit InstructionSettled(id, i.seller, i.buyer);
        if (!IERC20(asset).transfer(msg.sender, i.assetAmount)) {
            revert("asset transfer failed");
        }
    }
}
