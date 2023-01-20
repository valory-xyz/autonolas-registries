/*global ethers*/

const fs = require("fs");

async function deployByArtifact(filePath) {
    const dataFromJSON = fs.readFileSync(filePath, "utf8");
    const artifact = JSON.parse(dataFromJSON);

    const factory = await ethers.getContractFactoryFromArtifact(artifact);
    const instance = await factory.deploy();
    await instance.deployed();

    console.log(`Deployed ${artifact.contractName} at: ${instance.address}`);
    return instance;
}

module.exports = async () =>{
    deployByArtifact("/custom/artifacts/contracts/CustomContract.sol/CustomContract.json");
};
