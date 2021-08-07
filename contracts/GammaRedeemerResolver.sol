// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {IGammaRedeemerV1} from "./interfaces/IGammaRedeemerV1.sol";
import {IGammaOperator} from "./interfaces/IGammaOperator.sol";
import {IResolver} from "./interfaces/IResolver.sol";
import {MarginVault} from "./external/OpynVault.sol";

/// @author Willy Shen
/// @title GammaRedeemer Resolver
/// @notice A GammaRedeemer resolver for Gelato PokeMe checks
contract GammaRedeemerResolver is IResolver {
    address redeemer;

    constructor(address _redeemer) {
        redeemer = _redeemer;
    }

    // check if order can be processed without reverting
    function canProcessOrder(uint256 _orderId) public view returns (bool) {
        IGammaRedeemerV1.Order memory order = IGammaRedeemerV1(redeemer)
            .getOrder(_orderId);

        if (order.isSeller) {
            if (
                !IGammaOperator(redeemer).isValidVaultId(
                    order.owner,
                    order.vaultId
                ) || !IGammaOperator(redeemer).isOperatorOf(order.owner)
            ) return false;

            (
                MarginVault.Vault memory vault,
                uint256 typeVault,

            ) = IGammaOperator(redeemer).getVaultWithDetails(
                order.owner,
                order.vaultId
            );

            try IGammaOperator(redeemer).getVaultOtoken(vault) returns (
                address otoken
            ) {
                if (
                    !IGammaOperator(redeemer).hasExpiredAndSettlementAllowed(
                        otoken
                    )
                ) return false;

                (uint256 payout, bool isValidVault) = IGammaOperator(redeemer)
                    .getExcessCollateral(vault, typeVault);
                if (!isValidVault || payout == 0) return false;
            } catch {
                return false;
            }
        } else {
            if (
                !IGammaOperator(redeemer).hasExpiredAndSettlementAllowed(
                    order.otoken
                )
            ) return false;
        }

        return true;
    }

    function getProcessableOrders()
        public
        view
        override
        returns (uint256[] memory)
    {
        IGammaRedeemerV1.Order[] memory orders = IGammaRedeemerV1(redeemer)
            .getOrders();

        // Only proceess duplicate orders one at a time
        bytes32[] memory preCheckHashes = new bytes32[](orders.length);
        bytes32[] memory postCheckHashes = new bytes32[](orders.length);

        uint256 orderIdsLength;
        for (uint256 i = 0; i < orders.length; i++) {
            if (
                IGammaRedeemerV1(redeemer).shouldProcessOrder(i) &&
                canProcessOrder(i) &&
                !containDuplicateOrderType(orders[i], preCheckHashes)
            ) {
                preCheckHashes[i] = getOrderHash(orders[i]);
                orderIdsLength++;
            }
        }

        uint256 counter;
        uint256[] memory orderIds = new uint256[](orderIdsLength);
        for (uint256 i = 0; i < orders.length; i++) {
            if (
                IGammaRedeemerV1(redeemer).shouldProcessOrder(i) &&
                canProcessOrder(i) &&
                !containDuplicateOrderType(orders[i], postCheckHashes)
            ) {
                postCheckHashes[i] = getOrderHash(orders[i]);
                orderIds[counter] = i;
                counter++;
            }
        }
        return orderIds;
    }

    function containDuplicateOrderType(
        IGammaRedeemerV1.Order memory order,
        bytes32[] memory hashes
    ) public pure returns (bool containDuplicate) {
        bytes32 orderHash = getOrderHash(order);

        for (uint256 j = 0; j < hashes.length; j++) {
            if (hashes[j] == orderHash) {
                containDuplicate = true;
                break;
            }
        }
    }

    function getOrderHash(IGammaRedeemerV1.Order memory order)
        public
        pure
        returns (bytes32 orderHash)
    {
        if (order.isSeller) {
            orderHash = keccak256(abi.encode(order.owner, order.vaultId));
        } else {
            orderHash = keccak256(abi.encode(order.owner, order.otoken));
        }
    }
}
