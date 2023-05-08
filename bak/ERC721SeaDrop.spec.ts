import { expect } from "chai";
import { ethers, network } from "hardhat";

import {
  IERC165__factory,
  IERC721__factory,
  INFT__factory,
  IMetadata__factory,
} from "../typechain-types";

import { getInterfaceID, randomHex } from "./utils/encoding";
import { faucet } from "./utils/faucet";
import { VERSION } from "./utils/helpers";
import { whileImpersonating } from "./utils/impersonate";

import type { NFTDrop, IDrop } from "../typechain-types";
import type { PublicDropStruct } from "../typechain-types/src/NFT";
import type { Wallet } from "ethers";

describe(`NFTDrop (v${VERSION})`, function () {
  const { provider } = ethers;
  let Drop: IDrop;
  let token: NFTDrop;
  let owner: Wallet;
  let creator: Wallet;
  let minter: Wallet;
  let publicDrop: PublicDropStruct;

  after(async () => {
    await network.provider.request({
      method: "hardhat_reset",
    });
  });

  before(async () => {
    // Set the wallets
    owner = new ethers.Wallet(randomHex(32), provider);
    creator = new ethers.Wallet(randomHex(32), provider);
    minter = new ethers.Wallet(randomHex(32), provider);

    // Add eth to wallets
    for (const wallet of [owner, minter, creator]) {
      await faucet(wallet.address, provider);
    }

    // Deploy Drop
    const Drop = await ethers.getContractFactory("Drop", owner);
    Drop = await Drop.deploy();
  });

  beforeEach(async () => {
    // Deploy token
    const NFTDrop = await ethers.getContractFactory(
      "NFTDrop",
      owner
    );
    token = await NFTDrop.deploy("", "", [Drop.address]);

    publicDrop = {
      mintPrice: "100000000000000000", // 0.1 ether
      maxTotalMintableByWallet: 10,
      startTime: Math.round(Date.now() / 1000) - 100,
      endTime: Math.round(Date.now() / 1000) + 100,
      feeBps: 1000,
      restrictFeeRecipients: true,
    };
  });

  it("Should not be able to mint until the creator address is updated to non-zero", async () => {
    await token.connect(owner).updatePublicDrop(Drop.address, publicDrop);
    await token.setMaxSupply(5);

    const feeRecipient = new ethers.Wallet(randomHex(32), provider);
    await token.updateAllowedFeeRecipient(
      Drop.address,
      feeRecipient.address,
      true
    );

    await expect(
      Drop.mintPublic(
        token.address,
        feeRecipient.address,
        ethers.constants.AddressZero,
        1,
        { value: publicDrop.mintPrice }
      )
    ).to.be.revertedWith("CreatorPayoutAddressCannotBeZeroAddress");

    await token.updateAllowedFeeRecipient(
      Drop.address,
      feeRecipient.address,
      false
    );
  });

  it("Should only let the token owner update the drop URI", async () => {
    await expect(
      token.connect(creator).updateDropURI(Drop.address, "http://test.com")
    ).to.revertedWith("OnlyOwner");

    await expect(
      token.connect(owner).updateDropURI(Drop.address, "http://test.com")
    )
      .to.emit(Drop, "DropURIUpdated")
      .withArgs(token.address, "http://test.com");
  });

  it("Should only let the owner update the allowed fee recipients", async () => {
    const feeRecipient = new ethers.Wallet(randomHex(32), provider);

    expect(await Drop.getAllowedFeeRecipients(token.address)).to.deep.eq([]);

    expect(
      await Drop.getFeeRecipientIsAllowed(
        token.address,
        feeRecipient.address
      )
    ).to.be.false;

    await expect(
      token.updateAllowedFeeRecipient(
        Drop.address,
        ethers.constants.AddressZero,
        true
      )
    ).to.be.revertedWith("FeeRecipientCannotBeZeroAddress");

    await expect(
      token.updateAllowedFeeRecipient(
        Drop.address,
        feeRecipient.address,
        true
      )
    )
      .to.emit(Drop, "AllowedFeeRecipientUpdated")
      .withArgs(token.address, feeRecipient.address, true);

    await expect(
      token.updateAllowedFeeRecipient(
        Drop.address,
        feeRecipient.address,
        true
      )
    ).to.be.revertedWith("DuplicateFeeRecipient");

    expect(await Drop.getAllowedFeeRecipients(token.address)).to.deep.eq([
      feeRecipient.address,
    ]);

    expect(
      await Drop.getFeeRecipientIsAllowed(
        token.address,
        feeRecipient.address
      )
    ).to.be.true;

    // Now let's disallow the feeRecipient
    await expect(
      token.updateAllowedFeeRecipient(
        Drop.address,
        feeRecipient.address,
        false
      )
    )
      .to.emit(Drop, "AllowedFeeRecipientUpdated")
      .withArgs(token.address, feeRecipient.address, false);

    expect(await Drop.getAllowedFeeRecipients(token.address)).to.deep.eq([]);

    expect(
      await Drop.getFeeRecipientIsAllowed(
        token.address,
        feeRecipient.address
      )
    ).to.be.false;

    await expect(
      token.updateAllowedFeeRecipient(
        Drop.address,
        feeRecipient.address,
        false
      )
    ).to.be.revertedWith("FeeRecipientNotPresent");
  });

  it("Should only let the owner set the provenance hash", async () => {
    await token.setMaxSupply(1);
    expect(await token.provenanceHash()).to.equal(ethers.constants.HashZero);

    const defaultProvenanceHash = `0x${"0".repeat(64)}`;
    const firstProvenanceHash = `0x${"1".repeat(64)}`;
    const secondProvenanceHash = `0x${"2".repeat(64)}`;

    await expect(
      token.connect(creator).setProvenanceHash(firstProvenanceHash)
    ).to.revertedWith("OnlyOwner");

    await expect(token.connect(owner).setProvenanceHash(firstProvenanceHash))
      .to.emit(token, "ProvenanceHashUpdated")
      .withArgs(defaultProvenanceHash, firstProvenanceHash);

    // Provenance hash should not be updatable after the first token has minted.
    // Mint a token.
    await whileImpersonating(
      Drop.address,
      provider,
      async (impersonatedSigner) => {
        await token.connect(impersonatedSigner).mintDrop(minter.address, 1);
      }
    );

    await expect(
      token.connect(owner).setProvenanceHash(secondProvenanceHash)
    ).to.be.revertedWith("ProvenanceHashCannotBeSetAfterMintStarted");

    expect(await token.provenanceHash()).to.equal(firstProvenanceHash);
  });

  it("Should only let allowed Drop call DropMint", async () => {
    await token.setMaxSupply(1);

    await whileImpersonating(
      Drop.address,
      provider,
      async (impersonatedSigner) => {
        await expect(
          token.connect(impersonatedSigner).mintDrop(minter.address, 1)
        )
          .to.emit(token, "Transfer")
          .withArgs(ethers.constants.AddressZero, minter.address, 1);

        await expect(
          token.connect(impersonatedSigner).mintDrop(minter.address, 1)
        ).to.be.revertedWith("MintQuantityExceedsMaxSupply(2, 1)");
      }
    );

    await expect(
      token.connect(owner).mintDrop(minter.address, 1)
    ).to.be.revertedWith("OnlyAllowedDrop");
  });

  it("Should return supportsInterface true for supported interfaces", async () => {
    const supportedInterfacesNFTDrop = [
      [
        INFT__factory,
        IMetadata__factory,
        IERC165__factory,
      ],
      [IMetadata__factory],
    ];
    const supportedInterfacesERC721A = [
      [IERC721__factory, IERC165__factory],
      [IERC165__factory],
    ];

    for (const factories of [
      ...supportedInterfacesNFTDrop,
      ...supportedInterfacesERC721A,
    ]) {
      const interfaceId = factories
        .map((factory) => getInterfaceID(factory.createInterface()))
        .reduce((prev, curr) => prev.xor(curr))
        .toHexString();
      expect(await token.supportsInterface(interfaceId)).to.be.true;
    }

    // Ensure invalid interfaces return false.
    const invalidInterfaceIds = ["0x00000000", "0x10000000", "0x00000001"];
    for (const interfaceId of invalidInterfaceIds) {
      expect(await token.supportsInterface(interfaceId)).to.be.false;
    }
  });

  it("Should only let the token owner update the allowed Drop addresses", async () => {
    await expect(
      token.connect(creator).updateAllowedDrop([Drop.address])
    ).to.revertedWith("OnlyOwner");

    await expect(
      token.connect(minter).updateAllowedDrop([Drop.address])
    ).to.revertedWith("OnlyOwner");

    await expect(token.updateAllowedDrop([Drop.address]))
      .to.emit(token, "AllowedDropUpdated")
      .withArgs([Drop.address]);

    const address1 = `0x${"1".repeat(40)}`;
    const address2 = `0x${"2".repeat(40)}`;
    const address3 = `0x${"3".repeat(40)}`;

    await expect(token.updateAllowedDrop([Drop.address, address1]))
      .to.emit(token, "AllowedDropUpdated")
      .withArgs([Drop.address, address1]);

    await expect(token.updateAllowedDrop([address2]))
      .to.emit(token, "AllowedDropUpdated")
      .withArgs([address2]);

    await expect(
      token.updateAllowedDrop([
        address3,
        Drop.address,
        address2,
        address1,
      ])
    )
      .to.emit(token, "AllowedDropUpdated")
      .withArgs([address3, Drop.address, address2, address1]);

    await expect(token.updateAllowedDrop([Drop.address]))
      .to.emit(token, "AllowedDropUpdated")
      .withArgs([Drop.address]);
  });

  it("Should let the token owner use admin methods", async () => {
    // Test `updateAllowList` for coverage.
    const allowListData = {
      merkleRoot: `0x${"3".repeat(64)}`,
      publicKeyURIs: [],
      allowListURI: "",
    };
    await token.updateAllowList(Drop.address, allowListData);

    await expect(
      token.connect(creator).updateAllowList(Drop.address, allowListData)
    ).to.be.revertedWith("OnlyOwner");

    // Test `updateTokenGatedDrop` for coverage.
    const dropStage = {
      mintPrice: "10000000000000000", // 0.01 ether
      maxTotalMintableByWallet: 10,
      startTime: Math.round(Date.now() / 1000) - 100,
      endTime: Math.round(Date.now() / 1000) + 500,
      dropStageIndex: 1,
      maxTokenSupplyForStage: 100,
      feeBps: 100,
      restrictFeeRecipients: true,
    };
    await token.updateTokenGatedDrop(
      Drop.address,
      `0x${"4".repeat(40)}`,
      dropStage
    );

    await expect(
      token
        .connect(creator)
        .updateTokenGatedDrop(Drop.address, `0x${"4".repeat(40)}`, dropStage)
    ).to.be.revertedWith("OnlyOwner");

    const signedMintValidationParams = {
      minMintPrice: 10,
      maxMaxTotalMintableByWallet: 5,
      minStartTime: 50,
      maxEndTime: 100,
      maxMaxTokenSupplyForStage: 100,
      minFeeBps: 5,
      maxFeeBps: 1000,
    };

    // Test `updateSigner` for coverage.
    await token.updateSignedMintValidationParams(
      Drop.address,
      `0x${"5".repeat(40)}`,
      signedMintValidationParams
    );

    await expect(
      token
        .connect(creator)
        .updateSignedMintValidationParams(
          Drop.address,
          `0x${"5".repeat(40)}`,
          signedMintValidationParams
        )
    ).to.be.revertedWith("OnlyOwner");

    // Test `updatePayer` for coverage.
    await token.updatePayer(Drop.address, `0x${"6".repeat(40)}`, true);

    await expect(
      token
        .connect(creator)
        .updateSignedMintValidationParams(
          Drop.address,
          `0x${"6".repeat(40)}`,
          signedMintValidationParams
        )
    ).to.be.revertedWith("OnlyOwner");
  });

  it("Should be able to update the allowed payers", async () => {
    const payer = new ethers.Wallet(randomHex(32), provider);
    const payer2 = new ethers.Wallet(randomHex(32), provider);
    await faucet(payer.address, provider);
    await faucet(payer2.address, provider);

    await expect(
      token.updatePayer(Drop.address, payer.address, false)
    ).to.be.revertedWith("PayerNotPresent");

    await token.updatePayer(Drop.address, payer.address, true);

    // Ensure that the same payer cannot be added twice.
    await expect(
      token.updatePayer(Drop.address, payer.address, true)
    ).to.be.revertedWith("DuplicatePayer()");

    // Ensure that the zero address cannot be added as a payer.
    await expect(
      token.updatePayer(Drop.address, ethers.constants.AddressZero, true)
    ).to.be.revertedWith("PayerCannotBeZeroAddress()");

    // Remove the original payer for branch coverage.
    await token.updatePayer(Drop.address, payer.address, false);
    expect(await Drop.getPayerIsAllowed(token.address, payer.address)).to.eq(
      false
    );

    // Add two signers and remove the second for branch coverage.
    await token.updatePayer(Drop.address, payer.address, true);
    await token.updatePayer(Drop.address, payer2.address, true);
    await token.updatePayer(Drop.address, payer2.address, false);
    expect(await Drop.getPayerIsAllowed(token.address, payer.address)).to.eq(
      true
    );
    expect(
      await Drop.getPayerIsAllowed(token.address, payer2.address)
    ).to.eq(false);
  });

  it("Should only let the owner call update functions", async () => {
    const onlyOwnerMethods = [
      "updateAllowedDrop",
      "updatePublicDrop",
      "updateAllowList",
      "updateTokenGatedDrop",
      "updateDropURI",
      "updateCreatorPayoutAddress",
      "updateAllowedFeeRecipient",
      "updateSignedMintValidationParams",
      "updatePayer",
    ];

    const allowListData = {
      merkleRoot: `0x${"3".repeat(64)}`,
      publicKeyURIs: [],
      allowListURI: "",
    };

    const dropStage = {
      mintPrice: "10000000000000000", // 0.01 ether
      maxTotalMintableByWallet: 10,
      startTime: Math.round(Date.now() / 1000) - 100,
      endTime: Math.round(Date.now() / 1000) + 500,
      dropStageIndex: 1,
      maxTokenSupplyForStage: 100,
      feeBps: 100,
      restrictFeeRecipients: true,
    };

    const signedMintValidationParams = {
      minMintPrice: 10,
      maxMaxTotalMintableByWallet: 5,
      minStartTime: 50,
      maxEndTime: 100,
      maxMaxTokenSupplyForStage: 100,
      minFeeBps: 5,
      maxFeeBps: 1000,
    };

    const methodParams: any = {
      updateAllowedDrop: [[Drop.address]],
      updatePublicDrop: [Drop.address, publicDrop],
      updateAllowList: [Drop.address, allowListData],
      updateTokenGatedDrop: [Drop.address, `0x${"4".repeat(40)}`, dropStage],
      updateDropURI: [Drop.address, "http://test.com"],
      updateCreatorPayoutAddress: [Drop.address, `0x${"4".repeat(40)}`],
      updateAllowedFeeRecipient: [Drop.address, `0x${"4".repeat(40)}`, true],
      updateSignedMintValidationParams: [
        Drop.address,
        `0x${"4".repeat(40)}`,
        signedMintValidationParams,
      ],
      updatePayer: [Drop.address, `0x${"4".repeat(40)}`, true],
    };

    const paramsWithNonDrop = (method: string) => [
      creator.address,
      ...methodParams[method].slice(1),
    ];

    for (const method of onlyOwnerMethods) {
      await (token as any).connect(owner)[method](...methodParams[method]);

      await expect(
        (token as any).connect(creator)[method](...methodParams[method])
      ).to.be.revertedWith("OnlyOwner()");

      if (method !== "updateAllowedDrop") {
        await expect(
          (token as any).connect(owner)[method](...paramsWithNonDrop(method))
        ).to.be.revertedWith("OnlyAllowedDrop()");
      }
    }
  });
});
