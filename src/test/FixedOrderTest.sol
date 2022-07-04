// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./mocks/Tokens.sol";
import "../FixedOrder.sol";

contract ContractTest is Test {

    MockERC20 GEM;
    MockERC721 NFT;
    FixedOrder FOM; // Fixed Order Market

    uint256 ALICE_PK = 0x420420;
    uint256 BOB_PK = 0x696969;

    address ALICE = vm.addr(ALICE_PK);
    address BOB = vm.addr(BOB_PK);

    function setUp() public {

        // Deploy contracts
        FOM = new FixedOrder();
        GEM = new MockERC20("DAI", "DAI");
        NFT = new MockERC721("lsdCSV", "lsdCSV");

        // Update the whitelist to allow GEM + NFT 
        // to be traded within
        FOM.updateWhitelist(address(GEM));
        FOM.updateWhitelist(address(NFT));

        // Label all used addresses within VM
        vm.label(address(GEM), "TEST::ERC20");
        vm.label(address(NFT), "TEST::NFT");
        vm.label(ALICE, "USER::ALICE");
        vm.label(BOB, "USER::BOB");
    }

    function setUpBalances(
        uint128 price, 
        uint256 tokenId
    ) public {
        // Mint ALICE the price that's going to be paid to BOB
        GEM.mint(ALICE, price);

        // Mint BOB the NFT he's going to sell to Alice
        NFT.mint(BOB, tokenId);

        // Approve market to spend ALICE's tokens
        vm.prank(ALICE);
        GEM.approve(address(FOM), price);

        // Approve market to spend BOB's NFT
        vm.prank(BOB);
        NFT.approve(address(FOM), tokenId);
    }

    function testCreate(
        uint128 price, 
        uint256 tokenId,
        uint112 deadline
    ) public {
        setUpBalances(price, tokenId);
        
        vm.prank(BOB);
        uint256 orderId = FOM.create(
            address(NFT), 
            address(GEM), 
            tokenId, 
            price, 
            deadline
        );
        // Confirm owner of NFT has been passed to marketplace
        assertEq(NFT.ownerOf(tokenId), address(FOM)); 
        assertEq(orderId, 0);
    }

    function testBuy(
        uint128 price, 
        uint256 tokenId,
        uint112 deadline,
        uint256 fee
    ) public {

        vm.assume(price < type(uint128).max && price >= 10_000);
        vm.assume(tokenId < type(uint).max);
        vm.assume(deadline < type(uint112).max);
        vm.assume(fee <= 10_000);

        FOM.updateFeePercent(fee);

        testCreate(price, tokenId, deadline);

        vm.prank(ALICE);
        FOM.buy(0);

        uint256 EXPECTED_FEES = price * fee / 10_000;
        uint256 EXPECTED_BOB_BALANCE = price - EXPECTED_FEES;
        uint256 BOB_BALANCE = GEM.balanceOf(BOB);

        console.log("BOB_BALANCE", BOB_BALANCE, "EXPECTED_BOB_BALANCE", EXPECTED_BOB_BALANCE);
        assertEq(BOB_BALANCE, EXPECTED_BOB_BALANCE); 
        assertEq(NFT.ownerOf(tokenId), address(BOB)); 

    }

    // function testBuy() public {
        
    //     testCreate();

    //     vm.prank(ALICE);
    //     FOM.buy(0);

    //     assertEq(NFT.ownerOf(1), ALICE); 
    //     assertEq(GEM.balanceOf(ALICE), 0);
    //     assertEq(GEM.balanceOf(BOB), 100 ether);
    // }    
}