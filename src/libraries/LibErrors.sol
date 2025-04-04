// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library LibErrors {
    error NotOwner();
    error AddressZeroDetected();
    error TitleAndDescriptionCannotBeEmpty();
    error EventDoesNotExist();
    error OnlyOrganiserCanCreateTicket();
    error InvalidTicketFee();
    error ExpectedAttendeesIsTooLow();
    error PaidEventRequiresCategory();
    error VipFeeTooLow();
    error RegularTicketMustCostLessThanVipTicket();
    error FreeTicketForFreeEventOnly();
    error YouCanNotCreateThisTypeOfTicketForThisEvent();
    error EventHasEnded();
    error RegularTicketsAlreadyCreated();
    error VIPTicketsAlreadyCreated();
    error RegularTicketsNotAvailable();
    error VIPTicketsNotAvailable();
    error InvalidTicketCategory();
    error AlreadyRegistered();
    error RegistrationHasClosed();
    error InvalidDates();
    error EmptyTitleOrDescription();
    error NotRegisteredForEvent();
    error AlreadyVerified();
    error NotEventOrganizer();
    error EmptyAttendeesList();
    error EventNotStarted();
    error EventHasNotEnded();
    error EventNotEnded();
    error InsufficientAttendanceRate();
    error NoRevenueToRelease();
    error RevenueAlreadyReleased();
    error OnlyOwnerCanRelease();
    error OrganizerIsBlacklisted();
    error InsufficientInitialStake();
    error InsufficientStakeAmount();
    error InsufficientAllowance();
    error TokenAlreadySupported();
    error TokenNotSupported();
    error InvalidERC20Token();
    error OnlyOwnerAllowed();
}
