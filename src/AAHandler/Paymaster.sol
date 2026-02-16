// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {_packValidationData, calldataKeccak} from "@account-abstraction/contracts/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title MinimalPaymaster
/// @notice Simple paymaster for gasless onboarding with signature verification
contract Paymaster is BasePaymaster {
    using UserOperationLib for PackedUserOperation;

    /// @notice Paymaster data structure
    struct PaymasterData {
        uint48 validUntil;
        uint48 validAfter;
    }

    /// @notice The address authorized to sign sponsorship approvals
    address public verifyingSigner;

    /// @notice Event emitted when a user operation is sponsored
    /// @param userOpHash Hash of the sponsored user operation
    event UserOperationSponsored(bytes32 indexed userOpHash);

    /// @notice Error for invalid signature length
    error InvalidSignatureLength();

    /// @notice Error for renouncing ownership (disabled)
    error RenounceOwnershipDisabled();

    /// @notice Error for failed deposit
    error DepositFailed();

    /// @notice Constructor
    /// @param entryPoint The EntryPoint contract
    /// @param initialVerifyingSigner Address that can authorize sponsorships
    /// @param initialOwner Contract owner
    constructor(IEntryPoint entryPoint, address initialVerifyingSigner, address initialOwner)
        BasePaymaster(entryPoint, initialOwner)
    {
        _transferOwnership(initialOwner);
        verifyingSigner = initialVerifyingSigner;
    }

    /// @notice Receive ETH and deposit it into the EntryPoint
    receive() external payable {
        (bool success,) = payable(address(_entryPoint)).call{value: address(this).balance}("");
        if (!success) {
            revert DepositFailed();
        }
    }

    /// @notice Update the verifying signer
    /// @param newSigner New signer address
    function setVerifyingSigner(address newSigner) external onlyOwner {
        verifyingSigner = newSigner;
    }

    /// @notice Parse paymaster data from the paymasterAndData field
    /// @param paymasterAndData Raw paymaster data (after PAYMASTER_DATA_OFFSET)
    /// @return paymasterData Parsed data structure
    /// @return signature The signature bytes
    function parsePaymasterData(bytes calldata paymasterAndData)
        public
        pure
        returns (PaymasterData memory paymasterData, bytes calldata signature)
    {
        paymasterData.validUntil = uint48(bytes6(paymasterAndData[0:6]));
        paymasterData.validAfter = uint48(bytes6(paymasterAndData[6:12]));
        signature = paymasterAndData[12:77];
    }

    /// @notice Get the hash to be signed for authorization
    /// @param userOp The user operation
    /// @param paymasterData The paymaster data
    /// @return Hash to be signed
    function getHash(PackedUserOperation calldata userOp, PaymasterData memory paymasterData)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                calldataKeccak(userOp.initCode),
                calldataKeccak(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                paymasterData.validUntil,
                paymasterData.validAfter
            )
        );
    }

    /// @notice Validate a paymaster user operation
    /// @param userOp The user operation
    /// @param userOpHash Hash of the user operation
    /// @param maxCost Maximum cost of the operation
    /// @return context Context for postOp
    /// @return validationData Validation result and time range
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        // Silence unused variable warning
        maxCost;

        // 1. Parse the paymaster data
        (PaymasterData memory data, bytes calldata signature) =
            parsePaymasterData(userOp.paymasterAndData[UserOperationLib.PAYMASTER_DATA_OFFSET:]);

        // 2. Verify signature is exactly 65 bytes
        if (signature.length != 65) {
            revert InvalidSignatureLength();
        }

        // 3. Recover signer from signature
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(getHash(userOp, data));
        address recoveredSigner = ECDSA.recover(hash, signature);

        // 4. Check if signer is authorized
        if (recoveredSigner != verifyingSigner) {
            // Return validation failure
            return ("", _packValidationData(true, data.validUntil, data.validAfter));
        }

        // 5. Return success with context for postOp
        return (abi.encode(userOpHash), _packValidationData(false, data.validUntil, data.validAfter));
    }

    /// @notice Post-operation handler
    /// @param context Context from validation
    function _postOp(PostOpMode, bytes calldata context, uint256, uint256) internal override {
        bytes32 userOpHash = abi.decode(context, (bytes32));
        emit UserOperationSponsored(userOpHash);
    }

    /// @notice Transfer ownership (Ownable2Step override)
    /// @param newOwner New owner address
    function transferOwnership(address newOwner) public override(Ownable2Step) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    /// @notice Renounce ownership is disabled
    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    /// @notice Internal ownership transfer (Ownable2Step override)
    /// @param newOwner New owner address
    function _transferOwnership(address newOwner) internal override(Ownable2Step) {
        Ownable2Step._transferOwnership(newOwner);
    }
}
