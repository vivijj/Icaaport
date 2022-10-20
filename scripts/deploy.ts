import { ethers } from "hardhat";

async function main() {
  const Icaaport = await ethers.getContractFactory("Icaaport");
  const Collection = await ethers.getContractFactory("Collection");
  const icaaport = await Icaaport.deploy();
  const collection = await Collection.deploy("test", "test");

  await icaaport.deployed();
  await collection.deployed();


  console.log(`icaa deployed to ${icaaport.address}`);
  console.log(`collection deploy to ${collection.address}`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
