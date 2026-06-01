// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

abstract contract Context {
    function _msgSender() internal view virtual returns(address) {
        return msg.sender;
    }
}


library SafeMath {
   
    function add(uint256 a, uint256 b) internal pure returns(uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns(uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

   
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns(uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns(uint256) {
    
        if (a == 0) {
            return 0;
        }
 
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns(uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns(uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }
}
 
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns(address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    
    function renounceOwnership() internal virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) internal virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}


library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

interface IFlazepadFactory {
    function userContributors(address _user, uint256 _length) external view returns(address);
    function getAllAddresses() external view returns(address [] memory);
    function getUserContributorAddresses(address _user) external view returns(address [] memory);
    function funUserLists(address _user) external view returns(address [] memory);
}

interface IFlazepad {
    function getFunBasicInfo() external view returns(uint256 [11] memory, string [7] memory, address [4] memory, address [] memory, bool, uint256);
    function getTrending() external view returns(uint256);
    function getRisingPercent() external view returns (uint256);
    function useSocial() external view returns(bool);
}

interface IERC20 {
    function balanceOf(address account) external view returns(uint256);
    function owner() external view returns(address);
}

contract Multicall is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeMath for uint256;
    
    IFlazepadFactory public factory;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _factory) external initializer {
        __Ownable_init(msg.sender);
        factory = IFlazepadFactory(_factory);
    }

    function getMainInfo() public view returns(uint256 [] memory, uint256 [] memory, uint256 [] memory, uint256 [] memory, uint256 [] memory, address [] memory){
        address [] memory allFlazepadLaunchs = IFlazepadFactory(factory).getAllAddresses();
        uint256 lengths = allFlazepadLaunchs.length;
        uint256 [] memory startTimestamp = new uint256[](lengths);
        uint256 [] memory virtualTokenLp = new uint256[](lengths);
        uint256 [] memory virtualEthLp = new uint256[](lengths);
        uint256 [] memory tokenPrices = new uint256[](lengths);
        uint256 [] memory volumes = new uint256[](lengths);
        address [] memory contractAddresses = new address[](lengths);
        for(uint64 i = 0; i < lengths; i ++){
            uint256[11] memory tokenDatas;
            address[4] memory addresses;
            (tokenDatas, , addresses, , , ) = IFlazepad(allFlazepadLaunchs[i]).getFunBasicInfo();
            startTimestamp[i] = tokenDatas[1];
            virtualTokenLp[i] = tokenDatas[4];
            virtualEthLp[i] = tokenDatas[5];
            tokenPrices[i] = tokenDatas[8];
            volumes[i] = tokenDatas[9];
            contractAddresses[i] = addresses[0];
            
        }
        return ((startTimestamp), (virtualTokenLp), (virtualEthLp), (tokenPrices), (volumes), (contractAddresses));
    }

    function getOtherInfo() public view returns(string [] memory, string [] memory, string [] memory, string [] memory, string [] memory, uint256 [] memory){
        address [] memory allFlazepadLaunchs = IFlazepadFactory(factory).getAllAddresses();
        uint256 lengths = allFlazepadLaunchs.length;
        string [] memory names = new string[](lengths);
        string [] memory symbols = new string[](lengths);
        string [] memory websites = new string[](lengths);
        string [] memory twitters = new string[](lengths);
        string [] memory telegrams = new string[](lengths);
        uint256 [] memory risingPercents = new uint256[](lengths);
        for(uint64 i = 0; i < lengths; i ++){
            string[7] memory strings;
            address[4] memory addresses;
            (, strings, addresses, , , ) = IFlazepad(allFlazepadLaunchs[i]).getFunBasicInfo();
            risingPercents[i] = IFlazepad(allFlazepadLaunchs[i]).getRisingPercent();
            names[i] = strings[0];
            symbols[i] = strings[1];
            websites[i] = strings[2];
            twitters[i] = strings[3];
            telegrams[i] = strings[4];
            
        }
        return ((names), (symbols), (websites), (twitters), (telegrams), (risingPercents));
    }

    function getRestInfo() public view returns(uint256[] memory, bool[] memory, string[] memory, address[] memory, address [] memory) {
        address [] memory allFlazepadLaunchs = IFlazepadFactory(factory).getAllAddresses();
        uint256 lengths = allFlazepadLaunchs.length;
        uint256 [] memory featuredTimes = new uint256[](lengths);
        bool [] memory lpCreateds = new bool[](lengths);
        string [] memory infos = new string[](lengths);
        address [] memory routers = new address[](lengths);
        address [] memory devAddresses = new address[](lengths);
        for(uint256 i = 0; i < lengths; i ++){
            uint256 featuredTime;
            bool lpCreated;
            string[7] memory strings;
            address[4] memory addresses;
            (, strings,addresses , ,lpCreated , featuredTime) = IFlazepad(allFlazepadLaunchs[i]).getFunBasicInfo();
            featuredTimes[i] = featuredTime;
            lpCreateds[i] = lpCreated;
            infos[i] = strings[6];
            routers[i] = addresses[3];
            devAddresses[i] = addresses[2];
        }
        return ((featuredTimes), (lpCreateds), (infos), (routers), (devAddresses));
    }

    function getUserBalance(address _user) public view returns(string [] memory, string [] memory, address [] memory, uint256 [] memory){
        address [] memory allFlazepadLaunchs = IFlazepadFactory(factory).getUserContributorAddresses(_user);
        uint256 lengths = allFlazepadLaunchs.length;
        string [] memory names = new string[](lengths);
        string [] memory symbols = new string[](lengths);
        address [] memory contracts = new address[](lengths);
        uint256 [] memory balances = new uint256[](lengths);
        for(uint256 i = 0; i < lengths; i ++){
            address[4] memory addresses;
            string[7] memory strings;
            address user = _user;
            (, strings, addresses, , , ) = IFlazepad(allFlazepadLaunchs[i]).getFunBasicInfo();
            names[i] = strings[0];
            symbols[i] = strings[1];
            contracts[i] = addresses[0];
            balances[i] = IERC20(addresses[1]).balanceOf(user);
        }
        return ((names), (symbols), (contracts), (balances));
    }
    
    function getUserDeployMainInfo(address _user) public view returns(uint256 [] memory, uint256 [] memory, uint256 [] memory, uint256 [] memory, address [] memory, address [] memory, uint256 [] memory){
        address [] memory allFlazepadLaunchs = IFlazepadFactory(factory).funUserLists(_user);
        uint256 lengths = allFlazepadLaunchs.length;
        uint256 [] memory startTimestamp = new uint256[](lengths);
        uint256 [] memory virtualEthLp = new uint256[](lengths);
        uint256 [] memory tokenPrices = new uint256[](lengths);
        uint256 [] memory volumes = new uint256[](lengths);
        address [] memory contractAddresses = new address[](lengths);
        address [] memory devAddresses = new address[](lengths);
        uint256 [] memory accumulatedCreatorRewards = new uint256[](lengths);
        for(uint256 i = 0; i < lengths; i ++){
            uint256[11] memory tokenDatas;
            address[4] memory addresses;
            (tokenDatas, , addresses, , , ) = IFlazepad(allFlazepadLaunchs[i]).getFunBasicInfo();
            startTimestamp[i] = tokenDatas[1];
            volumes[i] = tokenDatas[9];
            virtualEthLp[i] = tokenDatas[5];
            tokenPrices[i] = tokenDatas[8];
            contractAddresses[i] = addresses[0];
            devAddresses[i] = addresses[2];
            accumulatedCreatorRewards[i] = tokenDatas[10];
        }
        return ((startTimestamp), (virtualEthLp), (tokenPrices), (volumes), (contractAddresses), (devAddresses), (accumulatedCreatorRewards));
    }

    function getUserDeployOtherInfo(address _user) public view returns(string [] memory, string [] memory, string [] memory, string [] memory, string [] memory, address [] memory){
        address [] memory allFlazepadLaunchs = IFlazepadFactory(factory).funUserLists(_user);
        uint256 lengths = allFlazepadLaunchs.length;
        string [] memory names = new string[](lengths);
        string [] memory symbols = new string[](lengths);
        string [] memory websites = new string[](lengths);
        string [] memory twitters = new string[](lengths);
        string [] memory telegrams = new string[](lengths);
        address [] memory tokenOwners = new address[](lengths);
        for(uint256 i = 0; i < lengths; i ++){
            string[7] memory strings;
            address[4] memory addresses;
            (, strings, addresses, , , ) = IFlazepad(allFlazepadLaunchs[i]).getFunBasicInfo();
            names[i] = strings[0];
            symbols[i] = strings[1];
            websites[i] = strings[2];
            twitters[i] = strings[3];
            telegrams[i] = strings[4];
            tokenOwners[i] = IERC20(addresses[1]).owner();
        }
        return ((names), (symbols), (websites), (twitters), (telegrams), (tokenOwners));
    }

    function updateFactory(address _newFactory) public onlyOwner{
        factory = IFlazepadFactory(_newFactory);
    }

    function funTrending() external view returns (uint256 [] memory, string [] memory, address [] memory){
        address [] memory allFlazepadLaunchs = IFlazepadFactory(factory).getAllAddresses();
        uint256 lengths = allFlazepadLaunchs.length;
        uint256 [] memory rates = new uint256[](lengths);
        string [] memory names = new string[](lengths);
        address [] memory addresses = new address[](lengths);
        for(uint256 i = 0; i < allFlazepadLaunchs.length; i ++){
            addresses[i] = allFlazepadLaunchs[i];
            rates[i] = IFlazepad(allFlazepadLaunchs[i]).getTrending();
        }
        return ((rates), (names), (addresses));
    }

    /**
     * @dev Get all addresses where useSocial is true
     * @return addresses Array of contract addresses that have useSocial enabled
     */
    function getUseSocialAddresses() external view returns (address[] memory) {
        address[] memory allFlazepadLaunchs = IFlazepadFactory(factory).getAllAddresses();
        uint256 count = 0;
        
        // First pass: count how many have useSocial = true
        for(uint256 i = 0; i < allFlazepadLaunchs.length; i++) {
            if(IFlazepad(allFlazepadLaunchs[i]).useSocial()) {
                count++;
            }
        }
        
        // Second pass: populate the result array
        address[] memory result = new address[](count);
        uint256 index = 0;
        for(uint256 i = 0; i < allFlazepadLaunchs.length; i++) {
            if(IFlazepad(allFlazepadLaunchs[i]).useSocial()) {
                result[index] = allFlazepadLaunchs[i];
                index++;
            }
        }
        
        return result;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    uint256[50] private __gap;
}