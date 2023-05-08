// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IDrop } from "./interfaces/IDrop.sol";

import { INFT } from "./interfaces/INFT.sol";
import { NFTMetadata, IMetadata } from "./NFTMetadata.sol";
import { AllowListData, PublicDrop, TokenGatedDropStage, SignedMintValidationParams } from "./lib/DropStructs.sol";

import { ERC721A } from "ERC721A/ERC721A.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { IERC165 } from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/**
 * @title  NFTDrop
 * @notice NFTDrop 是一个 代币合约, 其中包含与 Drop 正确交互的方法
 */
contract NFTDrop is NFTMetadata, INFT, ReentrancyGuard {

    /// @notice 如果 mint 超过最大供应量，则返回错误。
    error MintQuantityExceedsMaxSupply(uint256 total, uint256 maxSupply);

    /// @notice 跟踪允许的 Drop 地址
    mapping(address => bool) internal _allowedDrop;

    /// @notice 跟踪枚举的允许的 Drop 地址。
    address[] internal _enumeratedAllowedDrop;

    /**
     * @notice 限定访问权限的修饰符, 允许的 Drop 合约
     */
    modifier onlyAllowedDrop(address Drop) {
        if (_allowedDrop[Drop] != true) {
            revert OnlyAllowedDrop();
        }
        _;
    }

    /**
     * @notice Deploy the token contract with its name, symbol,
     *         and allowed Drop addresses.
     */
    constructor(string memory name, string memory symbol, address[] memory allowedDrop) 
        NFTMetadata(name, symbol) 
    {
        // Put the length on the stack for more efficient access.
        uint256 allowedDropLength = allowedDrop.length;

        // Set the mapping for allowed Drop contracts.
        for (uint256 i = 0; i < allowedDropLength; ) {
            _allowedDrop[allowedDrop[i]] = true;
            unchecked {
                ++i;
            }
        }

        // Set the enumeration.
        _enumeratedAllowedDrop = allowedDrop;
    }

    /**
     * @notice Update the allowed Drop contracts.
     *         Only the owner or administrator can use this function.
     *
     * @param allowedDrop The allowed Drop addresses.
     */
    function updateAllowedDrop(address[] calldata allowedDrop)
        external
        virtual
        override
        onlyOwner
    {
        _updateAllowedDrop(allowedDrop);
    }

    /**
     * @notice Internal function to update the allowed Drop contracts.
     *
     * @param allowedDrop The allowed Drop addresses.
     */
    function _updateAllowedDrop(address[] calldata allowedDrop) internal {
        // Put the length on the stack for more efficient access.
        uint256 enumeratedAllowedDropLength = _enumeratedAllowedDrop.length;
        uint256 allowedDropLength = allowedDrop.length;

        // Reset the old mapping.
        for (uint256 i = 0; i < enumeratedAllowedDropLength; ) {
            _allowedDrop[_enumeratedAllowedDrop[i]] = false;
            unchecked {
                ++i;
            }
        }

        // Set the new mapping for allowed Drop contracts.
        for (uint256 i = 0; i < allowedDropLength; ) {
            _allowedDrop[allowedDrop[i]] = true;
            unchecked {
                ++i;
            }
        }

        // Set the enumeration.
        _enumeratedAllowedDrop = allowedDrop;

        // Emit an event for the update.
        emit AllowedDropUpdated(allowedDrop);
    }

    /**
     * @dev Overrides the `_startTokenId` function from ERC721A
     *      to start at token id `1`.
     *
     *      This is to avoid future possible problems since `0` is usually
     *      used to signal values that have not been set or have been removed.
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

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
     *         ERC721A tracks these values automatically, but this note and
     *         nonReentrant modifier are left here to encourage best-practices
     *         when referencing this contract.
     *
     * @param minter   The address to mint to.
     * @param quantity The number of tokens to mint.
     */
    function mintDrop(address minter, uint256 quantity)
        external
        payable
        virtual
        override
        onlyAllowedDrop(msg.sender)
        nonReentrant
    {
        // Extra safety check to ensure the max supply is not exceeded.
        if (_totalMinted() + quantity > maxSupply()) {
            revert MintQuantityExceedsMaxSupply(
                _totalMinted() + quantity,
                maxSupply()
            );
        }

        // Mint the quantity of tokens to the minter.
        _safeMint(minter, quantity);
    }

  
    /**
     * @notice Update the drop URI for this nft contract on Drop.
     *         Only the owner can use this function.
     *
     * @param DropImpl The allowed Drop contract.
     * @param dropURI     The new drop URI.
     */
    function updateDropURI(address DropImpl, string calldata dropURI)
        external
        virtual
        override
        onlyOwner
        onlyAllowedDrop(DropImpl)
    {
        // Update the drop URI.
        IDrop(DropImpl).updateDropURI(dropURI);
    }

    /**
     * @notice Update the creator payout address for this nft contract on Drop.         // 更新收款地址
     *         Only the owner can set the creator payout address.                       // 只有合约拥有者可以设置收款地址
     *
     * @param DropImpl   The allowed Drop contract.                                     // Drop 合约
     * @param payoutAddress The new payout address.                                     // 收款地址
     */
    function updateCreatorPayoutAddress(address DropImpl, address payoutAddress) 
        external 
        onlyOwner 
        onlyAllowedDrop(DropImpl) 
    {
        // Update the creator payout address.
        IDrop(DropImpl).updateCreatorPayoutAddress(payoutAddress);
    }

    /**
     * @notice Update the allowed fee recipient for this nft contract
     *         on Drop.
     *         Only the owner can set the allowed fee recipient.
     *
     * @param DropImpl  The allowed Drop contract.
     * @param feeRecipient The new fee recipient.
     * @param allowed      If the fee recipient is allowed.
     */
    function updateAllowedFeeRecipient(
        address DropImpl,
        address feeRecipient,
        bool allowed
    ) external virtual onlyOwner onlyAllowedDrop(DropImpl) {
        // Update the allowed fee recipient.
        IDrop(DropImpl).updateAllowedFeeRecipient(feeRecipient, allowed);
    }

    /**
     * @notice Update the server-side signers for this nft contract
     *         on Drop.
     *         Only the owner can use this function.
     *
     * @param DropImpl                The allowed Drop contract.
     * @param signer                     The signer to update.
     * @param signedMintValidationParams Minimum and maximum parameters to
     *                                   enforce for signed mints.
     */
    function updateSignedMintValidationParams(
        address DropImpl,
        address signer,
        SignedMintValidationParams memory signedMintValidationParams
    ) external virtual override onlyOwner onlyAllowedDrop(DropImpl) {
        // Update the signer.
        IDrop(DropImpl).updateSignedMintValidationParams(signer, signedMintValidationParams);
    }

    /**
     * @notice Update the allowed payers for this nft contract on Drop.
     *         Only the owner can use this function.
     *
     * @param DropImpl The allowed Drop contract.
     * @param payer       The payer to update.
     * @param allowed     Whether the payer is allowed.
     */
    function updatePayer(
        address DropImpl,
        address payer,
        bool allowed
    ) external virtual override onlyOwner onlyAllowedDrop(DropImpl) {
        // Update the signers.
        IDrop(DropImpl).updatePayer(payer, allowed);
    }

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
        override
        returns (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply
        )
    {
        minterNumMinted = _numberMinted(minter);
        currentTotalSupply = _totalMinted();
        maxSupply = _maxSupply;
    }

    /**
     * @notice Returns whether the interface is supported.
     *
     * @param interfaceId The interface id to check against.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC721A)
        returns (bool)
    {
        return
            interfaceId == type(INFT).interfaceId ||
            interfaceId == type(IMetadata).interfaceId ||
            // ERC721A returns supportsInterface true for
            // ERC165, ERC721, ERC721Metadata
            super.supportsInterface(interfaceId);
    }
}
