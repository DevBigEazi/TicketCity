// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibErrors.sol";
import "../libraries/LibUtils.sol";
import "../interfaces/IExtendedERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenManagementFacet
 * @dev Handles supported token management for the Ticket_City platform
 */
contract TokenManagementFacet {
    using LibErrors for *;
    using LibUtils for *;

    IERC20 public token;

    /**
     * @dev Event emitted when a token is added to supported tokens
     */
    event TokenAdded(address indexed tokenAddress, string name, string symbol);

    /**
     * @dev Event emitted when a token is removed from supported tokens
     */
    event TokenRemoved(address indexed tokenAddress);

    /**
     * @dev Adds a new token to the list of supported payment tokens
     * @param _tokenAddress Address of the ERC20 token to add
     * @return success Boolean indicating if the operation was successful
     */
    function addSupportedToken(
        address _tokenAddress
    ) external payable returns (bool success) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // Validate the caller
        LibUtils.onlyOwner();

        if (_tokenAddress == address(0)) revert LibErrors.AddressZeroDetected();
        if (s.supportedTokens[_tokenAddress]) {
            revert LibErrors.TokenAlreadySupported();
        }

        // Try to interact with the token to verify it's a valid ERC20
        try token.totalSupply() returns (uint256) {
            // Token is valid, add it to supported tokens
            s.supportedTokens[_tokenAddress] = true;
            s.supportedTokensList.push(_tokenAddress);

            // Get token details for the event
            string memory name;
            string memory symbol;

            try IExtendedERC20(_tokenAddress).name() returns (
                string memory _name
            ) {
                name = _name;
            } catch {
                name = "???";
            }

            try IExtendedERC20(_tokenAddress).symbol() returns (
                string memory _symbol
            ) {
                symbol = _symbol;
            } catch {
                symbol = "???";
            }

            emit TokenAdded(_tokenAddress, name, symbol);
            return true;
        } catch {
            revert LibErrors.InvalidERC20Token();
        }
    }

    /**
     * @dev Removes a token from the list of supported payment tokens
     * @param _tokenAddress Address of the ERC20 token to remove
     * @return success Boolean indicating if the operation was successful
     */
    function removeSupportedToken(
        address _tokenAddress
    ) external payable returns (bool success) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // Validate the caller
        LibUtils.onlyOwner();

        if (_tokenAddress == address(0)) revert LibErrors.AddressZeroDetected();
        if (s.supportedTokens[_tokenAddress]) {
            // Remove token from mapping
            s.supportedTokens[_tokenAddress] = false;

            // Remove token from the list
            for (uint256 i = 0; i < s.supportedTokensList.length; i++) {
                if (s.supportedTokensList[i] == _tokenAddress) {
                    // Move the last element to the position of the removed element
                    s.supportedTokensList[i] = s.supportedTokensList[
                        s.supportedTokensList.length - 1
                    ];
                    // Remove the last element
                    s.supportedTokensList.pop();
                    break;
                }
            }

            emit TokenRemoved(_tokenAddress);
            return true;
        } else {
            revert LibErrors.TokenNotSupported();
        }
    }

    /**
     * @dev Checks if a token is supported
     * @param _tokenAddress Address of the ERC20 token to check
     * @return isSupported Boolean indicating if the token is supported
     */
    function isTokenSupported(
        address _tokenAddress
    ) external view returns (bool isSupported) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        return s.supportedTokens[_tokenAddress];
    }

    /**
     * @dev Returns the list of all supported tokens
     * @return tokens Array of supported token addresses
     */
    function getSupportedTokens()
        external
        view
        returns (address[] memory tokens)
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        return s.supportedTokensList;
    }
}
