# Running with custom contracts

You can use the the `valory/autonolas-registries` image as the base image and extend it to include any custom contract that you want.

To use custom smart contracts, first you'll have to define a custom deploy script which will be used during the deployment to deploy contracts. Use the `custom_deploy.js` file to start and define the deployment file. For example if you have a contract `CustomContract`, you can deploy it using

```js
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
```

Then you'll have to define a docker file using the format given in `Dockerfile.deploy` file in the root folder.

```dockerfile
FROM valory/autonolas-registries:v1.0.0

RUN mkdir /custom
COPY deploy/ /base/deploy/
COPY artifacts/ /custom/artifacts/

WORKDIR /base

ENTRYPOINT ["bash", "entrypoint.sh"]
```

Now you can build an image which will include your custom contract.

**Note** : If you want the registries contracts deployed before you deploy your custom contracts make sure you don't start the name of your file with `0` or an ascii symbol which will come before zero in the ascending order or your deployment script will run before the registry contracts deployment script.