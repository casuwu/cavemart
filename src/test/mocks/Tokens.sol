// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract MockERC20 is ERC20 {    
    constructor(
        string memory name, 
        string memory symbol
    ) ERC20(name, symbol) {}

    function mint(address guy, uint256 wad) public {
        _mint(guy, wad);
    }
}

contract MockERC721 is ERC721 {    
    constructor(
        string memory name, 
        string memory symbol
    ) ERC721(name, symbol) {}
    
    function mint(address guy, uint256 wad) public {
        _mint(guy, wad);
    }
    
    function tokenURI(uint256 id) public view override returns (string memory) {
        return '';
    }
}