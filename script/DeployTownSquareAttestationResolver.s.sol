// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {IEAS} from "@eas-contracts/IEAS.sol";
import {ISchemaRegistry} from "@eas-contracts/ISchemaRegistry.sol";

import {TownSquareAttestationResolver} from "../src/TownSquareAttestationResolver.sol";

/// @notice Deploys TownSquareAttestationResolver to Arbitrum Sepolia and optionally registers a schema.
/// @dev Env vars (all optional):
///      DEFAULT_ADMIN    - admin of the resolver (defaults to the broadcaster)
///      INITIAL_ATTESTER - granted ATTESTER_ROLE and REVOKE_ROLE (only if broadcaster is the admin)
///      SCHEMA           - schema string to register against the resolver, e.g. "uint256 score"
///      SCHEMA_REVOCABLE - whether the registered schema is revocable (defaults to true)
contract DeployTownSquareAttestationResolver is Script {
    uint256 private constant ARBITRUM_SEPOLIA_CHAIN_ID = 421_614;

    // Source: lib/eas-contracts/deployments/arbitrum-sepolia/*.json (EAS v1.3.0),
    // verified with `cast code` and EAS.getSchemaRegistry() on chain 421614.
    IEAS private constant EAS = IEAS(0x2521021fc8BF070473E1e1801D3c7B4aB701E1dE);
    ISchemaRegistry private constant SCHEMA_REGISTRY = ISchemaRegistry(0x45CB6Fa0870a8Af06796Ac15915619a0f22cd475);

    error WrongChain(uint256 chainId);
    error EASNotDeployed();
    error SchemaRegistryMismatch(address registry);

    function run() external returns (TownSquareAttestationResolver resolver, bytes32 schemaId) {
        if (block.chainid != ARBITRUM_SEPOLIA_CHAIN_ID) revert WrongChain(block.chainid);
        if (address(EAS).code.length == 0) revert EASNotDeployed();
        if (address(EAS.getSchemaRegistry()) != address(SCHEMA_REGISTRY)) {
            revert SchemaRegistryMismatch(address(EAS.getSchemaRegistry()));
        }

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        address admin = vm.envOr("DEFAULT_ADMIN", deployer);
        address initialAttester = vm.envOr("INITIAL_ATTESTER", address(0));
        string memory schema = vm.envOr("SCHEMA", string(""));
        bool revocable = vm.envOr("SCHEMA_REVOCABLE", true);

        resolver = new TownSquareAttestationResolver(EAS, admin);

        if (initialAttester != address(0)) {
            if (admin == deployer) {
                resolver.grantRole(resolver.ATTESTER_ROLE(), initialAttester);
                resolver.grantRole(resolver.REVOKE_ROLE(), initialAttester);
            } else {
                console.log("Skipping role grants: broadcaster is not DEFAULT_ADMIN");
            }
        }

        if (bytes(schema).length != 0) {
            schemaId = SCHEMA_REGISTRY.register(schema, resolver, revocable);
        }

        vm.stopBroadcast();

        console.log("TownSquareAttestationResolver:", address(resolver));
        console.log("Default admin:", admin);
        if (initialAttester != address(0) && admin == deployer) console.log("Initial attester:", initialAttester);
        if (schemaId != bytes32(0)) console.logBytes32(schemaId);
    }
}
