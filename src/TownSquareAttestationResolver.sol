// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEAS, Attestation} from "@eas-contracts/IEAS.sol";
import {SchemaResolver} from "@eas-contracts/resolver/SchemaResolver.sol";
import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/// @title TownSquareAttestationResolver
/// @notice EAS schema resolver that only accepts attestations and revocations from allowlisted attesters.
contract TownSquareAttestationResolver is SchemaResolver, AccessControlDefaultAdminRules {
    /// @notice Role allowed to create attestations under schemas using this resolver.
    bytes32 public constant ATTESTER_ROLE = keccak256("ATTESTER_ROLE");

    /// @notice Role allowed to revoke attestations under schemas using this resolver.
    bytes32 public constant REVOKE_ROLE = keccak256("REVOKE_ROLE");

    uint48 private constant ADMIN_TRANSFER_DELAY = 1 hours;

    /// @param eas The global EAS contract.
    /// @param defaultAdmin The initial holder of DEFAULT_ADMIN_ROLE.
    constructor(IEAS eas, address defaultAdmin)
        SchemaResolver(eas)
        AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, defaultAdmin)
    {}

    // msg.sender is always EAS in the hooks below, so roles are checked against attestation.attester.
    // EAS only lets the original attester revoke, so attestation.attester is also the revoker.

    /// @notice Accepts the attestation only if its attester holds ATTESTER_ROLE.
    function onAttest(Attestation calldata attestation, uint256 /*value*/ ) internal view override returns (bool) {
        return hasRole(ATTESTER_ROLE, attestation.attester);
    }

    /// @notice Accepts the revocation only if the attester holds REVOKE_ROLE.
    function onRevoke(Attestation calldata attestation, uint256 /*value*/ ) internal view override returns (bool) {
        return hasRole(REVOKE_ROLE, attestation.attester);
    }
}
