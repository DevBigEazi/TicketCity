// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibErrors.sol";

/**
 * @title LibUtils
 * @dev Utils functions used throughout the Ticket_City contract system
 */
library LibUtils {
    /**
     * @dev Validates event existence and organizer authorization
     * @param _eventId The ID of the event to validate
     */
    function _validateEventAndOrganizer(uint256 _eventId) internal view {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (msg.sender == address(0)) revert LibErrors.AddressZeroDetected();
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert LibErrors.EventDoesNotExist();
        if (msg.sender != s.events[_eventId].organiser)
            revert LibErrors.OnlyOrganiserCanCreateTicket();
    }
}
