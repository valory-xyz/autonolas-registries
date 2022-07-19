const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const componentRegistryName = parsedData.componentRegistryName;
const componentRegistrySymbol = parsedData.componentRegistrySymbol;
const baseURI = parsedData.baseURI;

module.exports = [
    componentRegistryName,
    componentRegistrySymbol,
    baseURI
];