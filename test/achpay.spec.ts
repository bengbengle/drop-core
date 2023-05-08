// import { expect } from "chai";
// import { BigNumber } from "ethers";
// import { ethers, network } from "hardhat";
// import crypto from "crypto";
// const sha1 = require('js-sha1');


// const getMerSign = (appId: string, appSecret: string, timestamp: string) => {
//     return sha1(appId + appSecret + String(timestamp));
// }

// const convertToQueryString = (obj: object) => {
//     let result = "";
//     const _map: Map<string, string> = new Map(Object.entries(obj));
//     _map.forEach((m, k) =>  result += `${k}=${m}&` );

//     result = result.substring(0, result.length - 1);

//     return result;
// }

// const encrypt = (obj: object, secretKey: string) => {

//     const rawText = convertToQueryString(obj);

//     try {
//         var hmac = crypto.createHmac("sha1", secretKey);
//         var signed = hmac.update(Buffer.from(rawText, 'utf-8')).digest("base64");
//         return signed;
//     } catch (e: any) {
//         console.log(`HmacSHA1 encrypting exception, msg is ${e.toString()}`);
//     }
//     return '';
// }

// describe(`ACH Pay - Signed`, function () {
//     const { provider } = ethers;

//     after(async () => {
//         await network.provider.request({ method: "hardhat_reset" });
//     });

//     before(async () => {

//     });

//     beforeEach(async () => {

//     });

//     it("request body signed", async () => {

//         let secretKey = "py2bwighth62ajq6";

//         const params = {
//             amount: "3000",
//             appId: "ahzxh0klegv1fzol",
//             callbackUrl: "https://alchemypay.org",
//             fiat: "USD",
//             merchantName: "merchantName",
//             merchantOrderNo: "ACH100001234",
//             name: "nftname",
//             nonce: "28518016",
//             picture: "https://download.bit.store/official/BitStore/pic/user_portrait/20.jpeg",
//             redirectUrl: "https://alchemypay.org",
//             targetFiat: "SGD",
//             timeout: "1675394255000",
//             timestamp: "1676525212",
//             type: "MARKET",
//             uniqueId: "1113"
//         }
         
//         const ciphertext = encrypt(params, secretKey);

//         console.log("pre encode sign is ", ciphertext);

//         const urlEncodeText = encodeURIComponent(ciphertext);

//         console.log("encode sign is ", urlEncodeText);

//     });

//     it("request head signed", async () => {
        
//         const secretKey = "py2bwighth62ajq6";

//         const appId = "ahzxh0klegv1fzol";

//         const timestamp = "1676525212";

//         const sign = getMerSign(appId, secretKey, timestamp);

//         console.log("sign is ", sign);

//     });
// });
