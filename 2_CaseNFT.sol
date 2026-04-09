// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title CaseNFT - Non-Fungible Token representing individual litigation cases
/// @notice Each NFT is a "passport" for a court case with on-chain metadata
/// @dev Only the owner (CaseManager) can mint and update cases
contract CaseNFT is ERC721, Ownable {

    /// @notice Possible stages of a litigation case
    enum Stage { Filed, Discovery, Trial, Verdict, Enforcement }
    
    /// @notice Possible outcomes of a case
    enum Status { Active, Won, Lost }

    /// @notice Metadata structure for each case
    struct CaseInfo {
        string jurisdiction;      // e.g. "New York, USA"
        string caseType;          // e.g. "Patent Infringement"
        uint256 claimAmount;      // Amount sought in the lawsuit (in USDC wei)
        uint256 fundingRequired;  // How much funding this case needs
        Stage stage;              // Current stage of proceedings
        Status status;            // Active, Won, or Lost
        uint256 createdAt;        // Timestamp when case was created
    }

    /// @notice Mapping from token ID to case information
    mapping(uint256 => CaseInfo) public cases;

    /// @notice Counter for generating unique token IDs
    uint256 private _nextTokenId;

    /// @notice Emitted when a new case is created
    event CaseCreated(uint256 indexed tokenId, string jurisdiction, string caseType, uint256 claimAmount);
    
    /// @notice Emitted when a case stage is updated
    event StageUpdated(uint256 indexed tokenId, Stage newStage);
    
    /// @notice Emitted when a case is resolved (won or lost)
    event CaseResolved(uint256 indexed tokenId, Status outcome);

    constructor() ERC721("Litigation Case", "CASE") Ownable(msg.sender) {}

    /// @notice Create a new case NFT
    /// @param to Address that will own the NFT (usually the CaseManager contract)
    /// @param jurisdiction The legal jurisdiction of the case
    /// @param caseType Type of litigation (e.g. "Commercial Dispute")
    /// @param claimAmount Total amount sought in the lawsuit
    /// @param fundingRequired Amount of funding needed for this case
    /// @return tokenId The ID of the newly created case NFT
    function mintCase(
        address to,
        string memory jurisdiction,
        string memory caseType,
        uint256 claimAmount,
        uint256 fundingRequired
    ) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        
        cases[tokenId] = CaseInfo({
            jurisdiction: jurisdiction,
            caseType: caseType,
            claimAmount: claimAmount,
            fundingRequired: fundingRequired,
            stage: Stage.Filed,
            status: Status.Active,
            createdAt: block.timestamp
        });

        emit CaseCreated(tokenId, jurisdiction, caseType, claimAmount);
        return tokenId;
    }

    /// @notice Update the stage of an active case
    /// @param tokenId The case NFT ID
    /// @param newStage The new stage to set
    function updateStage(uint256 tokenId, Stage newStage) external onlyOwner {
        require(cases[tokenId].status == Status.Active, "Case is not active");
        cases[tokenId].stage = newStage;
        emit StageUpdated(tokenId, newStage);
    }

    /// @notice Resolve a case as won or lost
    /// @param tokenId The case NFT ID
    /// @param won True if case was won, false if lost
    function resolveCase(uint256 tokenId, bool won) external onlyOwner {
        require(cases[tokenId].status == Status.Active, "Case already resolved");
        cases[tokenId].status = won ? Status.Won : Status.Lost;
        cases[tokenId].stage = Stage.Verdict;
        emit CaseResolved(tokenId, cases[tokenId].status);
    }

    /// @notice Get full information about a case
    /// @param tokenId The case NFT ID
    /// @return The CaseInfo struct with all metadata
    function getCaseInfo(uint256 tokenId) external view returns (CaseInfo memory) {
        return cases[tokenId];
    }
}
