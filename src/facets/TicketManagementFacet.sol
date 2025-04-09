// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibTypes.sol";
import "../libraries/LibErrors.sol";
import "../libraries/LibUtils.sol";
import "../interfaces/ITicket_NFT.sol";
import "../../src/Ticket_NFT.sol";
import "../interfaces/IExtendedERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title TicketManagementFacet
 * @dev Handles ticket creation, purchase, and verification functionality
 */
contract TicketManagementFacet is ReentrancyGuard {
    using LibTypes for *;
    using LibErrors for *;
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /**
     * @dev Set a verification code for an event (optional enhancement)
     * @param _eventId The ID of the event
     * @param _verificationCode A unique code displayed at the event that attendees can use
     */
    function setEventVerificationCode(
        uint256 _eventId,
        bytes32 _verificationCode
    ) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibUtils._validateEventAndOrganizer(_eventId);

        s.eventVerificationCodes[_eventId] = _verificationCode;

        emit LibEvents.VerificationCodeSet(_eventId, _verificationCode);
    }

    /**
     * @dev Creates a new NFT ticket contract for an event
     * @param _eventId The ID of the event
     * @param _ticketFee The price of the ticket
     * @param _ticketUri The URI for the ticket metadata
     * @param _ticketType The type of ticket (FREE, REGULAR, or VIP)
     * @return Address of the newly created ticket NFT contract
     */
    function _createTicket(
        uint256 _eventId,
        uint256 _ticketFee,
        string memory _ticketUri,
        string memory _ticketType
    ) internal returns (address) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Generate a random salt using some current block informations and sender address
        bytes32 uniqueSalt = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                blockhash(block.number - 1) // hash of the previous block
            )
        );

        string memory ticketName = eventDetails.title;
        address newTicketNFT = address(
            new Ticket_NFT{salt: uniqueSalt}(
                address(this),
                _ticketUri,
                ticketName,
                _ticketType
            )
        );

        eventDetails.ticketNFTAddr = newTicketNFT;
        eventDetails.ticketFee = _ticketFee;
        s.organiserRevBal[eventDetails.organiser][_eventId] += 0;

        return newTicketNFT;
    }

    /**
     * @dev Creates a ticket for an existing event using ERC20Permit for approval
     * @param _eventId The ID of the event
     * @param _category The category of the ticket (NONE for FREE, REGULAR or VIP for PAID events)
     * @param _ticketFee The price of the ticket (0 for FREE tickets)
     * @param _ticketUri The URI for the ticket metadata
     * @param _verificationCode Optional code that will be displayed at the event for attendees to verify
     * @param _v Signature v component
     * @param _r Signature r component
     * @param _s Signature s component
     */
    function createTicketWithPermit(
        uint256 _eventId,
        LibTypes.PaidTicketCategory _category,
        uint256 _ticketFee,
        string memory _ticketUri,
        bytes32 _verificationCode,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant returns (bool success_) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibUtils._validateEventAndOrganizer(_eventId);

        // Check if organizer is blacklisted
        if (s.blacklistedOrganizers[msg.sender]) {
            revert LibErrors.OrganizerIsBlacklisted();
        }

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];
        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

        setEventVerificationCode(_eventId, _verificationCode);

        // Handle FREE tickets
        if (_category == LibTypes.PaidTicketCategory.NONE) {
            if (eventDetails.ticketType != LibTypes.TicketType.FREE) {
                revert LibErrors.FreeTicketForFreeEventOnly();
            }

            address newTicketNFT = _createTicket(
                _eventId,
                LibConstants.FREE_TICKET_PRICE,
                _ticketUri,
                "FREE"
            );

            s.totalTicketCreated++;

            emit LibEvents.TicketCreated(
                _eventId,
                msg.sender,
                newTicketNFT,
                LibConstants.FREE_TICKET_PRICE,
                "FREE"
            );
            return true;
        }

        // Handle PAID tickets
        if (eventDetails.ticketType != LibTypes.TicketType.PAID) {
            revert LibErrors.YouCanNotCreateThisTypeOfTicketForThisEvent();
        }
        if (_ticketFee == 0) revert LibErrors.InvalidTicketFee();

        // If this is the first ticket being created, calculate and collect proper stake
        bool firstTicket = !tickets.hasRegularTicket && !tickets.hasVIPTicket;

        if (firstTicket) {
            // Calculate required stake based on this ticket's price
            uint256 requiredStake = LibUtils._calculateRequiredStake(
                msg.sender,
                eventDetails.expectedAttendees,
                LibTypes.TicketType.PAID,
                _ticketFee
            );

            // Subtract any stake already provided
            uint256 existingStake = s.stakedAmounts[_eventId];
            uint256 additionalStakeNeeded = 0;

            if (requiredStake > existingStake) {
                additionalStakeNeeded = requiredStake - existingStake;
            }

            if (
                IERC20(eventDetails.paymentToken).balanceOf(msg.sender) <
                additionalStakeNeeded
            ) {
                revert LibErrors.InsufficientStakeAmount();
            }

            // deadline of 30 minutes from now to prevent stale signatures
            uint256 deadline = block.timestamp + 30 minutes;

            // Check deadline is valid (must be in the future)
            if (deadline < block.timestamp) {
                revert LibErrors.ExpiredDeadline();
            }

            // Use permit for approval
            try
                IERC20Permit(eventDetails.paymentToken).permit(
                    msg.sender,
                    address(this),
                    additionalStakeNeeded,
                    deadline,
                    _v,
                    _r,
                    _s
                )
            {
                // Transfer the additional stake needed to the contract
                IERC20(eventDetails.paymentToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    additionalStakeNeeded
                );

                emit IExtendedERC20.Transfer(
                    msg.sender,
                    address(this),
                    additionalStakeNeeded
                );
            } catch {
                revert LibErrors.PermitFailed();
            }

            // Update total stake
            s.stakedAmounts[_eventId] += additionalStakeNeeded;
        }

        if (_category == LibTypes.PaidTicketCategory.REGULAR) {
            if (tickets.hasRegularTicket) {
                revert LibErrors.RegularTicketsAlreadyCreated();
            }
            if (tickets.hasVIPTicket && _ticketFee >= tickets.vipTicketFee) {
                revert LibErrors.RegularTicketMustCostLessThanVipTicket();
            }

            address newTicketNFT = _createTicket(
                _eventId,
                _ticketFee,
                _ticketUri,
                "REGULAR"
            );

            tickets.hasRegularTicket = true;
            tickets.regularTicketFee = _ticketFee;
            tickets.regularTicketNFT = newTicketNFT;

            s.totalTicketCreated++;

            emit LibEvents.TicketCreated(
                _eventId,
                msg.sender,
                newTicketNFT,
                _ticketFee,
                "REGULAR"
            );
            return true;
        } else if (_category == LibTypes.PaidTicketCategory.VIP) {
            if (tickets.hasVIPTicket) {
                revert LibErrors.VIPTicketsAlreadyCreated();
            }
            if (
                tickets.hasRegularTicket &&
                _ticketFee <= tickets.regularTicketFee
            ) {
                revert LibErrors.VipFeeTooLow();
            }

            address newTicketNFT = _createTicket(
                _eventId,
                _ticketFee,
                _ticketUri,
                "VIP"
            );

            tickets.hasVIPTicket = true;
            tickets.vipTicketFee = _ticketFee;
            tickets.vipTicketNFT = newTicketNFT;

            s.totalTicketCreated++;

            emit LibEvents.TicketCreated(
                _eventId,
                msg.sender,
                newTicketNFT,
                _ticketFee,
                "VIP"
            );
            return true;
        }
    }

    /**
     * @dev Purchase ticket using ERC20 tokens with permit
     * @param _eventId The ID of the event
     * @param _category The category of ticket to purchase
     * @param _v Signature v component
     * @param _r Signature r component
     * @param _s Signature s component
     */
    function purchaseTicketWithPermit(
        uint256 _eventId,
        LibTypes.PaidTicketCategory _category,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];
        if (s.hasRegistered[msg.sender][_eventId]) {
            revert LibErrors.AlreadyRegistered();
        }
        if (eventDetails.endDate < block.timestamp) {
            revert LibErrors.EventHasEnded();
        }
        if (eventDetails.userRegCount >= eventDetails.expectedAttendees) {
            revert LibErrors.RegistrationHasClosed();
        }

        // Check if event organizer is blacklisted
        if (s.blacklistedOrganizers[eventDetails.organiser]) {
            revert LibErrors.OrganizerIsBlacklisted();
        }

        // Check if event was confirmed as scam
        if (s.eventConfirmedScam[_eventId]) {
            revert LibErrors.EventConfirmedAscam_TicketsUnavailable();
        }

        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];
        address ticketNFTAddr;
        uint256 requiredFee;

        if (eventDetails.ticketType == LibTypes.TicketType.FREE) {
            if (_category != LibTypes.PaidTicketCategory.NONE) {
                revert LibErrors.FreeTicketForFreeEventOnly();
            }
            ticketNFTAddr = eventDetails.ticketNFTAddr;
            requiredFee = 0;
        } else {
            // Handle paid tickets
            if (_category == LibTypes.PaidTicketCategory.REGULAR) {
                if (!tickets.hasRegularTicket)
                    revert LibErrors.RegularTicketsNotAvailable();

                ticketNFTAddr = tickets.regularTicketNFT;
                requiredFee = tickets.regularTicketFee;
            } else if (_category == LibTypes.PaidTicketCategory.VIP) {
                if (!tickets.hasVIPTicket)
                    revert LibErrors.VIPTicketsNotAvailable();

                ticketNFTAddr = tickets.vipTicketNFT;
                requiredFee = tickets.vipTicketFee;
            } else {
                revert LibErrors.InvalidTicketCategory();
            }

            // Set deadline of 30 minutes from now to prevent stale signatures
            uint256 deadline = block.timestamp + 30 minutes;

            // Check deadline is valid
            if (deadline < block.timestamp) {
                revert LibErrors.ExpiredDeadline();
            }

            // Use permit for approval
            try
                IERC20Permit(eventDetails.paymentToken).permit(
                    msg.sender,
                    address(this),
                    requiredFee,
                    deadline,
                    _v,
                    _r,
                    _s
                )
            {
                // Transfer ERC20 tokens from buyer to escrow contract
                if (requiredFee > 0) {
                    IERC20(eventDetails.paymentToken).safeTransferFrom(
                        msg.sender,
                        address(this),
                        requiredFee
                    );
                }
            } catch {
                revert LibErrors.PermitFailed();
            }
        }

        if (ticketNFTAddr == address(0))
            revert LibErrors.TicketContractNotSet();

        // Mint NFT ticket
        ITicket_NFT ticketContract = ITicket_NFT(ticketNFTAddr);
        ticketContract.safeMint(msg.sender);

        // Update event details
        eventDetails.userRegCount += 1;
        s.hasRegistered[msg.sender][_eventId] = true;

        // Update organizer revenue balance
        s.organiserRevBal[eventDetails.organiser][_eventId] += requiredFee;

        // Add buyer to attendance list
        s.eventAttendees[_eventId].push(msg.sender);

        s.totalPurchasedTicket += 1;

        emit LibEvents.TicketPurchased(_eventId, msg.sender, requiredFee);
    }

    /**
     * @dev Verify attendance using attendee-generated ECDSA signature
     * @param _eventId The ID of the event
     * @param _verificationCode The verification code displayed at the event
     * @param _signature Signature created by the attendee to verify their attendance
     */
    function verifyAttendance(
        uint256 _eventId,
        bytes32 _verificationCode,
        bytes calldata _signature
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Validate event status
        if (_eventId == 0 || _eventId > s.totalEventOrganised) {
            revert LibErrors.EventDoesNotExist();
        }
        if (block.timestamp < eventDetails.startDate) {
            revert LibErrors.EventNotStarted();
        }

        // Check if already verified
        if (s.isVerified[msg.sender][_eventId]) {
            revert LibErrors.AlreadyVerified();
        }

        // Check if user has a ticket
        if (s.hasRegistered[msg.sender][_eventId]) {
            // Verify the provided verification code matches the one set for the event
            bytes32 eventCode = s.eventVerificationCodes[_eventId];
            if (eventCode == bytes32(0))
                revert LibErrors.VerificationCodeNotSet();
            if (eventCode != _verificationCode)
                revert LibErrors.InvalidVerificationCode();

            // Create the message hash including the verification code to prove presence
            bytes32 messageHash = keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(
                        abi.encodePacked(
                            "I verify my attendance at event",
                            _eventId,
                            "with code",
                            _verificationCode,
                            "at timestamp",
                            block.timestamp
                        )
                    )
                )
            );

            // Recover the signer address from the signature
            address recoveredSigner = ECDSA.recover(messageHash, _signature);

            // Verify the signature is from the attendee themselves
            if (recoveredSigner != msg.sender)
                revert LibErrors.InvalidSignature();

            // Mark attendee as verified
            s.isVerified[msg.sender][_eventId] = true;
            eventDetails.verifiedAttendeesCount += 1;

            emit LibEvents.AttendeeVerified(
                _eventId,
                msg.sender,
                block.timestamp
            );
        } else {
            revert LibErrors.NotRegisteredForEvent();
        }
    }

    /**
     * @dev Verify if an address has self-verified attendance for an event
     * @param _eventId The ID of the event
     * @param _address The address to check
     * @return True if address has verified their attendance
     */
    function isAddressVerified(
        uint256 _eventId,
        address _address
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // check if they are registered
        if (!s.hasRegistered[_address][_eventId]) {
            return false;
        }

        // check if they've verified their attendance
        return s.isVerified[_address][_eventId];
    }

    /**
     * @dev Returns all events a specific user has registered for
     * @param _user Address of the user to check
     * @return Array of event IDs the user has registered for
     */
    function allEventsRegisteredForByAUser(
        address _user
    ) external view returns (uint256[] memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (_user == address(0)) revert LibErrors.AddressZeroDetected();

        uint256 count = 0;

        // First pass: count events the user has registered for
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[_user][i]) {
                count++;
            }
        }

        // Second pass: populate the array
        uint256[] memory registeredEvents = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[_user][i]) {
                registeredEvents[index] = i;
                index++;
            }
        }

        return registeredEvents;
    }

    /**
     * @dev Determines if a user has a specific ticket type for an event
     * @param _user Address of the ticket holder to check
     * @param _eventId The ID of the event
     * @return ticketType String representation of ticket type ("FREE", "REGULAR", "VIP", or "NONE")
     */
    function getUserTicketType(
        address _user,
        uint256 _eventId
    ) public view returns (string memory) {
        return LibUtils._getUserTicketType(_user, _eventId);
    }

    /**
     * @dev Helper to check if a user has a VIP ticket
     * @param _user Address of the ticket holder
     * @param _eventId The ID of the event
     * @return bool True if user has a VIP ticket
     */
    function hasVIPTicket(
        address _user,
        uint256 _eventId
    ) public view returns (bool) {
        return LibUtils._hasVIPTicket(_user, _eventId);
    }

    /**
     * @dev Returns all ticket details for a user across events
     * @return eventIds Array of event IDs the user has tickets for
     * @return ticketTypes Array of ticket Types (FREE, REGULAR, VIP) corresponding to each event
     * @return verified Array indicating if attendance was verified for each event
     * @return canClaimRefund Array indicating if user can claim refund for scam events
     */
    function getMyTickets()
        external
        view
        returns (
            uint256[] memory eventIds,
            string[] memory ticketTypes,
            bool[] memory verified,
            bool[] memory canClaimRefund
        )
    {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        uint256 count = 0;

        // First pass: count tickets owned by the caller
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[msg.sender][i]) {
                count++;
            }
        }

        // Initialize return arrays
        eventIds = new uint256[](count);
        ticketTypes = new string[](count);
        verified = new bool[](count);
        canClaimRefund = new bool[](count);
        uint256 index = 0;

        // Second pass: populate arrays with ticket details
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[msg.sender][i]) {
                eventIds[index] = i;
                verified[index] = s.isVerified[msg.sender][i];

                // Check refund eligibility (if event confirmed as scam)
                canClaimRefund[index] =
                    s.eventConfirmedScam[i] &&
                    !s.hasClaimedRefund[msg.sender][i];

                // Determine ticket type using the utility function
                ticketTypes[index] = LibUtils._getUserTicketType(msg.sender, i);

                index++;
            }
        }

        return (eventIds, ticketTypes, verified, canClaimRefund);
    }
}
