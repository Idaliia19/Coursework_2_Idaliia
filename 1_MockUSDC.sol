// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC - Test stablecoin for Sepolia testnet
/// @notice This contract simulates USDC for testing purposes only
/// @dev Anyone can mint tokens to themselves for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    /// @notice Mint test USDC to your wallet
    /// @param amount The amount to mint (in wei, so 1000000 = 1 USDC with 6 decimals, but we use 18 here)
    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    /// @notice We use 18 decimals for simplicity (real USDC uses 6)
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
