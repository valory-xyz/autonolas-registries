const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const serviceRegistryName = parsedData.serviceRegistryName;
const serviceRegistrySymbol = parsedData.serviceRegistrySymbol;
const baseURI = parsedData.baseURI;
const agentRegistryAddress = parsedData.agentRegistryAddress;

module.exports = [
    serviceRegistryName,
    serviceRegistrySymbol,
    baseURI,
    agentRegistryAddress
];