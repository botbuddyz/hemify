// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IHemifyControl} from "../../interfaces/IHemifyControl.sol";
import {IHemifyEscrow} from "../../interfaces/IHemifyEscrow.sol";
import {IHemifySwap} from "../../interfaces/IHemifySwap.sol";
import {IHemifyTreasury} from "../../interfaces/IHemifyTreasury.sol";

/**
* @title HemifySwap
* @author fps (@0xfps).
* @custom:version 1.0.0
* @dev  HemifySwap contract.
* @notice   This contract allows two parties to swap their NFTs via an
*           order book model approach.
*
*           The 'placer' submits a request for a swap via the `placeSwapOrder()` function,
*           providing the desired NFT to give, and the desired NFT to receive. This will
*           give the 'placer' an orderId, to track their order, and the order state is set
*           to `LISTED`.
*
*           'Completers' that fulfill the order, also set their desired NFT to give (which
*           must match the "placer"'s NFT to receive) and their NFT to receive (which
*           must match the "placer"'s NFT to give). Once there is a match the swap happens
*           instantly and the order is deleted.
*
*           Swap fee is constant for now, and is demanded from the 'placer' and the
*           'completer'.
*
*           Orders set to `LISTED` can as well be deleted by their 'placer'.
*/

contract HemifySwap is IHemifySwap {
    IHemifyControl internal control;
    IHemifyEscrow internal escrow;
    IHemifyTreasury internal treasury;

    // Set now, variable later.
    uint256 public fee = 0.05 ether;
    // Set now, variable later.
    uint256 public markUpLimit = 2 ether;
    mapping(bytes32 => Order) private orders;

    constructor(
        address _control,
        address _escrow,
        address _treasury
    )
    {
        if (
            _control == address(0) ||
            _escrow == address(0) ||
            _treasury == address(0)
        ) revert ZeroAddress();

        control = IHemifyControl(_control);
        escrow = IHemifyEscrow(_escrow);
        treasury = IHemifyTreasury(_treasury);
    }

    /**
    * @dev Allows `msg.sender` to place a new swap order (request).
    * @notice   Orders can be placed by the `msg.sender` on the conditions that `_fromId`
    *           of the `_fromSwap` NFT will be owned or approved to be used by the `msg.sender`,
    *           `_fromSwap` and `_toSwap` are approved by the `Control`, fees are complete and there
    *           is no existing swap with the same `orderId`.
    *           `orderId`s are generated by the hash of the 4 function parameter
    *           values.
    *           Fee balances are refunded to `msg.sender`.
    * @param _fromSwap  NFT address owned by submitter to be swapped.
    * @param _fromId    NFT ID owned by submitter to be swapped.
    * @param _toSwap    NFT address wanted by the submitter.
    * @param _toId      NFT ID wanted by the submitter.
    * @param _markUp    Extra money to be added by the 'completer' to make swap.
    * @return bytes32   Order ID.
    * @return bool      Submission status.
    */
    function placeSwapOrder(
        IERC721 _fromSwap,
        uint256 _fromId,
        IERC721 _toSwap,
        uint256 _toId,
        uint256 _markUp
    )
        external
        payable
        returns (bytes32, bool)
    {
        if (!control.isSupportedForSwap(_fromSwap)) revert NFTNotSupported();
        if (!control.isSupportedForSwap(_toSwap)) revert NFTNotSupported();

        if (!_isOwnerOrAuthorized(_fromSwap, _fromId, msg.sender))
            revert NotOwnerOrAuthorized();

        if (_markUp > markUpLimit) revert HighMarkUp();

        bytes32 orderId = _getOrderId(
            _fromSwap,
            _fromId,
            _toSwap,
            _toId
        );

        if (_orderExists(orderId)) revert OrderExists();
        if (_toSwap.ownerOf(_toId) == address(0)) revert SwapNFTNonExistent();
        if (msg.value < fee) revert InsufficientFees();

        uint256 balance = msg.value - fee;

        Order memory _order;
        _order.state = OrderState.LISTED;
        _order.orderOwner = msg.sender;
        _order.fromSwap = _fromSwap;
        _order.fromId = _fromId;
        _order.toSwap = _toSwap;
        _order.toId = _toId;
        _order.markUp = _markUp;

        orders[orderId] = _order;

        bool paid = treasury.deposit{value: fee}();
        if (!paid) revert NotSent();

        bool sent = escrow.depositNFT(msg.sender, _fromSwap, _fromId);
        if (!sent) revert NotSent();

        (bool refund, ) = payable(msg.sender).call{value: balance}("");
        if (!refund) revert NotSent();

        emit OrderPlaced(orderId);

        return (orderId, sent);
    }

    /**
    * @dev Allows `msg.sender` to complete a placed swap order (request).
    * @notice   Orders can be placed by the `msg.sender` on the conditions that `_fromId`
    *           of the `_fromSwap` NFT will be owned or approved to be used by the `msg.sender`,
    *           fees are complete and there is an existing swap with the generated `orderId`.
    *           `orderId`s are generated by the hash of the 4 function parameter
    *           values.
    *           If there is a markup for the swap, the markup is sent as ETH.
    *           Fee balances are refunded to `msg.sender`.
    * @param _fromSwap  NFT address owned by submitter to be swapped.
    * @param _fromId    NFT ID owned by submitter to be swapped.
    * @param _toSwap    NFT address wanted by the submitter.
    * @param _toId      NFT ID wanted by the submitter.
    * @return bool      Submission status.
    */
    function completeSwapOrder(
        IERC721 _fromSwap,
        uint256 _fromId,
        IERC721 _toSwap,
        uint256 _toId
    )
        external
        payable
        returns (bool)
    {
        /// @dev    `_fromSwap` and `_toSwap` are not checked anymore, why?
        ///         because, this function depends on existing `orderId`s generated
        ///         and existing, as a result of `placeSwapOrder()`, and the checks
        ///         exist there.

        if (!_isOwnerOrAuthorized(_fromSwap, _fromId, msg.sender))
            revert NotOwnerOrAuthorized();

        /// @dev This hash is configured to match the hash in the `placeSwapOrder()`.
        bytes32 orderId = _getOrderId(
            _toSwap,
            _toId,
            _fromSwap,
            _fromId
        );

        if (!_orderExists(orderId)) revert OrderNotExistent();

        uint256 _markUp = orders[orderId].markUp;
        if (msg.value < (fee + _markUp)) revert InsufficientFees();

        address _orderOwner = orders[orderId].orderOwner;
        if (_orderOwner == msg.sender) revert OrderOwnerCannotSwap();

        uint256 balance = msg.value - (fee + _markUp);

        /// @dev    Updates orders[orderId] variables to default before proceeding.
        ///         orders[orderId].state is set to `NULL` here.
        delete orders[orderId];

        bool paid = treasury.deposit{value: fee}();
        if (!paid) revert NotSent();

        bool sent = escrow.depositNFT(msg.sender, _fromSwap, _fromId);
        if (!sent) revert NotSent();

        /// @dev Swapping.
        bool swapToOwner = escrow.sendNFT(_fromSwap, _fromId, _orderOwner);
        if (!swapToOwner) revert NotSent();

        bool swapToReceiver = escrow.sendNFT(_toSwap, _toId, msg.sender);
        if (!swapToReceiver) revert NotSent();

        if (_markUp != 0) {
            (bool payMarkUp, ) = payable(_orderOwner).call{value: _markUp}("");
            if (!payMarkUp) revert NotSent();
        }

        if (balance != 0) {
            (bool refund, ) = payable(msg.sender).call{value: balance}("");
            if (!refund) revert NotSent();
        }

        emit OrderCompleted(orderId, msg.sender);

        return sent;
    }

    /// @dev Allows order owner to cancel their order.
    /// @param _orderId Order ID.
    /// @return bool Cancellation state.
    function cancelSwapOrder(bytes32 _orderId) external returns (bool) {
        if (!_orderExists(_orderId)) revert OrderNotExistent();

        if (orders[_orderId].orderOwner != msg.sender) revert NotOrderOwner();

        IERC721 _nft = orders[_orderId].fromSwap;
        uint256 _id = orders[_orderId].fromId;

        delete orders[_orderId];

        bool sent = escrow.sendNFT(_nft, _id, msg.sender);
        if (!sent) revert NotSent();

        emit OrderCancelled(_orderId);

        return sent;
    }

    /// @dev Returns the details of order `_orderId`.
    /// @param _orderId Order ID.
    /// @return struct Order memory.
    function getSwapOrder(bytes32 _orderId) external view returns (Order memory) {
        if (!_orderExists(_orderId)) revert OrderNotExistent();

        Order memory order = orders[_orderId];
        return order;
    }

    /**
    * @dev Returns true or false if `_owner` is owner of NFT `_nft`'s id `_id`.
    * @param _nft   NFT Address.
    * @param _id    NFT ID.
    * @param _owner `msg.sender` from `placeSwapOrder()` and `completeSwapOrder()`.
    * @return bool True or false.
    */
    function _isOwnerOrAuthorized(
        IERC721 _nft,
        uint256 _id,
        address _owner
    )
        internal
        view
        returns (bool)
    {
        address nftOwner = _nft.ownerOf(_id);
        if (
            (nftOwner != _owner) &&
            (_nft.getApproved(_id) != _owner) &&
            (!_nft.isApprovedForAll(nftOwner, _owner))
        ) return false;

        return true;
    }

    /**
    * @dev Generate orderId by hashing all 4 values.
    * @param _fromSwap  NFT address owned by submitter to be swapped.
    * @param _fromId    NFT ID owned by submitter to be swapped.
    * @param _toSwap    NFT address wanted by the submitter.
    * @param _toId      NFT ID wanted by the submitter.
    * @return bytes32 Order ID.
    */
    function _getOrderId(
        IERC721 _fromSwap,
        uint256 _fromId,
        IERC721 _toSwap,
        uint256 _toId
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _fromSwap,
                _fromId,
                _toSwap,
                _toId
            )
        );
    }

    /// @dev Returns true if order `_orderId` is `LISTED`.
    /// @param _orderId Order ID.
    /// @return bool True or false.
    function _orderExists(bytes32 _orderId) private view returns (bool) {
        return orders[_orderId].state == OrderState.LISTED;
    }
}