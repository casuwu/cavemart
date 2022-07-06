// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import { MockERC20, MockERC721 } from "./mocks/Tokens.sol";

import "forge-std/Test.sol";

import "../FixedOrderMarket.sol";

contract FixedOrderMarketTest is Test {

    bytes32 public immutable FULFILL_TYPEHASH = keccak256("FulFill(address seller,address erc721,address erc20,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)");
    
    // @notice          GEM is an ERC20
    MockERC20 GEM;

    // @notice          NFT is an ERC721
    MockERC721 NFT;
    
    // @notice          FOM is a Fixed Order Market that 
    //                  allows users to trade ERC20<->ERC721 
    //                  with minimal calls.
    FixedOrderMarket FOM;

    // USER ALICE:
    // @notice          Alice is a huge fan of NFTs and 
    //                  buys them all the time using GEMs.
    uint256 ALICE_PK = 0xCAFE;
    address ALICE = vm.addr(ALICE_PK);

    // USER BOB:
    // @notice          Bob is an artist, and sells his art 
    //                  in the form of NFTs.
    uint256 BOB_PK = 0xBEEF;
    address BOB = vm.addr(BOB_PK);

    // USER EVE:
    // @notice          Eve owns the most valuable NFT, tokenId #420 
    //                  
    uint256 EVE_PK = 0xADAD;
    address EVE = vm.addr(EVE_PK);

    // PRE-TEST SETUP

    function setUp() public {

        // Deploy contracts
        FOM = new FixedOrderMarket();
        GEM = new MockERC20("DAI", "DAI");
        NFT = new MockERC721("lsdCSV", "lsdCSV");

        // Add tokens to whitelist
        FOM.updateWhitelist(address(GEM));
        FOM.updateWhitelist(address(NFT));

        // Label all used addresses within VM
        vm.label(address(GEM), "TEST::ERC20");
        vm.label(address(NFT), "TEST::NFT");
        vm.label(ALICE, "USER::ALICE");
        vm.label(BOB, "USER::BOB");
    }

    // PRE-TEST SETUP HELPERS

    function setUpBalances(
        uint256 amount, 
        uint256 tokenId
    ) public {

        // Mint ALICE the amount that's going to be paid to BOB
        GEM.mint(ALICE, amount);
        // Mint BOB the NFT he's going to sell to Alice
        NFT.mint(BOB, tokenId);
        // Approve market to spend ALICE's tokens
        vm.prank(ALICE);
        GEM.approve(address(FOM), amount);
        // Approve market to spend BOB's NFT
        vm.prank(BOB);
        NFT.approve(address(FOM), tokenId);
    }

    // TESTS   

    function testFulfill(uint256 amount, uint256 tokenId, uint256 feePercent) public {

        vm.assume(amount >= 1e4);
        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);
        vm.assume(feePercent <= 1e4);

        FOM.updateCollectionFee(address(NFT), feePercent);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, 0, block.timestamp))
                )
            )
        );

        vm.prank(ALICE);
        FOM.fulfill(BOB, address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);

        uint256 fee = FullMath.mulDiv(amount, feePercent, 1e4);

        assertEq(FOM.nonces(BOB), 1);
        assertEq(GEM.balanceOf(BOB), amount - fee);
        assertEq(NFT.ownerOf(tokenId), ALICE);
        // assertEq(GEM.balanceOf(address(FOM)), fee);
    }

    function testFulfillEth(uint256 amount, uint256 tokenId, uint256 feePercent) public {

        vm.assume(amount >= 1e4);
        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);
        vm.assume(feePercent <= 1e4);

        FOM.updateWhitelist(address(0));

        FOM.updateCollectionFee(address(NFT), feePercent);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(0), tokenId, amount, 0, block.timestamp))
                )
            )
        );

        vm.deal(ALICE, amount);
        vm.prank(ALICE);
        FOM.fulfill{value: amount}(BOB, address(NFT), address(0), tokenId, amount, block.timestamp, v, r, s);
        
        uint256 fee = FullMath.mulDiv(amount, feePercent, 1e4);

        assertEq(FOM.nonces(BOB), 1);
        assertEq(BOB.balance, amount - fee);
        assertEq(NFT.ownerOf(tokenId), ALICE);
        assertEq(address(FOM).balance, fee);
    }

    function testFailFulfillBadNonce(uint256 amount, uint256 tokenId, uint256 nonce) public {

        console.log(FOM.nonces(BOB));

        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);
        vm.assume(nonce > 0);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, nonce, block.timestamp))
                )
            )
        );

        vm.prank(ALICE);
        FOM.fulfill(BOB, address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);
    }

    function testFailFulfillBadDeadline(uint256 amount, uint256 tokenId, uint256 nonce) public {

        console.log(FOM.nonces(BOB));

        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);
        vm.assume(nonce > 0);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, nonce, block.timestamp))
                )
            )
        );

        vm.prank(ALICE);
        FOM.fulfill(BOB, address(NFT), address(GEM), tokenId, amount, block.timestamp + 1, v, r, s);
    }

    function testFailFulfillPastDeadline(uint256 amount, uint256 tokenId, uint256 nonce) public {

        console.log(FOM.nonces(BOB));


        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);
        vm.assume(nonce > 0);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, nonce, block.timestamp - 1))
                )
            )
        );

        vm.prank(ALICE);
        FOM.fulfill(BOB, address(NFT), address(GEM), tokenId, amount, block.timestamp - 1, v, r, s);
    }

    function testFailFulfillReplay(uint256 amount, uint256 tokenId) public {

        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, 0, block.timestamp))
                )
            )
        );

        vm.startPrank(ALICE);
        FOM.fulfill(BOB, address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);
        FOM.fulfill(BOB, address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);
        vm.stopPrank();
    }

    function testVerifyOrder(uint256 amount, uint256 tokenId) public {

        vm.assume(amount >= 1e4);
        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, 0, block.timestamp))
                )
            )
        );
        
        bool valid = FOM.verifyOrder(BOB, address(0), address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);

        assertTrue(valid);
    }

    function testFailVerifyOrderBadDeadline(uint256 amount, uint256 tokenId) public {

        vm.assume(amount >= 1e4);
        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, 0, block.timestamp))
                )
            )
        );

        vm.warp(block.timestamp + 1);
        
        bool valid = FOM.verifyOrder(BOB, address(0), address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);

        assertTrue(valid);
    }

    function testFailVerifyOrderPastDeadline(uint256 amount, uint256 tokenId) public {

        vm.assume(amount >= 1e4);
        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(amount, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, 0, block.timestamp - 1))
                )
            )
        );
        
        bool valid = FOM.verifyOrder(BOB, address(0), address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);

        assertTrue(valid);
    }

    function testFailVerifyOrderSellerTransfered(uint256 amount, uint256 tokenId) public {

        vm.assume(amount >= 1e4);
        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(amount, tokenId);

        vm.prank(BOB);
        NFT.safeTransferFrom(BOB, EVE, tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, BOB, address(NFT), address(GEM), tokenId, amount, 0, block.timestamp))
                )
            )
        );
        
        bool valid = FOM.verifyOrder(BOB, address(0), address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);

        assertTrue(valid);
    }

    function testFailVerifyOrderBobTriesToSellEvesNFT(uint256 amount, uint256 tokenId) public {
        
        vm.assume(amount >= 1e4);
        vm.assume(amount <= type(uint).max);
        vm.assume(tokenId <= type(uint).max);

        setUpBalances(amount, tokenId);

        vm.prank(BOB);
        NFT.safeTransferFrom(BOB, EVE, tokenId);

        vm.prank(EVE);
        NFT.approve(address(FOM), tokenId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            BOB_PK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    FOM.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(FULFILL_TYPEHASH, EVE, address(NFT), address(GEM), tokenId, amount, 0, block.timestamp))
                )
            )
        );

        bool valid = FOM.verifyOrder(BOB, address(0), address(NFT), address(GEM), tokenId, amount, block.timestamp, v, r, s);

        assertTrue(valid);
    }
}