const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const olasAddress = parsedData.olasAddress;
const minStakingDepositLimit = parsedData.minStakingDepositLimit;
const timeForEmissionsLimit = parsedData.timeForEmissionsLimit;
const numServicesLimit = parsedData.numServicesLimit;
const apyLimit = parsedData.apyLimit;
const serviceRegistryAddress = parsedData.serviceRegistryAddress;
const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;

module.exports = [
    olasAddress,
    serviceRegistryAddress,
    serviceRegistryTokenUtilityAddress,
    minStakingDepositLimit,
    timeForEmissionsLimit,
    numServicesLimit,
    apyLimit
];