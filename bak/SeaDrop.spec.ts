import { expect } from "chai";
import { ethers, network } from "hardhat";

import { randomHex } from "../test/utils/encoding";
import { faucet } from "../test/utils/faucet";
import { VERSION } from "../test/utils/helpers";
import { whileImpersonating } from "../test/utils/impersonate";

import type { NFT, IERC721, IDrop } from "../typechain-types";
import type { Wallet } from "ethers";

describe(`Drop (v${VERSION})`, function () {
  const { provider } = ethers;
  let Drop: IDrop;
  let token: NFT;
  let standard721Token: IERC721;
  let owner: Wallet;
  let admin: Wallet;
  let minter: Wallet;

  after(async () => {
    await network.provider.request({
      method: "hardhat_reset",
    });
  });

  before(async () => {
    // Set the wallets
    owner = new ethers.Wallet(randomHex(32), provider);
    admin = new ethers.Wallet(randomHex(32), provider);
    minter = new ethers.Wallet(randomHex(32), provider);

    // Add eth to wallets
    for (const wallet of [owner, admin, minter]) {
      await faucet(wallet.address, provider);
    }

    // Deploy Drop
    const Drop = await ethers.getContractFactory("Drop", owner);
    Drop = await Drop.deploy();

    // Deploy token
    const NFT = await ethers.getContractFactory(
      "NFT",
      owner
    );
    token = await NFT.deploy("", "", admin.address, [Drop.address]);

    // Deploy a standard (non-IER721Drop) token
    const ERC721A = await ethers.getContractFactory("ERC721A", owner);
    standard721Token = (await ERC721A.deploy("", "")) as unknown as IERC721;
  });

  it("Should not let a non-INFT token contract use the token methods", async () => {
    await whileImpersonating(
      standard721Token.address,
      provider,
      async (impersonatedSigner) => {
        const publicDrop = {
          mintPrice: 1000,
          maxTotalMintableByWallet: 1,
          startTime: Math.round(Date.now() / 1000) - 100,
          endTime: Math.round(Date.now() / 1000) + 100,
          feeBps: 1000,
          restrictFeeRecipients: false,
        };
        await expect(
          Drop.connect(impersonatedSigner).updatePublicDrop(publicDrop)
        ).to.be.revertedWith("OnlyINFT");

        const allowListData = {
          merkleRoot: ethers.constants.HashZero,
          publicKeyURIs: [],
          allowListURI: "",
        };
        await expect(
          Drop.connect(impersonatedSigner).updateAllowList(allowListData)
        ).to.be.revertedWith("OnlyINFT");

        const tokenGatedDropStage = {
          mintPrice: "10000000000000000", // 0.01 ether
          maxTotalMintableByWallet: 10,
          startTime: Math.round(Date.now() / 1000) - 100,
          endTime: Math.round(Date.now() / 1000) + 500,
          dropStageIndex: 1,
          maxTokenSupplyForStage: 100,
          feeBps: 100,
          restrictFeeRecipients: true,
        };
        await expect(
          Drop
            .connect(impersonatedSigner)
            .updateTokenGatedDrop(minter.address, tokenGatedDropStage)
        ).to.be.revertedWith("OnlyINFT");

        await expect(
          Drop
            .connect(impersonatedSigner)
            .updateCreatorPayoutAddress(minter.address)
        ).to.be.revertedWith("OnlyINFT");

        await expect(
          Drop
            .connect(impersonatedSigner)
            .updateAllowedFeeRecipient(minter.address, true)
        ).to.be.revertedWith("OnlyINFT");

        const signedMintValidationParams = {
          minMintPrice: 1,
          maxMaxTotalMintableByWallet: 11,
          minStartTime: 50,
          maxEndTime: "100000000000",
          maxMaxTokenSupplyForStage: 10000,
          minFeeBps: 1,
          maxFeeBps: 9000,
        };
        await expect(
          Drop
            .connect(impersonatedSigner)
            .updateSignedMintValidationParams(
              minter.address,
              signedMintValidationParams
            )
        ).to.be.revertedWith("OnlyINFT");

        await expect(
          Drop.connect(impersonatedSigner).updateDropURI("http://test.com")
        ).to.be.revertedWith("OnlyINFT");

        await expect(
          Drop.connect(impersonatedSigner).updatePayer(minter.address, true)
        ).to.be.revertedWith("OnlyINFT");
      }
    );

    await expect(
      token.connect(owner).updateDropURI(Drop.address, "http://test.com")
    )
      .to.emit(Drop, "DropURIUpdated")
      .withArgs(token.address, "http://test.com");
  });

  it("Should not allow reentrancy during mint", async () => {
    // Set a public drop with maxTotalMintableByWallet: 1
    // and restrictFeeRecipient: false
    await token.setMaxSupply(10);
    const oneEther = ethers.utils.parseEther("1");
    const publicDrop = {
      mintPrice: oneEther,
      maxTotalMintableByWallet: 1,
      startTime: Math.round(Date.now() / 1000) - 100,
      endTime: Math.round(Date.now() / 1000) + 100,
      feeBps: 1000,
      restrictFeeRecipients: false,
    };
    await whileImpersonating(
      token.address,
      provider,
      async (impersonatedSigner) => {
        await Drop.connect(impersonatedSigner).updatePublicDrop(publicDrop);
      }
    );

    const MaliciousRecipientFactory = await ethers.getContractFactory("MaliciousRecipient", owner);
    const maliciousRecipient = await MaliciousRecipientFactory.deploy();

    // Set the creator address to MaliciousRecipient.
    await token
      .connect(owner)
      .updateCreatorPayoutAddress(Drop.address, maliciousRecipient.address);

    // Should not be able to mint with reentrancy.
    await maliciousRecipient.setStartAttack({ value: oneEther.mul(10) });
    await expect(maliciousRecipient.attack(Drop.address, token.address)).to.be.revertedWith("ETH_TRANSFER_FAILED");
    expect(await token.totalSupply()).to.eq(0);
  });
});
