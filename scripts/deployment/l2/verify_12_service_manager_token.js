const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const serviceRegistryAddress = parsedData.serviceRegistryAddress;
const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
const operatorWhitelistAddress = parsedData.operatorWhitelistAddress;

module.exports = [
    serviceRegistryAddress,
    serviceRegistryTokenUtilityAddress,
    operatorWhitelistAddress
];