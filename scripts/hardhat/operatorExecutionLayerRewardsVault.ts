import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();
const hre = require("hardhat");
async function main() {
console.log(`Running deploy script... 👨‍🍳`);
  
const key: string = process.env.PRIVATE_KEY3 as string;
if (!key) {
    throw new Error("Please set your PRIVATE_KEY3 in a .env file");
}

const [owner] = await hre.ethers.getSigners();
console.log("wallet:", owner.address);

function sleep(ms:any) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var abi = [{"type":"constructor","inputs":[{"name":"_gteth","type":"address","internalType":"address"},{"name":"_treasury","type":"address","internalType":"address"}],"stateMutability":"nonpayable"},{"type":"receive","stateMutability":"payable"},{"type":"function","name":"GTETH","inputs":[],"outputs":[{"name":"","type":"address","internalType":"address"}],"stateMutability":"view"},{"type":"function","name":"TREASURY","inputs":[],"outputs":[{"name":"","type":"address","internalType":"address"}],"stateMutability":"view"},{"type":"function","name":"owner","inputs":[],"outputs":[{"name":"","type":"address","internalType":"address"}],"stateMutability":"view"},{"type":"function","name":"recoverERC20","inputs":[{"name":"_token","type":"address","internalType":"address"},{"name":"_amount","type":"uint256","internalType":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"recoverERC721","inputs":[{"name":"_token","type":"address","internalType":"address"},{"name":"_tokenId","type":"uint256","internalType":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"renounceOwnership","inputs":[],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"setGTETH","inputs":[{"name":"_gtETH","type":"address","internalType":"address"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"setTREASURY","inputs":[{"name":"_treasury","type":"address","internalType":"address"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"transferOwnership","inputs":[{"name":"newOwner","type":"address","internalType":"address"}],"outputs":[],"stateMutability":"nonpayable"},{"type":"function","name":"withdrawRewards","inputs":[{"name":"_maxAmount","type":"uint256","internalType":"uint256"}],"outputs":[{"name":"amount","type":"uint256","internalType":"uint256"}],"stateMutability":"nonpayable"},{"type":"event","name":"ERC20Recovered","inputs":[{"name":"requestedBy","type":"address","indexed":true,"internalType":"address"},{"name":"token","type":"address","indexed":true,"internalType":"address"},{"name":"amount","type":"uint256","indexed":false,"internalType":"uint256"}],"anonymous":false},{"type":"event","name":"ERC721Recovered","inputs":[{"name":"requestedBy","type":"address","indexed":true,"internalType":"address"},{"name":"token","type":"address","indexed":true,"internalType":"address"},{"name":"tokenId","type":"uint256","indexed":false,"internalType":"uint256"}],"anonymous":false},{"type":"event","name":"ETHReceived","inputs":[{"name":"amount","type":"uint256","indexed":false,"internalType":"uint256"}],"anonymous":false},{"type":"event","name":"OwnershipTransferred","inputs":[{"name":"previousOwner","type":"address","indexed":true,"internalType":"address"},{"name":"newOwner","type":"address","indexed":true,"internalType":"address"}],"anonymous":false},{"type":"error","name":"OwnableInvalidOwner","inputs":[{"name":"owner","type":"address","internalType":"address"}]},{"type":"error","name":"OwnableUnauthorizedAccount","inputs":[{"name":"account","type":"address","internalType":"address"}]},{"type":"error","name":"SafeERC20FailedOperation","inputs":[{"name":"token","type":"address","internalType":"address"}]}];
var contract = new ethers.Contract("0x42E27c9d456D969392e6cf790e649682654EDE00",abi,owner);

// 修改gteth合约地址
var updateGTETHTx = await contract.setGTETH("0xA5b68cE84F12c55ACAC70dEbB46A064624951554");
await updateGTETHTx.wait();
console.log("updateGTETHTx success!");

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});