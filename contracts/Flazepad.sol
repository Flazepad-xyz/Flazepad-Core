// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interface/IERC20.sol";
import "./Ownable.sol";
import "../interface/IPancakePair.sol";
import "../lib/SafeERC20.sol";
import "../lib/Clones.sol";
import "./FlazeCoinCurves.sol";

interface ICoin {
    function initialize(address wallet, string[] memory tokenData, uint256 supply, uint8 decimals) external;
}

contract FlazeCoinFactory is Ownable {
    using SafeERC20 for IERC20;
    using Clones for address;
    
    address[] allFlazeCoinLaunchs;
    address payable public devWallet;
    /// When set (non-zero), used as protocol fee recipient in bonding curve and on token (DEX) for all new launches
    address public protocolFeeAddress;
    uint256 public feeAmount;
    uint256[4] public featuredAmounts;
    uint256[4] public featuredTime = [0, 604800, 1209600, 2592000];
    uint8 public mainFee = 1;  // default trade fee is 1%
    mapping(address => address[]) flazecoinLaunchLists;
    uint256 public virtualTokenLp = 1073 * (10 ** 24);  // 1073 * (10 ** 6) amounts
    uint256 public virtualEthLp;
    uint256 public marketCap;
    uint256 public useFeatureFee = 0.01 ether;
    mapping(address => address[]) public userContributors;
    mapping(address => bool) public flazecoinLaunchAddresses;
    
    // Implementation contracts for cloning
    address public coinImplementation;
    address public flazepadImplementation;

    constructor(
        address _feeAddress,
        uint256 _feeAmount,
        uint256[4] memory _featuredAmounts,
        uint256 _virtualEthLp,
        uint256 _marketCap,
        address _coinImplementation,
        address _flazepadImplementation
    ) {
        devWallet = payable(_feeAddress);
        feeAmount = _feeAmount;
        featuredAmounts = _featuredAmounts;
        virtualEthLp = _virtualEthLp;
        marketCap = _marketCap;
        coinImplementation = _coinImplementation;
        flazepadImplementation = _flazepadImplementation;
    }
    
    receive() external payable {
    }
    
    function createFlazeCoinLaunch(
        string [] memory tokenDatas, //name, symbol, description, website, twitter, telegram, discord
        // uint8 maxBuyAmount,
        address dexRouter,
        uint8 featureNumber,
        bool usePrivacy,
        bool useSocial,
        address feeRecipient
    ) external payable returns (address) {        
        // require(msg.value >= feeAmount + featuredAmounts[featureNumber], "Insufficient Amount");
        if (useSocial && usePrivacy) {
            require(msg.value >= feeAmount + featuredAmounts[featureNumber] + useFeatureFee + useFeatureFee, "Insufficient Amount");
            devWallet.transfer(useFeatureFee + useFeatureFee);
        } else if (useSocial && !usePrivacy) {
            require(msg.value >= feeAmount + featuredAmounts[featureNumber] + useFeatureFee, "Insufficient Amount");
            devWallet.transfer(useFeatureFee);
        } else if (!useSocial && usePrivacy) {
            require(msg.value >= feeAmount + featuredAmounts[featureNumber] + useFeatureFee, "Insufficient Amount");
            devWallet.transfer(useFeatureFee);
        } else if (!useSocial && !usePrivacy) {
            require(msg.value >= feeAmount + featuredAmounts[featureNumber], "Insufficient Amount");
        }
        devWallet.transfer(feeAmount + featuredAmounts[featureNumber]);  

        // Clone Coin implementation
        address coinAddr = coinImplementation.clone();
        ICoin(coinAddr).initialize(address(this), tokenDatas, 1000000000, 18);

        uint256 tokenBalance = IERC20(coinAddr).balanceOf(address(this));

        uint256 additionalEthLp;
        if (usePrivacy && useSocial) {
            additionalEthLp = msg.value - feeAmount - featuredAmounts[featureNumber] - useFeatureFee - useFeatureFee;
        } else if (usePrivacy && !useSocial) {
            additionalEthLp = msg.value - feeAmount - featuredAmounts[featureNumber] - useFeatureFee;
        } else if (!usePrivacy && useSocial) {
            additionalEthLp = msg.value - feeAmount - featuredAmounts[featureNumber] - useFeatureFee;
        } else if (!usePrivacy && !useSocial) {
            additionalEthLp = msg.value - feeAmount - featuredAmounts[featureNumber];
        }

        uint256 newEthLp = virtualEthLp + additionalEthLp;
        uint256 newTokenLp = virtualEthLp * virtualTokenLp / newEthLp;
        uint256 tokenAmount = virtualTokenLp - newTokenLp;

        uint256 k = virtualEthLp * virtualTokenLp;

        // require(maxBuyAmount == 1 || maxBuyAmount == 2);
        // require(tokenAmount <= tokenBalance * maxBuyAmount / 100);
        PumpData memory pumpData = PumpData(
            tokenAmount,
            // msg.value - feeAmount - featuredAmounts[featureNumber],
            additionalEthLp,
            virtualEthLp,
            virtualTokenLp,
            k,
            block.timestamp + featuredTime[featureNumber],
            marketCap
        );

        AddressData memory addressData = AddressData(
            coinAddr,
            address(this),
            dexRouter
        );

        // Clone FlazeCoinCurves implementation
        address flazecoinLaunchAddr = flazepadImplementation.clone();
        FlazeCoinCurves(payable(flazecoinLaunchAddr)).initialize(msg.sender, tokenDatas, /*maxBuyAmount,*/ addressData, pumpData, useSocial, feeRecipient, protocolFeeAddress);
        // payable(flazecoinLaunchAddr).transfer(msg.value - feeAmount - featuredAmounts[featureNumber]);
        payable(flazecoinLaunchAddr).transfer(additionalEthLp);

        // Transfer tokens to launch contract and creator before ownership transfer
        // Use SafeERC20 to ensure transfers succeed
        IERC20(coinAddr).safeTransfer(flazecoinLaunchAddr, tokenBalance - tokenAmount);
        
        // Transfer creator's tokens to feeRecipient (or creator if feeRecipient is zero) - must happen before ownership transfer
        if (tokenAmount > 0) {
            address recipient = feeRecipient != address(0) ? feeRecipient : msg.sender;
            IERC20(coinAddr).safeTransfer(recipient, tokenAmount);
        }
        
        // Transfer ownership to launch contract after token transfers
        Ownable(coinAddr).transferOwnership(flazecoinLaunchAddr);
        
        // Setup token fee addresses after ownership transfer
        FlazeCoinCurves(payable(flazecoinLaunchAddr)).setupTokenFees();
        
        allFlazeCoinLaunchs.push(flazecoinLaunchAddr);
        flazecoinLaunchLists[msg.sender].push(flazecoinLaunchAddr);
        flazecoinLaunchAddresses[flazecoinLaunchAddr] = true;
        return flazecoinLaunchAddr;
    }

    function updateDatas(uint256 _newFee, uint8 _mainFee, uint256 _marketCap, address payable _newDev, uint256[4] memory _featuredTime) external onlyOwner{
        feeAmount = _newFee;
        mainFee = _mainFee;
        marketCap = _marketCap;
        devWallet = _newDev;
        featuredTime = _featuredTime;
    }

    /**
     * @dev Set protocol fee address. Used as protocol fee recipient in bonding curve buy/sell and on token (DEX) after migration for all new launches.
     */
    function setProtocolFeeAddress(address _protocolFeeAddress) external onlyOwner {
        protocolFeeAddress = _protocolFeeAddress;
    }

    function updateContributors(address _user, address _flazecoinLaunch) external {
        require(flazecoinLaunchAddresses[msg.sender] == true);
        userContributors[_user].push(_flazecoinLaunch);
    }

    function getAllAddresses() external view returns(address [] memory){
        return((allFlazeCoinLaunchs));
    }

    function getUserContributorAddresses(address _user) external view returns(address [] memory){
        return((userContributors[_user]));
    }

    function funUserLists(address _user) external view returns (address [] memory){
        return (flazecoinLaunchLists[_user]);
    }

    function updateVirtualLiquidity(uint256 _ethLp, uint256 _tokenLp) external onlyOwner {
        virtualEthLp = _ethLp;
        virtualTokenLp = _tokenLp;
    }
    
    function updateImplementations(address _coinImpl, address _flazepadImpl) external onlyOwner {
        coinImplementation = _coinImpl;
        flazepadImplementation = _flazepadImpl;
    }
}
