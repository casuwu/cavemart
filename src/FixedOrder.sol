// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC721}      from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC20}       from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract FixedOrder {

    /////////////////////////////////////////////////////////////////
    //                           EVENTS
    /////////////////////////////////////////////////////////////////

    event OrderCreated(
        address indexed erc721, 
        address indexed erc20, 
        address creator, 
        uint256 nftId, 
        uint256 price, 
        uint256 deadline
    );
    
    event OrderSold(
        address indexed erc721, 
        address indexed erc20, 
        uint256 nftId, 
        address seller, 
        address taker, 
        uint256 price
    );

    event OrderCancelled(address indexed erc721, uint256 indexed nftId, address seller);
    event OrderAdjusted(uint256 orderId, uint128 price);
    event FeePercentUpdated(uint256 percent);
    event FeeAddressUpdated(address feeAddress);
    event WhitelistUpdated(address token, bool whitelisted);

    /////////////////////////////////////////////////////////////////
    //                          MODIFIERS
    /////////////////////////////////////////////////////////////////

    modifier access() {
        require(msg.sender == feeAddress, "!ACCESS");
        _;
    }

    /////////////////////////////////////////////////////////////////
    //                          CONSTANTS
    /////////////////////////////////////////////////////////////////

    string internal constant NOT_TOKEN_OWNER = "!TOKEN_OWNER";

    uint256 public constant FEE_DIVISOR = 10_000;

    /////////////////////////////////////////////////////////////////
    //                        MUTABLE STATE
    /////////////////////////////////////////////////////////////////

    struct Order {
        address seller;
        address erc721;
        address erc20;
        uint256 nftId;
        uint128 price;
        uint112 deadline;
    }

    Order[] public orders;

    mapping(address => uint256[]) public ordersOf;

    mapping(address => bool) public allowed;

    uint256 public fee; // default is zero

    address public feeAddress = msg.sender; // default is contract creator

    /////////////////////////////////////////////////////////////////
    //                           ACTIONS
    /////////////////////////////////////////////////////////////////

    function buy(
        uint256 orderId
    ) external {
        
        // cache order in memory
        Order memory order = orders[orderId];
        
        // // make sure the order hasn't expired
        // require(block.timestamp <= order.deadline, "EXPIRED");
        
        // delete the order from storage
        delete ordersOf[order.seller];
        delete orders[orderId];

        uint256 feeAmt = order.price * fee / FEE_DIVISOR;
    
        IERC20(order.erc20).transferFrom(msg.sender, order.seller, order.price - feeAmt);
        
        if (feeAmt > 0) IERC20(order.erc20).transferFrom(msg.sender, feeAddress, feeAmt);

        IERC721(order.erc721).transferFrom(address(this), msg.sender, order.nftId);

        // T2 - Are events emitted for every storage mutating function?
        emit OrderSold(order.erc721, order.erc20, orderId, order.seller, msg.sender, order.price);
    }

	function create(
		address erc721,
        address erc20,
        uint256 nftId,
		uint128 price,
		uint112 deadline
	) external returns (uint256 orderId) {
        
        // make sure both the erc721 being offered and the erc20 wanted are allowed to be traded
        require(allowed[erc721] && allowed[erc20], '!WHITELISTED');
        
        // make sure the caller owns the nft being sold, to prevent others from spending on owner's behalf
        require(msg.sender == IERC721(erc721).ownerOf(nftId), NOT_TOKEN_OWNER);
        
        // push the new order to storage
        orders.push(Order(msg.sender, erc721, erc20, nftId, price, deadline));  

        // determine the orderId
        orderId = ordersOf[msg.sender].length;

        // update ordersOf seller to include the newly created order
        ordersOf[msg.sender].push(orderId);

        // pull the users erc721 into escrow so it can be sold
        IERC721(erc721).safeTransferFrom(msg.sender, address(this), nftId);
        
        // T2 - Are events emitted for every storage mutating function?
        emit OrderCreated(erc721, erc20, msg.sender, nftId, price, deadline);
	}

	function cancel(uint256 orderId) external {
        
        // cache order in memory
        Order memory order = orders[orderId];
        
        // make sure caller is the owner of the order
        require(msg.sender == order.seller, NOT_TOKEN_OWNER);
        
        // delete order from storage for gas refund
        delete ordersOf[order.seller][orderId];
        delete orders[orderId];
        
        // refund the sellers nft
        IERC721(order.erc721).safeTransferFrom(address(this), order.seller, order.nftId);
        
        // T2 - Are events emitted for every storage mutating function?
        emit OrderCancelled(order.erc721, orderId, order.seller);
	}

    function adjust(uint256 orderId, uint128 price) external {
        
        // cache order in memory
        Order memory order = orders[orderId];
        
        // make sure caller is the owner of the order
        require(msg.sender == order.seller, NOT_TOKEN_OWNER);
        
        // update order price
        ordersOf[order.seller][orderId] = price;
        orders[orderId].price = price;

        // T2 - Are events emitted for every storage mutating function?
        emit OrderAdjusted(orderId, price);
    }

    /////////////////////////////////////////////////////////////////
    //                         ERC721Holder
    /////////////////////////////////////////////////////////////////

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        // return this.onERC721Received.selector;
        return 0x150b7a02;
    }

    /////////////////////////////////////////////////////////////////
    //                          MANAGEMENT
    /////////////////////////////////////////////////////////////////

	function updateFeeAddress(address _feeAddress) external access {
        feeAddress = _feeAddress;
        // T2 - Are events emitted for every storage mutating function?
        emit FeeAddressUpdated(feeAddress);
	}

	function updateFeePercent(uint256 percent) external access {
		fee = percent;
        // T2 - Are events emitted for every storage mutating function?
        emit FeePercentUpdated(percent);
    }

    function updateWhitelist(address nftId) external access {
        bool whitelisted = !allowed[nftId];
        allowed[nftId] = whitelisted;
        // T2 - Are events emitted for every storage mutating function?
        emit WhitelistUpdated(nftId, whitelisted);
    }

    /////////////////////////////////////////////////////////////////
    //                            VIEW
    /////////////////////////////////////////////////////////////////

    function orderPrice(uint256 orderId) external view returns (uint256) {
        return orders[orderId].price;
    }

    function totalOrdersOf(address who) external view returns (uint256) {
        return ordersOf[who].length;
    }

    function totalOrders() external view returns (uint256) {
        return orders.length;
    }
}