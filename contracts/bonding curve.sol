// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interface/IERC20.sol";
import "../interface/IPancakeRouter02.sol";
import "../contracts/Ownable.sol";
import "../abstract/ReentrancyGuard.sol";
import "../lib/SafeERC20.sol";
import "../interface/IFactoryContract.sol";

// Interface for PancakeSwap Factory to get pair address
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
    uint256 public virtualTokenLp; // 1073 * (10 ** 6) amounts
    uint256 public virtualEthLp;
    uint256 public realTokenLp = 2 * (10 ** 26);
    uint256 public realEthLp;
    uint256 public total = 10 ** 27; // 10 ** 9
    uint256 public k;
    uint256 public finalMarketCap;
    uint256 public featuredTime;
    bool public lpCreated;
    uint256 public startTimestamp;
    uint8 public maxBuy;
    uint256 public accumulatedCreatorReward = 0;

    // Fun Information
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

    FactoryContract public factoryContract;

    // Fee distribution: 50% protocol, 40% creator, 10% ecosystem
    uint16 public constant PROTOCOL_FEE_BPS = 5000; // 50%
    uint16 public constant CREATOR_FEE_BPS = 4000; // 40%
    uint16 public constant ECOSYSTEM_FEE_BPS = 1000; // 10%

    // Ecosystem fee sent to this address on buy/sell (settable by owner)
    address public ecosystemFeeRecipient;

    // Protocol fee sent to this address on buy/sell (settable by owner)
    address public protocolFeeAddress;

    // Fee recipient set at launch: receives creator fee on buy/sell and after migration (DEX). When set, overrides creator/privacy per-tx for fee destination.
    address public feeRecipient;

    // Reward pools (accumulated fees)
    uint256 public creatorRewardPool; // Pool for creator rewards (accumulated from fees)
    uint256 public distributeToHolderPool; // Pool for Flaze token holders (accumulated from fees)

    // Track total fundraising for migration reward calculation
    uint256 public totalFundraising;

    // Token holder tracking for distribution
    address[] public tokenHolders;
    mapping(address => bool) public isHolder;
    mapping(address => bool) public excludedFromDistribution;
    uint256 public minBalanceForDistribution = 1000 * (10 ** 18); // Minimum balance to receive distribution
    uint256 public minDistributionAmount = 0.001 ether; // Minimum amount per holder to avoid dust (0.001 BNB)
    uint256 public gasFeeReserveBps = 200; // 2% of distribution reserved for gas fees
    uint256 public maxHoldersPerDistribution = 200; // Maximum holders to process per distribution call

    bool private initialized;

    receive() external payable {}

    // Empty constructor for clone pattern
    constructor() {
        initialized = true; // Prevent implementation from being initialized
    }

    /**
     * @dev Initialize function for clones (replaces constructor)
     */
    function initialize(
        address wallet,
        string[] memory tokenDatas,
        // uint8 maxBuyAmount,
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
        tokenStartPrice =
            (_otherDatas.virtualEthLp * 10 ** 12) /
            _otherDatas.virtualTokenLp;
        finalMarketCap = _otherDatas.marketCap;
        router = _addresses.dexRouter;
        _transferOwnership(wallet);
        token = _addresses.coinAddr;
        // maxBuy = maxBuyAmount;
        total = 10 ** 27;
        realTokenLp = 2 * (10 ** 26);
        name = tokenDatas[0];
        symbol = tokenDatas[1];
        info = tokenDatas[2];
        website = tokenDatas[3];
        twitter = tokenDatas[4];
        telegram = tokenDatas[5];
        discord = tokenDatas[6];
        factoryContract = FactoryContract(_addresses.factoryAddr);
        startTimestamp = block.timestamp;
        // Default fee recipients (factory protocolFeeAddress when set, else factory devWallet; owner can change via setEcosystemFeeRecipient / setProtocolFeeAddress)
        ecosystemFeeRecipient = 0x44547a1935da5f8Da5BE6Bde73C577879E34105C;
        protocolFeeAddress = _protocolFeeAddress != address(0) ? _protocolFeeAddress : FactoryContract(_addresses.factoryAddr).devWallet();
        tokenPriceDatas.push(
            TokenPriceData(
                startTimestamp,
                tokenStartPrice,
                currentTokenPrice(),
                _otherDatas.ethAmount
            )
        );
        volume = _otherDatas.ethAmount;

        // Exclude certain addresses from distribution
        excludedFromDistribution[address(this)] = true;
        excludedFromDistribution[address(0)] = true;
        excludedFromDistribution[address(0xdead)] = true;
        
        // Note: Token fee address and creator will be set after ownership transfer
        // via setupTokenFees() function
    }
    
    /**
     * @dev Setup token fee addresses (callable after token ownership is transferred)
     * This should be called after the factory transfers token ownership to this contract
     * Can be called by owner or factory contract
     */
    function setupTokenFees() external {
        require(
            owner() == msg.sender || 
            msg.sender == address(factoryContract) || 
            msg.sender == address(this), 
            "Unauthorized"
        );
        address tokenFeeAddr = protocolFeeAddress != address(0) ? protocolFeeAddress : FactoryContract(factoryContract).devWallet();
        _setTokenFeeAddress(tokenFeeAddr);
        _setTokenCreator(feeRecipient != address(0) ? feeRecipient : creator);
    }
    
    /**
     * @dev Internal function to set fee address on token contract
     */
    function _setTokenFeeAddress(address _feeAddress) internal {
        // Call setFeeAddress on token contract using low-level call
        (bool success, ) = token.call(
            abi.encodeWithSignature("setFeeAddress(address)", _feeAddress)
        );
        require(success, "Failed to set token fee address");
    }
    
    /**
     * @dev Internal function to set creator address on token contract
     */
    function _setTokenCreator(address _creator) internal {
        // Call setCreator on token contract using low-level call
        (bool success, ) = token.call(
            abi.encodeWithSignature("setCreator(address)", _creator)
        );
        require(success, "Failed to set token creator address");
    }

    modifier onlyLive() {
        require(lpCreated == false);
        _;
    }

    /**
     * @dev Buy tokens from bonding curve
     * @param _ref Referral address
     * @param minTokensOut Minimum tokens the buyer expects (slippage protection)
     */
    function buyToken(address _ref, uint256 minTokensOut) external payable onlyLive nonReentrant {
        uint256 openPrice = currentTokenPrice();
        uint8 mainFee = FactoryContract(factoryContract).mainFee();
        uint256 amounts = tokenAmount(msg.value);
        // Slippage check: revert if output is less than user expectation
        require(amounts >= minTokensOut, "Slippage: insufficient tokens out");
        uint256 feeAmount = (msg.value * mainFee) / 100;
        uint256 referFee;
        if (_ref != address(0) && _ref != msg.sender) {
            referFee = feeAmount / 2;
            feeAmount -= referFee;
            payable(_ref).transfer(referFee);
            if (refAmounts[_ref] == 0) {
                refCount++;
                refAddresses.push(_ref);
            }
            refAmounts[_ref] += referFee;
            totalRefAmounts += referFee;
        }

        // Split fee: 50% protocol, 40% creator, 10% ecosystem
        uint256 protocolFee = (feeAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 creatorFee = (feeAmount * CREATOR_FEE_BPS) / 10000;
        uint256 ecosystemFee = feeAmount - protocolFee - creatorFee; // Remaining 10%

        // Send protocol fee to protocolFeeAddress
        if (protocolFeeAddress != address(0) && protocolFee > 0) {
            payable(protocolFeeAddress).transfer(protocolFee);
        }

        // Creator fee: feeRecipient (launch-set) or creator
        if (feeRecipient != address(0) && creatorFee > 0) {
            payable(feeRecipient).transfer(creatorFee);
        } else if (creatorFee > 0) {
            payable(creator).transfer(creatorFee);
        }

        accumulatedCreatorReward += creatorFee;
        // Send ecosystem fee to ecosystemFeeRecipient
        if (ecosystemFeeRecipient != address(0) && ecosystemFee > 0) {
            payable(ecosystemFeeRecipient).transfer(ecosystemFee);
        }

        uint256 sendingAmount = msg.value - feeAmount - referFee;
        totalFundraising += sendingAmount; // Track fundraising for migration reward

        // uint256 tokenBalance = IERC20(token).balanceOf(msg.sender);
        // require(
        //     amounts + tokenBalance < (total * maxBuy) / 100,
        //     "Exceed max wallet amount"
        // );
        virtualTokenLp -= amounts;
        virtualEthLp += sendingAmount;
        realEthLp += sendingAmount;
        volume += sendingAmount;
        IERC20(token).transfer(msg.sender, amounts);

        tokenPriceDatas.push(
            TokenPriceData(
                block.timestamp,
                openPrice,
                currentTokenPrice(),
                sendingAmount
            )
        );
        uint256 currentMarketCap = (tokenPrice() * total) / (10 ** 12);
        if (finalMarketCap < currentMarketCap) {
            finalize();
        }
        if (contributorSet[msg.sender][address(this)] == false) {
            FactoryContract(factoryContract).updateContributors(
                msg.sender,
                address(this)
            );
            contributorSet[msg.sender][address(this)] = true;
        }
    }

    /**
     * @dev Sell tokens back to bonding curve
     * @param _amount Token amount to sell
     * @param _ref Referral address
     * @param minEthOut Minimum ETH the seller expects (slippage protection)
     */
    function sellToken(
        uint256 _amount,
        address _ref,
        uint256 minEthOut
    ) external onlyLive nonReentrant {
        uint256 openPrice = currentTokenPrice();
        // require(_amount < (total * maxBuy) / 100, "Exceed max wallet amount");
        uint8 mainFee = FactoryContract(factoryContract).mainFee();
        uint256 ethOutAmount = ethAmount(_amount);
        uint256 feeAmount = (ethOutAmount * mainFee) / 100;
        uint256 referFee;
        if (_ref != address(0) && _ref != msg.sender) {
            referFee = feeAmount / 2;
            feeAmount -= referFee;
            payable(_ref).transfer(referFee);
            if (refAmounts[_ref] == 0) {
                refCount++;
                refAddresses.push(_ref);
            }
            refAmounts[_ref] += referFee;
            totalRefAmounts += referFee;
        }
        // Split fee: 50% protocol, 40% creator, 10% ecosystem
        uint256 protocolFee = (feeAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 creatorFee = (feeAmount * CREATOR_FEE_BPS) / 10000;
        uint256 ecosystemFee = feeAmount - protocolFee - creatorFee; // Remaining 10%

        // Send protocol fee to protocolFeeAddress
        if (protocolFeeAddress != address(0) && protocolFee > 0) {
            payable(protocolFeeAddress).transfer(protocolFee);
        }

        // Creator fee: feeRecipient (launch-set) or creator
        if (feeRecipient != address(0) && creatorFee > 0) {
            payable(feeRecipient).transfer(creatorFee);
        } else if (creatorFee > 0) {
            payable(creator).transfer(creatorFee);
        }

        accumulatedCreatorReward += creatorFee;
        // Send ecosystem fee to ecosystemFeeRecipient
        if (ecosystemFeeRecipient != address(0) && ecosystemFee > 0) {
            payable(ecosystemFeeRecipient).transfer(ecosystemFee);
        }

        uint256 sendingAmount = ethOutAmount - feeAmount - referFee;

        if (sendingAmount > address(this).balance) {
            sendingAmount = address(this).balance;
        }
        // Slippage check: revert if output is less than user expectation
        require(sendingAmount >= minEthOut, "Slippage: insufficient ETH out");
        payable(msg.sender).transfer(sendingAmount);
        virtualTokenLp += _amount;
        virtualEthLp -= ethOutAmount;
        if (realEthLp > sendingAmount) {
            realEthLp -= sendingAmount;
        } else {
            realEthLp = 0;
        }
        volume += sendingAmount;
        IERC20(token).transferFrom(msg.sender, address(this), _amount);
        tokenPriceDatas.push(
            TokenPriceData(
                block.timestamp,
                openPrice,
                currentTokenPrice(),
                sendingAmount
            )
        );
    }

    function tokenAmount(uint256 _ethAmount) internal view returns (uint256) {
        uint256 newEthAmount = virtualEthLp + _ethAmount;
        uint256 newTokenAmount = k / newEthAmount;
        uint256 tokenAmounts = virtualTokenLp - newTokenAmount;
        return tokenAmounts;
    }

    function ethAmount(uint256 _tokenAmount) internal view returns (uint256) {
        uint256 newTokenAmount = virtualTokenLp + _tokenAmount;
        uint256 newEthAmount = k / newTokenAmount;
        uint256 ethAmounts;
        if (virtualEthLp >= newEthAmount) {
            ethAmounts = virtualEthLp - newEthAmount;
        } else {
            ethAmounts = 0;
        }
        return ethAmounts;
    }

    function tokenPrice() public view returns (uint256) {
        return (realEthLp * (10 ** 12)) / realTokenLp;
    }

    function currentTokenPrice() public view returns (uint256) {
        return ((virtualEthLp) * (10 ** 12)) / virtualTokenLp;
    }

    function ethOrTokenAmount(
        uint256 _amount,
        uint8 _id
    ) external view returns (uint256) {
        if (_id == 0) {
            return ethAmount(_amount);
        } else {
            return tokenAmount(_amount);
        }
    }

    function finalize() internal {
        lpCreated = true;
        IERC20(token).safeApprove(router, realTokenLp);
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance < realTokenLp) {
            realTokenLp = tokenBalance;
        } else {
            uint256 remainTokens = tokenBalance - realTokenLp;
            IERC20(token).transfer(address(0xdead), remainTokens);
        }

        // Calculate migration rewards: 1% of total fundraising to creator, rest to DEX
        // Exclude creatorRewardPool from contract balance (creator fees are claimable separately)
        uint256 contractBalance = address(this).balance;
        
        // Reserve creatorRewardPool for creator to claim later (exclude from migration)
        uint256 availableBalance;
        if (contractBalance >= creatorRewardPool) {
            availableBalance = contractBalance - creatorRewardPool;
        } else {
            // Edge case: contract balance is less than creatorRewardPool (shouldn't happen normally)
            availableBalance = 0;
        }
        
        uint256 creatorMigrationReward = (totalFundraising * 100) / 10000; // 1% of total fundraising

        // Ensure creator reward doesn't exceed available balance (excluding creatorRewardPool)
        if (creatorMigrationReward > availableBalance) {
            creatorMigrationReward = availableBalance;
        }

        uint256 dexMigrationAmount = availableBalance - creatorMigrationReward;

        // Give 1% of total fundraising to creator as reward
        if (creatorMigrationReward > 0 && owner() != address(0)) {
            payable(owner()).transfer(creatorMigrationReward);
        }

        // Rest goes to DEX migration
        require(
            dexMigrationAmount > 0,
            "Insufficient balance for DEX migration"
        );
        IPancakeRouter02(router).addLiquidityETH{value: dexMigrationAmount}(
            token,
            realTokenLp,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0xdead),
            block.timestamp + 400
        );
        
        // Set token's creator for DEX fees when feeRecipient is set at launch
        if (feeRecipient != address(0)) {
            _setTokenCreator(feeRecipient);
        }
        // Setup DEX pair address in token contract for fee collection
        // Must be done before renouncing ownership (addDexPair requires owner)
        _setupDexPair();
        
        // Renounce ownership after setting up DEX pair
        Ownable(token).renounceOwnership();
        
        // Note: creatorRewardPool remains in contract and can be claimed by creator via creatorclaim()
    }
    
    /**
     * @dev Setup DEX pair address in token contract after migration
     * This enables fee collection on DEX trades
     */
    function _setupDexPair() internal {
        // Get factory address from router
        address factoryAddress = IPancakeRouter02(router).factory();
        IPancakeFactory factory = IPancakeFactory(factoryAddress);
        
        // Get WETH address from router
        address wethAddress = IPancakeRouter02(router).WETH();
        
        // Get the pair address (token/WETH pair)
        address pairAddress = factory.getPair(token, wethAddress);
        
        require(pairAddress != address(0), "Pair not found");
        
        // Set router and factory addresses in token contract
        (bool success1, ) = token.call(
            abi.encodeWithSignature("setPancakeSwapAddresses(address,address)", router, factoryAddress)
        );
        require(success1, "Failed to set PancakeSwap addresses");
        
        // Add pair address to isDexPair mapping
        (bool success2, ) = token.call(
            abi.encodeWithSignature("addDexPair(address)", pairAddress)
        );
        require(success2, "Failed to add DEX pair");
    }

    function emergencyWithdraw() external {
        address feeAddress = FactoryContract(factoryContract).devWallet();
        require(feeAddress == msg.sender);
        payable(feeAddress).transfer(address(this).balance);
    }

    function updateFinalmarketcap(uint256 _marketcap) external {
        address devAddress = FactoryContract(factoryContract).devWallet();
        require(devAddress == msg.sender);
        finalMarketCap = _marketcap;
    }

    /**
     * @dev Set address that receives the ecosystem fee (10% of trading fees) on buy/sell.
     */
    function setEcosystemFeeRecipient(address _recipient) external onlyOwner {
        ecosystemFeeRecipient = _recipient;
    }

    /**
     * @dev Set address that receives the protocol fee (50% of trading fees) on buy/sell.
     */
    function setProtocolFeeAddress(address _address) external onlyOwner {
        protocolFeeAddress = _address;
    }

    function getTrending() external view returns (uint256) {
        uint256 rate;
        if (!lpCreated) {
            rate = virtualEthLp / (block.timestamp - startTimestamp);
        } else {
            rate = 0;
        }
        return rate;
    }

    function getRisingPercent() external view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 time24HoursAgo = currentTime - 24 hours;
        uint256 len = tokenPriceDatas.length;

        TokenPriceData memory firstPriceData24HoursAgo;
        bool found = false;

        // Find the first data with time smaller than 24 hours ago
        for (uint256 i = len; i > 0; i--) {
            TokenPriceData memory data = tokenPriceDatas[i - 1];
            if (data.time < time24HoursAgo) {
                firstPriceData24HoursAgo = data;
                found = true;
                break;
            }
        }

        uint256 lastClose = tokenPriceDatas[len - 1].close;

        uint256 risingPercent;

        if (found) {
            // Check for underflow before calculation
            if (lastClose >= firstPriceData24HoursAgo.close) {
                risingPercent =
                    ((lastClose - firstPriceData24HoursAgo.close) * 10000) /
                    firstPriceData24HoursAgo.close;
            } else {
                risingPercent = 0; // Return 0 if there's an underflow
            }
        } else {
            uint256 firstClose = tokenPriceDatas[0].close;
            // Check for underflow before calculation
            if (lastClose >= firstClose) {
                risingPercent = ((lastClose - firstClose) * 10000) / firstClose;
            } else {
                risingPercent = 0; // Return 0 if there's an underflow
            }
        }

        return risingPercent;
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
        string[7] memory strings = [
            name,
            symbol,
            website,
            twitter,
            telegram,
            discord,
            info
        ];
        address[4] memory addresses = [address(this), token, owner(), router];
        return (
            (tokenDatas),
            (strings),
            (addresses),
            (refAddresses),
            lpCreated,
            featuredTime
        );
    }

    function getAllPrices() external view returns (TokenPriceData[] memory) {
        return ((tokenPriceDatas));
    }

    /**
     * @dev Creator can claim their accumulated rewards from the pool
     * Transfers all accumulated creator fees to creator's wallet
     */
    function creatorclaim() external nonReentrant {
        require(msg.sender == creator, "Only creator can claim");
        require(creatorRewardPool > 0, "No rewards to claim");
        uint256 amount = creatorRewardPool;
        creatorRewardPool = 0;
        payable(creator).transfer(amount);
    }

    /**
     * @dev Distribute BNB from ecosystem pool to Flaze token holders proportionally
     * @param holders Array of holder addresses to distribute to
     * @param holdingAmounts Array of token holding amounts for each holder (used for proportional calculation)
     * Distribution is calculated as: (holderAmount / totalHoldingAmount) * distributeToHolderPool
     */
    function DistributeToFlazer(
        address[] calldata holders,
        uint256[] calldata holdingAmounts
    ) external nonReentrant {
        require(distributeToHolderPool > 0, "No funds to distribute");
        require(
            holders.length == holdingAmounts.length,
            "Arrays length mismatch"
        );
        require(holders.length > 0, "Empty arrays");

        // Calculate total holding amount for proportional distribution
        uint256 totalHoldingAmount = 0;
        for (uint256 i = 0; i < holdingAmounts.length; i++) {
            totalHoldingAmount += holdingAmounts[i];
        }
        require(
            totalHoldingAmount > 0,
            "Total holding amount must be greater than zero"
        );

        // Get the pool amount to distribute
        uint256 poolToDistribute = distributeToHolderPool;
        uint256 totalDistributed = 0;

        // Distribute proportionally to each holder based on their holding amount
        for (uint256 i = 0; i < holders.length; i++) {
            if (
                holders[i] != address(0) &&
                holdingAmounts[i] > 0 &&
                !excludedFromDistribution[holders[i]]
            ) {
                // Calculate proportional share: (holdingAmount / totalHoldingAmount) * poolToDistribute
                uint256 share = (poolToDistribute * holdingAmounts[i]) /
                    totalHoldingAmount;

                if (share > 0) {
                    payable(holders[i]).transfer(share);
                    totalDistributed += share;
                }
            }
        }

        // Update pool balance (subtract what was actually distributed)
        distributeToHolderPool -= totalDistributed;
    }

    /**
     * @dev Set minimum balance required to receive distribution
     */
    function setMinBalanceForDistribution(
        uint256 _minBalance
    ) external onlyOwner {
        minBalanceForDistribution = _minBalance;
    }

    /**
     * @dev Set minimum distribution amount per holder (to avoid dust)
     */
    function setMinDistributionAmount(uint256 _minAmount) external onlyOwner {
        minDistributionAmount = _minAmount;
    }

    /**
     * @dev Set gas fee reserve percentage (in basis points)
     */
    function setGasFeeReserveBps(uint16 _gasFeeReserveBps) external onlyOwner {
        require(_gasFeeReserveBps <= 1000, "Gas fee reserve cannot exceed 10%");
        gasFeeReserveBps = _gasFeeReserveBps;
    }

    /**
     * @dev Set maximum holders to process per distribution call
     */
    function setMaxHoldersPerDistribution(
        uint256 _maxHolders
    ) external onlyOwner {
        require(_maxHolders > 0 && _maxHolders <= 500, "Invalid max holders");
        maxHoldersPerDistribution = _maxHolders;
    }

    /**
     * @dev Get pool balances and distribution info
     */
    function getPoolInfo()
        external
        view
        returns (
            uint256 _creatorRewardPool,
            uint256 _distributeToHolderPool,
            uint256 _eligibleHoldersCount,
            uint256 _estimatedGasFeeReserve,
            uint256 _netDistributionAmount
        )
    {
        _creatorRewardPool = creatorRewardPool;
        _distributeToHolderPool = distributeToHolderPool;

        // Calculate gas fee reserve and net distribution
        _estimatedGasFeeReserve =
            (distributeToHolderPool * gasFeeReserveBps) /
            10000;
        _netDistributionAmount =
            distributeToHolderPool -
            _estimatedGasFeeReserve;

        // Count eligible holders
        for (uint256 i = 0; i < tokenHolders.length; i++) {
            address holder = tokenHolders[i];
            if (!excludedFromDistribution[holder]) {
                uint256 balance = IERC20(token).balanceOf(holder);
                if (balance >= minBalanceForDistribution) {
                    _eligibleHoldersCount++;
                }
            }
        }
    }

    /**
     * @dev Get distribution status for batch processing
     * @return totalEligibleHolders Total number of eligible holders
     * @return estimatedBatches Number of batches needed
     * @return canDistribute Whether distribution can be triggered
     */
    function getDistributionStatus()
        external
        view
        returns (
            uint256 totalEligibleHolders,
            uint256 estimatedBatches,
            bool canDistribute
        )
    {
        // Count eligible holders
        for (uint256 i = 0; i < tokenHolders.length; i++) {
            address holder = tokenHolders[i];
            if (!excludedFromDistribution[holder]) {
                uint256 balance = IERC20(token).balanceOf(holder);
                if (balance >= minBalanceForDistribution) {
                    totalEligibleHolders++;
                }
            }
        }

        if (totalEligibleHolders > 0 && maxHoldersPerDistribution > 0) {
            estimatedBatches =
                (totalEligibleHolders + maxHoldersPerDistribution - 1) /
                maxHoldersPerDistribution;
        }

        canDistribute = distributeToHolderPool > 0 && totalEligibleHolders > 0;
    }

    /**
     * @dev Get list of token holders
     */
    function getTokenHolders() external view returns (address[] memory) {
        return tokenHolders;
    }
}
