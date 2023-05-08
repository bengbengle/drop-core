// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { NFTDrop } from "./NFTDrop.sol";
import { IDrop } from "./interfaces/IDrop.sol";
import { TwoStepAdministered } from "utility-contracts/TwoStepAdministered.sol";

import { AllowListData, PublicDrop, TokenGatedDropStage, SignedMintValidationParams } from "./lib/DropStructs.sol";

/**
 * @title  NFT
 * @notice NFT is a token contract that contains methods
 *         to properly interact with Drop, with additional administrative
 *         functionality tailored for business requirements around partnered
 *         mints with off-chain agreements in place between two parties.
 *
 *         The "Owner" should control mint specifics such as price and start.
 *         The "Administrator" should control fee parameters.
 *
 *         Otherwise, for ease of administration, either Owner or Administrator
 *         should be able to configure mint parameters. They have the ability
 *         to override each other's actions in many circumstances, which is
 *         why the establishment of off-chain trust is important.
 *
 *         Note: An Administrator is not required to interface with Drop.
 */
contract NFT is NFTDrop, TwoStepAdministered {
    /// @notice 为了防止所有者覆盖费用, 管理员必须首先用费用 初始化
    error AdministratorMustInitializeWithFee();

    /**
     * @notice Deploy the token contract with its name, symbol,
     *         administrator, and allowed Drop addresses.
     */
    constructor(string memory name, string memory symbol, address administrator, address[] memory allowedDrop)
        NFTDrop(name, symbol, allowedDrop)
        TwoStepAdministered(administrator)
    {}

    /**
     * @notice Update the allowed Drop contracts.
     *         Only the owner or administrator can use this function.
     *
     * @param allowedDrop The allowed Drop addresses.
     */
    function updateAllowedDrop(address[] calldata allowedDrop)
        external
        override
        onlyOwnerOrAdministrator
    {
        _updateAllowedDrop(allowedDrop);
    }


    /**
     * @notice Update the drop URI for this nft contract on Drop.
     *         Only the owner or administrator can use this function.
     *
     * @param DropImpl The allowed Drop contract.
     * @param dropURI     The new drop URI.
     */
    function updateDropURI(address DropImpl, string calldata dropURI)
        external
        virtual
        override
        onlyOwnerOrAdministrator
    {
        // Update the drop URI.
        IDrop(DropImpl).updateDropURI(dropURI);
    }

    /**
     * @notice Update the allowed fee recipient for this nft contract on Drop.
     *         Only the administrator can set the allowed fee recipient.
     *
     * @param DropImpl  The allowed Drop contract.
     * @param feeRecipient The new fee recipient.
     * @param allowed      If the fee recipient is allowed.
     */
    function updateAllowedFeeRecipient(address DropImpl, address feeRecipient, bool allowed) 
        external 
        override 
        onlyAdministrator 
    {
        // Update the allowed fee recipient.
        IDrop(DropImpl).updateAllowedFeeRecipient(feeRecipient, allowed);
    }

    /**
     * @notice Update the server-side signers for this nft contract on Drop.
     *         Only the owner or administrator can use this function.
     *
     * @param DropImpl                The allowed Drop contract.
     * @param signer                     The signer to update.
     * @param signedMintValidationParams Minimum and maximum parameters to enforce for signed mints.
     */
    function updateSignedMintValidationParams(
        address DropImpl,
        address signer,
        SignedMintValidationParams memory signedMintValidationParams
    )
        external
        virtual
        override
        onlyOwnerOrAdministrator
    {
        // Track the newly supplied params
        SignedMintValidationParams memory supplied = signedMintValidationParams;
 
        // Update the signed mint validation params.
        IDrop(DropImpl).updateSignedMintValidationParams(signer, supplied);
    }

    /**
     * @notice Update the allowed payers for this nft contract on Drop.
     *         Only the owner or administrator can use this function.
     *
     * @param DropImpl The allowed Drop contract.
     * @param payer       The payer to update.
     * @param allowed     Whether the payer is allowed.
     */
    function updatePayer(
        address DropImpl,
        address payer,
        bool allowed
    )
        external
        virtual
        override
        onlyOwnerOrAdministrator
    {
        // Update the payers.
        IDrop(DropImpl).updatePayer(payer, allowed);
    }
}
