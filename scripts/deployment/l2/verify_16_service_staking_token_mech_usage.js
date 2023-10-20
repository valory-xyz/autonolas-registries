const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const serviceStakingParams = parsedData.serviceStakingParams;
const serviceRegistryAddress = parsedData.serviceRegistryAddress;
const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
const olasAddress = parsedData.olasAddress;
const multisigProxyHash130 = parsedData.multisigProxyHash130;
const agentMechAddress = parsedData.agentMechAddress;

module.exports = [
    serviceStakingParams,
    serviceRegistryAddress,
    serviceRegistryTokenUtilityAddress,
    olasAddress,
    multisigProxyHash130,
    agentMechAddress
];