// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import "hardhat/console.sol";

/**
 * Icaaport provide 2 methods you can use to sell your NFTs.
 * You can sell your NFT for a fixed price and allow buyers to purchase it outright,
 * or you can list it for timed auction.
 */
contract Icaaport {
    // An event when an auction is created
    event AuctionCreated(address token, uint256 tokenId, uint256 startTime, uint256 endTime);

    event AuctionCancel(address token, uint256 tokenId);

    event BidProposed(address token, uint256 tokenId, uint256 amount, address bidder);

    event FixedPriceSet(address token, uint256 tokenId, uint256 fixedPrice);

    event TokenOnSold(address token, uint256 tokenId, uint256 amount, address collector);

    event BidWithdrawn(address token, uint256 tokenId);

    struct Collection {
        // erc721 token address for this collection.
        address token;
        // address to receive creator earnings.
        address payable creator;
        // in `%` format,e.g. 10 means 10%
        uint256 creatorEarningPercentage;
    }

    /**
     * list item may contain the fix price sale or auction state or both set.
     */
    struct ListItem {
        uint256 fixedPrice;
        uint256 auctionPrice;
        uint256 auctionStartTime;
        uint256 auctionEndTime;
        address bidder;
        // if true means fixed-price sale.
        bool onSale;
        // if true means in timed auction.
        bool inAuction;
    }

    // The maxium time period an auction can open for
    uint256 public maximumAuctionPeriod = 7 days;
    // The maxium time before the auction go live
    uint256 public maximumAuctionPreparingTime = 3 days;
    address public platform;

    uint256 serviceFeePercentage;
    // the minimum % increase for new bids coming
    uint256 public minBidIncreasePercent;

    mapping(address => Collection) collections;
    // token addr => (tokenId => item)
    mapping(address => mapping(uint256 => ListItem)) listingItems;

    modifier onlyPlatform() {
        require(msg.sender == platform);
        _;
    }
    constructor() {
        platform = msg.sender;
        minBidIncreasePercent = 1;
        serviceFeePercentage = 0;
    }

    function addNewCollection(
        address _token,
        address _creator,
        uint256 _creatorEarning
    ) external onlyPlatform {
        require(!collectionExist(_token), "collection already list in icaa");
        collections[_token] = Collection(_token, payable(_creator), _creatorEarning);
    }

    function openTimedAuction(
        address _token,
        uint256 _tokenId,
        uint256 _prepareTime,
        uint256 _auctionTime,
        uint256 _auctionPrice
    ) external {
        require(collectionExist(_token), "collection not on our platform");
        require(isApprovedOrOwner(msg.sender, _token, _tokenId), "Not the owner or approver!");
        ListItem storage item = listingItems[_token][_tokenId];

        require(!item.inAuction, "Item in auction now");
        require(_prepareTime <= maximumAuctionPreparingTime, "Exceed max preparing time");
        require(_auctionTime <= maximumAuctionPeriod, "Exceed max auction time!");

        item.auctionStartTime = block.timestamp + _prepareTime;
        item.auctionEndTime = item.auctionStartTime + _auctionTime;
        item.auctionPrice = _auctionPrice;
        emit AuctionCreated(_token, _tokenId, item.auctionStartTime, item.auctionEndTime);
    }

    // Allow the owner to cancel the auction before it goes live
    function cancelAuction(address _token, uint256 _tokenId) external {
        require(isApprovedOrOwner(msg.sender, _token, _tokenId), "Not the owner!");
        ListItem storage item = listingItems[_token][_tokenId];
        require(block.timestamp <= item.auctionStartTime, "auction has started");
        item.inAuction = false;
        item.auctionStartTime = 0;
        item.auctionEndTime = 0;
        emit AuctionCancel(_token, _tokenId);
    }

    function bid(address _token, uint256 _tokenId) external payable {
        ListItem storage item = listingItems[_token][_tokenId];
        require(msg.value >= item.auctionPrice && msg.value > 0, "Invalid value amount");
        // check the auction expiring time
        require(block.timestamp >= item.auctionStartTime, "Auction hasn't start");
        require(block.timestamp <= item.auctionEndTime, "Auction expiered");
        // owner/ apporver is not allowed to bid on their own tokens
        require(!isApprovedOrOwner(msg.sender, _token, _tokenId));
        if (pendingBidExist(_token, _tokenId)) {
            require(
                msg.value >= (item.auctionPrice * (100 + minBidIncreasePercent)) / 100,
                "Bid should higher than the previous bid in exactly %"
            );
            safeFundsTransfer(item.bidder, item.auctionPrice);
        }
        item.bidder = msg.sender;
        item.auctionPrice = msg.value;
        // Emit event for the bid proposal
        emit BidProposed(_token, _tokenId, msg.value, msg.sender);
    }

    // allows an address with a pending bid to withdraw it
    function withdrawBid(address _token, uint256 _tokenId) external {
        // check that there is a bid from the sender to withdraw (also allows platform address to withdraw a bid on someone's behalf)
        require(msg.sender == platform);
        require(pendingBidExist(_token, _tokenId));
        ListItem storage item = listingItems[_token][_tokenId];
        safeFundsTransfer(item.bidder, item.auctionPrice);
        item.bidder = address(0);
        item.auctionPrice = 0;
        item.inAuction = false;
        emit BidWithdrawn(_token, _tokenId);
    }

    // Allow anyone to accept the highest bid for a token
    function acceptBid(address _token, uint256 _tokenId) external {
        // can only be accepted when auction ended
        require(block.timestamp >= listingItems[_token][_tokenId].auctionEndTime);
        // check if there's a bid to accept
        require(pendingBidExist(_token, _tokenId));
        executeSale(
            _token,
            _tokenId,
            listingItems[_token][_tokenId].auctionPrice,
            listingItems[_token][_tokenId].bidder
        );
    }

    /**
     * @param _fixedPrice: = 0 if cancel the listing.
     */
    function setFixPriceSale(
        address _token,
        uint256 _tokenId,
        uint256 _fixedPrice
    ) external {
        require(collectionExist(_token), "collections not list");
        require(isApprovedOrOwner(msg.sender, _token, _tokenId), "Not the owner or approver!");
        listingItems[_token][_tokenId].fixedPrice = _fixedPrice;
        emit FixedPriceSet(_token, _tokenId, _fixedPrice);
    }

    /**
     * buy the item in fixed price, this will cancel the exist auction.
     */
    function purchaseByFixedPrice(address _token, uint256 _tokenId) external payable {
        // don't let owners/approved buy their own tokens
        require(!isApprovedOrOwner(msg.sender, _token, _tokenId), "owner is not allow to buy the token");
        ListItem storage item = listingItems[_token][_tokenId];
        // check that there is a buy price
        require(item.fixedPrice > 0, "Not sale for fixed price");
        // check that the buyer sent exact amount to purchase
        require(msg.value == item.fixedPrice, "value is invalid");
        // Return all highest bidder's money
        if (pendingBidExist(_token, _tokenId)) {
            safeFundsTransfer(item.bidder, item.auctionPrice);
        }
        executeSale(_token, _tokenId, item.fixedPrice, msg.sender);
    }

    // ****************************** Internal Function *************************
    function isApprovedOrOwner(
        address _spender,
        address _token,
        uint256 _tokenId
    ) internal view returns (bool) {
        address owner = IERC721(_token).ownerOf(_tokenId);
        return (_spender == owner ||
            IERC721(_token).isApprovedForAll(owner, _spender) ||
            IERC721(_token).getApproved(_tokenId) == _spender);
    }

    // transfer the amount of asset and revert if fail
    function safeFundsTransfer(address recipient, uint256 amount) internal {
        payable(recipient).transfer(amount);
    }

    /**
     * executeSale will:
     * 1. distribute fund to seller, platform(service fee), creator(creator fee).
     * 2. transfer the NFT to the new collector
     * Note: This will clear all the bid and listing
     * This will transfer the ERC721 token and distribute the sale amount to seller, platform and creator.
     * and will transfer the NFT to the new collector.
     */
    function executeSale(
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        address _collector
    ) internal {
        uint256 marketplaceFee = (_amount * serviceFeePercentage) / 100;
        uint256 creatorFee = (_amount * collections[_token].creatorEarningPercentage) / 100;
        safeFundsTransfer(platform, marketplaceFee);
        safeFundsTransfer(collections[_token].creator, creatorFee);
        address owner = IERC721(_token).ownerOf(_tokenId);
        safeFundsTransfer(payable(owner), _amount - marketplaceFee - creatorFee);

        listingItems[_token][_tokenId] = ListItem(0, 0, 0, 0, address(0), false, false);
        IERC721(_token).transferFrom(owner, _collector, _tokenId);
        emit TokenOnSold(_token, _tokenId, _amount, _collector);
    }

    function pendingBidExist(address _token, uint256 _tokenId) internal view returns (bool) {
        return listingItems[_token][_tokenId].bidder != address(0);
    }

    function collectionExist(address _token) internal view returns (bool) {
        return collections[_token].token != address(0);
    }
}
