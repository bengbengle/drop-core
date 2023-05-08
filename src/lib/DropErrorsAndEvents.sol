// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { PublicDrop, TokenGatedDropStage, SignedMintValidationParams } from "./DropStructs.sol";

interface DropErrorsAndEvents {

    error NotActive(
        uint256 currentTimestamp,
        uint256 startTimestamp,
        uint256 endTimestamp
    );

    error MintQuantityCannotBeZero();
    error MintQuantityExceedsMaxMintedPerWallet(uint256 total, uint256 allowed);
    error MintQuantityExceedsMaxSupply(uint256 total, uint256 maxSupply);
    error MintQuantityExceedsMaxTokenSupplyForStage(uint256 total, uint256 maxTokenSupplyForStage);
    error FeeRecipientCannotBeZeroAddress();
    error FeeRecipientNotPresent();
     error InvalidFeeBps(uint256 feeBps);
    error DuplicateFeeRecipient();
    error FeeRecipientNotAllowed();
    error CreatorPayoutAddressCannotBeZeroAddress();
    error IncorrectPayment(uint256 got, uint256 want);
    error InvalidProof();
    error SignerCannotBeZeroAddress();
    error InvalidSignature(address recoveredSigner);
    error SignerNotPresent();
    error PayerNotPresent();
    error DuplicatePayer();
    error PayerNotAllowed();
    error PayerCannotBeZeroAddress();
    error OnlyINFT(address sender);

    error TokenGatedNotTokenOwner(
        address nftContract,
        address allowedNftToken,
        uint256 allowedNftTokenId
    );
    
    error TokenGatedTokenIdAlreadyRedeemed(
        address nftContract,
        address allowedNftToken,
        uint256 allowedNftTokenId
    );
 
    error TokenGatedDropStageNotPresent();
    
    error TokenGatedDropAllowedNftTokenCannotBeZeroAddress();
    
    error TokenGatedDropAllowedNftTokenCannotBeDropToken();

    error InvalidSignedMintPrice(uint256 got, uint256 minimum);

    error InvalidSignedMaxTotalMintableByWallet(uint256 got, uint256 maximum);

    error InvalidSignedStartTime(uint256 got, uint256 minimum);

    error InvalidSignedEndTime(uint256 got, uint256 maximum);

    error InvalidSignedMaxTokenSupplyForStage(uint256 got, uint256 maximum);
    
    error InvalidSignedFeeBps(uint256 got, uint256 minimumOrMaximum);

    error SignedMintsMustRestrictFeeRecipients();

    error SignatureAlreadyUsed();

    event DropMint(
        address indexed nftContract,
        address indexed minter,
        address indexed feeRecipient,
        address payer,
        uint256 quantityMinted,
        uint256 unitMintPrice,
        uint256 feeBps,
        uint256 dropStageIndex
    );

    event PublicDropUpdated(
        address indexed nftContract,
        PublicDrop publicDrop
    );

   
    event TokenGatedDropStageUpdated(
        address indexed nftContract,
        address indexed allowedNftToken,
        TokenGatedDropStage dropStage
    );

    event AllowListUpdated(
        address indexed nftContract,
        bytes32 indexed previousMerkleRoot,
        bytes32 indexed newMerkleRoot,
        string[] publicKeyURI,
        string allowListURI
    );
  
    event DropURIUpdated(address indexed nftContract, string newDropURI);
   
    event CreatorPayoutAddressUpdated(
        address indexed nftContract,
        address indexed newPayoutAddress
    );

    event AllowedFeeRecipientUpdated(
        address indexed nftContract,
        address indexed feeRecipient,
        bool indexed allowed
    );

    event SignedMintValidationParamsUpdated(
        address indexed nftContract,
        address indexed signer,
        SignedMintValidationParams signedMintValidationParams
    );   

    event PayerUpdated(
        address indexed nftContract,
        address indexed payer,
        bool indexed allowed
    );
}
