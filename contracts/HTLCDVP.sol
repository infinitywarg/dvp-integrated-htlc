// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HTLCDVP {
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
        uint256 timelock;
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
        bytes32 hashlock,
        uint256 timelock
    ) public returns (bytes32 id) {
        require(assetAmount != 0 && cashAmount != 0, "zero amount");

        Instruction memory i = Instruction(
            msg.sender,
            buyer,
            assetAmount,
            cashAmount,
            hashlock,
            timelock,
            0x00,
            Status.PENDING
        );
        id = keccak256(abi.encode(i));
        require(instruction[id].seller == address(0), "settlement id exists");
        require(timelock > block.timestamp, "timelock must be in future");
        instruction[id] = i;
        emit InstructionCreated(id, i.seller, buyer);
        if (!IERC20(asset).transferFrom(msg.sender, address(this), assetAmount)) {
            revert("asset transfer failed");
        }
    }

    function executeSettlement(bytes32 id, bytes32 secret) external {
        Instruction memory i = instruction[id];
        require(i.seller != address(0), "settlement id doesnt exist");
        require(i.hashlock == keccak256(abi.encode(secret)), "hashlock invalid");
        require(i.buyer == msg.sender, "sender not buyer");
        require(i.status == Status.PENDING, "settlement not pending");
        require(i.timelock > block.timestamp, "timelock expired");
        i.secret = secret;
        i.status = Status.SETTLED;
        instruction[id] = i;
        emit InstructionSettled(id, i.seller, i.buyer);
        if (!IERC20(cash).transferFrom(msg.sender, i.seller, i.cashAmount)) {
            revert("cash transfer failed");
        }
        if (!IERC20(asset).transfer(msg.sender, i.assetAmount)) {
            revert("asset transfer failed");
        }
    }

    function abortSettlement(bytes32 id) external {
        Instruction memory i = instruction[id];
        require(i.seller != address(0), "settlement id doesnt exist");
        require(i.seller == msg.sender, "sender not seller");
        require(i.status != Status.SETTLED && i.status != Status.ABORTED, "already settled or aborted");
        require(i.timelock <= block.timestamp, "timelock not expired");
        i.status = Status.ABORTED;
        instruction[id] = i;
        emit InstructionSettled(id, i.seller, i.buyer);
        if (!IERC20(asset).transfer(msg.sender, i.assetAmount)) {
            revert("asset transfer failed");
        }
    }
}
