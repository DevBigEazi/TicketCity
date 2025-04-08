// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibTypes.sol";
import "../libraries/LibErrors.sol";
import "../libraries/LibUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RevenueManagementFacet
 * @dev Handles revenue management, release, refunds, and scam event processing
 */
contract RevenueManagementFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using LibTypes for *;
    using LibErrors for *;

    /**
     * @dev Checks if flagging threshold is met based on the 70% of non-verified attendees formula
     * @param _eventId The ID of the event to check
     * @return isFlaggingThresholdMet True if flagging threshold is met
     */
    function handleIsFlaggingThresholdMet(
        uint256 _eventId
    ) internal view returns (bool) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // If no one registered, can't be flagged
        if (eventDetails.userRegCount == 0) {
            return false;
        }

        // Calculate the number of non-verified attendees
        uint256 nonVerifiedCount = 0;
        if (eventDetails.userRegCount > eventDetails.verifiedAttendeesCount) {
            nonVerifiedCount =
                eventDetails.userRegCount -
                eventDetails.verifiedAttendeesCount;
        }

        // If everyone verified attendance, no flagging threshold can be met
        if (nonVerifiedCount == 0) {
            return false;
        }

        // Calculate the threshold count - 70% of non-verified attendees
        uint256 thresholdCount = (nonVerifiedCount *
            LibConstants.FLAGGING_THRESHOLD) / 100;

        // Check if the actual flag count exceeds the threshold
        return s.totalFlagsCount[_eventId] >= thresholdCount;
    }

    /**
     * @dev Releases event revenue to the organizer in ERC20 tokens
     */
    function releaseRevenue(uint256 _eventId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Existing validations remain the same
        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }
        if (block.timestamp <= eventDetails.endDate) {
            revert LibErrors.EventNotEnded();
        }
        if (s.revenueReleased[_eventId])
            revert LibErrors.RevenueAlreadyReleased();
        if (s.eventConfirmedScam[_eventId]) revert("Event confirmed as scam");

        uint256 revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) revert LibErrors.NoRevenueToRelease();
        if (msg.sender != eventDetails.organiser)
            revert LibErrors.NotEventOrganizer();

        // Calculate attendance rate
        uint256 attendanceRate = eventDetails.userRegCount > 0
            ? (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount
            : 0;

        // Check flagging status
        bool isAfterFlaggingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.FLAGGING_PERIOD;
        bool isFlaggingThresholdMet = handleIsFlaggingThresholdMet(_eventId);

        if (
            attendanceRate < LibConstants.MINIMUM_ATTENDANCE_RATE &&
            !isAfterFlaggingPeriod
        ) {
            revert("Low attendance rate: Must wait 4 days after event ends");
        }
        if (isFlaggingThresholdMet) {
            revert("Event has been flagged by attendees");
        }

        // Calculate and deduct platform fees
        uint256 serviceFee;
        if (eventDetails.ticketType == LibTypes.TicketType.FREE) {
            // Free event service fee calculation
            if (
                eventDetails.userRegCount >
                LibConstants.FREE_EVENT_ATTENDEE_THRESHOLD
            ) {
                uint256 multiplier = eventDetails.userRegCount /
                    LibConstants.FREE_EVENT_ATTENDEE_THRESHOLD;
                serviceFee =
                    LibConstants.FREE_EVENT_SERVICE_FEE_BASE *
                    multiplier;
                serviceFee = serviceFee > revenue ? revenue : serviceFee;
            }
        } else {
            // Paid event service fee (5%)
            serviceFee =
                (revenue * LibConstants.PAID_EVENT_SERVICE_FEE_PERCENT) /
                100;
        }

        // Update balances
        s.revenueReleased[_eventId] = true;
        s.organiserRevBal[eventDetails.organiser][_eventId] = 0;

        // Transfer funds
        IERC20 paymentToken = IERC20(eventDetails.paymentToken);
        if (serviceFee > 0) {
            paymentToken.safeTransfer(address(this), serviceFee);
            revenue -= serviceFee;
            s.platformRevenue += serviceFee;
        }
        paymentToken.safeTransfer(eventDetails.organiser, revenue);

        // Update organizer reputation
        s.organizerSuccessfulEvents[eventDetails.organiser]++;

        emit LibEvents.RevenueReleased(
            _eventId,
            eventDetails.organiser,
            revenue,
            attendanceRate,
            false
        );
    }

    /**
     * @dev Claim refund for scam event in ERC20 tokens
     */
    function claimScamEventRefund(uint256 _eventId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        require(s.eventConfirmedScam[_eventId], "Event not confirmed as scam");
        require(s.hasRegistered[msg.sender][_eventId], "Not a ticket buyer");
        require(!s.hasClaimedRefund[msg.sender][_eventId], "Already claimed");

        uint256 refundAmount = 0;
        IERC20 paymentToken = IERC20(eventDetails.paymentToken);

        if (eventDetails.ticketType != LibTypes.TicketType.FREE) {
            LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

            if (LibUtils._hasVIPTicket(msg.sender, _eventId)) {
                refundAmount = tickets.vipTicketFee;
            } else if (LibUtils._hasRegularTicket(msg.sender, _eventId)) {
                refundAmount = tickets.regularTicketFee;
            }
        }

        // Add share of staked amount (90% divided among all attendees)
        uint256 stakeShare = eventDetails.userRegCount > 0
            ? (s.stakedAmounts[_eventId] * 90) /
                (eventDetails.userRegCount * 100)
            : 0;

        uint256 totalRefund = refundAmount + stakeShare;

        // Mark as claimed
        s.hasClaimedRefund[msg.sender][_eventId] = true;
        s.claimedRefundAmount[msg.sender][_eventId] = totalRefund;

        // Process refund
        if (totalRefund > 0) {
            // Check if enough balance in contract
            uint256 contractBalance = paymentToken.balanceOf(address(this));
            require(
                contractBalance >= totalRefund,
                "Insufficient contract balance"
            );

            // Transfer refund
            paymentToken.safeTransfer(msg.sender, totalRefund);

            emit LibEvents.RefundClaimed(
                _eventId,
                msg.sender,
                totalRefund,
                stakeShare
            );
        }
    }

    /**
     * @dev Checks if an event can have its revenue released
     * @param _eventId The ID of the event to check
     * @return canRelease Whether revenue can be released
     * @return reason Reason code for status (0=can release, 1=waiting period, 2=flagged, 3=already released, 4=confirmed scam)
     */
    function checkReleaseStatus(
        uint256 _eventId
    ) external view returns (bool canRelease, uint8 reason) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (
            _eventId == 0 ||
            _eventId > s.totalEventOrganised ||
            block.timestamp <= eventDetails.endDate
        ) {
            return (false, 1); // Event doesn't exist or hasn't ended
        }

        // Check if revenue was already released
        if (s.revenueReleased[_eventId]) {
            return (false, 3); // Already released
        }

        // Check if confirmed as scam
        if (s.eventConfirmedScam[_eventId]) {
            return (false, 4); // Confirmed scam
        }

        // Calculate attendance rate
        uint256 attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Check if flagging threshold is met using our new calculation
        bool isFlaggingThresholdMet = false;

        // Calculate non-verified attendees
        uint256 nonVerifiedCount = 0;
        if (eventDetails.userRegCount > eventDetails.verifiedAttendeesCount) {
            nonVerifiedCount =
                eventDetails.userRegCount -
                eventDetails.verifiedAttendeesCount;
        }

        // If there are non-verified attendees, calculate threshold
        if (nonVerifiedCount > 0) {
            // Calculate threshold (70% of non-verified attendees)
            uint256 thresholdCount = (nonVerifiedCount *
                LibConstants.FLAGGING_THRESHOLD) / 100;

            // Check if flag count meets the threshold
            isFlaggingThresholdMet =
                s.totalFlagsCount[_eventId] >= thresholdCount;
        }

        if (isFlaggingThresholdMet) {
            return (false, 2); // Flagged by users
        }

        // Can release if after flagging period OR if attendance rate is sufficient
        bool isAfterFlaggingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.FLAGGING_PERIOD;

        if (
            isAfterFlaggingPeriod ||
            attendanceRate >= LibConstants.MINIMUM_ATTENDANCE_RATE
        ) {
            return (true, 0); // Can release
        }

        return (false, 1); // Still in waiting period
    }

    /**
     * @dev Returns revenue details and determines if revenue can be automatically released
     * @param _eventId The ID of the event to check
     * @return canRelease Boolean indicating whether revenue can be released
     * @return attendanceRate The percentage of registered users who were verified as attendees
     * @return revenue The total revenue amount available for release
     */
    function canReleaseRevenue(
        uint256 _eventId
    )
        external
        view
        returns (bool canRelease, uint256 attendanceRate, uint256 revenue)
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        if (
            block.timestamp <= eventDetails.endDate ||
            s.revenueReleased[_eventId] ||
            s.eventConfirmedScam[_eventId]
        ) {
            return (false, 0, 0);
        }

        revenue = s.organiserRevBal[eventDetails.organiser][_eventId];
        if (revenue == 0) {
            return (false, 0, 0);
        }

        attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Check if after flagging period or attendance rate meets requirement
        bool isAfterFlaggingPeriod = block.timestamp >
            eventDetails.endDate + LibConstants.FLAGGING_PERIOD;
        canRelease =
            isAfterFlaggingPeriod ||
            attendanceRate >= LibConstants.MINIMUM_ATTENDANCE_RATE;

        return (canRelease, attendanceRate, revenue);
    }

    /**
     * @dev Function for contract owner to get a list of events that require manual validation
     * @return eventIds Array of event IDs needing manual review
     * @return organizers Array of organizer addresses corresponding to each event
     * @return attendanceRates Array of attendance rates for each event
     * @return flagPercentages Array of flag percentages for each event
     * @return revenues Array of revenue amounts for each event
     * @return hasRequestedReview Array indicating if organizer requested manual review
     */
    function getEventsRequiringManualReview()
        external
        view
        returns (
            uint256[] memory eventIds,
            address[] memory organizers,
            uint256[] memory attendanceRates,
            uint256[] memory flagPercentages,
            uint256[] memory revenues,
            bool[] memory hasRequestedReview
        )
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // Count events requiring manual review
        uint256 count = 0;
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            LibTypes.EventDetails storage eventDetails = s.events[i];

            // Skip if already released, confirmed as scam, or event hasn't ended
            if (
                s.revenueReleased[i] ||
                s.eventConfirmedScam[i] ||
                block.timestamp <= eventDetails.endDate
            ) {
                continue;
            }

            uint256 revenue = s.organiserRevBal[eventDetails.organiser][i];
            if (revenue == 0) {
                continue;
            }

            uint256 attendanceRate = 0;
            if (eventDetails.userRegCount > 0) {
                attendanceRate =
                    (eventDetails.verifiedAttendeesCount * 100) /
                    eventDetails.userRegCount;
            }

            uint256 flagPercentage = 0;
            if (eventDetails.userRegCount > 0) {
                flagPercentage =
                    (s.totalFlagsCount[i] * 100) /
                    eventDetails.userRegCount;
            }

            // If attendance is low or event flagged, it needs review
            if (
                attendanceRate < LibConstants.MINIMUM_ATTENDANCE_RATE ||
                flagPercentage >= LibConstants.FLAGGING_THRESHOLD
            ) {
                count++;
            }
        }

        // Initialize arrays
        eventIds = new uint256[](count);
        organizers = new address[](count);
        attendanceRates = new uint256[](count);
        flagPercentages = new uint256[](count);
        revenues = new uint256[](count);
        hasRequestedReview = new bool[](count);

        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            LibTypes.EventDetails storage eventDetails = s.events[i];

            // Skip if already released, confirmed as scam, or event hasn't ended
            if (
                s.revenueReleased[i] ||
                s.eventConfirmedScam[i] ||
                block.timestamp <= eventDetails.endDate
            ) {
                continue;
            }

            uint256 revenue = s.organiserRevBal[eventDetails.organiser][i];
            if (revenue == 0) {
                continue;
            }

            uint256 attendanceRate = 0;
            if (eventDetails.userRegCount > 0) {
                attendanceRate =
                    (eventDetails.verifiedAttendeesCount * 100) /
                    eventDetails.userRegCount;
            }

            uint256 flagPercentage = 0;
            if (eventDetails.userRegCount > 0) {
                flagPercentage =
                    (s.totalFlagsCount[i] * 100) /
                    eventDetails.userRegCount;
            }

            // If attendance is low or event flagged, add to arrays
            if (
                attendanceRate < LibConstants.MINIMUM_ATTENDANCE_RATE ||
                flagPercentage >= LibConstants.FLAGGING_THRESHOLD
            ) {
                eventIds[index] = i;
                organizers[index] = eventDetails.organiser;
                attendanceRates[index] = attendanceRate;
                flagPercentages[index] = flagPercentage;
                revenues[index] = revenue;
                hasRequestedReview[index] = s.manualReviewRequestTime[i] > 0;
                index++;
            }
        }

        return (
            eventIds,
            organizers,
            attendanceRates,
            flagPercentages,
            revenues,
            hasRequestedReview
        );
    }

    /**
     * @dev Checks if a user can claim a refund for a scam event
     * @param _eventId The ID of the event
     * @param _user Address of the user to check
     * @return canClaim Whether the user can claim a refund
     * @return refundAmount Estimated refund amount (ticket price + stake share)
     * @return alreadyClaimed Whether user has already claimed
     */
    function checkRefundEligibility(
        uint256 _eventId,
        address _user
    )
        external
        view
        returns (bool canClaim, uint256 refundAmount, bool alreadyClaimed)
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event is confirmed as scam
        if (!s.eventConfirmedScam[_eventId]) {
            return (false, 0, false);
        }

        // Check if user is a ticket buyer
        if (!s.hasRegistered[_user][_eventId]) {
            return (false, 0, false);
        }

        // Check if already claimed
        if (s.hasClaimedRefund[_user][_eventId]) {
            return (false, s.claimedRefundAmount[_user][_eventId], true);
        }

        // Calculate ticket price refund
        uint256 ticketPrice = 0;
        if (eventDetails.ticketType != LibTypes.TicketType.FREE) {
            LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

            // Check if they have a VIP ticket
            if (LibUtils._hasVIPTicket(_user, _eventId)) {
                ticketPrice = tickets.vipTicketFee;
            } else if (LibUtils._hasRegularTicket(_user, _eventId)) {
                ticketPrice = tickets.regularTicketFee;
            }
        }

        // Calculate stake share (90% of stake divided by number of attendees)
        uint256 stakeShare = 0;
        if (eventDetails.userRegCount > 0) {
            stakeShare =
                (s.stakedAmounts[_eventId] * 90) /
                (eventDetails.userRegCount * 100);
        }

        return (true, ticketPrice + stakeShare, false);
    }
}
