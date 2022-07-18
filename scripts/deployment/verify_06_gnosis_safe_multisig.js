const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const gnosisSafeAddress = parsedData.gnosisSafeAddress;
const gnosisSafeProxyFactoryAddress = parsedData.gnosisSafeProxyFactoryAddress;

module.exports = [
    gnosisSafeAddress,
    gnosisSafeProxyFactoryAddress
];