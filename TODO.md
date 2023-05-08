### 修改 allowed Drop 合约
    
    updateAllowedDrop 

### 在 Drop 上更新此 nft 合约的公开掉落数据。 
    * 只有所有者或管理员可以使用此功能。 * 
    * 管理员只能更新 `feeBps`。 *

updatePublicDrop

### Update the token gated drop stage

    updateTokenGatedDrop

### Update the drop URI for this nft contract on Drop

    updateDropURI

### Update the allowed fee recipient for this nft contract on Drop

    updateAllowedFeeRecipient

### Update the server-side signers for this nft contract on Drop

    updateSignedMintValidationParams

### Update the allowed payers for this nft contract on Drop.


### NOTE
    Only the administrator (OpenSea) can set feeBps on Partner contracts
    Administrator must first set fee.
    Administrator can only initialize (maxTotalMintableByWallet > 0) and set feeBps/restrictFeeRecipients.
