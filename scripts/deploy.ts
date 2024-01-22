import { SigningKey } from "ethers";
import { ethers } from "hardhat";
import * as crypto from "crypto";

// async function encrypt(preimage: string, key: string) {
//   const iv = crypto.randomBytes(16).toString("hex");
//   preimage = preimage.slice(2);
//   let cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
//   let encrypted = cipher.update(preimage);
//   encrypted = Buffer.concat(encrypted, cipher.final());
//   return encrypted;
// }

function encryptWithAES(inputHex: string, keyHex: string): string {
  // Convert hex strings to buffers
  const inputBuffer = Buffer.from(inputHex, "hex");
  const keyBuffer = Buffer.from(keyHex, "hex");

  // Generate a random IV (Initialization Vector)
  const iv = crypto.randomBytes(16);

  // Create an AES-256-CBC cipher with the provided key and IV
  const cipher = crypto.createCipheriv("aes-256-cbc", keyBuffer, iv);

  // Encrypt the input buffer
  const encryptedBuffer = Buffer.concat([
    cipher.update(inputBuffer),
    cipher.final(),
  ]);

  console.log(`iv: ${iv.toString("hex")}`);
  console.log(`enc: ${encryptedBuffer.toString("hex")}`);

  // Concatenate IV and encrypted data, and convert to hex string
  const resultHex = iv.toString("hex") + encryptedBuffer.toString("hex");

  return resultHex;
}

function decryptWithAES(encryptedHex: string, keyHex: string): string {
  // Convert hex strings to buffers
  const ivBuffer = Buffer.from(encryptedHex.slice(32), "hex");
  const encryptedBuffer = Buffer.from(
    encryptedHex.substring(encryptedHex.length - 32),
    "hex"
  );
  const keyBuffer = Buffer.from(keyHex, "hex");

  // Extract IV from the first 16 bytes of the encrypted buffer
  // const iv = encryptedBuffer.slice(0, 16);

  // Create an AES-256-CBC decipher with the provided key and IV
  const decipher = crypto.createDecipheriv("aes-256-cbc", keyBuffer, ivBuffer);

  // Decrypt the encrypted buffer
  const decryptedBuffer = Buffer.concat([
    decipher.update(encryptedBuffer),
    decipher.final(),
  ]);

  // Convert the decrypted buffer to a hex string
  const resultHex = decryptedBuffer.toString("hex");

  return resultHex;
}

async function main() {
  const [assetOwner, cashOwner, dvpOwner, funder] = await ethers.getSigners();

  const sellerWallet = ethers.Wallet.createRandom();
  const seller = await ethers.getImpersonatedSigner(sellerWallet.address);
  const buyerWallet = ethers.Wallet.createRandom();
  const buyer = await ethers.getImpersonatedSigner(buyerWallet.address);

  await funder.sendTransaction({
    to: sellerWallet.address,
    value: ethers.parseEther("1.0"), // Sends exactly 1.0 ether
  });

  await funder.sendTransaction({
    to: buyerWallet.address,
    value: ethers.parseEther("1.0"), // Sends exactly 1.0 ether
  });

  const asset = await ethers.deployContract(
    "Asset",
    [assetOwner.address],
    assetOwner
  );
  await asset.waitForDeployment();
  const assetAddress = await asset.getAddress();
  console.log(
    `Asset contract deployed to ${assetAddress} from owner ${assetOwner.address}`
  );

  await asset.connect(assetOwner).mint(seller.address, "100000");
  console.log(`amount 100000 minted to seller ${seller.address}`);

  const cash = await ethers.deployContract(
    "Cash",
    [cashOwner.address],
    cashOwner
  );
  await cash.waitForDeployment();
  const cashAddress = await cash.getAddress();
  console.log(
    `Cash contract deployed to ${cashAddress} from owner ${cashOwner.address}`
  );
  await cash.connect(cashOwner).mint(buyer.address, "20000000");
  console.log(`amount 20000000 minted to buyer ${buyer.address}`);

  const dvp = await ethers.deployContract(
    "DVP",
    [assetAddress, cashAddress],
    dvpOwner
  );
  await dvp.waitForDeployment();
  const dvpAddress = await dvp.getAddress();
  console.log(
    `DVP contract deployed to ${dvpAddress} from owner ${dvpOwner.address}`
  );

  await dvp.connect(seller).registerPublicKey(sellerWallet.publicKey);
  console.log(
    `seller public key registered: ${await dvp.publicKey(sellerWallet.address)}`
  );
  await dvp.connect(buyer).registerPublicKey(buyerWallet.publicKey);
  console.log(
    `buyer public key registered: ${await dvp.publicKey(buyerWallet.address)}`
  );

  console.log(`creating new settlement instruction`);
  const preimage = ethers.hexlify(ethers.randomBytes(32));
  console.log(`preimage:${preimage}`);
  const secretKey = ethers.keccak256(
    sellerWallet.signingKey.computeSharedSecret(buyerWallet.publicKey)
  );
  console.log(`secret key: ${secretKey}`);
  const e = encryptWithAES(preimage, secretKey.slice(2));
  console.log(`encrypted: ${e}`);
  const d = decryptWithAES(e, secretKey.slice(2));
  console.log(`decrypted: ${d}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
