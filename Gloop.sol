// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IAgentIDRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title GLOOP — free-mint NFT on BSC with in-contract proof-of-work.
/// 3,333 Gloops, all public: every token is minted through the same public
/// free mint. Minting is free and gated by holding a SPACE ID Agent ID,
/// one per wallet, and the mint requires a proof-of-work nonce verified
/// INSIDE this contract: keccak256(minter, nonce) must show at least
/// difficultyBits() leading zero bits. Difficulty rises in phases as
/// publicMinted grows, on a deliberately light ladder:
/// 18 bits -> 21 at 834 -> 24 at 1,670 -> 27 at 2,504 public mints.
/// Each mint's tier is drawn pseudo-randomly at mint time from the locked
/// tier quotas (Common 2,000 / Rare 833 / Epic 333 / Legendary 167).
/// Royalty (EIP-2981) 5% to the creator.
contract Gloop is ERC721, ERC2981, Ownable {
    uint256 public constant TOTAL_SUPPLY = 3333;
    uint96 public constant ROYALTY_BPS = 500; // 5%

    /// @notice Public mint opens 2026-11-08 12:00 UTC. Fixed in the source
    /// at build time — a constant, not an owner switch; it cannot be moved.
    uint256 public constant MINT_START = 1794139200;

    // Tier ids: 0 = Common, 1 = Rare, 2 = Epic, 3 = Legendary.
    uint256[4] public tierQuota = [2000, 833, 333, 167];
    uint256[4] public tierMinted;

    IAgentIDRegistry public constant AGENT_REGISTRY =
        IAgentIDRegistry(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);

    uint256 public totalMinted;
    mapping(address => bool) public hasMinted;
    mapping(uint256 => uint8) public tokenTier;

    string private _baseTokenURI;
    bool public baseURILocked;

    event GloopMinted(
        address indexed minter,
        uint256 tokenId,
        uint8 tier,
        uint256 nonce,
        uint256 difficultyBits
    );
    event BaseURISet(string uri);
    event BaseURILocked();

    constructor(
        address creator_,
        address owner_,
        string memory baseURI_
    ) ERC721("Gloop", "GLOOP") Ownable(owner_) {
        require(creator_ != address(0), "creator=0");
        _baseTokenURI = baseURI_;
        _setDefaultRoyalty(creator_, ROYALTY_BPS);
    }

    /// @notice Current proof-of-work difficulty, in leading zero bits.
    /// Light ladder (redeployed 2026-11-07 at the owner's request so the
    /// mint pace is not throttled by the proof-of-work):
    /// Phase 1 (mints 0-833): 18 bits. Phase 2 (834-1,669): 21 bits.
    /// Phase 3 (1,670-2,503): 24 bits. Phase 4 (2,504-3,332): 27 bits.
    function difficultyBits() public view returns (uint256) {
        uint256 m = totalMinted;
        if (m < 834) return 18;
        if (m < 1670) return 21;
        if (m < 2504) return 24;
        return 27;
    }

    /// @notice True once the public launch moment (MINT_START) is reached.
    function mintOpen() public view returns (bool) {
        return block.timestamp >= MINT_START;
    }

    /// @notice Free PoW mint. Find a nonce such that
    /// keccak256(abi.encodePacked(yourAddress, nonce)) has at least
    /// difficultyBits() leading zero bits, then call mint(nonce).
    /// The tier is drawn at mint time; quotas are enforced exactly.
    function mint(uint256 nonce) external {
        require(AGENT_REGISTRY.balanceOf(msg.sender) > 0, "Agent ID required");
        require(!hasMinted[msg.sender], "already minted");
        require(totalMinted < TOTAL_SUPPLY, "sold out");
        uint256 bits = difficultyBits();
        bytes32 digest = keccak256(abi.encodePacked(msg.sender, nonce));
        require(uint256(digest) >> (256 - bits) == 0, "proof too weak");
        require(block.timestamp >= MINT_START, "mint not open yet");
        uint8 tier = _drawTier(msg.sender, nonce);
        hasMinted[msg.sender] = true;
        tierMinted[tier] += 1;
        totalMinted += 1;
        uint256 tokenId = totalMinted;
        tokenTier[tokenId] = tier;
        _safeMint(msg.sender, tokenId);
        emit GloopMinted(msg.sender, tokenId, tier, nonce, bits);
    }

    /// @dev Draw a tier weighted by the remaining quotas. Re-draws with a
    /// bumped seed while the drawn tier's quota is exhausted, so the final
    /// totals always match the locked quotas exactly.
    function _drawTier(address minter, uint256 nonce)
        internal
        view
        returns (uint8)
    {
        uint256 remaining = TOTAL_SUPPLY - totalMinted;
        uint256 seed = uint256(
            keccak256(abi.encodePacked(minter, nonce, totalMinted))
        );
        for (uint256 attempt = 0; attempt < 64; attempt++) {
            uint256 r = (seed + attempt) % remaining;
            uint256 acc = 0;
            for (uint256 t = 0; t < 4; t++) {
                acc += tierQuota[t] - tierMinted[t];
                if (r < acc) return uint8(t);
            }
        }
        // Unreachable in practice: fall back to any tier with quota left.
        for (uint256 t = 0; t < 4; t++) {
            if (tierMinted[t] < tierQuota[t]) return uint8(t);
        }
        revert("no tier left");
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        require(!baseURILocked, "baseURI locked");
        _baseTokenURI = uri;
        emit BaseURISet(uri);
    }

    function lockBaseURI() external onlyOwner {
        baseURILocked = true;
        emit BaseURILocked();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireOwned(tokenId);
        return
            string(
                abi.encodePacked(
                    _baseTokenURI,
                    Strings.toString(tokenId),
                    ".json"
                )
            );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
