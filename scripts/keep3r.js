/*global process ethers*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

async function main() {
    // Read ABI from the JSON file
    const fs = require("fs");
    const Keep3rJSON = "lib/keep3r-notebooks/artifacts/Keep3r.sol/Keep3r.json";
    let contractFromJSON = fs.readFileSync(Keep3rJSON, "utf8");
    let contract = JSON.parse(contractFromJSON);
    const Keep3rABI = contract["abi"];

    // Get the Keep3r contract instance
    const keep3r = await ethers.getContractAt(Keep3rABI, "0xeb02addCfD8B773A5FFA6B9d1FE99c566f8c44CC");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
