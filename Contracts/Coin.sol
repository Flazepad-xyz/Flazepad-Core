// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../contracts/ERC20.sol";
import "../contracts/Ownable.sol";
import "../interface/IPancakePair.sol";

contract Coin is ERC20, Ownable {
    using SafeMath for uint256;
    string public _description;

    // Reserved for backward-compatible storage; transfer fee is disabled.
    address public creator;
    
    // Reserved for backward-compatible storage; transfer fee is disabled.
    address public feeAddress;
    
    // PancakeSwap router and factory addresses (BSC mainnet)
    address public pancakeSwapRouter;
    address public pancakeSwapFactory;
    
    // Mapping to track DEX pair addresses
    mapping(address => bool) public isDexPair;
    
    // Events
    event DexPairAdded(address indexed pair);
    event FeeAddressSet(address indexed feeAddress);
    
    bool private initialized;

    // Empty constructor for clone pattern
    constructor() {
        initialized = true; // Prevent implementation from being initialized
    }

    /**
     * @dev Initialize function for clones (replaces constructor)
     */
    function initialize(
        address wallet,
        string [] memory tokenData,
        uint256 supply,
        uint8 decimals
    ) external {
        require(!initialized, "Already initialized");
        initialized = true;
        
        _initERC20(tokenData[0], tokenData[1], decimals);
        _transferOwnership(msg.sender);
        
        // Store creator address (wallet that receives initial tokens)
        creator = wallet;

        _name = tokenData[0];
        _symbol = tokenData[1];
        _description = tokenData[2];
        _mint(wallet, supply * (10 ** decimals));
    }

    receive() external payable {
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (amount == 0) {
            super._transfer(sender, recipient, 0);
            return;
        }

        // Standard ERC20 transfers without fee (including DEX trades after migration).
        super._transfer(sender, recipient, amount);

        if (owner() != address(0)) {
            require(!_isContract(recipient) || sender == owner() || recipient == owner(), "Can't send tokens to contracts before launch");
        }
    }

    function _isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /**
     * @dev Set PancakeSwap router and factory addresses
     */
    function setPancakeSwapAddresses(address _router, address _factory) external onlyOwner {
        pancakeSwapRouter = _router;
        pancakeSwapFactory = _factory;
    }

    /**
     * @dev Add DEX pair address (PancakeSwap pair)
     */
    function addDexPair(address _pair) external onlyOwner {
        require(_pair != address(0), "Invalid pair address");
        isDexPair[_pair] = true;
        emit DexPairAdded(_pair);
    }

    /**
     * @dev Batch add multiple DEX pair addresses
     */
    function batchAddDexPairs(address[] calldata _pairs) external onlyOwner {
        for (uint256 i = 0; i < _pairs.length; i++) {
            if (_pairs[i] != address(0)) {
                isDexPair[_pairs[i]] = true;
                emit DexPairAdded(_pairs[i]);
            }
        }
    }

    /**
     * @dev Remove DEX pair address
     */
    function removeDexPair(address _pair) external onlyOwner {
        isDexPair[_pair] = false;
    }

    // Kept for compatibility with existing integrations/storage.
    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "Invalid fee address");
        feeAddress = _feeAddress;
        emit FeeAddressSet(_feeAddress);
    }
    
    // Kept for compatibility with existing integrations/storage.
    function setCreator(address _creator) external onlyOwner {
        require(_creator != address(0), "Invalid creator address");
        creator = _creator;
    }
}