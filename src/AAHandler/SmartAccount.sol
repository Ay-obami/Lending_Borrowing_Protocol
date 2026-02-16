// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract SimpleSmartAccount is IAccount {
    address public owner;
    IEntryPoint public immutable ENTRYPOINT;

    constructor(IEntryPoint _entryPoint, address _owner) {
        ENTRYPOINT = _entryPoint;
        owner = _owner;
    }

    // Validate user's signature
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData)
    {
        require(msg.sender == address(ENTRYPOINT), "only EntryPoint");

        // Verify signature
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address recovered = ECDSA.recover(hash, userOp.signature);

        if (recovered != owner) {
            return 1; // Validation failed
        }

        // Pay EntryPoint if needed
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            require(success);
        }

        return 0; // Validation success
    }

    // Execute calls
    function execute(address dest, uint256 value, bytes calldata func) external {
        require(msg.sender == address(ENTRYPOINT), "only EntryPoint");
        (bool success, bytes memory result) = dest.call{value: value}(func);
        require(success, string(result));
    }

    receive() external payable {}
}
