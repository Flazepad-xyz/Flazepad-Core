// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interface/IERC20.sol";
import "../interface/IERC20Metadata.sol";
import "../context/Context.sol";
import "../lib/SafeMath.sol";
 
contract ERC20 is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;
 
    uint256 private _totalSupply;
 
    string _name;
    string _symbol;
    uint8 _decimals;

    constructor() {
        // Empty constructor for clone pattern
    }

    function _initERC20(string memory name_, string memory symbol_, uint8 decimals_) internal {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    
    function name() public view virtual override returns(string memory) {
        return _name;
    }

   
    function symbol() public view virtual override returns(string memory) {
        return _symbol;
    }

    
    function decimals() public view virtual override returns(uint8) {
        return _decimals;
    }

   
    function totalSupply() public view virtual override returns(uint256) {
        return _totalSupply;
    }

    
    function balanceOf(address account) public view virtual override returns(uint256) {
        return _balances[account];
    }

    
    function transfer(address recipient, uint256 amount) public virtual override returns(bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    
    function allowance(address owner, address spender) public view virtual override returns(uint256) {
        return _allowances[owner][spender];
    }

    
    function approve(address spender, uint256 amount) public virtual override returns(bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns(bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns(bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns(bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased cannot be below zero"));
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        
        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

}