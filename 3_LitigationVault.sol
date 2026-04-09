// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title LitigationVault - Tokenized vault for passive litigation finance investors
/// @notice Investors deposit USDC and receive LIT tokens representing their share
/// @dev Based on ERC-4626 standard for automatic share price accounting
contract LitigationVault is ERC4626, Ownable {

    /// @notice Address of the CaseManager contract (authorized to withdraw funds and receive payouts)
    address public caseManager;

    /// @notice Total amount currently deployed in active cases
    uint256 public totalDeployed;

    /// @notice Emitted when funds are sent to finance a case
    event FundsDeployed(uint256 indexed caseId, uint256 amount);
    
    /// @notice Emitted when payout is received from a resolved case
    event PayoutReceived(uint256 indexed caseId, uint256 amount);

    /// @notice Emitted when CaseManager address is set
    event CaseManagerSet(address indexed caseManager);

    constructor(
        IERC20 _asset
    ) ERC4626(_asset) ERC20("Litigation Vault Token", "LIT") Ownable(msg.sender) {}

    /// @notice Set the CaseManager contract address (only owner, once)
    /// @param _caseManager Address of the deployed CaseManager contract
    function setCaseManager(address _caseManager) external onlyOwner {
        require(_caseManager != address(0), "Invalid address");
        caseManager = _caseManager;
        emit CaseManagerSet(_caseManager);
    }

    /// @notice Modifier to restrict functions to CaseManager only
    modifier onlyCaseManager() {
        require(msg.sender == caseManager, "Only CaseManager can call this");
        _;
    }

    /// @notice Deploy funds from vault to finance a case (called by CaseManager)
    /// @param caseId The case NFT ID for tracking
    /// @param amount Amount of USDC to deploy
    function deployFunds(uint256 caseId, uint256 amount) external onlyCaseManager {
        require(amount <= IERC20(asset()).balanceOf(address(this)), "Insufficient vault balance");
        totalDeployed += amount;
        IERC20(asset()).transfer(caseManager, amount);
        emit FundsDeployed(caseId, amount);
    }

    /// @notice Receive payout from a resolved case (called by CaseManager)
    /// @param caseId The case NFT ID for tracking
    /// @param amount Amount of USDC returned to vault
    function receivePayout(uint256 caseId, uint256 amount) external onlyCaseManager {
        if (amount <= totalDeployed) {
            totalDeployed -= amount;
        } else {
            totalDeployed = 0;
        }
        // Note: CaseManager must have already transferred USDC to this vault before calling
        emit PayoutReceived(caseId, amount);
    }

    /// @notice Override totalAssets to account for deployed capital
    /// @return Total assets including both idle USDC in vault and deployed capital
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalDeployed;
    }
}
