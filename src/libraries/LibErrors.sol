// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title LibErrors
 * @dev Library for custom error definitions used across facets
 */
library LibErrors {
    // Event management errors
    error EventDoesNotExist();
    error EventNotStarted();
    error EventHasEnded();
    error EventNotEnded();
    error InvalidDates();
    error ExpectedAttendeesIsTooLow();
    error EmptyTitleOrDescription();
    error AddressZeroDetected();
    error RevenueAlreadyReleased();
    error NoRevenueToRelease();
    error TokenNotSupported();

    // Ticket management errors
    error NotEventOrganizer();
    error NotRegisteredForEvent();
    error AlreadyVerified();
    error AlreadyRegistered();
    error OrganizerIsBlacklisted();
    error FreeTicketForFreeEventOnly();
    error YouCanNotCreateThisTypeOfTicketForThisEvent();
    error InvalidTicketFee();
    error RegularTicketsAlreadyCreated();
    error VIPTicketsAlreadyCreated();
    error RegularTicketMustCostLessThanVipTicket();
    error VipFeeTooLow();
    error RegularTicketsNotAvailable();
    error VIPTicketsNotAvailable();
    error InvalidTicketCategory();
    error RegistrationHasClosed();

    // Staking errors
    error InsufficientInitialStake();
    error InsufficientStakeAmount();
    error InsufficientAllowance();

    // Token errors
    error OnlyOwnerAllowed();
    error TokenAlreadySupported();
    error InvalidERC20Token();

    // Flagging errors
    error AlreadyFlagged();
    error FlaggingPeriodEnded();
}
