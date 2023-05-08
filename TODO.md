### 修改 allowed SeaDrop 合约
    
    updateAllowedSeaDrop 

### 在 SeaDrop 上更新此 nft 合约的公开掉落数据。 
    * 只有所有者或管理员可以使用此功能。 * 
    * 管理员只能更新 `feeBps`。 *

updatePublicDrop

### Update the token gated drop stage

    updateTokenGatedDrop

### Update the drop URI for this nft contract on SeaDrop

    updateDropURI

### Update the allowed fee recipient for this nft contract on SeaDrop

    updateAllowedFeeRecipient

### Update the server-side signers for this nft contract on SeaDrop

    updateSignedMintValidationParams

### Update the allowed payers for this nft contract on SeaDrop.


### NOTE
    Only the administrator (OpenSea) can set feeBps on Partner contracts
    Administrator must first set fee.
    Administrator can only initialize (maxTotalMintableByWallet > 0) and set feeBps/restrictFeeRecipients.
