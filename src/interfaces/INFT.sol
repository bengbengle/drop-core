// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMetadata} from "../interfaces/IMetadata.sol";

import {
    SignedMintValidationParams
} from "../lib/DropStructs.sol";

import {
    IERC165
} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

interface INFT is IMetadata, IERC165 {
    /**
     * @dev Revert with an error if a contract is not an allowed
     *      Drop address.
     */
    error OnlyAllowedDrop();

    /**
     * @dev Emit an event when allowed Drop contracts are updated.
     */
    event AllowedDropUpdated(address[] allowedDrop);

    /**
     * @notice Update the allowed Drop contracts.
     *         Only the owner or administrator can use this function.
     *
     * @param allowedDrop The allowed Drop addresses.
     */
    function updateAllowedDrop(address[] calldata allowedDrop) external;

    /**
     * @notice Mint tokens, restricted to the Drop contract.
     *
     * @dev    NOTE: If a token registers itself with multiple Drop
     *         contracts, the implementation of this function should guard
     *         against reentrancy. If the implementing token uses
     *         _safeMint(), or a feeRecipient with a malicious receive() hook
     *         is specified, the token or fee recipients may be able to execute
     *         another mint in the same transaction via a separate Drop
     *         contract.
     *         This is dangerous if an implementing token does not correctly
     *         update the minterNumMinted and currentTotalSupply values before
     *         transferring minted tokens, as Drop references these values
     *         to enforce token limits on a per-wallet and per-stage basis.
     *
     * @param minter   The address to mint to.
     * @param quantity The number of tokens to mint.
     */
    function mintDrop(address minter, uint256 quantity) external payable;

    /**
     * @notice Returns a set of mint stats for the address.
     *         This assists Drop in enforcing maxSupply,
     *         maxTotalMintableByWallet, and maxTokenSupplyForStage checks.
     *
     * @dev    NOTE: Implementing contracts should always update these numbers
     *         before transferring any tokens with _safeMint() to mitigate
     *         consequences of malicious onERC721Received() hooks.
     *
     * @param minter The minter address.
     */
    function getMintStats(address minter)
        external
        view
        returns (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply
        );


    /**
     * @notice Update the drop URI for this nft contract on Drop.
     *         Only the owner or administrator can use this function.
     *
     * @param DropImpl The allowed Drop contract.
     * @param dropURI     The new drop URI.
     */
    function updateDropURI(address DropImpl, string calldata dropURI) external;

    /**
     * @notice Update the creator payout address for this nft contract on Drop.
     *         Only the owner can set the creator payout address.
     *
     * @param DropImpl   The allowed Drop contract.
     * @param payoutAddress The new payout address.
     */
    function updateCreatorPayoutAddress(
        address DropImpl,
        address payoutAddress
    ) external;

    /**
     * @notice Update the allowed fee recipient for this nft contract
     *         on Drop.
     *         Only the administrator can set the allowed fee recipient.
     *
     * @param DropImpl  The allowed Drop contract.
     * @param feeRecipient The new fee recipient.
     */
    function updateAllowedFeeRecipient(
        address DropImpl,
        address feeRecipient,
        bool allowed
    ) external;

    /**
     * @notice Update the server-side signers for this nft contract
     *         on Drop.
     *         Only the owner or administrator can use this function.
     *
     * @param DropImpl                The allowed Drop contract.
     * @param signer                     The signer to update.
     * @param signedMintValidationParams Minimum and maximum parameters
     *                                   to enforce for signed mints.
     */
    function updateSignedMintValidationParams(
        address DropImpl,
        address signer,
        SignedMintValidationParams memory signedMintValidationParams
    ) external;

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
    ) external;
}
