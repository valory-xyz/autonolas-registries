const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const serviceStakingParams = parsedData.serviceStakingParams;
const serviceRegistryAddress = parsedData.serviceRegistryAddress;
const multisigProxyHash130 = parsedData.multisigProxyHash130;
const agentMechAddress = parsedData.agentMechAddress;

module.exports = [
    serviceStakingParams,
    serviceRegistryAddress,
    multisigProxyHash130,
    agentMechAddress
];