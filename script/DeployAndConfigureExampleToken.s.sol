// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { NFTDrop } from "../src/NFTDrop.sol";

import { IDrop } from "../src/interfaces/IDrop.sol";

import { PublicDrop } from "../src/lib/DropStructs.sol";

contract DeployAndConfigureExampleToken is Script {
    // Addresses
    address Drop = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    address creator = 0x26faf8AE18d15Ed1CA0563727Ad6D4Aa02fb2F80;
    address feeRecipient = 0x0000a26b00c1F0DF003000390027140000fAa719;

    // Token config
    uint256 maxSupply = 100;

    // Drop config
    uint16 feeBps = 500; // 5%
    uint80 mintPrice = 0.0001 ether;
    uint16 maxTotalMintableByWallet = 5;

    function run() external {
        vm.startBroadcast();

        address[] memory allowedDrop = new address[](1);
        allowedDrop[0] = Drop;

        // This example uses NFTDrop. For separate Owner and
        // Administrator privileges, use NFT.
        NFTDrop token = new NFTDrop("My Example Token", "ExTKN", allowedDrop);

        // Configure the token.
        token.setMaxSupply(maxSupply);

        // Configure the drop parameters.
        token.updateCreatorPayoutAddress(Drop, creator);
        token.updateAllowedFeeRecipient(Drop, feeRecipient, true);
        // token.updatePublicDrop(
        //     drop,
        //     PublicDrop(
        //         mintPrice,
        //         uint48(block.timestamp), // start time
        //         uint48(block.timestamp) + 1000, // end time
        //         maxTotalMintableByWallet,
        //         feeBps,
        //         true
        //     )
        // );

        // We are ready, let's mint the first 3 tokens!
        // IDrop(Drop).mintPublic{ value: mintPrice * 3 }(
        //     address(token),
        //     feeRecipient,
        //     address(0),
        //     3 // quantity
        // );
    }
}
