// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DVP {
    enum Status {
        PENDING,
        SETTLED,
        ABORTED
    }

    struct ExtData {
        bytes32 hashedEcdhKey;
        bytes encryptedPreimage;
    }

    struct Instruction {
        address seller;
        address buyer;
        uint256 assetAmount;
        uint256 cashAmount;
        bytes32 hashlock;
        uint256 timelock;
        bytes32 preimage;
        Status status;
    }

    address immutable asset;
    address immutable cash;

    mapping(address => bytes) public publicKey;
    mapping(bytes32 => Instruction) public instruction;

    event InstructionCreated(
        bytes32 indexed id,
        address indexed seller,
        address indexed buyer,
        ExtData data
    );

    event InstructionSettled(
        bytes32 indexed id,
        address indexed seller,
        address indexed buyer
    );

    event InstructionAborted(
        bytes32 indexed id,
        address indexed seller,
        address indexed buyer
    );

    constructor(address asset_, address cash_) {
        require(asset_ != address(0) && cash_ != address(0), "zero address");
        asset = asset_;
        cash = cash_;
    }

    function registerPublicKey(bytes memory key) public returns (bool) {
        // check if public key corresponds to the address
        publicKey[msg.sender] = key;
        return true;
    }

    function createSettlement(
        address buyer,
        uint256 assetAmount,
        uint256 cashAmount,
        bytes32 hashlock,
        uint256 timelock,
        ExtData memory data
    ) public returns (bytes32 id) {
        require(assetAmount != 0 && cashAmount != 0, "zero amount");
        require(publicKey[msg.sender].length != 0, "seller public key missing");
        require(publicKey[buyer].length != 0, "buyer public key missing");
        require(
            data.encryptedPreimage.length == 64,
            "malformed encrypted preimage"
        );
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
        emit InstructionCreated(id, i.seller, buyer, data);
        if (
            !IERC20(asset).transferFrom(msg.sender, address(this), assetAmount)
        ) {
            revert("asset transfer failed");
        }
    }

    function executeSettlement(
        bytes32 id,
        bytes32 preimage
    ) public returns (bool success) {
        Instruction memory i = instruction[id];
        require(i.seller != address(0), "settlement id doesnt exist");
        require(
            i.hashlock == keccak256(abi.encode(preimage)),
            "hashlock invalid"
        );
        require(i.buyer == msg.sender, "sender not buyer");
        require(i.status == Status.PENDING, "settlement not pending");
        require(i.timelock > block.timestamp, "timelock expired");
        i.preimage = preimage;
        i.status = Status.SETTLED;
        instruction[id] = i;
        emit InstructionSettled(id, i.seller, i.buyer);
        if (!IERC20(cash).transferFrom(msg.sender, i.seller, i.cashAmount)) {
            revert("asset transfer failed");
        }
        if (!IERC20(asset).transfer(msg.sender, i.assetAmount)) {
            revert("asset transfer failed");
        }

        success = true;
    }

    function abortSettlement(bytes32 id) public returns (bool success) {
        Instruction memory i = instruction[id];
        require(i.seller != address(0), "settlement id doesnt exist");
        require(i.seller == msg.sender, "sender not seller");
        require(
            i.status != Status.SETTLED && i.status != Status.ABORTED,
            "already settled or aborted"
        );
        require(i.timelock <= block.timestamp, "timelock not expired");
        i.status = Status.ABORTED;
        instruction[id] = i;
        emit InstructionSettled(id, i.seller, i.buyer);
        if (!IERC20(asset).transfer(msg.sender, i.assetAmount)) {
            revert("asset transfer failed");
        }
        success = true;
    }
}
