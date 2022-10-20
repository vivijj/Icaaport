import { ethers } from "hardhat";

async function main() {
    let [platform, creator, collector] = await ethers.getSigners();

    const Icaaport = await ethers.getContractFactory("Icaaport");
    const Collection = await ethers.getContractFactory("Collection");
    let icaaport = await Icaaport.attach("0x5FbDB2315678afecb367f032d93F642f64180aa3");
    let collection = await Collection.attach("0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512");

    // add collection
    await icaaport.addNewCollection("0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", creator.address,0);

    // mint token
    collection = collection.connect(creator);
    await collection.mintCollectionItem("xxx");
    console.log(`current owner is ${await collection.ownerOf(0)}`);
    // approve
    await collection.setApprovalForAll(icaaport.address, true);
    
    icaaport = icaaport.connect(creator);
    await icaaport.setFixPriceSale("0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", 0, 120);

    icaaport = icaaport.connect(collector);
    await icaaport.purchaseByFixedPrice("0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",0, {value: 120});
    console.log(`new owner is ${await collection.ownerOf(0)}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
