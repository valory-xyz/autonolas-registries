const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const gnosisSafeL2Address = parsedData.gnosisSafeL2Address;
const gnosisSafeProxyFactoryAddress = parsedData.gnosisSafeProxyFactoryAddress;

module.exports = [
    gnosisSafeL2Address,
    gnosisSafeProxyFactoryAddress
];