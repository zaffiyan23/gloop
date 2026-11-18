// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IGloop {
    function totalMinted() external view returns (uint256);
}

/// @title GLOOP Marketplace — official secondary market for GLOOP NFTs.
///
/// Mechanics (owner's final spec, 2026-11-06):
/// - LISTING FEE: fixed constant 0.0000857 BNB (85700000000000 wei, about
///   $0.06 at build-time prices), charged EXACTLY on every list() and
///   forwarded IMMEDIATELY to FEE_RECIPIENT (the market owner, ghoffar26).
///   The fee is non-refundable: cancel does not return it and re-listing
///   after a cancel charges it again. setPrice() and cancel() are free.
///   The fee recipient lists for free.
/// - MINIMUM PRICE: `minPrice` is a FIXED constant 0.0001 BNB
///   (100000000000000 wei), enforced in list() AND setPrice() for every
///   seller INCLUDING the fee recipient / owner. It never changes: there
///   is no ratchet and no owner override — the floor rule is the same for
///   everyone, forever, in the code itself.
/// - BUY GATE: listing is open from launch, but buy() stays LOCKED until
///   500 Gloops are minted: buy() reverts unless the NFT contract reports
///   totalMinted >= 500. No manual override, no time fallback — the gate
///   is the mint count itself. Listings never expire.
/// - ROYALTY: the collection's EIP-2981 royalty (5%) is paid on every
///   sale out of the sale price; the listing fee is never deducted from
///   the sale price.
contract GloopMarket is Ownable, ReentrancyGuard {
    uint256 public constant LISTING_FEE = 85700000000000; // 0.0000857 BNB ~ $0.06
    uint256 public constant MIN_PRICE = 100000000000000; // 0.0001 BNB, fixed
    uint256 public constant BUY_UNLOCK_MINTED = 500; // buy opens at 500 minted

    IERC721 public immutable NFT;
    address public immutable FEE_RECIPIENT;

    struct ListingData {
        address seller;
        uint256 price;
    }

    mapping(uint256 => ListingData) private _listings;
    uint256[] private _listedIds;
    mapping(uint256 => uint256) private _listedPos; // tokenId -> index + 1

    event Listing(uint256 indexed tokenId, address indexed seller, uint256 price);
    event ListingFeePaid(address indexed seller, uint256 fee);
    event PriceUpdate(uint256 indexed tokenId, uint256 price);
    event Cancel(uint256 indexed tokenId);
    event Sale(
        uint256 indexed tokenId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 royalty
    );

    constructor(address nft_, address owner_, address feeRecipient_)
        Ownable(owner_)
    {
        NFT = IERC721(nft_);
        FEE_RECIPIENT = feeRecipient_;
    }

    /// @notice The fixed minimum listing price (0.0001 BNB). Constant —
    /// there is deliberately no setter.
    function minPrice() external pure returns (uint256) {
        return MIN_PRICE;
    }

    /// @notice Buying opens once 500 Gloops have been minted.
    function tradingOpen() public view returns (bool) {
        return IGloop(address(NFT)).totalMinted() >= BUY_UNLOCK_MINTED;
    }

    function list(uint256 tokenId, uint256 price) external payable nonReentrant {
        require(price >= MIN_PRICE, "price below minimum");
        require(_listings[tokenId].seller == address(0), "already listed");
        require(NFT.ownerOf(tokenId) == msg.sender, "not the owner");
        require(
            NFT.getApproved(tokenId) == address(this) ||
                NFT.isApprovedForAll(msg.sender, address(this)),
            "market not approved"
        );
        if (msg.sender == FEE_RECIPIENT) {
            require(msg.value == 0, "fee recipient lists free");
        } else {
            require(msg.value == LISTING_FEE, "exact listing fee required");
            (bool okF, ) = FEE_RECIPIENT.call{value: LISTING_FEE}("");
            require(okF, "listing fee forward failed");
            emit ListingFeePaid(msg.sender, LISTING_FEE);
        }
        _listings[tokenId] = ListingData(msg.sender, price);
        _listedPos[tokenId] = _listedIds.length + 1;
        _listedIds.push(tokenId);
        emit Listing(tokenId, msg.sender, price);
    }

    function setPrice(uint256 tokenId, uint256 price) external {
        ListingData storage l = _listings[tokenId];
        require(l.seller == msg.sender, "not the seller");
        require(price >= MIN_PRICE, "price below minimum");
        l.price = price;
        emit PriceUpdate(tokenId, price);
    }

    function cancel(uint256 tokenId) external {
        require(_listings[tokenId].seller == msg.sender, "not the seller");
        _remove(tokenId);
        emit Cancel(tokenId);
    }

    /// @notice Remove a stale listing whose NFT has left the seller.
    function cleanListing(uint256 tokenId) external {
        address seller = _listings[tokenId].seller;
        require(seller != address(0), "not listed");
        require(NFT.ownerOf(tokenId) != seller, "listing still valid");
        _remove(tokenId);
        emit Cancel(tokenId);
    }

    function buy(uint256 tokenId) external payable nonReentrant {
        require(tradingOpen(), "trading opens at 500 minted");
        ListingData memory l = _listings[tokenId];
        require(l.seller != address(0), "not listed");
        require(msg.value == l.price, "wrong value");
        require(NFT.ownerOf(tokenId) == l.seller, "stale listing");

        uint256 royalty = 0;
        address royaltyReceiver = address(0);
        try IERC2981(address(NFT)).royaltyInfo(tokenId, l.price) returns (
            address receiver,
            uint256 amount
        ) {
            if (receiver != address(0) && amount <= l.price) {
                royaltyReceiver = receiver;
                royalty = amount;
            }
        } catch {}

        _remove(tokenId);
        NFT.transferFrom(l.seller, msg.sender, tokenId);
        if (royalty > 0) {
            (bool okR, ) = royaltyReceiver.call{value: royalty}("");
            require(okR, "royalty payment failed");
        }
        (bool okS, ) = l.seller.call{value: l.price - royalty}("");
        require(okS, "seller payment failed");
        emit Sale(tokenId, msg.sender, l.seller, l.price, royalty);
    }

    function getListing(uint256 tokenId)
        external
        view
        returns (address seller, uint256 price)
    {
        ListingData memory l = _listings[tokenId];
        return (l.seller, l.price);
    }

    function listedCount() external view returns (uint256) {
        return _listedIds.length;
    }

    function listedIdAt(uint256 index) external view returns (uint256) {
        return _listedIds[index];
    }

    function _remove(uint256 tokenId) internal {
        uint256 pos = _listedPos[tokenId];
        if (pos == 0) return;
        uint256 idx = pos - 1;
        uint256 last = _listedIds[_listedIds.length - 1];
        _listedIds[idx] = last;
        _listedPos[last] = pos;
        _listedIds.pop();
        delete _listedPos[tokenId];
        delete _listings[tokenId];
    }
}
