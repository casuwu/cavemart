// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC721.sol";
import "solmate/auth/Owned.sol";
import "./FullMath.sol";


/// @notice Allows a buyer to execute an order given they've got an secp256k1 
/// signature from a seller containing verifiable metadata about the trade. The 
/// seller can accept native ETH or an ERC-20 if they're whitelisted.
/// @author Dionysus @ConcaveFi
contract Marketplace is Owned {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;

    /// -----------------------------------------------------------------------
    /// IMMUTABLE STORAGE
    /// -----------------------------------------------------------------------

    uint256 internal constant FEE_DIVISOR = 10_000;

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    // keccak256("Swap(address seller,address erc721,address erc20,uint256 tokenId,uint256 startPrice,uint256 endPrice,uint256 start,uint256 deadline)")
    bytes32 public constant SWAP_TYPEHASH
        = 0xce02533ba8247ea665b533936094078425c41815f15e8e856183c2fadc084ea3;

    /// -----------------------------------------------------------------------
    /// MUTABLE STORAGE
    /// -----------------------------------------------------------------------
    
    /// @notice Returns the fee charged for selling a token from specific erc721 collection.
    mapping(address => uint256) public collectionFee;

    /// @notice Returns whether a token is whitelisted to be traded within this contract.
    mapping(address => bool) public whitelisted;

    /// @notice Returns whether a specific signature has been executed before.
    mapping(bytes32 => bool) public executed;

    /// -----------------------------------------------------------------------
    /// CONSTRUCTION
    /// -----------------------------------------------------------------------

    // Marketplace is owned by deployer by default
    constructor() Owned(msg.sender) {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /// -----------------------------------------------------------------------
    /// EVENTS
    /// -----------------------------------------------------------------------
    
    event OrderExecuted(
        address indexed seller,
        address indexed erc721,
        address indexed erc20,
        uint256 tokenId,
        uint256 price,
        uint256 deadline
    );

    event FeeCollection(
        address indexed token,
        uint256 amount
    );

    event WhitelistUpdated(
        address indexed token,
        bool isWhitelisted
    );

    event CollectionFeeUpdated(
        address indexed token,
        uint256 fee
    );

    /// -----------------------------------------------------------------------
    /// ERRORS
    /// -----------------------------------------------------------------------

    error Error_TokenNotWhitelisted();

    error Error_SignatureExpired();

    error Error_SignatureReplayed();

    error Error_SignatureInvalid();

    error Error_OrderExpired();

    error Error_InsufficientMsgValue();

    /// -----------------------------------------------------------------------
    /// EIP-712 LOGIC
    /// -----------------------------------------------------------------------

    /// @notice Struct containing metadata for a ERC721 <-> ERC20 trade.
    /// @param seller The address of the account that wants to sell their 'erc721' 
    /// in exchange for 'price' denominated in 'erc20'.
    /// @param erc721 The address of a contract that follows the ERC-721 standard, also
    /// the address of the collection that holds the token that you're purchasing.
    /// @param erc20 The address of a contract that follows the ERC-20 standard, also 
    /// the address of the token that the seller wants in exchange for their 'erc721'.
    /// @dev If 'erc20' is equal to address(0), we assume the seller wants native  
    /// ETH in exchange for their 'erc721'.
    /// @param tokenId The 'erc721' token identification number, 'tokenId'.
    /// @param startPrice The starting or fixed price the offered 'erc721' is being
    /// sold for, if ZERO we assume the 'seller' is hosting a dutch auction.
    /// @dev If a 'endPrice' and 'start' time are both defined, we assume the order 
    /// type is a dutch auction. So 'startPrice' would be the price the auction starts 
    /// at, otherwise 'startPrice' is the fixed cost the 'seller' is charging.
    /// @param endPrice The 'endPrice' is the price in which a dutch auction would
    /// no longer be valid after.
    /// @param start The time in which the dutch auction starts, if ZERO we assume 
    /// the 'seller' is hosting a dutch auction.
    /// @param deadline The time in which the signature/swap is not valid after.   
    struct SwapMetadata {
        address seller;
        address erc721;
        address erc20;
        uint256 tokenId;
        uint256 startPrice;
        uint256 endPrice;
        uint256 start;
        uint256 deadline;
    }

    function computeSigner(
        SwapMetadata calldata data,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual view returns (address signer) {
        
        signer = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01", 
                    DOMAIN_SEPARATOR(), 
                    keccak256(
                        abi.encode(
                            SWAP_TYPEHASH, 
                            data.seller, 
                            data.erc721, 
                            data.erc20, 
                            data.tokenId, 
                            data.startPrice,
                            data.endPrice, 
                            data.start, 
                            data.deadline
                        )
                    )
                )
            ), v, r, s);
    }

    function DOMAIN_SEPARATOR() public virtual view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? 
            INITIAL_DOMAIN_SEPARATOR : 
            computeDomainSeparator();
    }

    function computeDomainSeparator() internal virtual view returns (bytes32) {
        return keccak256(
            abi.encode(
                // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                // keccak256("Marketplace"),
                0x893ab71b0c6fc92bef28fc4ee2bc8018ee56220e13f8a287176138660baa87c4,
                // keccak256("1"),
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6,
                block.chainid,
                address(this)
            )
        );
    }

    /// -----------------------------------------------------------------------
    /// PRICE LOGIC
    /// -----------------------------------------------------------------------

    function computePrice(
        SwapMetadata calldata data
    ) public virtual view returns (uint256 price) {
        data.endPrice == 0 || data.start == 0 ? 
            price = data.startPrice : 
            price = data.startPrice - FullMath.mulDiv(
                data.startPrice - data.endPrice, 
                block.timestamp - data.start, 
                data.deadline - data.start
            );
    }

    /// -----------------------------------------------------------------------
    /// USER ACTIONS
    /// -----------------------------------------------------------------------

    /// @notice Allows a buyer to execute an order given they've got an 
    /// secp256k1 signature from a seller containing verifiable swap metadata.
    /// @param data Struct containing metadata for a ERC721 <-> ERC20 trade.
    /// @param v Part of a valid secp256k1 signature from the seller.
    /// @param r Part of a valid secp256k1 signature from the seller.
    /// @param s Part of a valid secp256k1 signature from the seller.
    function swap(
        SwapMetadata calldata data,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual payable {

        // CHECKS

        // Make sure both the 'erc721' and the 'erc20' wanted in exchange are both whitelisted.
        if (!whitelisted[data.erc721] || !whitelisted[data.erc20]) 
            revert Error_TokenNotWhitelisted();

        // Make sure the deadline the 'seller' has specified has not elapsed.
        if (data.deadline < block.timestamp) 
            revert Error_OrderExpired();

        bytes32 dataHash = keccak256(abi.encode(data));

        // Make sure the signature has not already been executed.
        if (executed[dataHash]) 
            revert Error_SignatureReplayed();
        
        address signer = computeSigner(data, v, r, s);

        // Make sure the recovered address is not NULL, and is equal to the 'seller'.
        if (signer == address(0) || signer != data.seller) 
            revert Error_SignatureInvalid();

        // EFFECTS
        
        executed[dataHash] = true;

        uint256 price = computePrice(data);

        // Cache the fee that's going to be charged to the 'seller'.
        uint256 fee = FullMath.mulDiv(price, collectionFee[data.erc721], FEE_DIVISOR);

        // If 'erc20' is NULL, we assume the seller wants native ETH.
        if (data.erc20 == address(0)) {

            // Make sure the amount of ETH sent is at least the price specified.
            if (msg.value < price) 
                revert Error_InsufficientMsgValue();

            // Transfer msg.value minus 'fee' from this contract to 'seller'
            signer.safeTransferETH(price - fee);

        // If 'erc20' is not NULL, we assume the seller wants a ERC20.
        } else {

            // Transfer 'erc20' 'price' minus 'fee' from caller to 'seller'.
            ERC20(data.erc20).safeTransferFrom(msg.sender, signer, price - fee);
            
            // Transfer 'fee' to 'owner'.
            if (fee > 0) ERC20(data.erc20).safeTransferFrom(msg.sender, owner, fee);
        }

        // Transfer 'erc721' from 'seller' to msg.sender/caller.
        ERC721(data.erc721).safeTransferFrom(signer, msg.sender, data.tokenId);

        // Emit event since state was mutated.
        emit OrderExecuted(signer, data.erc721, data.erc20, data.tokenId, price, data.deadline);
    }

    /// -----------------------------------------------------------------------
    /// OWNER ACTIONS
    /// -----------------------------------------------------------------------

    function updateCollectionFee(address collection, uint256 percent) external virtual onlyOwner {

        collectionFee[collection] = percent;
        
        emit CollectionFeeUpdated(collection, percent);
    }

    function updateWhitelist(address token) external virtual onlyOwner {
        
        bool isWhitelisted = !whitelisted[token];

        whitelisted[token] = isWhitelisted;
        
        emit WhitelistUpdated(token, isWhitelisted);
    }

    function collectEther() external virtual onlyOwner {

        uint256 balance = address(this).balance;

        owner.safeTransferETH(balance);

        emit FeeCollection(address(0), balance);
    }

    function collectERC20(address token) external virtual onlyOwner {

        uint256 balance = ERC20(token).balanceOf(address(this));

        ERC20(token).safeTransfer(owner, balance);

        emit FeeCollection(token, balance);
    }

    /// -----------------------------------------------------------------------
    /// SIGNATURE VERIFICATION
    /// -----------------------------------------------------------------------

    function isValidSignature(
        SwapMetadata calldata data,
        address buyer, // address(0) to avoid buyer balance checks
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual view returns (bool valid) {

        // Make sure the order hasn't already been executed.
        if (executed[keccak256(abi.encode(data))]) 
            return false;

        // Make sure current time is greater than 'start' if order type is dutch auction. 
        if ((data.start == 0 || data.endPrice == 0) && data.start > block.timestamp) 
            return false;

        // Make sure both the 'erc721' and the 'erc20' wanted in exchange are both whitelisted.
        if (!whitelisted[data.erc721] || !whitelisted[data.erc20]) 
            return false;

        // Make sure the deadline the 'seller' has specified has not elapsed.
        if (data.deadline < block.timestamp) 
            return false;

        // Make sure the 'seller' still owns the 'erc721' being offered, and has
        // approved this contract to spend it.
        if (
            ERC721(data.erc721).ownerOf(data.tokenId) != data.seller || 
            ERC721(data.erc721).getApproved(data.tokenId) != address(this)
        ) return false;

        // Make sure the buyer has 'price' denominated in 'erc20' if 'erc20' is not native ETH.
        if (
            data.erc20 != address(0) && 
            (ERC20(data.erc20).balanceOf(buyer) < computePrice(data) && buyer != address(0))
        ) return false;

        address signer = computeSigner(data, v, r, s);

        // Make sure the recovered address is not NULL, and is equal to the 'seller'.
        if (signer == address(0) || signer != data.seller) 
            return false;

        return true;
    }

    function isExecuted(
        SwapMetadata calldata data
    ) external virtual view returns (bool) {
        return executed[keccak256(abi.encode(data))];
    }

    /// -----------------------------------------------------------------------
    /// HOOKS/FALLBACKS
    /// -----------------------------------------------------------------------

	/// @dev This function ensures this contract can receive Native ETH.
	receive() external payable {}

    /// @dev This function ensures this contract can receive ERC721 tokens.
    function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
        return 0x150b7a02;
    }
}