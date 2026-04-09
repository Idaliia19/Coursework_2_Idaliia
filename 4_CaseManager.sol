// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ============================================
//  Interfaces for interacting with other contracts
// ============================================

interface ICaseNFT {
    function mintCase(
        address to,
        string memory jurisdiction,
        string memory caseType,
        uint256 claimAmount,
        uint256 fundingRequired
    ) external returns (uint256);
    
    function resolveCase(uint256 tokenId, bool won) external;
    function updateStage(uint256 tokenId, uint8 newStage) external;
}

interface ILitigationVault {
    function deployFunds(uint256 caseId, uint256 amount) external;
    function receivePayout(uint256 caseId, uint256 amount) external;
}

// ============================================
//  CaseToken - ERC-20 token for direct investors in a specific case
// ============================================

/// @title CaseToken - Fungible token representing direct investment in a specific case
/// @notice Created automatically by CaseManager for each new case
contract CaseToken is ERC20 {
    address public immutable manager;

    constructor(
        string memory name,
        string memory symbol,
        address _manager
    ) ERC20(name, symbol) {
        manager = _manager;
    }

    /// @notice Only the CaseManager can mint tokens
    function mint(address to, uint256 amount) external {
        require(msg.sender == manager, "Only manager can mint");
        _mint(to, amount);
    }

    /// @notice Only the CaseManager can burn tokens
    function burn(address from, uint256 amount) external {
        require(msg.sender == manager, "Only manager can burn");
        _burn(from, amount);
    }
}

// ============================================
//  CaseManager - Main coordinator contract
// ============================================

