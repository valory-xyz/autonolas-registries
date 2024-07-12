const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const olasAddress = parsedData.olasAddress;
const rewardsPerSecondLimit = parsedData.rewardsPerSecondLimit;
const timeForEmissionsLimit = parsedData.timeForEmissionsLimit;
const numServicesLimit = parsedData.numServicesLimit;
const serviceRegistryAddress = parsedData.serviceRegistryAddress;
const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;

module.exports = [
    olasAddress,
    serviceRegistryAddress,
    serviceRegistryTokenUtilityAddress,
    rewardsPerSecondLimit,
    timeForEmissionsLimit,
    numServicesLimit
];