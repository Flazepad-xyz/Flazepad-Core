// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interface/IERC20.sol";
import "../interface/IPancakeRouter02.sol";
import "../contracts/Ownable.sol";
import "../abstract/ReentrancyGuard.sol";
import "../lib/SafeERC20.sol";
import "../interface/IFactoryContract.sol";

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function WETH() external pure returns (address);
}

struct PumpData {
    uint256 tokenAmount;
    uint256 ethAmount;
    uint256 virtualEthLp;
    uint256 virtualTokenLp;
    uint256 k;
    uint256 featuredTime;
    uint256 marketCap;
}

struct AddressData {
    address coinAddr;
    address factoryAddr;
    address dexRouter;
}

contract FlazeCoinCurves is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public token;
    address public router;
    address public creator;
    bool public useSocial;
    uint256 public tokenStartPrice;
    uint256 public virtualTokenLp;
    uint256 public virtualEthLp;
    uint256 public realTokenLp = 2 * (10 ** 26);
    uint256 public realEthLp;
    uint256 public total = 10 ** 27;
    uint256 public k;
    uint256 public finalMarketCap;
    uint256 public featuredTime;
    bool public lpCreated;
    uint256 public startTimestamp;
    uint8 public maxBuy;
    uint256 public accumulatedCreatorReward;

    string public name;
    string public info;
    string public symbol;
    string public website;
    string public twitter;
    string public telegram;
    string public discord;
    mapping(address => mapping(address => bool)) public contributorSet;

    struct TokenPriceData {
        uint256 time;
        uint256 open;
        uint256 close;
        uint256 amount;
    }
    TokenPriceData[] internal tokenPriceDatas;

    mapping(address => uint256) public refAmounts;
    uint16 public refCount;
    address[] public refAddresses;
    uint256 public totalRefAmounts;
    uint256 public volume;
    uint256 public totalFundraising;

    FactoryContract public factoryContract;

    uint16 public constant PROTOCOL_FEE_BPS = 5000;
    uint16 public constant CREATOR_FEE_BPS  = 4000;
    uint16 public constant ECOSYSTEM_FEE_BPS = 1000;

    address public ecosystemFeeRecipient;
    address public protocolFeeAddress;
    address public feeRecipient;

    bool private initialized;

    // --- Events (M-2) ---
    event TokenPurchased(address indexed buyer, uint256 ethIn, uint256 tokensOut, uint256 newPrice);
    event TokenSold(address indexed seller, uint256 tokensIn, uint256 ethOut, uint256 newPrice);
    event Finalized(uint256 dexEth, uint256 dexTokens);
    event EcosystemFeeRecipientUpdated(address indexed previous, address indexed next);
    event ProtocolFeeAddressUpdated(address indexed previous, address indexed next);
    event MarketCapUpdated(uint256 previous, uint256 next);

    receive() external payable {}

    constructor() {
        initialized = true;
    }

    function initialize(
        address wallet,
        string[] memory tokenDatas,
        uint8 maxBuyAmount,
        AddressData memory _addresses,
        PumpData memory _otherDatas,
        bool _useSocial,
        address _feeRecipient,
        address _protocolFeeAddress
    ) external {
        require(!initialized, "Already initialized");
        initialized = true;

        creator = wallet;
        useSocial = _useSocial;
        feeRecipient = _feeRecipient;
        virtualEthLp = _otherDatas.virtualEthLp + _otherDatas.ethAmount;
        virtualTokenLp = _otherDatas.virtualTokenLp - _otherDatas.tokenAmount;
        k = _otherDatas.k;
        featuredTime = _otherDatas.featuredTime;
        tokenStartPrice = (_otherDatas.virtualEthLp * 10 ** 12) / _otherDatas.virtualTokenLp;
        finalMarketCap = _otherDatas.marketCap;
        router = _addresses.dexRouter;
        _transferOwnership(wallet);
        token = _addresses.coinAddr;
        maxBuy = maxBuyAmount;
        total = 10 ** 27;
        realTokenLp = 2 * (10 ** 26);
        name     = tokenDatas[0];
        symbol   = tokenDatas[1];
        info     = tokenDatas[2];
        website  = tokenDatas[3];
        twitter  = tokenDatas[4];
        telegram = tokenDatas[5];
        discord  = tokenDatas[6];
        factoryContract = FactoryContract(_addresses.factoryAddr);
        startTimestamp = block.timestamp;
        ecosystemFeeRecipient = 0x44547a1935da5f8Da5BE6Bde73C577879E34105C;
        protocolFeeAddress = _protocolFeeAddress != address(0)
            ? _protocolFeeAddress
            : FactoryContract(_addresses.factoryAddr).devWallet();
        tokenPriceDatas.push(TokenPriceData(
            startTimestamp,
            tokenStartPrice,
            currentTokenPrice(),
            _otherDatas.ethAmount
        ));
        volume = _otherDatas.ethAmount;
    }

    function setupTokenFees() external {
        require(
            msg.sender == owner() ||
            msg.sender == address(factoryContract) ||
            msg.sender == address(this),
            "Unauthorized"
        );
        address tokenFeeAddr = protocolFeeAddress != address(0)
            ? protocolFeeAddress
            : FactoryContract(factoryContract).devWallet();
        _setTokenFeeAddress(tokenFeeAddr);
        _setTokenCreator(feeRecipient != address(0) ? feeRecipient : creator);
    }

    function _setTokenFeeAddress(address _feeAddress) internal {
        (bool success, ) = token.call(abi.encodeWithSignature("setFeeAddress(address)", _feeAddress));
        require(success, "Failed to set token fee address");
    }

    function _setTokenCreator(address _creator) internal {
        (bool success, ) = token.call(abi.encodeWithSignature("setCreator(address)", _creator));
        require(success, "Failed to set token creator address");
    }

    // --- Modifiers ---

    modifier onlyLive() {
        require(!lpCreated, "Bonding curve closed");
        _;
    }

    // H-1 / M-6: shared modifier for dev-only admin functions
    modifier onlyDev() {
        require(msg.sender == FactoryContract(factoryContract).devWallet(), "Not authorized");
        _;
    }

    // --- Core trading ---

    /**
     * @dev Buy tokens from bonding curve.
     * @param _ref      Referral address
     * @param minTokensOut Minimum tokens expected (slippage protection)
     */
    function buyToken(address _ref, uint256 minTokensOut) external payable onlyLive nonReentrant {
        uint256 openPrice = currentTokenPrice();
        uint8 mainFee = FactoryContract(factoryContract).mainFee();
        uint256 amounts = tokenAmount(msg.value);

        require(amounts >= minTokensOut, "Slippage: insufficient tokens out");
        require(
            amounts + IERC20(token).balanceOf(msg.sender) < (total * maxBuy) / 100,
            "Exceed max wallet amount"
        );

        uint256 feeAmount = (msg.value * mainFee) / 100;
        uint256 referFee;
        if (_ref != address(0) && _ref != msg.sender) {
            referFee = feeAmount / 2;
            feeAmount -= referFee;
        }

        uint256 protocolFee  = (feeAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 creatorFee   = (feeAmount * CREATOR_FEE_BPS)  / 10000;
        uint256 ecosystemFee = feeAmount - protocolFee - creatorFee;

        uint256 sendingAmount = msg.value - feeAmount - referFee;

        // --- Effects (C-1: state before interactions) ---
        virtualTokenLp -= amounts;
        virtualEthLp   += sendingAmount;
        realEthLp      += sendingAmount;
        volume         += sendingAmount;
        totalFundraising += sendingAmount;
        accumulatedCreatorReward += creatorFee;

        tokenPriceDatas.push(TokenPriceData(block.timestamp, openPrice, currentTokenPrice(), sendingAmount));

        // --- Interactions ---
        IERC20(token).safeTransfer(msg.sender, amounts);  // M-4: use safeTransfer

        if (referFee > 0) {
            (bool okRef,) = payable(_ref).call{value: referFee}("");
            require(okRef, "ETH transfer failed");
            if (refAmounts[_ref] == 0) { refCount++; refAddresses.push(_ref); }
            refAmounts[_ref] += referFee;
            totalRefAmounts  += referFee;
        }
        if (protocolFeeAddress != address(0) && protocolFee > 0) {
            (bool ok,) = payable(protocolFeeAddress).call{value: protocolFee}("");
            require(ok, "ETH transfer failed");
        }
        if (feeRecipient != address(0) && creatorFee > 0) {
            (bool ok,) = payable(feeRecipient).call{value: creatorFee}("");
            require(ok, "ETH transfer failed");
        } else if (creatorFee > 0) {
            (bool ok,) = payable(creator).call{value: creatorFee}("");
            require(ok, "ETH transfer failed");
        }
        if (ecosystemFeeRecipient != address(0) && ecosystemFee > 0) {
            (bool ok,) = payable(ecosystemFeeRecipient).call{value: ecosystemFee}("");
            require(ok, "ETH transfer failed");
        }

        emit TokenPurchased(msg.sender, sendingAmount, amounts, currentTokenPrice());

        uint256 currentMarketCap = (tokenPrice() * total) / (10 ** 12);
        if (finalMarketCap < currentMarketCap) {
            finalize();
        }
        if (!contributorSet[msg.sender][address(this)]) {
            FactoryContract(factoryContract).updateContributors(msg.sender, address(this));
            contributorSet[msg.sender][address(this)] = true;
        }
    }

    /**
     * @dev Sell tokens back to bonding curve.
     * @param _amount   Token amount to sell
     * @param _ref      Referral address
     * @param minEthOut Minimum ETH expected (slippage protection)
     */
    function sellToken(uint256 _amount, address _ref, uint256 minEthOut) external onlyLive nonReentrant {
        require(_amount > 0, "Amount must be greater than zero");
        require(_amount < (total * maxBuy) / 100, "Exceed max wallet amount");

        uint256 openPrice    = currentTokenPrice();
        uint8 mainFee        = FactoryContract(factoryContract).mainFee();
        uint256 ethOutAmount = ethAmount(_amount);
        uint256 feeAmount    = (ethOutAmount * mainFee) / 100;
        uint256 referFee;
        if (_ref != address(0) && _ref != msg.sender) {
            referFee  = feeAmount / 2;
            feeAmount -= referFee;
        }

        uint256 protocolFee  = (feeAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 creatorFee   = (feeAmount * CREATOR_FEE_BPS)  / 10000;
        uint256 ecosystemFee = feeAmount - protocolFee - creatorFee;

        uint256 sendingAmount = ethOutAmount - feeAmount - referFee;
        if (sendingAmount > address(this).balance) {
            sendingAmount = address(this).balance;
        }
        require(sendingAmount >= minEthOut, "Slippage: insufficient ETH out");

        // --- Effects (C-1: pull tokens and update state before sending ETH) ---
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

        virtualTokenLp += _amount;
        virtualEthLp   -= ethOutAmount;
        if (realEthLp > sendingAmount) {
            realEthLp -= sendingAmount;
        } else {
            realEthLp = 0;
        }
        volume += sendingAmount;
        accumulatedCreatorReward += creatorFee;

        tokenPriceDatas.push(TokenPriceData(block.timestamp, openPrice, currentTokenPrice(), sendingAmount));

        // --- Interactions ---
        (bool okSell,) = payable(msg.sender).call{value: sendingAmount}("");
        require(okSell, "ETH transfer failed");

        if (referFee > 0) {
            (bool ok,) = payable(_ref).call{value: referFee}("");
            require(ok, "ETH transfer failed");
            if (refAmounts[_ref] == 0) { refCount++; refAddresses.push(_ref); }
            refAmounts[_ref] += referFee;
            totalRefAmounts  += referFee;
        }
        if (protocolFeeAddress != address(0) && protocolFee > 0) {
            (bool ok,) = payable(protocolFeeAddress).call{value: protocolFee}("");
            require(ok, "ETH transfer failed");
        }
        if (feeRecipient != address(0) && creatorFee > 0) {
            (bool ok,) = payable(feeRecipient).call{value: creatorFee}("");
            require(ok, "ETH transfer failed");
        } else if (creatorFee > 0) {
            (bool ok,) = payable(creator).call{value: creatorFee}("");
            require(ok, "ETH transfer failed");
        }
        if (ecosystemFeeRecipient != address(0) && ecosystemFee > 0) {
            (bool ok,) = payable(ecosystemFeeRecipient).call{value: ecosystemFee}("");
            require(ok, "ETH transfer failed");
        }

        emit TokenSold(msg.sender, _amount, sendingAmount, currentTokenPrice());
    }

    // --- Internal math ---

    function tokenAmount(uint256 _ethAmount) internal view returns (uint256) {
        uint256 newEthAmount   = virtualEthLp + _ethAmount;
        uint256 newTokenAmount = k / newEthAmount;
        return virtualTokenLp - newTokenAmount;
    }

    function ethAmount(uint256 _tokenAmount) internal view returns (uint256) {
        uint256 newTokenAmount = virtualTokenLp + _tokenAmount;
        uint256 newEthAmount   = k / newTokenAmount;
        return virtualEthLp >= newEthAmount ? virtualEthLp - newEthAmount : 0;
    }

    function tokenPrice() public view returns (uint256) {
        return (realEthLp * (10 ** 12)) / realTokenLp;
    }

    function currentTokenPrice() public view returns (uint256) {
        return (virtualEthLp * (10 ** 12)) / virtualTokenLp;
    }

    function ethOrTokenAmount(uint256 _amount, uint8 _id) external view returns (uint256) {
        return _id == 0 ? ethAmount(_amount) : tokenAmount(_amount);
    }

    // --- Migration ---

    function finalize() internal {
        lpCreated = true;
        IERC20(token).safeApprove(router, realTokenLp);

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance < realTokenLp) {
            realTokenLp = tokenBalance;
        } else {
            IERC20(token).transfer(address(0xdead), tokenBalance - realTokenLp);
        }

        uint256 availableBalance     = address(this).balance;
        uint256 creatorMigrationReward = (totalFundraising * 100) / 10000; // 1%
        if (creatorMigrationReward > availableBalance) {
            creatorMigrationReward = availableBalance;
        }
        uint256 dexMigrationAmount = availableBalance - creatorMigrationReward;

        // C-2: guard against negligible liquidity addition
        require(dexMigrationAmount > 0, "Insufficient ETH for DEX migration");
        require(realTokenLp > 0,        "Insufficient tokens for DEX migration");

        if (creatorMigrationReward > 0 && owner() != address(0)) {
            (bool ok,) = payable(owner()).call{value: creatorMigrationReward}("");
            require(ok, "ETH transfer failed");
        }

        IPancakeRouter02(router).addLiquidityETH{value: dexMigrationAmount}(
            token,
            realTokenLp,
            (realTokenLp * 95) / 100,      // C-2: 5% slippage tolerance on tokens
            (dexMigrationAmount * 95) / 100, // C-2: 5% slippage tolerance on ETH
            address(0xdead),
            block.timestamp + 400
        );

        emit Finalized(dexMigrationAmount, realTokenLp);

        if (feeRecipient != address(0)) {
            _setTokenCreator(feeRecipient);
        }
        _setupDexPair();
        Ownable(token).renounceOwnership();
    }

    function _setupDexPair() internal {
        address factoryAddress = IPancakeRouter02(router).factory();
        address wethAddress    = IPancakeRouter02(router).WETH();
        address pairAddress    = IPancakeFactory(factoryAddress).getPair(token, wethAddress);
        require(pairAddress != address(0), "Pair not found");

        (bool ok1,) = token.call(abi.encodeWithSignature("setPancakeSwapAddresses(address,address)", router, factoryAddress));
        require(ok1, "Failed to set PancakeSwap addresses");

        (bool ok2,) = token.call(abi.encodeWithSignature("addDexPair(address)", pairAddress));
        require(ok2, "Failed to add DEX pair");
    }

    // --- Admin ---

    /**
     * @dev Emergency ETH withdrawal. H-1: restricted to post-migration only.
     */
    function emergencyWithdraw() external onlyDev {
        require(lpCreated, "Only callable after migration");
        address feeAddress = FactoryContract(factoryContract).devWallet();
        (bool ok,) = payable(feeAddress).call{value: address(this).balance}("");
        require(ok, "ETH transfer failed");
    }

    /**
     * @dev H-2: validate new market cap before accepting it.
     */
    function updateFinalmarketcap(uint256 _marketcap) external onlyDev {
        require(_marketcap > 0, "Market cap must be greater than zero");
        emit MarketCapUpdated(finalMarketCap, _marketcap);
        finalMarketCap = _marketcap;
    }

    /**
     * @dev M-5: zero address check added.
     */
    function setEcosystemFeeRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Zero address");
        emit EcosystemFeeRecipientUpdated(ecosystemFeeRecipient, _recipient);
        ecosystemFeeRecipient = _recipient;
    }

    /**
     * @dev M-5: zero address check added.
     */
    function setProtocolFeeAddress(address _address) external onlyOwner {
        require(_address != address(0), "Zero address");
        emit ProtocolFeeAddressUpdated(protocolFeeAddress, _address);
        protocolFeeAddress = _address;
    }

    // --- Views ---

    function getTrending() external view returns (uint256) {
        if (!lpCreated) {
            return virtualEthLp / (block.timestamp - startTimestamp);
        }
        return 0;
    }

    function getRisingPercent() external view returns (uint256) {
        uint256 len           = tokenPriceDatas.length;
        uint256 time24HoursAgo = block.timestamp - 24 hours;
        uint256 lastClose     = tokenPriceDatas[len - 1].close;

        for (uint256 i = len; i > 0; i--) {
            TokenPriceData memory data = tokenPriceDatas[i - 1];
            if (data.time < time24HoursAgo) {
                if (lastClose >= data.close) {
                    return ((lastClose - data.close) * 10000) / data.close;
                }
                return 0;
            }
        }

        uint256 firstClose = tokenPriceDatas[0].close;
        if (lastClose >= firstClose) {
            return ((lastClose - firstClose) * 10000) / firstClose;
        }
        return 0;
    }

    function getFunBasicInfo()
        external
        view
        returns (
            uint256[11] memory,
            string[7] memory,
            address[4] memory,
            address[] memory,
            bool,
            uint256
        )
    {
        uint256[11] memory tokenDatas = [
            total,
            startTimestamp,
            maxBuy,
            tokenStartPrice,
            virtualTokenLp,
            virtualEthLp,
            totalRefAmounts,
            uint256(refCount),
            currentTokenPrice(),
            volume,
            accumulatedCreatorReward
        ];
        string[7] memory strings = [name, symbol, website, twitter, telegram, discord, info];
        address[4] memory addresses = [address(this), token, owner(), router];
        return (tokenDatas, strings, addresses, refAddresses, lpCreated, featuredTime);
    }

    function getAllPrices() external view returns (TokenPriceData[] memory) {
        return tokenPriceDatas;
    }
}
