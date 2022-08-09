// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import { MockERC20, MockERC721 } from "./mocks/Tokens.sol";

import "forge-std/Test.sol";

import "../Marketplace.sol";
import "solmate/auth/Owned.sol";

contract marketplaceTest is Test {

    // @notice          erc20 is an ERC20
    MockERC20 erc20;

    // @notice          erc721 is an ERC721
    MockERC721 erc721;
    // @notice          marketplace is a Fixed Order Market that 
    //                  allows users to trade ERC20<->ERC721 
    //                  with minimal calls.
    Marketplace marketplace;

    // USER ALICE:
    // @notice          Alice is a huge fan of erc721s and 
    //                  buys them all the time using erc20s.
    uint256 ALICE_PK = 0xCAFE;
    address ALICE = vm.addr(ALICE_PK);

    // USER BOB:
    // @notice          Bob is an artist, and sells his art 
    //                  in the form of erc721s.
    uint256 BOB_PK = 0xBEEF;
    address BOB = vm.addr(BOB_PK);

    // USER EVE:
    // @notice          Eve owns the most valuable erc721, tokenId #420 
    //                  
    uint256 EVE_PK = 0xADAD;
    address EVE = vm.addr(EVE_PK);

    

    // PRE-TEST SETUP

    function setUp() public {

        // Deploy contracts
        marketplace = new Marketplace();
        erc20 = new MockERC20("DAI", "DAI");
        erc721 = new MockERC721("lsdCSV", "lsdCSV");

        // Add tokens to whitelist
        marketplace.updateWhitelist(address(erc20));
        marketplace.updateWhitelist(address(erc721));

        // Label all used addresses within VM
        vm.label(address(erc20), " ERC20 ");
        vm.label(address(erc721), " erc721 ");
        vm.label(ALICE, " ALICE ");
        vm.label(BOB, " BOB ");
    }

    // function testThing() public {
    //     assertEq(marketplace.computeDomainSeparator(), marketplace.computeDomainSeparatorOld());
    // }

    // PRE-TEST SETUP HELPERS
    
    function setUpBalances(
        uint256 startPrice, 
        uint256 tokenId
    ) public {
        // Mint ALICE the startPrice that's going to be paid to BOB
        erc20.mint(ALICE, startPrice);
        // Mint BOB the erc721 he's going to sell to Alice
        erc721.mint(BOB, tokenId);
        // Approve market to spend ALICE's tokens
        vm.prank(ALICE);
        erc20.approve(address(marketplace), startPrice);
        // Approve market to spend BOB's erc721
        vm.prank(BOB);
        erc721.approve(address(marketplace), tokenId);
    }

    // TESTS   

    function sign(
        address user, 
        uint256 userPk, 
        address erc721, 
        address erc20, 
        uint256 tokenId, 
        uint256 startPrice, 
        uint256 endPrice, 
        uint256 start, 
        uint256 deadline
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {

        bytes32 hash = keccak256(abi.encode(marketplace.SWAP_TYPEHASH(),user,erc721,erc20,tokenId,startPrice,endPrice,start,deadline));

        (v, r, s) = vm.sign(userPk, keccak256(abi.encodePacked("\x19\x01", marketplace.DOMAIN_SEPARATOR(), hash)));
    }

    function testComputeSigner(uint256 startPrice, uint256 tokenId, uint256 feePercent) public {

        vm.assume(startPrice >= 1e4);
        vm.assume(feePercent <= 1e4);

        marketplace.updateCollectionFee(address(erc721), feePercent);

        setUpBalances(startPrice, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = sign(
            BOB,
            BOB_PK,
            address(erc721), 
            address(erc20), 
            tokenId,
            startPrice,
            0,      // Denotes Fixed Price Order 
            0,      // Denotes Fixed Price Order
            block.timestamp
        );

        address signer = marketplace.computeSigner(
            Marketplace.SwapMetadata(
                BOB,
                address(erc721), 
                address(erc20), 
                tokenId, 
                startPrice,
                0,      // Denotes Fixed Price Order 
                0,      // Denotes Fixed Price Order
                block.timestamp
            ),
            v, 
            r, 
            s
        );

        assertEq(BOB, signer);
    }

    function testSwapFixed(uint256 startPrice, uint256 tokenId, uint256 feePercent) public {

        vm.assume(startPrice >= 1e4);
        vm.assume(feePercent <= 1e4);

        marketplace.updateCollectionFee(address(erc721), feePercent);

        setUpBalances(startPrice, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = sign(
            BOB,
            BOB_PK,
            address(erc721), 
            address(erc20), 
            tokenId, 
            startPrice,
            0,      // Denotes Fixed Price Order 
            0,      // Denotes Fixed Price Order
            block.timestamp
        );

        vm.prank(ALICE);
        marketplace.swap(
            Marketplace.SwapMetadata(
                BOB, 
                address(erc721), 
                address(erc20), 
                tokenId, 
                startPrice, 
                0, 
                0, 
                block.timestamp
            ), v, r, s
        );

        uint256 fee = FullMath.mulDiv(startPrice, feePercent, 1e4);

        // assertEq(marketplace.nonces(BOB), 1);
        assertEq(erc20.balanceOf(BOB), startPrice - fee);
        assertEq(erc721.ownerOf(tokenId), ALICE);
        // assertEq(erc20.balanceOf(marketplace.owner), fee);
    }

    // function testSwapDutch(uint256 startPrice, uint256 endPrice, uint256 tokenId, uint256 feePercent, uint256 start) public {

    //     vm.assume(start < block.timestamp);
    //     vm.assume(startPrice > endPrice);
    //     vm.assume(startPrice >= 1e4);
    //     vm.assume(endPrice >= 1e4);
    //     vm.assume(feePercent <= 1e4);

    //     marketplace.updateCollectionFee(address(erc721), feePercent);

    //     (uint8 v, bytes32 r, bytes32 s) = sign(
    //         BOB,
    //         BOB_PK,
    //         address(erc721), 
    //         address(erc20), 
    //         tokenId, 
    //         startPrice,
    //         endPrice,
    //         start,      // Denotes Fixed Price Order
    //         block.timestamp
    //     );

    //     marketplace.SwapMetadata memory data = Marketplace.SwapMetadata(
    //         BOB, 
    //         address(erc721), 
    //         address(erc20), 
    //         tokenId, 
    //         startPrice, 
    //         endPrice, 
    //         start,
    //         block.timestamp
    //     );

    //     uint256 price = marketplace.computePrice(data);

    //     setUpBalances(price, tokenId);

    //     vm.prank(ALICE);
    //     marketplace.swap(data, v, r, s);


    //     uint256 fee = FullMath.mulDiv(price, feePercent, 1e4);

    //     // assertEq(marketplace.nonces(BOB), 1);
    //     assertEq(erc20.balanceOf(BOB), price - fee);
    //     assertEq(erc721.ownerOf(tokenId), ALICE);
    //     assertEq(erc20.balanceOf(marketplace.feeAddress()), fee);
    // }

    function testSwapEthFixed(uint256 startPrice, uint256 tokenId, uint256 feePercent) public {

        vm.assume(startPrice >= 1e4);
        vm.assume(feePercent <= 1e4);

        marketplace.updateWhitelist(address(0));

        marketplace.updateCollectionFee(address(erc721), feePercent);

        setUpBalances(startPrice, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = sign(
            BOB, 
            BOB_PK, 
            address(erc721), 
            address(0), 
            tokenId, 
            startPrice, 
            0, 
            0, 
            block.timestamp
        );

        vm.deal(ALICE, startPrice);
        vm.prank(ALICE);
        marketplace.swap{value: startPrice}(
            Marketplace.SwapMetadata(
                BOB, 
                address(erc721), 
                address(0), 
                tokenId, 
                startPrice, 
                0, 
                0, 
                block.timestamp
            ), v, r, s
        );

        uint256 fee = FullMath.mulDiv(startPrice, feePercent, 1e4);

        // assertEq(marketplace.nonces(BOB), 1);
        assertEq(BOB.balance, startPrice - fee);
        assertEq(erc721.ownerOf(tokenId), ALICE);
        assertEq(address(marketplace).balance, fee);
    }

    function testSwapEthDutch(uint256 startPrice, uint256 endPrice, uint256 tokenId, uint256 feePercent, uint256 start) public {

        vm.assume(start < block.timestamp);
        vm.assume(startPrice > endPrice);
        vm.assume(startPrice >= 1e4);
        vm.assume(endPrice >= 1e4);
        vm.assume(feePercent <= 1e4);

        marketplace.updateWhitelist(address(0));

        marketplace.updateCollectionFee(address(erc721), feePercent);

        setUpBalances(0, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = sign(
            BOB, 
            BOB_PK, 
            address(erc721), 
            address(0), 
            tokenId, 
            startPrice, 
            endPrice, 
            start, 
            block.timestamp
        );

        Marketplace.SwapMetadata memory data = Marketplace.SwapMetadata(
            BOB, 
            address(erc721), 
            address(0), 
            tokenId, 
            startPrice, 
            endPrice, 
            start,
            block.timestamp
        );

        uint256 price = marketplace.computePrice(data);

        vm.deal(ALICE, price);
        vm.prank(ALICE);
        marketplace.swap{value: price}(data, v, r, s);

        uint256 fee = FullMath.mulDiv(price, feePercent, 1e4);

        // assertEq(marketplace.nonces(BOB), 1);
        assertEq(BOB.balance, price - fee);
        assertEq(erc721.ownerOf(tokenId), ALICE);
        assertEq(address(marketplace).balance, fee);
    }

    function testFailSwapBadDeadline(uint256 startPrice, uint256 tokenId) public {

        vm.assume(startPrice >= 1e4);

        setUpBalances(startPrice, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = sign(
            BOB,
            BOB_PK,
            address(erc721), 
            address(erc20), 
            tokenId, 
            startPrice,
            0,      // Denotes Fixed Price Order 
            0,      // Denotes Fixed Price Order
            block.timestamp
        );

        vm.prank(ALICE);
        marketplace.swap(
            Marketplace.SwapMetadata(
                BOB, 
                address(erc721), 
                address(erc20), 
                tokenId, 
                startPrice, 
                0, 
                0, 
                block.timestamp + 1
            ), v, r, s
        );
    }

    function testFailSwapPastDeadline(uint256 startPrice, uint256 tokenId) public {

        vm.assume(startPrice >= 1e4);

        setUpBalances(startPrice, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = sign(
            BOB,
            BOB_PK,
            address(erc721), 
            address(erc20), 
            tokenId, 
            startPrice,
            0,      // Denotes Fixed Price Order 
            0,      // Denotes Fixed Price Order
            block.timestamp - 1
        );

        vm.prank(ALICE);
        marketplace.swap(
            Marketplace.SwapMetadata(
                BOB, 
                address(erc721), 
                address(erc20), 
                tokenId, 
                startPrice, 
                0, 
                0, 
                block.timestamp - 1
            ), v, r, s
        );
    }

    function testFailSwapReplay(uint256 startPrice, uint256 tokenId) public {

        setUpBalances(startPrice, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = sign(
            BOB,
            BOB_PK,
            address(erc721), 
            address(erc20), 
            tokenId, 
            startPrice,
            0,      // Denotes Fixed Price Order 
            0,      // Denotes Fixed Price Order
            block.timestamp
        );

        vm.startPrank(ALICE);
        marketplace.swap(
            Marketplace.SwapMetadata(
                BOB, 
                address(erc721), 
                address(erc20), 
                tokenId, 
                startPrice, 
                0, 
                0, 
                block.timestamp
            ), v, r, s
        );
        marketplace.swap(
            Marketplace.SwapMetadata(
                BOB, 
                address(erc721), 
                address(erc20), 
                tokenId, 
                startPrice, 
                0, 
                0, 
                block.timestamp
            ), v, r, s
        );
        vm.stopPrank();
    }

    // function testVerifyOrder(uint256 startPrice, uint256 tokenId) public {

    //     vm.assume(startPrice >= 1e4);
    //     vm.assume(startPrice <= type(uint).max);
    //     vm.assume(tokenId <= type(uint).max);

    //     setUpBalances(startPrice, tokenId);

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(
    //         BOB_PK,
    //         keccak256(
    //             abi.encodePacked(
    //                 "\x19\x01",
    //                 marketplace.DOMAIN_SEPARATOR(),
    //                 keccak256(abi.encode(marketplace.SWAP_TYPEHASH(), BOB, address(erc721), address(erc20), tokenId, startPrice, 0, block.timestamp))
    //             )
    //         )
    //     );
        
    //     bool valid = marketplace.verify(BOB, address(0), address(erc721), address(erc20), tokenId, startPrice, block.timestamp, v, r, s);

    //     assertTrue(valid);
    // }

    // function testFailVerifyOrderBadDeadline(uint256 startPrice, uint256 tokenId) public {

    //     vm.assume(startPrice >= 1e4);
    //     vm.assume(startPrice <= type(uint).max);
    //     vm.assume(tokenId <= type(uint).max);

    //     setUpBalances(startPrice, tokenId);

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(
    //         BOB_PK,
    //         keccak256(
    //             abi.encodePacked(
    //                 "\x19\x01",
    //                 marketplace.DOMAIN_SEPARATOR(),
    //                 keccak256(abi.encode(marketplace.SWAP_TYPEHASH(), BOB, address(erc721), address(erc20), tokenId, startPrice, 0, block.timestamp))
    //             )
    //         )
    //     );

    //     vm.warp(block.timestamp + 1);
        
    //     bool valid = marketplace.verify(BOB, address(0), address(erc721), address(erc20), tokenId, startPrice, block.timestamp, v, r, s);

    //     assertTrue(valid);
    // }

    // function testFailVerifyOrderPastDeadline(uint256 startPrice, uint256 tokenId) public {

    //     vm.assume(startPrice >= 1e4);
    //     vm.assume(startPrice <= type(uint).max);
    //     vm.assume(tokenId <= type(uint).max);

    //     setUpBalances(startPrice, tokenId);

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(
    //         BOB_PK,
    //         keccak256(
    //             abi.encodePacked(
    //                 "\x19\x01",
    //                 marketplace.DOMAIN_SEPARATOR(),
    //                 keccak256(abi.encode(marketplace.SWAP_TYPEHASH(), BOB, address(erc721), address(erc20), tokenId, startPrice, 0, block.timestamp - 1))
    //             )
    //         )
    //     );
        
    //     bool valid = marketplace.verify(BOB, address(0), address(erc721), address(erc20), tokenId, startPrice, block.timestamp, v, r, s);

    //     assertTrue(valid);
    // }

    function testVerifyOrderSellerTransfered(uint256 startPrice, uint256 tokenId) public {

        vm.assume(startPrice >= 1e4);
        vm.assume(startPrice <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(startPrice, tokenId);

        vm.prank(BOB);
        erc721.safeTransferFrom(BOB, EVE, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    marketplace.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(marketplace.SWAP_TYPEHASH(), BOB, address(erc721), address(erc20), tokenId, startPrice, 0, block.timestamp))
                )
            )
        );



        bool valid = marketplace.isValidSignature(Marketplace.SwapMetadata(
            address(0), 
            address(erc721), 
            address(erc20), 
            tokenId, 
            startPrice, 
            0, 
            0, 
            block.timestamp
        ), BOB, v, r, s);

        assertTrue(valid);
    }

    function testVerifyOrderBobTriesToSellEveserc721(uint256 startPrice, uint256 tokenId) public {
        
        vm.assume(startPrice >= 1e4);
        vm.assume(startPrice <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(startPrice, tokenId);

        vm.prank(BOB);
        erc721.safeTransferFrom(BOB, EVE, tokenId);

        vm.prank(EVE);
        erc721.approve(address(marketplace), tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    marketplace.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(marketplace.SWAP_TYPEHASH(), EVE, address(erc721), address(erc20), tokenId, startPrice, 0, block.timestamp))
                )
            )
        );

        bool valid = marketplace.isValidSignature(Marketplace.SwapMetadata(
            address(0), 
            address(erc721), 
            address(erc20), 
            tokenId, 
            startPrice, 
            0, 
            0, 
            block.timestamp
        ), BOB, v, r, s);

        assertTrue(valid);
    }
}