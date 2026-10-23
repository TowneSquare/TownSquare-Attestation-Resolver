// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEAS,
    AttestationRequest,
    AttestationRequestData,
    RevocationRequest,
    RevocationRequestData,
    MultiAttestationRequest
} from "@eas-contracts/IEAS.sol";
import {EAS} from "@eas-contracts/EAS.sol";
import {SchemaRegistry} from "@eas-contracts/SchemaRegistry.sol";
import {ISchemaRegistry} from "@eas-contracts/ISchemaRegistry.sol";
import {AccessDenied, InvalidEAS} from "@eas-contracts/Common.sol";
import {Attestation} from "@eas-contracts/Common.sol";

import {TownSquareAttestationResolver} from "../src/TownSquareAttestationResolver.sol";

contract TownSquareAttestationResolverTest is Test {
    SchemaRegistry internal registry;
    EAS internal eas;
    TownSquareAttestationResolver internal resolver;
    bytes32 internal schemaId;

    address internal admin = makeAddr("admin");
    address internal attester = makeAddr("attester");
    address internal outsider = makeAddr("outsider");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        registry = new SchemaRegistry();
        eas = new EAS(ISchemaRegistry(address(registry)));
        resolver = new TownSquareAttestationResolver(IEAS(address(eas)), admin);
        schemaId = registry.register("uint256 score", resolver, true);

        vm.startPrank(admin);
        resolver.grantRole(resolver.ATTESTER_ROLE(), attester);
        resolver.grantRole(resolver.REVOKE_ROLE(), attester);
        vm.stopPrank();
    }

    function _request() internal view returns (AttestationRequest memory) {
        return AttestationRequest({
            schema: schemaId,
            data: AttestationRequestData({
                recipient: recipient,
                expirationTime: 0,
                revocable: true,
                refUID: bytes32(0),
                data: abi.encode(uint256(42)),
                value: 0
            })
        });
    }

    function _attest(address from) internal returns (bytes32) {
        vm.prank(from);
        return eas.attest(_request());
    }

    function _revoke(address from, bytes32 uid) internal {
        vm.prank(from);
        eas.revoke(RevocationRequest({schema: schemaId, data: RevocationRequestData({uid: uid, value: 0})}));
    }

    function test_constructor_revertsWhenEasIsZero() public {
        vm.expectRevert(InvalidEAS.selector);
        new TownSquareAttestationResolver(IEAS(address(0)), admin);
    }

    function test_constructor_setsAdmin() public view {
        assertEq(resolver.defaultAdmin(), admin);
        assertEq(resolver.defaultAdminDelay(), 1 hours);
        assertFalse(resolver.isPayable());
    }

    function test_attest_succeedsForAttester() public {
        bytes32 uid = _attest(attester);
        Attestation memory a = eas.getAttestation(uid);
        assertEq(a.attester, attester);
        assertEq(a.recipient, recipient);
    }

    function test_attest_revertsForOutsider() public {
        vm.expectRevert(EAS.InvalidAttestation.selector);
        _attest(outsider);
    }

    function test_attest_revertsAfterRoleRevoked() public {
        bytes32 role = resolver.ATTESTER_ROLE();
        vm.prank(admin);
        resolver.revokeRole(role, attester);

        vm.expectRevert(EAS.InvalidAttestation.selector);
        _attest(attester);
    }

    function test_attest_revertsWhenAdminDoesNotHoldAttesterRole() public {
        vm.expectRevert(EAS.InvalidAttestation.selector);
        _attest(admin);
    }

    function test_multiAttest_revertsIfAnyAttesterLacksRole() public {
        AttestationRequestData[] memory data = new AttestationRequestData[](2);
        data[0] = _request().data;
        data[1] = _request().data;
        MultiAttestationRequest[] memory reqs = new MultiAttestationRequest[](1);
        reqs[0] = MultiAttestationRequest({schema: schemaId, data: data});

        vm.prank(attester);
        bytes32[] memory uids = eas.multiAttest(reqs);
        assertEq(uids.length, 2);

        vm.prank(outsider);
        vm.expectRevert(EAS.InvalidAttestations.selector);
        eas.multiAttest(reqs);
    }

    function test_revoke_succeedsForRevoker() public {
        bytes32 uid = _attest(attester);
        _revoke(attester, uid);
        assertGt(eas.getAttestation(uid).revocationTime, 0);
    }

    function test_revoke_revertsWithoutRevokeRole() public {
        bytes32 uid = _attest(attester);
        bytes32 role = resolver.REVOKE_ROLE();
        vm.prank(admin);
        resolver.revokeRole(role, attester);

        vm.expectRevert(EAS.InvalidRevocation.selector);
        _revoke(attester, uid);
    }

    function test_revoke_revertsForNonAttesterEvenWithRole() public {
        bytes32 uid = _attest(attester);
        bytes32 role = resolver.REVOKE_ROLE();
        vm.prank(admin);
        resolver.grantRole(role, outsider);

        // EAS itself restricts revocation to the original attester
        vm.expectRevert(AccessDenied.selector);
        _revoke(outsider, uid);
    }

    function test_attest_revertsWhenCalledDirectly() public {
        Attestation memory a;
        a.attester = attester;
        vm.prank(attester);
        vm.expectRevert(AccessDenied.selector);
        resolver.attest(a);
    }

    function test_revoke_revertsWhenCalledDirectly() public {
        Attestation memory a;
        a.attester = attester;
        vm.prank(attester);
        vm.expectRevert(AccessDenied.selector);
        resolver.revoke(a);
    }

    function test_receive_revertsOnEthTransfer() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool ok,) = address(resolver).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function testFuzz_attest_onlyRoleHoldersSucceed(address caller) public {
        vm.assume(caller != attester && caller != address(0));
        vm.expectRevert(EAS.InvalidAttestation.selector);
        _attest(caller);
    }
}
