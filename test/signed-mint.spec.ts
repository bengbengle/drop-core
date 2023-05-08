import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers, network } from "hardhat";

import { randomHex } from "./utils/encoding";
import { faucet } from "./utils/faucet";
import { VERSION } from "./utils/helpers";
import { whileImpersonating } from "./utils/impersonate";

import type { NFT, IDrop } from "../typechain-types";
import type { SignedMintValidationParamsStruct } from "../typechain-types/src/NFTDrop";
import type { MintParamsStruct } from "../typechain-types/src/Drop";
import type { Wallet } from "ethers";

describe(`Drop - Mint Signed (v${VERSION})`, function () {
  const { provider } = ethers;
  let drop: IDrop;
  let nft: NFT;
  let admin: Wallet;
  let creator: Wallet;
  let minter: Wallet;
  let feeRecipient: Wallet;
  let mintParams: MintParamsStruct;
  let signedMintValidationParams: SignedMintValidationParamsStruct;
 
  let eip712Domain: { [key: string]: string | number };
  let eip712Types: Record<string, Array<{ name: string; type: string }>>;
  let salt: BigNumber;

  after(async () => {
    await network.provider.request({method: "hardhat_reset"});
  });

  before(async () => {
    // Set the wallets
    admin = new ethers.Wallet(randomHex(32), provider);
    minter = new ethers.Wallet(randomHex(32), provider);
    creator = new ethers.Wallet(randomHex(32), provider);

    feeRecipient = new ethers.Wallet(randomHex(32), provider);

    // Add eth to wallets
    for (const wallet of [admin, minter]) {
      await faucet(wallet.address, provider);
    }

    // Deploy Drop
    const Drop = await ethers.getContractFactory("Drop", admin);
    drop = await Drop.deploy();

    // Configure EIP-712 params
    eip712Domain = {
      name: "Drop",
      version: "1.0",
      chainId: (await provider.getNetwork()).chainId,
      verifyingContract: drop.address,
    };
    eip712Types = {
      SignedMint: [
        { name: "nftContract", type: "address" },
        { name: "minter", type: "address" },
        { name: "feeRecipient", type: "address" },
        { name: "mintParams", type: "MintParams" },
        { name: "salt", type: "uint256" },
      ],
      MintParams: [
        { name: "mintPrice", type: "uint256" },
        { name: "maxTotalMintableByWallet", type: "uint256" },
        { name: "startTime", type: "uint256" },
        { name: "endTime", type: "uint256" },
        { name: "dropStageIndex", type: "uint256" },
        { name: "maxTokenSupplyForStage", type: "uint256" },
        { name: "feeBps", type: "uint256" },
        { name: "restrictFeeRecipients", type: "bool" },
      ],
    };
  });

  beforeEach(async () => {
    // Deploy token
    const nftFactory = await ethers.getContractFactory("NFT", admin);
    nft = await nftFactory.deploy("", "", admin.address, [drop.address]);

    // Configure token
    await nft.setMaxSupply(100);
    await nft.updateCreatorPayoutAddress(drop.address, creator.address);
    

    signedMintValidationParams = {
      minMintPrice: 1,                    // 最小铸造价格
      maxMaxTotalMintableByWallet: 3,     // 最大可铸造数 / 每个钱包
      minStartTime: 50,                   // 开始时间
      maxEndTime: "100000000000",         // 结束时间
      maxMaxTokenSupplyForStage: 10000,   // 最大铸造数 / 每个阶段
      minFeeBps: 1,                       // 最小费用
      maxFeeBps: 9000,                    // 最大费用
    };

    console.log("signedMintValidationParams:", signedMintValidationParams);

    await nft
            .connect(admin)
            .updateSignedMintValidationParams(drop.address, admin.address, signedMintValidationParams);

    // Set a random salt.
    salt = BigNumber.from(randomHex(32));

  });

 

  it("Should mint a signed mint", async () => {

    mintParams = {
      mintPrice: "100000000000000000", // 0.1 ether 
      maxTotalMintableByWallet: 3,                    // 最大可铸造数 / 每个钱包
      startTime: Math.round(Date.now() / 1000) - 100, // 开始时间
      endTime: Math.round(Date.now() / 1000) + 100,   // 结束时间
      dropStageIndex: 1,                              // drop 铸造阶段
      maxTokenSupplyForStage: 100,                    // 最大铸造数 / 每个阶段 
      feeBps: 1000,                                   
      restrictFeeRecipients: true,
    };

    const signMint = async (nftContract: string, minter: Wallet, feeRecipient: Wallet, mintParams: MintParamsStruct, salt: BigNumber, signer: Wallet) => {
      const signedMint = {
        nftContract,
        minter: minter.address,
        feeRecipient: feeRecipient.address,
        mintParams,
        salt,
      };
  
      const signature = await signer._signTypedData(
        eip712Domain,
        eip712Types,
        signedMint
      );
      const verifiedAddress = ethers.utils.verifyTypedData(
        eip712Domain,
        eip712Types,
        signedMint,
        signature
      );
      expect(verifiedAddress).to.eq(signer.address);
      return signature;
    };
    
    // Mint signed with payer for minter.
    let signature = await signMint(nft.address, minter, feeRecipient, mintParams, salt, admin);

    const value = BigNumber.from(mintParams.mintPrice).mul(3);

    let params = await drop.getSignedMintValidationParams(nft.address, admin.address);

    console.log("params:", params);
 
    let _nftContract = nft.address
    let _feeRecipient = feeRecipient.address
    let _minterIfNotPayer = minter.address
    let _quantity = 3
    let _mintParams = mintParams
    let _salt = salt
    let _signature = signature

    await expect(
      drop
        .connect(minter)
        .mintSigned(
          _nftContract, 
          _feeRecipient, 
          _minterIfNotPayer, 
          _quantity, 
          _mintParams, 
          _salt, 
          _signature, 
          {value}
        )
        
    ).to.emit(drop, "DropMint")
      

    let minterBalance = await nft.balanceOf(minter.address);
    expect(minterBalance).to.eq(3);
    expect(await nft.totalSupply()).to.eq(3);
 
  });
 
});
