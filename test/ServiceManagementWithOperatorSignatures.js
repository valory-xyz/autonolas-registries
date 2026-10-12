/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("ServiceManagementWithOperatorSignatures", function () {
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
    let token;
    let operatorContract;
    let timelock;
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
    // Deadline of signed messages that do not test it
    const maxDeadline = ethers.constants.MaxUint256;
    // "Unbond(address operator,address serviceOwner,uint256 serviceId,uint256 deadline,uint256 nonce)"
    const EIP712_UNBOND_TX_TYPE = {
        Unbond: [
            { type: "address", name: "operator" },
            { type: "address", name: "serviceOwner" },
            { type: "uint256", name: "serviceId" },
            { type: "uint256", name: "deadline" },
            { type: "uint256", name: "nonce" },
        ]
    };
    // "RegisterAgents(address operator,address serviceOwner,uint256 serviceId,address[] agentInstances,
    // uint32[] agentIds,address bondToken,uint256 maxBond,uint256 deadline,uint256 nonce)"
    const EIP712_REGISTER_AGENTS_TX_TYPE = {
        RegisterAgents: [
            { type: "address", name: "operator" },
            { type: "address", name: "serviceOwner" },
            { type: "uint256", name: "serviceId" },
            { type: "address[]", name: "agentInstances" },
            { type: "uint32[]", name: "agentIds" },
            { type: "address", name: "bondToken" },
            { type: "uint256", name: "maxBond" },
            { type: "uint256", name: "deadline" },
            { type: "uint256", name: "nonce" },
        ]
    };
    let bytecodeHash;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        operator = signers[1];

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

        const GnosisSafeProxy = await ethers.getContractFactory("GnosisSafeProxy");
        const gnosisSafeProxy = await GnosisSafeProxy.deploy(gnosisSafe.address);
        await gnosisSafeProxy.deployed();
        const bytecode = await ethers.provider.getCode(gnosisSafeProxy.address);
        bytecodeHash = ethers.utils.keccak256(bytecode);

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(bytecodeHash, gnosisSafe.address);
        await gnosisSafeSameAddressMultisig.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", "https://localhost/service/",
            agentRegistry.address);
        await serviceRegistry.deployed();

        const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
        serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
        await serviceRegistryTokenUtility.deployed();

        const ServiceManager = await ethers.getContractFactory("ServiceManager");
        serviceManager = await ServiceManager.deploy(serviceRegistry.address, serviceRegistryTokenUtility.address);
        await serviceManager.deployed();

        let proxyData = serviceManager.interface.encodeFunctionData("initialize", []);
        // Deploy serviceManager proxy based on the needed serviceManager initialization
        const ServiceManagerProxy = await ethers.getContractFactory("ServiceManagerProxy");
        const serviceManagerProxy = await ServiceManagerProxy.deploy(serviceManager.address, proxyData);
        await serviceManagerProxy.deployed();

        // Wrap serviceManager proxy contract
        serviceManager = await ethers.getContractAt("ServiceManager", serviceManagerProxy.address);

        const Token = await ethers.getContractFactory("ERC20Token");
        token = await Token.deploy();
        await token.deployed();

        const OperatorContract = await ethers.getContractFactory("MockOperatorContract");
        operatorContract = await OperatorContract.deploy();
        await operatorContract.deployed();

        const Timelock = await ethers.getContractFactory("MockTimelock");
        timelock = await Timelock.deploy();
        await timelock.deployed();

        // Change registries managers
        await componentRegistry.changeManager(deployer.address);
        await agentRegistry.changeManager(deployer.address);
        await serviceRegistry.changeManager(deployer.address);
        // Create one default component
        await componentRegistry.create(deployer.address, defaultHash, []);
    });

    context("Redeployment of services", async function () {
        it("Changing the service owner and redeploying with the new multisig owner", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

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
            const unbondNonce = await serviceManager.getOperatorUnbondNonce(operator.address, serviceId);
            const unbondTx = { operator: operator.address, serviceOwner: serviceOwnerAddress, serviceId: serviceId, deadline: maxDeadline, nonce: unbondNonce };
            const chainId = (await ethers.provider.getNetwork()).chainId;

            const managerName = await serviceManager.NAME();
            const managerVersion = await serviceManager.VERSION();
            const EIP712_DOMAIN = { name: managerName, version: managerVersion, chainId: chainId, verifyingContract: serviceManager.address };
            // Get the signature of an unbond transaction
            let signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_UNBOND_TX_TYPE, unbondTx);
            // Unbond the agent instance in order to update the service using a pre-signed operator message
            nonce = await serviceOwnerMultisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceManager, "unbondWithSignature",
                [operator.address, serviceId, maxDeadline, signatureBytes], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);

            // Check that the unbond nonce has changed
            expect(await serviceManager.getOperatorUnbondNonce(operator.address, serviceId)).to.equal(unbondNonce + 1);

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
            const registerAgentsNonce = await serviceManager.getOperatorRegisterAgentsNonce(operator.address, serviceId);
            const agentIds = new Array(4).fill(agentId);
            // Bond terms the operator signs for: the service bond token and the total bond of the four instances
            const bondToken = ETHAddress;
            const maxBond = agentIds.length * regBond;
            const registerAgentsTx = { operator: operator.address, serviceOwner: serviceOwnerAddress, serviceId: serviceId,
                agentInstances: agentInstancesAddresses, agentIds: agentIds, bondToken: bondToken, maxBond: maxBond,
                deadline: maxDeadline, nonce: registerAgentsNonce };

            // Get the signature for the register agents transaction
            signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_REGISTER_AGENTS_TX_TYPE, registerAgentsTx);

            // Register agent instances via a signed operator transaction
            nonce = await serviceOwnerMultisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceManager, "registerAgentsWithSignature",
                [operator.address, serviceId, agentInstancesAddresses, agentIds, bondToken, maxBond, maxDeadline, signatureBytes], nonce, 0, 0);
            txHashData.value = 4 * regBond;
            signMessageData = [await safeContracts.safeSignMessage(serviceOwnerOwners[0], serviceOwnerMultisig, txHashData, 0),
                await safeContracts.safeSignMessage(serviceOwnerOwners[1], serviceOwnerMultisig, txHashData, 0)];
            await safeContracts.executeTx(serviceOwnerMultisig, txHashData, signMessageData, 0);
            // Check that the register agents nonce has changed
            expect(await serviceManager.getOperatorRegisterAgentsNonce(operator.address, serviceId)).to.equal(registerAgentsNonce + 1);

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

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Several scenarios with errors when unbonding using operator signatures with the token-secured service", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const agentInstances = [signers[2], signers[3], signers[4], signers[5]];
            const agentInstancesAddresses = [signers[2].address, signers[3].address, signers[4].address, signers[5].address];
            const maxThreshold = 1;
            const newMaxThreshold = 4;
            const serviceOwner = signers[6];
            const serviceOwnerAddress = serviceOwner.address;

            // Mint tokens to the service owner and the operator and approve for the Service Registry Token Utility contract
            const initSupply = "1" + "0".repeat(20);
            await token.mint(operator.address, initSupply);
            await token.mint(serviceOwnerAddress, initSupply);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            await token.connect(serviceOwner).approve(serviceRegistryTokenUtility.address, initSupply);

            // Create an agent
            await agentRegistry.create(signers[0].address, defaultHash, [1]);

            // Change Service Registry manager to the real one
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);

            // Create services and activate the agent instance registration
            await serviceManager.connect(serviceOwner).create(serviceOwner.address, token.address, defaultHash, [1], [[1, regBond]], maxThreshold);

            // Activate agent instance registration
            await serviceManager.connect(serviceOwner).activateRegistration(serviceId, {value: 1});

            /// Register agent instance
            await serviceManager.connect(operator).registerAgents(serviceId, [agentInstances[0].address], [agentId], {value: 1});

            // Whitelist both gnosis multisig implementations
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

            // Deploy the service and create a multisig and get its address
            const safe = await serviceManager.connect(serviceOwner).deploy(serviceId, gnosisSafeMultisig.address, payload);
            let result = await safe.wait();
            const proxyAddress = result.events[0].address;
            // Getting a real multisig address
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // AT THIS POINT THE SERVICE IS CONSIDERED TO BE TRANSFERRED TO ANOTHER OWNER

            // Terminate a service after some time
            await serviceManager.connect(serviceOwner).terminate(serviceId);

            // Try to unbond agent instances on behalf of the operator not by the service owner
            await expect(
                serviceManager.connect(operator).unbondWithSignature(AddressZero, serviceId, maxDeadline, "0x")
            ).to.be.revertedWithCustomError(serviceManager, "OwnerOnly");

            // Try to unbond agent instances on behalf of the operator with the zero operator address
            await expect(
                serviceManager.connect(serviceOwner).unbondWithSignature(AddressZero, serviceId, maxDeadline, "0x")
            ).to.be.revertedWithCustomError(serviceManager, "ZeroOperatorAddress");

            // Try to unbond agent instances on behalf of the operator with the zero signature bytes
            await expect(
                serviceManager.connect(serviceOwner).unbondWithSignature(operator.address, serviceId, maxDeadline, "0x")
            ).to.be.revertedWithCustomError(serviceManager, "IncorrectSignatureLength");

            // Get the unbond function related data for the operator signed transaction
            const unbondNonce = await serviceManager.getOperatorUnbondNonce(operator.address, serviceId);
            const unbondTx = { operator: operator.address, serviceOwner: serviceOwnerAddress, serviceId: serviceId, deadline: maxDeadline, nonce: unbondNonce };
            const chainId = (await ethers.provider.getNetwork()).chainId;

            const managerName = await serviceManager.NAME();
            const managerVersion = await serviceManager.VERSION();
            const EIP712_DOMAIN = { name: managerName, version: managerVersion, chainId: chainId, verifyingContract: serviceManager.address };
            // Get the signature of an unbond transaction
            let signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_UNBOND_TX_TYPE, unbondTx);

            // Unbond the agent instance in order to update the service using a pre-signed operator message
            // Case 1. Simulate the unbond when the message was signed by the ledger (change v value to 0-3 in theory)
            // Take last byte of the v value and subtract 27
            const lastByte = signatureBytes.slice(-2);
            const lastByteValue = parseInt(lastByte, 16) - 27;
            const ledgerSignatureBytes = signatureBytes.substring(0, signatureBytes.length - 2) + "0" + lastByteValue.toString(16);

            result = await serviceManager.connect(serviceOwner).callStatic.unbondWithSignature(operator.address, serviceId, maxDeadline, ledgerSignatureBytes);
            expect(result.success).to.be.true;

            // Case 2. Approve the hash and provide the signature to follow the approved hash path
            // Build the signature to follow the approved hash path
            const approveSignatureBytes = "0x000000000000000000000000" + operator.address.slice(2) +
                "0000000000000000000000000000000000000000000000000000000000000000" + "05";

            // Try to unbond agent instances on behalf of the operator without the hash being pre-approved
            await expect(
                serviceManager.connect(serviceOwner).unbondWithSignature(operator.address, serviceId, maxDeadline, approveSignatureBytes)
            ).to.be.revertedWithCustomError(serviceManager, "HashNotApproved");

            // Approve the hash by the operator
            let msgHash = await serviceManager.getUnbondHash(operator.address, serviceOwner.address, serviceId, maxDeadline, unbondNonce);
            await serviceManager.connect(operator).operatorApproveHash(msgHash);
            // Check that the hash is approved
            expect(await serviceManager.isOperatorHashApproved(operator.address, msgHash)).to.be.true;

            // Simulate the unbond with the pre-approved hash
            result = await serviceManager.connect(serviceOwner).callStatic.unbondWithSignature(operator.address, serviceId, maxDeadline, approveSignatureBytes);
            expect(result.success).to.be.true;

            // Case 3. Provide the signature to follow the isValidSignature() path when the operator is the contract
            // Build the signature to follow the contract hash verification path
            const verifySignatureBytes = "0x000000000000000000000000" + operatorContract.address.slice(2) +
                "0000000000000000000000000000000000000000000000000000000000000000" + "04";

            // Try to unbond agent instances on behalf of the operator without the hash being validated
            await expect(
                serviceManager.connect(serviceOwner).unbondWithSignature(operatorContract.address, serviceId, maxDeadline, verifySignatureBytes)
            ).to.be.revertedWithCustomError(serviceManager, "HashNotValidated");

            // Validate the hash
            msgHash = await serviceManager.getUnbondHash(operatorContract.address, serviceOwner.address, serviceId, maxDeadline, unbondNonce);
            await operatorContract.approveHash(msgHash);

            // Simulate the unbond with the pre-approved hash
            // Just checking for the approval part and failing as the operator does not have any agent instances
            await expect(
                serviceManager.connect(serviceOwner).callStatic.unbondWithSignature(operatorContract.address, serviceId, maxDeadline, verifySignatureBytes)
            ).to.be.revertedWithCustomError(serviceManager, "OperatorHasNoInstances");

            // Try to use a different operator address
            await expect(
                serviceManager.connect(serviceOwner).callStatic.unbondWithSignature(serviceOwnerAddress, serviceId, maxDeadline, signatureBytes)
            ).to.be.revertedWithCustomError(serviceManager, "WrongOperatorAddress");

            // Perform the actual unbond
            await serviceManager.connect(serviceOwner).unbondWithSignature(operator.address, serviceId, maxDeadline, ledgerSignatureBytes);

            // At this point of time the agent instance gives the ownership rights to the service owner
            // In other words, swap the owner of the multisig to the service owner (agent instance to give up rights for the service owner)
            // Since there was only one agent instance, the previous multisig owner address is the sentinel one defined by gnosis (0x1)
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const sentinelOwners = "0x" + "0".repeat(39) + "1";
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "swapOwner",
                [sentinelOwners, agentInstances[0].address, serviceOwnerAddress], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Updating a service
            await serviceManager.connect(serviceOwner).update(token.address, defaultHash, [1], [[4, regBond]], newMaxThreshold, serviceId);

            // Activate agent instance registration
            await serviceManager.connect(serviceOwner).activateRegistration(serviceId, {value: 1});

            const agentIds = new Array(4).fill(agentId);
            // Try to register agent instances on behalf of the operator not by the service owner
            await expect(
                serviceManager.connect(operator).registerAgentsWithSignature(operator.address, serviceId,
                    agentInstancesAddresses, agentIds, token.address, 0, maxDeadline, "0x")
            ).to.be.revertedWithCustomError(serviceManager, "OwnerOnly");

            // Try to register agent instances on behalf of the operator with the wrong signature
            await expect(
                serviceManager.connect(serviceOwner).registerAgentsWithSignature(operator.address, serviceId,
                    agentInstancesAddresses, agentIds, token.address, 0, maxDeadline, "0x")
            ).to.be.revertedWithCustomError(serviceManager, "IncorrectSignatureLength");

            // Get the register agents function related data for the operator signed transaction
            const registerAgentsNonce = await serviceManager.getOperatorRegisterAgentsNonce(operator.address, serviceId);
            // Bond terms the operator signs for: the service bond token and the total bond of the four instances
            const bondToken = token.address;
            const maxBond = agentIds.length * regBond;
            const registerAgentsTx = { operator: operator.address, serviceOwner: serviceOwnerAddress, serviceId: serviceId,
                agentInstances: agentInstancesAddresses, agentIds: agentIds, bondToken: bondToken, maxBond: maxBond,
                deadline: maxDeadline, nonce: registerAgentsNonce };

            // Get the signature for the register agents transaction
            signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_REGISTER_AGENTS_TX_TYPE, registerAgentsTx);

            // Register agent instances via a signed operator transaction
            await serviceManager.connect(serviceOwner).registerAgentsWithSignature(operator.address, serviceId,
                agentInstancesAddresses, agentIds, bondToken, maxBond, maxDeadline, signatureBytes, {value: agentInstances.length});

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
            await multisig.connect(serviceOwner).approveHash(messageHash);

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
            await serviceManager.connect(serviceOwner).deploy(serviceId, gnosisSafeSameAddressMultisig.address, packedData);

            // Check that the service is deployed
            const service = await serviceRegistry.getService(serviceId);
            expect(service.state).to.equal(4);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Redeploy service in one shot via the timelock contract", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const agentInstances = [signers[2], signers[3], signers[4], signers[5]];
            const agentInstancesAddresses = [signers[2].address, signers[3].address, signers[4].address, signers[5].address];
            const maxThreshold = 1;
            const newMaxThreshold = 4;
            const serviceOwner = signers[6];
            let serviceOwnerAddress = serviceOwner.address;

            // Mint tokens to the current service owner, timelock and the operator
            const initSupply = "1" + "0".repeat(20);
            await token.mint(operator.address, initSupply);
            await token.mint(serviceOwnerAddress, initSupply);
            await token.mint(serviceOwnerAddress, initSupply);
            // Approve for the Service Registry Token Utility contract
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            await token.connect(serviceOwner).approve(serviceRegistryTokenUtility.address, initSupply);

            // Create an agent
            await agentRegistry.create(signers[0].address, defaultHash, [1]);

            // Change Service Registry manager to the real one
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);

            // Create services and activate the agent instance registration
            await serviceManager.connect(serviceOwner).create(serviceOwner.address, token.address, defaultHash, [1], [[1, regBond]], maxThreshold);

            // Activate agent instance registration
            await serviceManager.connect(serviceOwner).activateRegistration(serviceId, {value: 1});

            /// Register agent instance
            await serviceManager.connect(operator).registerAgents(serviceId, [agentInstances[0].address], [agentId], {value: 1});

            // Whitelist both gnosis multisig implementations
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

            // Deploy the service and create a multisig and get its address
            const safe = await serviceManager.connect(serviceOwner).deploy(serviceId, gnosisSafeMultisig.address, payload);
            let result = await safe.wait();
            const proxyAddress = result.events[0].address;
            // Getting a real multisig address
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // AT THIS POINT THE SERVICE IS CONSIDERED TO BE TRANSFERRED TO THE TIMELOCK
            await serviceRegistry.connect(serviceOwner)["safeTransferFrom(address,address,uint256)"](serviceOwnerAddress,
                timelock.address, serviceId);
            serviceOwnerAddress = timelock.address;

            // Send some ETH to the timelock address
            await deployer.sendTransaction({to: serviceOwnerAddress, value: ethers.utils.parseEther("1000")});

            // An agent instance gives the ownership rights to the new service owner or the timelock address
            // In other words, swap the owner of the multisig to the service owner (agent instance to give up rights for the service owner)
            // Since there was only one agent instance, the previous multisig owner address is the sentinel one defined by gnosis (0x1)
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const sentinelOwners = "0x" + "0".repeat(39) + "1";
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "swapOwner",
                [sentinelOwners, agentInstances[0].address, serviceOwnerAddress], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            let targets = new Array();
            let values = new Array();
            let payloads = new Array();

            // Approve timelock tokens for the Service Registry Token Utility contract
            targets.push(token.address);
            values.push(0);
            payloads.push(token.interface.encodeFunctionData("approve", [serviceRegistryTokenUtility.address, initSupply]));
            //await token.connect(timelock).approve(serviceRegistryTokenUtility.address, initSupply);

            // Terminate a service after some time
            targets.push(serviceManager.address);
            values.push(0);
            payloads.push(serviceManager.interface.encodeFunctionData("terminate", [serviceId]));
            //await serviceManager.connect(timelock).terminate(serviceId);

            // Get the unbond function related data for the operator signed transaction
            const unbondNonce = await serviceManager.getOperatorUnbondNonce(operator.address, serviceId);
            const unbondTx = { operator: operator.address, serviceOwner: serviceOwnerAddress, serviceId: serviceId, deadline: maxDeadline, nonce: unbondNonce };
            const chainId = (await ethers.provider.getNetwork()).chainId;

            const managerName = await serviceManager.NAME();
            const managerVersion = await serviceManager.VERSION();
            const EIP712_DOMAIN = { name: managerName, version: managerVersion, chainId: chainId, verifyingContract: serviceManager.address };
            // Get the signature of an unbond transaction
            let signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_UNBOND_TX_TYPE, unbondTx);

            // Unbond the agent instance in order to update the service using a pre-signed operator message
            targets.push(serviceManager.address);
            values.push(0);
            payloads.push(serviceManager.interface.encodeFunctionData("unbondWithSignature", [operator.address,
                serviceId, maxDeadline, signatureBytes]));
            //await serviceManager.connect(timelock).unbondWithSignature(operator.address, serviceId, maxDeadline, ledgerSignatureBytes);

            // Update a service
            targets.push(serviceManager.address);
            values.push(0);
            payloads.push(serviceManager.interface.encodeFunctionData("update", [token.address, defaultHash, [1],
                [[4, regBond]], newMaxThreshold, serviceId]));
            //await serviceManager.connect(timelock).update(token.address, defaultHash, [1], [[4, regBond]], newMaxThreshold, serviceId);

            // Activate agent instance registration
            targets.push(serviceManager.address);
            values.push(1);
            payloads.push(serviceManager.interface.encodeFunctionData("activateRegistration", [serviceId]));
            //await serviceManager.connect(timelock).activateRegistration(serviceId, {value: 1});

            const agentIds = new Array(4).fill(agentId);
            // Get the register agents function related data for the operator signed transaction
            const registerAgentsNonce = await serviceManager.getOperatorRegisterAgentsNonce(operator.address, serviceId);
            // Bond terms the operator signs for: the service bond token and the total bond of the four instances
            const bondToken = token.address;
            const maxBond = agentIds.length * regBond;
            const registerAgentsTx = { operator: operator.address, serviceOwner: serviceOwnerAddress, serviceId: serviceId,
                agentInstances: agentInstancesAddresses, agentIds: agentIds, bondToken: bondToken, maxBond: maxBond,
                deadline: maxDeadline, nonce: registerAgentsNonce };

            // Get the signature for the register agents transaction
            signatureBytes = await operator._signTypedData(EIP712_DOMAIN, EIP712_REGISTER_AGENTS_TX_TYPE, registerAgentsTx);

            // Register agent instances via a signed operator transaction
            targets.push(serviceManager.address);
            values.push(agentInstances.length);
            payloads.push(serviceManager.interface.encodeFunctionData("registerAgentsWithSignature", [operator.address,
                serviceId, agentInstancesAddresses, agentIds, bondToken, maxBond, maxDeadline, signatureBytes]));
            //await serviceManager.connect(timelock).registerAgentsWithSignature(operator.address, serviceId,
            //agentInstancesAddresses, agentIds, bondToken, maxBond, maxDeadline, signatureBytes, {value: agentInstances.length});

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
            targets.push(multisig.address);
            values.push(0);
            payloads.push(multisig.interface.encodeFunctionData("approveHash", [messageHash]));
            //await multisig.connect(timelock).approveHash(messageHash);

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
            targets.push(serviceManager.address);
            values.push(0);
            payloads.push(serviceManager.interface.encodeFunctionData("deploy", [serviceId,
                gnosisSafeSameAddressMultisig.address, packedData]));
            //await serviceManager.connect(timelock).deploy(serviceId, gnosisSafeSameAddressMultisig.address, packedData);

            //console.log(targets);
            //console.log(values);
            //console.log(payloads);

            // Execute the timelock transaction that does the full cycle and redeploys the service
            await timelock.executeBatch(targets, values, payloads);

            // Check that the service is deployed
            const service = await serviceRegistry.getService(serviceId);
            expect(service.state).to.equal(4);

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });

    context("Operator-signed messages", async function () {
        const serviceOwnerIndex = 6;
        let serviceOwner;

        beforeEach(async function () {
            serviceOwner = signers[serviceOwnerIndex];
            // Mint tokens to the operator and the service owner and approve them for the Service Registry Token Utility
            const initSupply = "1" + "0".repeat(20);
            for (const account of [operator, serviceOwner]) {
                await token.mint(account.address, initSupply);
                await token.connect(account).approve(serviceRegistryTokenUtility.address, initSupply);
            }
            // Two agents, so that registrations can mix agent Ids with different bonds
            await agentRegistry.create(deployer.address, defaultHash, [1]);
            await agentRegistry.create(deployer.address, defaultHash, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);
        });

        // Creates a service with the given bond token and per-agent [slots, bond] params, then activates it
        async function createActiveService(bondToken, agentIds, agentParams) {
            const numInstances = agentParams.reduce((sum, params) => sum + params[0], 0);
            await serviceManager.connect(serviceOwner).create(serviceOwner.address, bondToken, defaultHash, agentIds,
                agentParams, numInstances);
            const sId = await serviceRegistry.totalSupply();
            const securityDeposit = bondToken == ETHAddress ? Math.max(...agentParams.map((params) => params[1])) : 1;
            await serviceManager.connect(serviceOwner).activateRegistration(sId, {value: securityDeposit});
            return sId;
        }

        async function domain() {
            return { name: await serviceManager.NAME(), version: await serviceManager.VERSION(),
                chainId: (await ethers.provider.getNetwork()).chainId, verifyingContract: serviceManager.address };
        }

        // Typed register agents message of the operator for the current nonce
        async function registerAgentsMessage(signer, sId, agentInstances, agentIds, bondToken, maxBond, deadline) {
            return { operator: signer.address, serviceOwner: serviceOwner.address, serviceId: sId,
                agentInstances: agentInstances, agentIds: agentIds, bondToken: bondToken, maxBond: maxBond,
                deadline: deadline, nonce: await serviceManager.getOperatorRegisterAgentsNonce(signer.address, sId) };
        }

        async function signRegisterAgents(signer, sId, agentInstances, agentIds, bondToken, maxBond, deadline) {
            const message = await registerAgentsMessage(signer, sId, agentInstances, agentIds, bondToken, maxBond,
                deadline);
            return signer._signTypedData(await domain(), EIP712_REGISTER_AGENTS_TX_TYPE, message);
        }

        function register(sId, agentInstances, agentIds, bondToken, maxBond, deadline, signature, value) {
            return serviceManager.connect(serviceOwner).registerAgentsWithSignature(operator.address, sId,
                agentInstances, agentIds, bondToken, maxBond, deadline, signature, {value: value});
        }

        // Signature bytes that select the pre-approved hash path for the given operator
        function approvedHashSignature(operatorAddress) {
            return "0x000000000000000000000000" + operatorAddress.slice(2) + "0".repeat(64) + "05";
        }

        const instances = [signers => signers[2].address, signers => signers[3].address, signers => signers[4].address];
        function agentInstances(n) {
            return instances.slice(0, n).map((get) => get(signers));
        }

        it("Digests equal the standard EIP-712 encoding, including multiple elements and repeated agent Ids",
            async function () {
                const typedDomain = await domain();
                const cases = [
                    { agentInstances: agentInstances(1), agentIds: [1] },
                    { agentInstances: agentInstances(3), agentIds: [1, 1, 2] },
                    { agentInstances: agentInstances(3), agentIds: [2, 1, 2] },
                ];
                for (const [i, c] of cases.entries()) {
                    const message = { operator: operator.address, serviceOwner: deployer.address, serviceId: 7 + i,
                        agentInstances: c.agentInstances, agentIds: c.agentIds, bondToken: token.address,
                        maxBond: 12345 + i, deadline: 1700000000 + i, nonce: i };
                    const expected = ethers.utils._TypedDataEncoder.hash(typedDomain, EIP712_REGISTER_AGENTS_TX_TYPE,
                        message);
                    expect(await serviceManager.getRegisterAgentsHash(message.operator, message.serviceOwner,
                        message.serviceId, message.agentInstances, message.agentIds, message.bondToken, message.maxBond,
                        message.deadline, message.nonce)).to.equal(expected);
                }

                const unbond = { operator: operator.address, serviceOwner: deployer.address, serviceId: 9,
                    deadline: 1700000000, nonce: 3 };
                expect(await serviceManager.getUnbondHash(unbond.operator, unbond.serviceOwner, unbond.serviceId,
                    unbond.deadline, unbond.nonce)).to.equal(
                    ethers.utils._TypedDataEncoder.hash(typedDomain, EIP712_UNBOND_TX_TYPE, unbond));

                // Type hashes are those of the standard type strings
                const registerEncoder = ethers.utils._TypedDataEncoder.from(EIP712_REGISTER_AGENTS_TX_TYPE);
                expect(await serviceManager.REGISTER_AGENTS_TYPE_HASH()).to.equal(
                    ethers.utils.id(registerEncoder.encodeType("RegisterAgents")));
                const unbondEncoder = ethers.utils._TypedDataEncoder.from(EIP712_UNBOND_TX_TYPE);
                expect(await serviceManager.UNBOND_TYPE_HASH()).to.equal(ethers.utils.id(unbondEncoder.encodeType("Unbond")));
            });

        it("Token-secured service: the provided value must match the bond wrapper total", async function () {
            const sId = await createActiveService(token.address, [1], [[2, regBond]]);
            const instancesList = agentInstances(2);
            const ids = [1, 1];
            const maxBond = 2 * regBond;
            const totalBond = instancesList.length;
            const signature = await signRegisterAgents(operator, sId, instancesList, ids, token.address, maxBond,
                maxDeadline);

            // Try to register with more and with less value than the bond wrapper total
            for (const value of [totalBond + 1, 0, totalBond - 1]) {
                await expect(register(sId, instancesList, ids, token.address, maxBond, maxDeadline, signature, value))
                    .to.be.revertedWithCustomError(serviceManager, "IncorrectAgentBondingValue")
                    .withArgs(value, totalBond, sId);
            }

            // Register with the exact value
            await register(sId, instancesList, ids, token.address, maxBond, maxDeadline, signature, totalBond);
            expect(await ethers.provider.getBalance(serviceManager.address)).to.equal(0);
            expect((await serviceRegistry.getService(sId)).state).to.equal(3);
        });

        it("ETH-secured service: the registry still checks the provided value", async function () {
            const sId = await createActiveService(ETHAddress, [1], [[2, regBond]]);
            const instancesList = agentInstances(2);
            const ids = [1, 1];
            const maxBond = 2 * regBond;
            const signature = await signRegisterAgents(operator, sId, instancesList, ids, ETHAddress, maxBond,
                maxDeadline);

            // A wrong value is still rejected by the Service Registry
            await expect(register(sId, instancesList, ids, ETHAddress, maxBond, maxDeadline, signature, regBond))
                .to.be.revertedWithCustomError(serviceRegistry, "IncorrectAgentBondingValue");

            // The full bond registers the agent instances
            await register(sId, instancesList, ids, ETHAddress, maxBond, maxDeadline, signature, maxBond);
            expect((await serviceRegistry.getService(sId)).state).to.equal(3);
            expect(await ethers.provider.getBalance(serviceManager.address)).to.equal(0);
        });

        it("The deadline is inclusive for registration and unbonding", async function () {
            const sId = await createActiveService(ETHAddress, [1], [[1, regBond]]);
            const instancesList = agentInstances(1);
            const deadline = (await helpers.time.latest()) + 1000;
            const signature = await signRegisterAgents(operator, sId, instancesList, [1], ETHAddress, regBond,
                deadline);

            // One second after the deadline the message is expired
            await helpers.time.setNextBlockTimestamp(deadline + 1);
            await expect(register(sId, instancesList, [1], ETHAddress, regBond, deadline, signature, regBond))
                .to.be.revertedWithCustomError(serviceManager, "SignatureExpired").withArgs(deadline, deadline + 1);

            // A message whose deadline is the current block timestamp is still valid
            const lastDeadline = (await helpers.time.latest()) + 10;
            const lastSignature = await signRegisterAgents(operator, sId, instancesList, [1], ETHAddress, regBond,
                lastDeadline);
            await helpers.time.setNextBlockTimestamp(lastDeadline);
            await register(sId, instancesList, [1], ETHAddress, regBond, lastDeadline, lastSignature, regBond);

            // Unbond: terminate, then sign an unbond message
            await serviceManager.connect(serviceOwner).terminate(sId);
            const unbondDeadline = (await helpers.time.latest()) + 1000;
            const unbondMessage = { operator: operator.address, serviceOwner: serviceOwner.address, serviceId: sId,
                deadline: unbondDeadline, nonce: await serviceManager.getOperatorUnbondNonce(operator.address, sId) };
            const unbondSignature = await operator._signTypedData(await domain(), EIP712_UNBOND_TX_TYPE, unbondMessage);

            await helpers.time.setNextBlockTimestamp(unbondDeadline + 1);
            await expect(serviceManager.connect(serviceOwner).unbondWithSignature(operator.address, sId, unbondDeadline,
                unbondSignature)).to.be.revertedWithCustomError(serviceManager, "SignatureExpired")
                .withArgs(unbondDeadline, unbondDeadline + 1);

            const lastUnbondDeadline = (await helpers.time.latest()) + 10;
            unbondMessage.deadline = lastUnbondDeadline;
            const lastUnbondSignature = await operator._signTypedData(await domain(), EIP712_UNBOND_TX_TYPE,
                unbondMessage);
            await helpers.time.setNextBlockTimestamp(lastUnbondDeadline);
            await serviceManager.connect(serviceOwner).unbondWithSignature(operator.address, sId, lastUnbondDeadline,
                lastUnbondSignature);
            expect(await serviceManager.getOperatorUnbondNonce(operator.address, sId)).to.equal(unbondMessage.nonce + 1);
        });

        it("The signed bond token must be the service bond token", async function () {
            const ETH_TOKEN_ADDRESS = await serviceManager.ETH_TOKEN_ADDRESS();
            expect(ETH_TOKEN_ADDRESS).to.equal(ETHAddress);
            const tokenService = await createActiveService(token.address, [1], [[1, regBond]]);
            const nativeService = await createActiveService(ETHAddress, [1], [[1, regBond]]);
            const instancesList = agentInstances(1);

            // [service, expected token, signed token]
            const wrong = [
                [tokenService, token.address, ETHAddress],
                [tokenService, token.address, AddressZero],
                [nativeService, ETHAddress, token.address],
                // The internal zero-address representation of a native-token service is not accepted
                [nativeService, ETHAddress, AddressZero],
            ];
            for (const [sId, expected, signed] of wrong) {
                const signature = await signRegisterAgents(operator, sId, instancesList, [1], signed, regBond,
                    maxDeadline);
                await expect(register(sId, instancesList, [1], signed, regBond, maxDeadline, signature, regBond))
                    .to.be.revertedWithCustomError(serviceManager, "WrongBondToken").withArgs(signed, expected);
            }
        });

        it("The bond cap is the total over the listed instances, repeated agent Ids included", async function () {
            // Agent 1 holds two slots with bond regBond, agent 2 one slot with bond 3 * regBond
            const bonds = { 1: regBond, 2: 3 * regBond };
            const ids = [1, 2, 1];
            const total = ids.reduce((sum, id) => sum + bonds[id], 0);

            for (const [bondToken, instancesList] of [[token.address, agentInstances(3)],
                [ETHAddress, [signers[7].address, signers[8].address, signers[9].address]]]) {
                const sId = await createActiveService(bondToken, [1, 2], [[2, bonds[1]], [1, bonds[2]]]);
                const value = bondToken == ETHAddress ? total : instancesList.length;

                // One below the total is rejected before any bond is collected
                const lowSignature = await signRegisterAgents(operator, sId, instancesList, ids, bondToken, total - 1,
                    maxDeadline);
                const operatorBalance = await token.balanceOf(operator.address);
                await expect(register(sId, instancesList, ids, bondToken, total - 1, maxDeadline, lowSignature, value))
                    .to.be.revertedWithCustomError(serviceManager, "BondExceedsMax").withArgs(total, total - 1);
                expect(await token.balanceOf(operator.address)).to.equal(operatorBalance);

                // A cap equal to the total registers
                const signature = await signRegisterAgents(operator, sId, instancesList, ids, bondToken, total,
                    maxDeadline);
                await register(sId, instancesList, ids, bondToken, total, maxDeadline, signature, value);
                expect((await serviceRegistry.getService(sId)).state).to.equal(3);
            }
        });

        it("A bond raised after signing exceeds the signed cap", async function () {
            for (const bondToken of [token.address, ETHAddress]) {
                // The operator signs for the bond configured at that time
                await serviceManager.connect(serviceOwner).create(serviceOwner.address, bondToken, defaultHash, [1],
                    [[1, regBond]], 1);
                const sId = await serviceRegistry.totalSupply();
                const instancesList = agentInstances(1);
                const signature = await signRegisterAgents(operator, sId, instancesList, [1], bondToken, regBond,
                    maxDeadline);

                // The service owner then raises the bond and activates the registration
                await serviceManager.connect(serviceOwner).update(bondToken, defaultHash, [1], [[1, 2 * regBond]], 1,
                    sId);
                await serviceManager.connect(serviceOwner).activateRegistration(sId,
                    {value: bondToken == ETHAddress ? 2 * regBond : 1});

                await expect(register(sId, instancesList, [1], bondToken, regBond, maxDeadline, signature,
                    bondToken == ETHAddress ? 2 * regBond : 1))
                    .to.be.revertedWithCustomError(serviceManager, "BondExceedsMax").withArgs(2 * regBond, regBond);
            }
        });

        it("A used registration message cannot be replayed", async function () {
            const sId = await createActiveService(ETHAddress, [1], [[2, regBond]]);
            const instancesList = agentInstances(1);
            const signature = await signRegisterAgents(operator, sId, instancesList, [1], ETHAddress, regBond,
                maxDeadline);
            await register(sId, instancesList, [1], ETHAddress, regBond, maxDeadline, signature, regBond);

            // The nonce has moved, so the same signature recovers a different address
            await expect(register(sId, instancesList, [1], ETHAddress, regBond, maxDeadline, signature, regBond))
                .to.be.revertedWithCustomError(serviceManager, "WrongOperatorAddress");
        });

        it("Pre-approved v2 hashes and EIP-1271 operators are accepted", async function () {
            const sId = await createActiveService(ETHAddress, [1], [[2, regBond]]);

            // Pre-approved hash
            const first = agentInstances(1);
            const message = await registerAgentsMessage(operator, sId, first, [1], ETHAddress, regBond, maxDeadline);
            const digest = ethers.utils._TypedDataEncoder.hash(await domain(), EIP712_REGISTER_AGENTS_TX_TYPE, message);
            await serviceManager.connect(operator).operatorApproveHash(digest);
            await register(sId, first, [1], ETHAddress, regBond, maxDeadline, approvedHashSignature(operator.address),
                regBond);

            // EIP-1271 operator contract
            const second = [signers[3].address];
            const contractMessage = { operator: operatorContract.address, serviceOwner: serviceOwner.address,
                serviceId: sId, agentInstances: second, agentIds: [1], bondToken: ETHAddress, maxBond: regBond,
                deadline: maxDeadline,
                nonce: await serviceManager.getOperatorRegisterAgentsNonce(operatorContract.address, sId) };
            const contractDigest = ethers.utils._TypedDataEncoder.hash(await domain(), EIP712_REGISTER_AGENTS_TX_TYPE,
                contractMessage);
            await operatorContract.approveHash(contractDigest);
            const contractSignature = "0x000000000000000000000000" + operatorContract.address.slice(2) +
                "0".repeat(64) + "04";
            await serviceManager.connect(serviceOwner).registerAgentsWithSignature(operatorContract.address, sId,
                second, [1], ETHAddress, regBond, maxDeadline, contractSignature, {value: regBond});
            expect((await serviceRegistry.getService(sId)).state).to.equal(3);
        });
    });
});