/// @title CaseManager - Coordinates case creation, funding, resolution, and payout distribution
/// @notice This is the brain of the litigation finance platform
/// @dev Connects CaseNFT, LitigationVault, and direct investors
contract CaseManager is Ownable {

    // ---- External contract references ----
    IERC20 public immutable usdc;
    ICaseNFT public immutable caseNFT;
    ILitigationVault public immutable vault;

    // ---- Data structures ----

    /// @notice Funding information for each case
    struct CaseFunding {
        uint256 vaultAmount;        // How much the vault invested
        uint256 directAmount;       // How much direct investors invested in total
        uint256 totalFundingGoal;   // How much funding this case needs
        bool fundingClosed;         // Whether funding round is closed
        bool resolved;              // Whether case has been resolved
        address caseToken;          // Address of the CASE-XXX ERC-20 token
        uint256 payoutAmount;       // Total payout received (0 if lost)
    }

    /// @notice Mapping from case ID to funding information
    mapping(uint256 => CaseFunding) public caseFunding;

    /// @notice Track each direct investor's claimable payout per case
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // ---- Events ----
    event CaseCreated(uint256 indexed caseId, address caseToken, uint256 fundingGoal);
    event VaultFunded(uint256 indexed caseId, uint256 amount);
    event DirectFunded(uint256 indexed caseId, address indexed investor, uint256 amount);
    event FundingClosed(uint256 indexed caseId);
    event CaseResolved(uint256 indexed caseId, bool won, uint256 payoutAmount);
    event PayoutClaimed(uint256 indexed caseId, address indexed investor, uint256 amount);

    constructor(
        address _usdc,
        address _caseNFT,
        address _vault
    ) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        caseNFT = ICaseNFT(_caseNFT);
        vault = ILitigationVault(_vault);
    }

    // ============================================
    //  Step 1: Create a new case
    // ============================================

    /// @notice Create a new litigation case with NFT and case-specific token
    /// @param jurisdiction Legal jurisdiction (e.g. "New York, USA")
    /// @param caseType Type of case (e.g. "Patent Infringement")
    /// @param claimAmount Total amount sought in lawsuit
    /// @param fundingGoal Amount of funding needed
    /// @return caseId The ID of the new case
    function createCase(
        string memory jurisdiction,
        string memory caseType,
        uint256 claimAmount,
        uint256 fundingGoal
    ) external onlyOwner returns (uint256) {
        // Mint the Case NFT (owned by this contract)
        uint256 caseId = caseNFT.mintCase(
            address(this),
            jurisdiction,
            caseType,
            claimAmount,
            fundingGoal
        );

        // Create a case-specific ERC-20 token for direct investors
        string memory tokenName = string(abi.encodePacked("Case Token ", _uint2str(caseId)));
        string memory tokenSymbol = string(abi.encodePacked("CASE-", _uint2str(caseId)));
        CaseToken newToken = new CaseToken(tokenName, tokenSymbol, address(this));

        // Store funding information
        caseFunding[caseId] = CaseFunding({
            vaultAmount: 0,
            directAmount: 0,
            totalFundingGoal: fundingGoal,
            fundingClosed: false,
            resolved: false,
            caseToken: address(newToken),
            payoutAmount: 0
        });

        emit CaseCreated(caseId, address(newToken), fundingGoal);
        return caseId;
    }

    // ============================================
    //  Step 2: Fund a case (two paths)
    // ============================================

    /// @notice Fund a case from the vault (passive investor path)
    /// @param caseId The case to fund
    /// @param amount Amount of USDC to deploy from vault
    function fundFromVault(uint256 caseId, uint256 amount) external onlyOwner {
        CaseFunding storage cf = caseFunding[caseId];
        require(!cf.fundingClosed, "Funding is closed");
        require(cf.vaultAmount + cf.directAmount + amount <= cf.totalFundingGoal, "Exceeds funding goal");

        // Tell vault to send funds to this contract
        vault.deployFunds(caseId, amount);
        cf.vaultAmount += amount;

        emit VaultFunded(caseId, amount);
    }

    /// @notice Fund a case directly as an individual investor
    /// @param caseId The case to fund
    /// @param amount Amount of USDC to invest
    function fundDirect(uint256 caseId, uint256 amount) external {
        CaseFunding storage cf = caseFunding[caseId];
        require(!cf.fundingClosed, "Funding is closed");
        require(cf.vaultAmount + cf.directAmount + amount <= cf.totalFundingGoal, "Exceeds funding goal");

        // Transfer USDC from investor to this contract
        usdc.transferFrom(msg.sender, address(this), amount);
        cf.directAmount += amount;

        // Mint case-specific tokens to the investor
        CaseToken(cf.caseToken).mint(msg.sender, amount);

        emit DirectFunded(caseId, msg.sender, amount);
    }

    /// @notice Close the funding round for a case (no more investments accepted)
    /// @param caseId The case to close funding for
    function closeFunding(uint256 caseId) external onlyOwner {
        caseFunding[caseId].fundingClosed = true;
        emit FundingClosed(caseId);
    }

    // ============================================
    //  Step 3: Resolve a case and distribute payout
    // ============================================

    /// @notice Resolve a case and distribute the payout proportionally
    /// @param caseId The case NFT ID
    /// @param won Whether the case was won
    /// @param payoutAmount Total payout received (0 if lost)
    function resolveCase(uint256 caseId, bool won, uint256 payoutAmount) external onlyOwner {
        CaseFunding storage cf = caseFunding[caseId];
        require(!cf.resolved, "Case already resolved");
        require(cf.fundingClosed, "Close funding first");

        cf.resolved = true;
        cf.payoutAmount = payoutAmount;

        // Update NFT status
        caseNFT.resolveCase(caseId, won);

        if (won && payoutAmount > 0) {
            // Transfer payout USDC into this contract (admin must have sent it first)
            // In production, this would come from an oracle or bridge
            // For testnet: admin transfers USDC to this contract before calling resolveCase

            uint256 totalFunded = cf.vaultAmount + cf.directAmount;

            // Calculate vault's share proportionally
            if (cf.vaultAmount > 0) {
                uint256 vaultShare = (payoutAmount * cf.vaultAmount) / totalFunded;
                usdc.transfer(address(vault), vaultShare);
                vault.receivePayout(caseId, vaultShare);
            }

            // Direct investors' share stays in this contract for claiming
            // (they claim individually via claimDirectPayout)
        }

        emit CaseResolved(caseId, won, payoutAmount);
    }

    // ============================================
    //  Step 4: Direct investors claim their payout
    // ============================================

    /// @notice Direct investor claims their share of the payout
    /// @param caseId The resolved case ID
    function claimDirectPayout(uint256 caseId) external {
        CaseFunding storage cf = caseFunding[caseId];
        require(cf.resolved, "Case not resolved yet");
        require(!hasClaimed[caseId][msg.sender], "Already claimed");

        CaseToken token = CaseToken(cf.caseToken);
        uint256 investorTokens = token.balanceOf(msg.sender);
        require(investorTokens > 0, "No tokens to claim with");

        hasClaimed[caseId][msg.sender] = true;

        if (cf.payoutAmount > 0 && cf.directAmount > 0) {
            uint256 totalFunded = cf.vaultAmount + cf.directAmount;
            uint256 directPoolShare = (cf.payoutAmount * cf.directAmount) / totalFunded;
            uint256 investorShare = (directPoolShare * investorTokens) / cf.directAmount;

            // Burn the case tokens
            token.burn(msg.sender, investorTokens);

            // Send USDC payout
            if (investorShare > 0) {
                usdc.transfer(msg.sender, investorShare);
            }

            emit PayoutClaimed(caseId, msg.sender, investorShare);
        } else {
            // Case lost - burn tokens, no payout
            token.burn(msg.sender, investorTokens);
            emit PayoutClaimed(caseId, msg.sender, 0);
        }
    }

    // ============================================
    //  View functions
    // ============================================

    /// @notice Get funding details for a case
    function getCaseFunding(uint256 caseId) external view returns (CaseFunding memory) {
        return caseFunding[caseId];
    }

    /// @notice Get the case token address for direct investment
    function getCaseToken(uint256 caseId) external view returns (address) {
        return caseFunding[caseId].caseToken;
    }

    // ============================================
    //  Helper function
    // ============================================

    /// @dev Convert uint to string (for token naming)
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
