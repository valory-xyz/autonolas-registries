/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceRedeployment", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let serviceRegistryTokenUtility;
    let serviceManager;
    let gnosisSafe;
    let gnosisSafeMultisig;
    let gnosisSafeProxyFactory;
    let defaultCallbackHandler;
    let multiSend;
    let gnosisSafeSameAddressMultisig;
    let signers;
    let deployer;
    let operator;
    const defaultHash = "0x" + "5".repeat(64);
    const regBond = 1000;
    const regDeposit = 1000;
    const serviceId = 1;
    const agentId = 1;
    const AddressZero = "0x" + "0".repeat(40);
    const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    const payload = "0x";

    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const DefaultCallbackHandler = await ethers.getContractFactory("DefaultCallbackHandler");
        defaultCallbackHandler = await DefaultCallbackHandler.deploy();
        await defaultCallbackHandler.deployed();

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy();
        await gnosisSafeSameAddressMultisig.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", "https://localhost/service/",
            agentRegistry.address);
        await serviceRegistry.deployed();

        const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
        serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
        await serviceRegistryTokenUtility.deployed();

        const ServiceManager = await ethers.getContractFactory("ServiceManagerToken");
        serviceManager = await ServiceManager.deploy(serviceRegistry.address, serviceRegistryTokenUtility.address,
            AddressZero);
        await serviceManager.deployed();

        signers = await ethers.getSigners();
        deployer = signers[0];
        operator = signers[1];

        // Change registries managers
        await componentRegistry.changeManager(deployer.address);
        await agentRegistry.changeManager(deployer.address);
        await serviceRegistry.changeManager(deployer.address);
        // Create one default component
        await componentRegistry.create(deployer.address, defaultHash, []);

    });

    context("Redeployment of services", async function () {
        it("Changing the service owner and redeploying with the new multisig owner", async function () {
            const agentInstances = [signers[2], signers[3], signers[4], signers[5]];
            const agentInstancesAddresses = [signers[2].address, signers[3].address, signers[4].address, signers[5].address];
            const maxThreshold = 1;
            const newMaxThreshold = 4;
            const serviceOwnerOwners = [signers[6], signers[7], signers[8]];
            const serviceOwnerOwnersAddresses = [signers[6].address, signers[7].address, signers[8].address];
            const serviceOwnerThreshold = 2;

            // Create a multisig that will be the service owner
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const setupData = gnosisSafe.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                // defaultCallbackHandler is needed for the ERC721 support
                [serviceOwnerOwnersAddresses, serviceOwnerThreshold, AddressZero, "0x",
                    defaultCallbackHandler.address, AddressZero, 0, AddressZero]
            );
            let proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafe.address,
                setupData, 0);
            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafe.address, setupData, 0).then((tx) => tx.wait());
            const serviceOwnerMultisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
            const serviceOwnerAddress = serviceOwnerMultisig.address;

            // Send some ETH to the serviceOwnerAddress
            await deployer.sendTransaction({to: serviceOwnerAddress, value: ethers.utils.parseEther("1000")});

            // Create an agent
            await agentRegistry.create(signers[0].address, defaultHash, [1]);

            // Create services and activate the agent instance registration
            await serviceRegistry.create(serviceOwnerAddress, defaultHash, [1], [[1, regBond]], maxThreshold);

            // Activate agent instance registration
            await serviceRegistry.activateRegistration(serviceOwnerAddress, serviceId, {value: regDeposit});

            /// Register agent instance
            await serviceRegistry.registerAgents(operator.address, serviceId, [agentInstances[0].address], [agentId], {value: regBond});

            // Whitelist both gnosis multisig implementations
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

            // Deploy the service and create a multisig and get its address
            const safe = await serviceRegistry.deploy(serviceOwnerAddress, serviceId, gnosisSafeMultisig.address, payload);
            const result = await safe.wait();
            proxyAddress = result.events[0].address;
            // Getting a real multisig address
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // AT THIS POINT THE SERVICE IS CONSIDERED TO BE TRANSFERRED TO ANOTHER MULTISIG OWNER

            // Change Service Registry manager to the real one
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);

            // Terminate a service after some time
            let nonce = await serviceOwnerMultisig.nonce();
            let txHashData = await safeContracts.buildContractCall(serviceManager, "terminate", [serviceId], nonce, 0, 0);
            let signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);

            // Get the unbond function related data for the operator signed transaction
            const unbondTx = { operator: operator.address, serviceId: serviceId };
            const chainId = (await ethers.provider.getNetwork()).chainId;
            const EIP712_UNBOND_TX_TYPE = {
                // "Unbond(address operator,uint256 serviceId)"
                Unbond: [
                    { type: "address", name: "operator" },
                    { type: "uint256", name: "serviceId" },
                ]
            };

            const managerVersion = await serviceManager.VERSION();
            const EIP712_DOMAIN = {version: managerVersion, chainId: chainId, verifyingContract: serviceManager.address};
            // Get the signature of an unbond transaction
            let signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_UNBOND_TX_TYPE, unbondTx);
            // Unbond the agent instance in order to update the service using a pre-signed operator message
            nonce = await serviceOwnerMultisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceManager, "unbondWithSignature",
                [operator.address, serviceId, signatureBytes], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);
            //await serviceManager.connect().unbondWithSignature(operator.address, serviceId, signatureBytes);

            // At this point of time the agent instance gives the ownership rights to the service owner
            // In other words, swap the owner of the multisig to the service owner (agent instance to give up rights for the service owner)
            // Since there was only one agent instance, the previous multisig owner address is the sentinel one defined by gnosis (0x1)
            const sentinelOwners = "0x" + "0".repeat(39) + "1";
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "swapOwner",
                [sentinelOwners, agentInstances[0].address, serviceOwnerAddress], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Updating a service
            nonce = await serviceOwnerMultisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceManager, "update",
                [ETHAddress, defaultHash, [1], [[4, regBond]], newMaxThreshold, serviceId], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);

            // Activate agent instance registration
            nonce = await serviceOwnerMultisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceManager, "activateRegistration",
                [serviceId], nonce, 0, 0);
            txHashData.value = regDeposit;
            signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);

            // Get the register agents function related data for the operator signed transaction
            const agentIds = new Array(4).fill(agentId);
            // Get the solidity counterpart of keccak256(abi.encode(agentInstances, agentIds))
            const agentsData = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["address[]", "uint32[]"],
                [agentInstancesAddresses, agentIds]));
            const registerAgentsTx = { operator: operator.address, serviceId: serviceId, agentsData: agentsData };
            const EIP712_REGISTER_AGENTS_TX_TYPE = {
                // "RegisterAgents(address operator,uint256 serviceId,bytes32 agentsData)"
                RegisterAgents: [
                    { type: "address", name: "operator" },
                    { type: "uint256", name: "serviceId" },
                    { type: "bytes32", name: "agentsData" },
                ]
            };

            // Get the signature for the register agents transaction
            signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_REGISTER_AGENTS_TX_TYPE, registerAgentsTx);

            // Register agent instances via a signed operator transaction
            nonce = await serviceOwnerMultisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceManager, "registerAgentsWithSignature",
                [operator.address, serviceId, agentInstancesAddresses, agentIds, signatureBytes], nonce, 0, 0);
            txHashData.value = 4 * regBond;
            signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);

            /// Register agent instances with signature
            //await serviceManager.connect(operator).registerAgents(serviceId, agentInstancesAddresses, agentIds, {value: 4 * regBond});

            // Change the existent multisig owners and threshold in a multisend transaction using the service owner access
            let callData = [];
            let txs = [];
            nonce = await multisig.nonce();
            // Add the addresses, but keep the threshold the same
            for (let i = 0; i < agentInstances.length; i++) {
                callData[i] = multisig.interface.encodeFunctionData("addOwnerWithThreshold", [agentInstances[i].address, 1]);
                txs[i] = safeContracts.buildSafeTransaction({to: multisig.address, data: callData[i], nonce: 0});
            }
            // Remove the original multisig owner and change the threshold
            // Note that the prevOwner is the very first added address as it corresponds to the reverse order of added addresses
            // The order in the gnosis safe multisig is as follows: sentinelOwners => agentInstances[last].address => ... =>
            // => newOwnerAddresses[0].address => serviceOwnerAddress
            callData.push(multisig.interface.encodeFunctionData("removeOwner", [agentInstances[0].address, serviceOwnerAddress,
                newMaxThreshold]));
            txs.push(safeContracts.buildSafeTransaction({to: multisig.address, data: callData[callData.length - 1], nonce: 0}));

            // Build a multisend transaction to be executed by the service multisig
            const safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);

            // Create a message data from the multisend transaction
            const messageHash = await multisig.getTransactionHash(safeTx.to, safeTx.value, safeTx.data,
                safeTx.operation, safeTx.safeTxGas, safeTx.baseGas, safeTx.gasPrice, safeTx.gasToken,
                safeTx.refundReceiver, nonce);

            // Approve hash for the multisend transaction in the service multisig by the service owner multisig
            await safeContracts.executeContractCallWithSigners(serviceOwnerMultisig, multisig, "approveHash",
                [messageHash], [serviceOwnerOwners[0], serviceOwnerOwners[1]], false);
            // on the front-end: await multisig.connect(serviceOwnerMultisig).approveHash(messageHash);

            // Get the signature line. Since the hash is approved, it's enough to base one on the service owner address
            signatureBytes = "0x000000000000000000000000" + serviceOwnerAddress.slice(2) +
                "0000000000000000000000000000000000000000000000000000000000000000" + "01";

            // Form the multisend execTransaction call in the service multisig
            const safeExecData = gnosisSafe.interface.encodeFunctionData("execTransaction", [safeTx.to, safeTx.value,
                safeTx.data, safeTx.operation, safeTx.safeTxGas, safeTx.baseGas, safeTx.gasPrice, safeTx.gasToken,
                safeTx.refundReceiver, signatureBytes]);

            // Add the service multisig address on top of the multisig exec transaction data
            const packedData = ethers.utils.solidityPack(["address", "bytes"], [multisig.address, safeExecData]);

            // Redeploy the service updating the multisig with new owners and threshold
            nonce = await serviceOwnerMultisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceManager, "deploy",
                [serviceId, gnosisSafeSameAddressMultisig.address, packedData], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);

            // Check that the service is deployed
            const service = await serviceRegistry.getService(serviceId);
            expect(service.state).to.equal(4);
        });
    });
});