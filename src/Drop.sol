// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IDrop } from "./interfaces/IDrop.sol";

import { INFT } from "./interfaces/INFT.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { IERC721 } from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import { IERC165 } from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import { ECDSA } from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import { MintParams, SignedMintValidationParams } from "./lib/DropStructs.sol";


contract Drop is IDrop, ReentrancyGuard {

    using ECDSA for bytes32;

    /// @notice Track the creator payout addresses.
    mapping(address => address) private _creatorPayoutAddresses;

    /// @notice Track the allowed fee recipients.
    mapping(address => mapping(address => bool)) private _allowedFeeRecipients;

    /// @notice Track the enumerated allowed fee recipients.
    mapping(address => address[]) private _enumeratedFeeRecipients;

    /// @notice Track the parameters for allowed signers for server-side drops.
    mapping(address => mapping(address => SignedMintValidationParams)) private _signedParams;

    /// @notice Track the signers for each server-side drop.
    mapping(address => address[]) private _enumeratedSigners;

    /// @notice Track the used signature digests.
    mapping(bytes32 => bool) private _usedDigests;

    /// @notice Track the allowed payers.
    mapping(address => mapping(address => bool)) private _allowedPayers;

    /// @notice Track the enumerated allowed payers.
    mapping(address => address[]) private _enumeratedPayers;

    /// @notice Track the tokens for token gated drops.
    mapping(address => address[]) private _enumeratedTokenGatedTokens;

    /// @notice Track the redeemed token IDs for token gated drop stages.
    mapping(address => mapping(address => mapping(uint256 => bool))) private _tokenGatedRedeemed;

    /// @notice Internal constants for EIP-712: Typed structured
    ///         data hashing and signing
    bytes32 internal constant _SIGNED_MINT_TYPEHASH =
        // prettier-ignore
        keccak256(
             "SignedMint("
                "address nftContract,"
                "address minter,"
                "address feeRecipient,"
                "MintParams mintParams,"
                "uint256 salt"
            ")"
            "MintParams("
                "uint256 mintPrice,"
                "uint256 maxTotalMintableByWallet,"
                "uint256 startTime,"
                "uint256 endTime,"
                "uint256 dropStageIndex,"
                "uint256 maxTokenSupplyForStage,"
                "uint256 feeBps,"
                "bool restrictFeeRecipients"
            ")"
        );
    bytes32 internal constant _MINT_PARAMS_TYPEHASH =
        // prettier-ignore
        keccak256(
            "MintParams("
                "uint256 mintPrice,"
                "uint256 maxTotalMintableByWallet,"
                "uint256 startTime,"
                "uint256 endTime,"
                "uint256 dropStageIndex,"
                "uint256 maxTokenSupplyForStage,"
                "uint256 feeBps,"
                "bool restrictFeeRecipients"
            ")"
        );
    bytes32 internal constant _EIP_712_DOMAIN_TYPEHASH =
        // prettier-ignore
        keccak256(
            "EIP712Domain("
                "string name,"
                "string version,"
                "uint256 chainId,"
                "address verifyingContract"
            ")"
        );
    bytes32 internal constant _NAME_HASH = keccak256("Drop");
    bytes32 internal constant _VERSION_HASH = keccak256("1.0");
    uint256 internal immutable _CHAIN_ID = block.chainid;
    bytes32 internal immutable _DOMAIN_SEPARATOR;
    
    uint256 internal constant _UNLIMITED_MAX_TOKEN_SUPPLY_FOR_STAGE = type(uint256).max;

    uint256 internal constant _PUBLIC_DROP_STAGE_INDEX = 0;

    /**
     * @notice Ensure only tokens implementing INFT can call the update methods.
     */
    modifier onlyINFT() virtual {
        if (
            !IERC165(msg.sender).supportsInterface(type(INFT).interfaceId)
        ) {
            revert OnlyINFT(msg.sender);
        }
        _;
    }

    /**
     * @notice Constructor for the contract deployment.
     */
    constructor() {
        // Derive the domain separator.
        _DOMAIN_SEPARATOR = _deriveDomainSeparator();
    }

    /**
     * @notice Mint with a server-side signature.
     *         Note that a signature can only be used once.
     *
     * @param nftContract      The nft contract to mint.
     * @param feeRecipient     The fee recipient.
     * @param minterIfNotPayer The mint recipient if different than the payer.
     * @param quantity         The number of tokens to mint.
     * @param mintParams       The mint parameters.
     * @param salt             The salt for the signed mint.
     * @param signature        The server-side signature, must be an allowed signer.
     */
    function mintSigned(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity,
        MintParams calldata mintParams,
        uint256 salt,
        bytes calldata signature
    ) external payable override {
        // Check that the drop stage is active.
        _checkActive(mintParams.startTime, mintParams.endTime);

        // Validate payment is correct for number minted.
        _checkCorrectPayment(quantity, mintParams.mintPrice);

        // Get the minter address.
        address minter = minterIfNotPayer != address(0) ? minterIfNotPayer : msg.sender;

        // Ensure the payer is allowed if not the minter.
        if (minter != msg.sender) {
            if (!_allowedPayers[nftContract][msg.sender]) {
                revert PayerNotAllowed();
            }
        }

        // Check that the minter is allowed to mint the desired quantity.
        _checkMintQuantity(
            nftContract,
            minter,
            quantity,
            mintParams.maxTotalMintableByWallet,
            mintParams.maxTokenSupplyForStage
        );

        // Check that the fee recipient is allowed if restricted.
        // _checkFeeRecipientIsAllowed(nftContract, feeRecipient, mintParams.restrictFeeRecipients);

        // Validate the signature in a block scope to avoid "stack too deep".
        {
            // Get the digest to verify the EIP-712 signature.
            bytes32 digest = _getDigest(nftContract, minter, feeRecipient, mintParams, salt);

            // Ensure the digest has not already been used.
            if (_usedDigests[digest]) {
                revert SignatureAlreadyUsed();
            }

            // Mark the digest as used.
            _usedDigests[digest] = true;

            // Use the recover method to see what address was used to create
            // the signature on this data.
            // Note that if the digest doesn't exactly match what was signed we'll
            // get a random recovered address.
            address recoveredAddress = digest.recover(signature);
            _validateSignerAndParams(nftContract, mintParams, recoveredAddress);
        }

        // Mint the token(s), split the payout, emit an event.
        _mintAndPay(
            nftContract,
            minter,
            quantity,
            mintParams.mintPrice,
            mintParams.dropStageIndex,
            mintParams.feeBps,
            feeRecipient
        );
    }

    /**
     * @notice Enforce stored parameters for signed mints to mitigate the effects of a malicious signer.
     * @notice 强制存储的参数以减轻恶意签名者的影响
     */
    function _validateSignerAndParams(address nftContract, MintParams memory mintParams, address signer) 
        internal 
        view 
    {

        SignedMintValidationParams memory signedParams = _signedParams[nftContract][signer];

        // Check that SignedMintValidationParams have been initialized; if not, this is an invalid signer.
        // 检查 SignedMintValidationParams 是否已经初始化；如果不是，这是一个无效的签名者
        if (signedParams.maxMaxTotalMintableByWallet == 0) {
            revert InvalidSignature(signer);
        }

        // Validate individual params.
        if (mintParams.mintPrice < signedParams.minMintPrice) {

            revert InvalidSignedMintPrice(mintParams.mintPrice, signedParams.minMintPrice);
        }
        if (mintParams.maxTotalMintableByWallet > signedParams.maxMaxTotalMintableByWallet) {

            revert InvalidSignedMaxTotalMintableByWallet(mintParams.maxTotalMintableByWallet, signedParams.maxMaxTotalMintableByWallet);
        
        }
        if (mintParams.startTime < signedParams.minStartTime) {

            revert InvalidSignedStartTime(mintParams.startTime, signedParams.minStartTime);
        
        }
        if (mintParams.endTime > signedParams.maxEndTime) {

            revert InvalidSignedEndTime(mintParams.endTime, signedParams.maxEndTime);
        
        }
        if (
            mintParams.maxTokenSupplyForStage > signedParams.maxMaxTokenSupplyForStage
        ) {
            revert InvalidSignedMaxTokenSupplyForStage(
                mintParams.maxTokenSupplyForStage,
                signedParams.maxMaxTokenSupplyForStage
            );
        }
        if (mintParams.feeBps > signedParams.maxFeeBps) {
            revert InvalidSignedFeeBps(
                mintParams.feeBps,
                signedParams.maxFeeBps
            );
        }
        if (mintParams.feeBps < signedParams.minFeeBps) {
            revert InvalidSignedFeeBps(
                mintParams.feeBps,
                signedParams.minFeeBps
            );
        }
        if (!mintParams.restrictFeeRecipients) {
            revert SignedMintsMustRestrictFeeRecipients();
        }
    }


    /**
     * @notice Check that the drop stage is active.
     *
     * @param startTime The drop stage start time.
     * @param endTime   The drop stage end time.
     */
    function _checkActive(uint256 startTime, uint256 endTime) internal view {
        if (block.timestamp < startTime || block.timestamp > endTime) {
            // Revert if the drop stage is not active.
            revert NotActive(block.timestamp, startTime, endTime);
        }
    }

    /**
     * @notice Check that the fee recipient is allowed.
     *
     * @param nftContract           The nft contract.
     * @param feeRecipient          The fee recipient.
     * @param restrictFeeRecipients If the fee recipients are restricted.
     */
    function _checkFeeRecipientIsAllowed(
        address nftContract,
        address feeRecipient,
        bool restrictFeeRecipients
    ) internal view {
        // Ensure the fee recipient is not the zero address.
        if (feeRecipient == address(0)) {
            revert FeeRecipientCannotBeZeroAddress();
        }

        // Revert if the fee recipient is restricted and not allowed.
        if (restrictFeeRecipients)
            if (!_allowedFeeRecipients[nftContract][feeRecipient]) {
                revert FeeRecipientNotAllowed();
            }
    }

    /**
     * @notice Check that the wallet is allowed to mint the desired quantity.
     *
     * @param nftContract              The nft contract.
     * @param minter                   The mint recipient.
     * @param quantity                 The number of tokens to mint.
     * @param maxTotalMintableByWallet The max allowed mints per wallet.
     * @param maxTokenSupplyForStage   The max token supply for the drop stage.
     */
    function _checkMintQuantity(
        address nftContract,
        address minter,
        uint256 quantity,
        uint256 maxTotalMintableByWallet,
        uint256 maxTokenSupplyForStage
    ) internal view {
        // Mint quantity of zero is not valid.
        if (quantity == 0) {
            revert MintQuantityCannotBeZero();
        }

        // Get the mint stats.
        (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply
        ) = INFT(nftContract).getMintStats(minter);

        // Ensure mint quantity doesn't exceed maxTotalMintableByWallet.
        if (quantity + minterNumMinted > maxTotalMintableByWallet) {
            revert MintQuantityExceedsMaxMintedPerWallet(
                quantity + minterNumMinted,
                maxTotalMintableByWallet
            );
        }

        // Ensure mint quantity doesn't exceed maxSupply.
        if (quantity + currentTotalSupply > maxSupply) {
            revert MintQuantityExceedsMaxSupply(
                quantity + currentTotalSupply,
                maxSupply
            );
        }

        // Ensure mint quantity doesn't exceed maxTokenSupplyForStage.
        if (quantity + currentTotalSupply > maxTokenSupplyForStage) {
            revert MintQuantityExceedsMaxTokenSupplyForStage(
                quantity + currentTotalSupply,
                maxTokenSupplyForStage
            );
        }
    }

    /**
     * @notice Revert if the payment is not the quantity times the mint price.
     *
     * @param quantity  The number of tokens to mint.
     * @param mintPrice The mint price per token.
     */
    function _checkCorrectPayment(uint256 quantity, uint256 mintPrice)
        internal
        view
    {
        // Revert if the tx's value doesn't match the total cost.
        if (msg.value != quantity * mintPrice) {
            revert IncorrectPayment(msg.value, quantity * mintPrice);
        }
    }

    /**
     * @notice Split the payment payout for the creator and fee recipient.
     *
     * @param nftContract  The nft contract.
     * @param feeRecipient The fee recipient.
     * @param feeBps       The fee basis points.
     */
    function _splitPayout(
        address nftContract,
        address feeRecipient,
        uint256 feeBps
    ) internal {
        // Revert if the fee basis points is greater than 10_000.
        if (feeBps > 10_000) {
            revert InvalidFeeBps(feeBps);
        }

        // Get the creator payout address.
        address creatorPayoutAddress = _creatorPayoutAddresses[nftContract];            // 获取创作者支付地址

        // Ensure the creator payout address is not the zero address.
        if (creatorPayoutAddress == address(0)) {
            revert CreatorPayoutAddressCannotBeZeroAddress();
        }

        // msg.value has already been validated by this point, so can use it directly.

        // If the fee is zero, just transfer to the creator and return.
        if (feeBps == 0) {
            SafeTransferLib.safeTransferETH(creatorPayoutAddress, msg.value);
            return;
        }

        // Get the fee amount.
        // Note that the fee amount is rounded down in favor of the creator.
        uint256 feeAmount = (msg.value * feeBps) / 10_000;

        // Get the creator payout amount. Fee amount is <= msg.value per above.
        uint256 payoutAmount;
        unchecked {
            payoutAmount = msg.value - feeAmount;
        }

        // Transfer the fee amount to the fee recipient.
        if (feeAmount > 0) {
            SafeTransferLib.safeTransferETH(feeRecipient, feeAmount);
        }

        // Transfer the creator payout amount to the creator.
        SafeTransferLib.safeTransferETH(creatorPayoutAddress, payoutAmount);
    }

    /**
     * @notice Mints a number of tokens, splits the payment,
     *         and emits an event.
     *
     * @param nftContract    The nft contract.
     * @param minter         The mint recipient.
     * @param quantity       The number of tokens to mint.
     * @param mintPrice      The mint price per token.
     * @param dropStageIndex The drop stage index.
     * @param feeBps         The fee basis points.
     * @param feeRecipient   The fee recipient.
     */
    function _mintAndPay(
        address nftContract,
        address minter,
        uint256 quantity,
        uint256 mintPrice,
        uint256 dropStageIndex,
        uint256 feeBps,
        address feeRecipient
    ) internal nonReentrant {
        // Mint the token(s).
        INFT(nftContract).mintDrop(minter, quantity);

        if (mintPrice != 0) {
            // Split the payment between the creator and fee recipient.
            _splitPayout(nftContract, feeRecipient, feeBps);
        }

        // Emit an event for the mint.
        emit DropMint(
            nftContract,
            minter,
            feeRecipient,
            msg.sender,
            quantity,
            mintPrice,
            feeBps,
            dropStageIndex
        );
    }

    /**
     * @dev Internal view function to get the EIP-712 domain separator. If the
     *      chainId matches the chainId set on deployment, the cached domain
     *      separator will be returned; otherwise, it will be derived from
     *      scratch.
     *
     * @return The domain separator.
     */
    function _domainSeparator() internal view returns (bytes32) {
        // prettier-ignore
        return block.chainid == _CHAIN_ID
            ? _DOMAIN_SEPARATOR
            : _deriveDomainSeparator();
    }

    /**
     * @dev Internal view function to derive the EIP-712 domain separator.
     *
     * @return The derived domain separator.
     */
    function _deriveDomainSeparator() internal view returns (bytes32) {
        // prettier-ignore
        return keccak256(
            abi.encode(
                _EIP_712_DOMAIN_TYPEHASH,
                _NAME_HASH,
                _VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Returns the creator payout address for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getCreatorPayoutAddress(address nftContract)
        external
        view
        returns (address)
    {
        return _creatorPayoutAddresses[nftContract];
    }


    /**
     * @notice Returns if the specified fee recipient is allowed
     *         for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getFeeRecipientIsAllowed(address nftContract, address feeRecipient)
        external
        view
        returns (bool)
    {
        return _allowedFeeRecipients[nftContract][feeRecipient];
    }

    /**
     * @notice Returns an enumeration of allowed fee recipients for an
     *         nft contract when fee recipients are enforced.
     *
     * @param nftContract The nft contract.
     */
    function getAllowedFeeRecipients(address nftContract)
        external
        view
        returns (address[] memory)
    {
        return _enumeratedFeeRecipients[nftContract];
    }

    /**
     * @notice Returns the server-side signers for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getSigners(address nftContract)
        external
        view
        returns (address[] memory)
    {
        return _enumeratedSigners[nftContract];
    }

    /**
     * @notice Returns the struct of SignedMintValidationParams for a signer.
     *
     * @param nftContract The nft contract.
     * @param signer      The signer.
     */
    function getSignedMintValidationParams(address nftContract, address signer)
        external
        view
        returns (SignedMintValidationParams memory)
    {
        return _signedParams[nftContract][signer];
    }

    /**
     * @notice Returns the payers for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getPayers(address nftContract)
        external
        view
        returns (address[] memory)
    {
        return _enumeratedPayers[nftContract];
    }

    /**
     * @notice Returns if the specified payer is allowed
     *         for the nft contract.
     *
     * @param nftContract The nft contract.
     * @param payer       The payer.
     */
    function getPayerIsAllowed(address nftContract, address payer)
        external
        view
        returns (bool)
    {
        return _allowedPayers[nftContract][payer];
    }

    /**
     * @notice Returns the allowed token gated drop tokens for the nft contract.
     *
     * @param nftContract The nft contract.
     */
    function getTokenGatedAllowedTokens(address nftContract)
        external
        view
        returns (address[] memory)
    {
        return _enumeratedTokenGatedTokens[nftContract];
    }

     

    /**
     * @notice Returns whether the token id for a token gated drop has been
     *         redeemed.
     *
     * @param nftContract       The nft contract.
     * @param allowedNftToken   The token gated nft token.
     * @param allowedNftTokenId The token gated nft token id to check.
     */
    function getAllowedNftTokenIdIsRedeemed(
        address nftContract,
        address allowedNftToken,
        uint256 allowedNftTokenId
    ) external view returns (bool) {
        return
            _tokenGatedRedeemed[nftContract][allowedNftToken][
                allowedNftTokenId
            ];
    }

    /**
     * @notice Emits an event to notify update of the drop URI.
     *
     * @param dropURI The new drop URI.
     */
    function updateDropURI(string calldata dropURI)
        external
        onlyINFT
    {
        // Emit an event with the update.
        emit DropURIUpdated(msg.sender, dropURI);
    }

 
    /**
     * @notice Updates the creator payout address and emits an event.   // 更新创建者支付地址并发出事件
     *
     * @param _payoutAddress The creator payout address.
     */
    function updateCreatorPayoutAddress(address _payoutAddress) 
        external 
        onlyINFT
    {
        if (_payoutAddress == address(0)) {
            revert CreatorPayoutAddressCannotBeZeroAddress();
        }

        // Set the creator payout address.
        _creatorPayoutAddresses[msg.sender] = _payoutAddress;

        // Emit an event with the update.
        emit CreatorPayoutAddressUpdated(msg.sender, _payoutAddress);
    }

    /**
     * @notice Updates the allowed fee recipient and emits an event.        // 更新允许的费用接收者并发出事件
     *
     * @param feeRecipient The fee recipient.
     * @param allowed      If the fee recipient is allowed.
     */
    function updateAllowedFeeRecipient(address feeRecipient, bool allowed)
        external
        onlyINFT
    {
        if (feeRecipient == address(0)) {
            revert FeeRecipientCannotBeZeroAddress();
        }

        // Track the enumerated storage.
        address[] storage enumeratedStorage = _enumeratedFeeRecipients[
            msg.sender
        ];
        mapping(address => bool)
            storage feeRecipientsMap = _allowedFeeRecipients[msg.sender];

        if (allowed) {
            if (feeRecipientsMap[feeRecipient]) {
                revert DuplicateFeeRecipient();
            }
            feeRecipientsMap[feeRecipient] = true;
            enumeratedStorage.push(feeRecipient);
        } else {
            if (!feeRecipientsMap[feeRecipient]) {
                revert FeeRecipientNotPresent();
            }
            delete _allowedFeeRecipients[msg.sender][feeRecipient];
            _removeFromEnumeration(feeRecipient, enumeratedStorage);
        }

        // Emit an event with the update.
        emit AllowedFeeRecipientUpdated(msg.sender, feeRecipient, allowed);
    }

    /**
     * @notice Updates the allowed server-side signers and emits an event. 
     *
     * @param signer                     The signer to update.
     * @param signedParams Minimum and maximum parameters
     *                                   to enforce for signed mints.
     */
    function updateSignedMintValidationParams(address signer, SignedMintValidationParams calldata signedParams) 
        external 
        onlyINFT 
    {
        if (signer == address(0)) {
            revert SignerCannotBeZeroAddress();
        }

        if (signedParams.minFeeBps > 10_000) {
            revert InvalidFeeBps(signedParams.minFeeBps);
        }
        
        if (signedParams.maxFeeBps > 10_000) {
            revert InvalidFeeBps(signedParams.maxFeeBps);
        }

        // Track the enumerated storage.
        address[] storage enumeratedStorage = _enumeratedSigners[msg.sender];

        mapping(address => SignedMintValidationParams) storage signedParamsMap = _signedParams[msg.sender];

        SignedMintValidationParams storage existingSignedMintValidationParams = signedParamsMap[signer];

        bool signedParamsDoNotExist;
        assembly {
            signedParamsDoNotExist := iszero(sload(existingSignedMintValidationParams.slot))
        }
        // Use maxMaxTotalMintableByWallet as sentry for add/update or delete.
        bool addOrUpdate = signedParams.maxMaxTotalMintableByWallet > 0;

        if (addOrUpdate) {
            signedParamsMap[signer] = signedParams;
            if (signedParamsDoNotExist) {
                enumeratedStorage.push(signer);
            }
        } else {
            if (
                existingSignedMintValidationParams.maxMaxTotalMintableByWallet == 0
            ) {
                revert SignerNotPresent();
            }
            delete _signedParams[msg.sender][signer];
            _removeFromEnumeration(signer, enumeratedStorage);
        }

        // Emit an event with the update.
        emit SignedMintValidationParamsUpdated(
            msg.sender,
            signer,
            signedParams
        );
    }

    /**
     * @notice Updates the allowed payer and emits an event.
     *
     * @param payer  The payer to add or remove.
     * @param allowed Whether to add or remove the payer.
     */
    function updatePayer(address payer, bool allowed)
        external
        onlyINFT
    {
        if (payer == address(0)) {
            revert PayerCannotBeZeroAddress();
        }

        // Track the enumerated storage.
        address[] storage enumeratedStorage = _enumeratedPayers[msg.sender];
        mapping(address => bool) storage payersMap = _allowedPayers[msg.sender];

        if (allowed) {
            if (payersMap[payer]) {
                revert DuplicatePayer();
            }
            payersMap[payer] = true;
            enumeratedStorage.push(payer);
        } else {
            if (!payersMap[payer]) {
                revert PayerNotPresent();
            }
            delete _allowedPayers[msg.sender][payer];
            _removeFromEnumeration(payer, enumeratedStorage);
        }

        // Emit an event with the update.
        emit PayerUpdated(msg.sender, payer, allowed);
    }

    /**
     * @notice Remove an address from a supplied enumeration.
     *
     * @param toRemove    The address to remove.
     * @param enumeration The enumerated addresses to parse.
     */
    function _removeFromEnumeration(
        address toRemove,
        address[] storage enumeration
    ) internal {
        // Cache the length.
        uint256 enumerationLength = enumeration.length;
        for (uint256 i = 0; i < enumerationLength; ) {
            // Check if the enumerated element is the one we are deleting.
            if (enumeration[i] == toRemove) {
                // Swap with the last element.
                enumeration[i] = enumeration[enumerationLength - 1];
                // Delete the (now duplicated) last element.
                enumeration.pop();
                // Exit the loop.
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Verify an EIP-712 signature by recreating the data structure
     *         that we signed on the client side, and then using that to recover
     *         the address that signed the signature for this data.
     *
     * @param nftContract  The nft contract.
     * @param minter       The mint recipient.
     * @param feeRecipient The fee recipient.
     * @param mintParams   The mint params.
     * @param salt         The salt for the signed mint.
     */
    function _getDigest(
        address nftContract,
        address minter,
        address feeRecipient,
        MintParams memory mintParams,
        uint256 salt
    ) internal view returns (bytes32 digest) {
        bytes32 mintParamsHashStruct = keccak256(
            abi.encode(
                _MINT_PARAMS_TYPEHASH,
                mintParams.mintPrice,
                mintParams.maxTotalMintableByWallet,
                mintParams.startTime,
                mintParams.endTime,
                mintParams.dropStageIndex,
                mintParams.maxTokenSupplyForStage,
                mintParams.feeBps,
                mintParams.restrictFeeRecipients
            )
        );
        digest = keccak256(
            bytes.concat(
                bytes2(0x1901),
                _domainSeparator(),
                keccak256(
                    abi.encode(
                        _SIGNED_MINT_TYPEHASH,
                        nftContract,
                        minter,
                        feeRecipient,
                        mintParamsHashStruct,
                        salt
                    )
                )
            )
        );
    }
}
