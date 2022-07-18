const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const componentRegistryName = parsedData.componentRegistryName;
const componentRegistrySymbol = parsedData.componentRegistrySymbol;
const componentRegistryBaseURI = parsedData.componentRegistryBaseURI;

module.exports = [
    componentRegistryName,
    componentRegistrySymbol,
    componentRegistryBaseURI
];