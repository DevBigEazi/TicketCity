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
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title TicketManagementFacet
 * @dev Handles ticket creation, purchase, and verification functionality
 */
contract TicketManagementFacet is ReentrancyGuard {
    using LibTypes for *;
    using LibErrors for *;
    using SafeERC20 for IERC20;

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

        string memory ticketName = eventDetails.title;
        address newTicketNFT = address(
            new Ticket_NFT(address(this), _ticketUri, ticketName, _ticketType)
        );

        eventDetails.ticketNFTAddr = newTicketNFT;
        eventDetails.ticketFee = _ticketFee;
        s.organiserRevBal[eventDetails.organiser][_eventId] += 0;

        return newTicketNFT;
    }

    /**
     * @dev Creates a ticket for an existing event
     * @param _eventId The ID of the event
     * @param _category The category of the ticket (NONE for FREE, REGULAR or VIP for PAID events)
     * @param _ticketFee The price of the ticket (0 for FREE tickets)
     * @param _ticketUri The URI for the ticket metadata
     */
    function createTicket(
        uint256 _eventId,
        LibTypes.PaidTicketCategory _category,
        uint256 _ticketFee,
        string memory _ticketUri
    ) external nonReentrant returns (bool success_) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibUtils._validateEventAndOrganizer(_eventId);

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];
        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

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
            return success_;
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
            uint256 requiredStake = calculateRequiredStake(
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
            ) revert LibErrors.InsufficientStakeAmount();

            // Transfer the additional stake needed stake to the contract
            IERC20(eventDetails.paymentToken).safeTransferFrom(
                msg.sender,
                address(this),
                additionalStakeNeeded
            );

            // Update total stake
            s.stakedAmounts[_eventId] += additionalStakeNeeded;

            emit IExtendedERC20.Transfer(
                msg.sender,
                address(this),
                additionalStakeNeeded
            );
        }

        if (_category == LibTypes.PaidTicketCategory.REGULAR) {
            if (tickets.hasRegularTicket)
                revert LibErrors.RegularTicketsAlreadyCreated();
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
            return success_;
        } else if (_category == LibTypes.PaidTicketCategory.VIP) {
            if (tickets.hasVIPTicket)
                revert LibErrors.VIPTicketsAlreadyCreated();
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
            return success_;
        }
    }

    /**
     * @dev Purchase ticket using ERC20 tokens (stablecoin)
     * @param _eventId The ID of the event
     * @param _category The category of ticket to purchase
     */
    function purchaseTicket(
        uint256 _eventId,
        LibTypes.PaidTicketCategory _category
    ) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];
        if (s.hasRegistered[msg.sender][_eventId])
            revert LibErrors.AlreadyRegistered();
        if (eventDetails.endDate < block.timestamp)
            revert LibErrors.EventHasEnded();
        if (eventDetails.userRegCount >= eventDetails.expectedAttendees)
            revert LibErrors.RegistrationHasClosed();

        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];
        address ticketNFTAddr;
        uint256 requiredFee;

        if (eventDetails.ticketType == LibTypes.TicketType.FREE) {
            if (_category != LibTypes.PaidTicketCategory.NONE)
                revert LibErrors.FreeTicketForFreeEventOnly();
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

            // Transfer ERC20 tokens from buyer to contract
            if (requiredFee > 0) {
                IERC20(eventDetails.paymentToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    requiredFee
                );
            }
        }

        require(ticketNFTAddr != address(0), "Ticket contract not set");

        // Mint NFT ticket
        ITicket_NFT ticketContract = ITicket_NFT(ticketNFTAddr);
        ticketContract.safeMint(msg.sender);

        // Update event details
        eventDetails.userRegCount += 1;
        s.hasRegistered[msg.sender][_eventId] = true;

        // Update organizer revenue balance
        s.organiserRevBal[eventDetails.organiser][_eventId] += requiredFee;

        // Add buyer to attendance list for Merkle tree
        s.eventAttendees[_eventId].push(msg.sender);

        s.totalPurchasedTicket += 1;

        emit LibEvents.TicketPurchased(_eventId, msg.sender, requiredFee);
    }

    /**
     * @dev Verify attendance using Merkle proof
     * @param _eventId The ID of the event
     * @param _merkleProof Merkle proof verifying the caller's inclusion in the attendee list
     */
    function verifyAttendance(
        uint256 _eventId,
        bytes32[] calldata _merkleProof
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];

        // Validate event status
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert LibErrors.EventDoesNotExist();
        if (block.timestamp < eventDetails.startDate)
            revert LibErrors.EventNotStarted();

        // Check if already verified
        if (s.isVerified[msg.sender][_eventId])
            revert LibErrors.AlreadyVerified();

        // Check if user has a ticket
        if (!s.hasRegistered[msg.sender][_eventId])
            revert LibErrors.NotRegisteredForEvent();

        // Get the Merkle root for this event
        bytes32 merkleRoot = s.eventMerkleRoots[_eventId];
        require(merkleRoot != bytes32(0), "Merkle root not set for this event");

        // Create leaf node by hashing the address
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));

        // Verify the proof
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid Merkle proof"
        );

        // Mark attendee as verified
        s.isVerified[msg.sender][_eventId] = true;
        eventDetails.verifiedAttendeesCount += 1;

        emit LibEvents.AttendeeVerified(_eventId, msg.sender, block.timestamp);
    }

    /**
     * @dev Verify if an address is whitelisted for an event using Merkle proof
     * @param _eventId The ID of the event
     * @param _address The address to verify
     * @param _merkleProof Merkle proof for the address
     * @return True if address is whitelisted
     */
    function isAddressWhitelisted(
        uint256 _eventId,
        address _address,
        bytes32[] calldata _merkleProof
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        bytes32 merkleRoot = s.eventMerkleRoots[_eventId];
        if (merkleRoot == bytes32(0)) return false;

        bytes32 leaf = keccak256(abi.encodePacked(_address));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
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
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        if (!s.hasRegistered[_user][_eventId]) {
            return "NONE";
        }

        LibTypes.EventDetails storage eventDetails = s.events[_eventId];
        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

        if (eventDetails.ticketType == LibTypes.TicketType.FREE) {
            return "FREE";
        }

        // Check for VIP ticket
        if (tickets.hasVIPTicket && tickets.vipTicketNFT != address(0)) {
            try ITicket_NFT(tickets.vipTicketNFT).balanceOf(_user) returns (
                uint256 balance
            ) {
                if (balance > 0) {
                    return "VIP";
                }
            } catch {}
        }

        // Check for REGULAR ticket
        if (
            tickets.hasRegularTicket && tickets.regularTicketNFT != address(0)
        ) {
            try ITicket_NFT(tickets.regularTicketNFT).balanceOf(_user) returns (
                uint256 balance
            ) {
                if (balance > 0) {
                    return "REGULAR";
                }
            } catch {}
        }

        return "UNKNOWN";
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
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        LibTypes.TicketTypes storage tickets = s.eventTickets[_eventId];

        if (!tickets.hasVIPTicket || tickets.vipTicketNFT == address(0)) {
            return false;
        }

        try ITicket_NFT(tickets.vipTicketNFT).balanceOf(_user) returns (
            uint256 balance
        ) {
            return balance > 0;
        } catch {
            return false;
        }
    }

    /**
     * @dev Returns all ticket details for a user across events
     * @return eventIds Array of event IDs the user has tickets for
     * @return ticketLibTypes Array of ticket LibTypes (FREE, REGULAR, VIP) corresponding to each event
     * @return verified Array indicating if attendance was verified for each event
     */
    function getMyTickets()
        external
        view
        returns (
            uint256[] memory eventIds,
            string[] memory ticketLibTypes,
            bool[] memory verified
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
        ticketLibTypes = new string[](count);
        verified = new bool[](count);
        uint256 index = 0;

        // Second pass: populate arrays with ticket details
        for (uint256 i = 1; i <= s.totalEventOrganised; i++) {
            if (s.hasRegistered[msg.sender][i]) {
                eventIds[index] = i;
                verified[index] = s.isVerified[msg.sender][i];

                // Determine ticket type
                LibTypes.TicketTypes storage tickets = s.eventTickets[i];

                if (s.events[i].ticketType == LibTypes.TicketType.FREE) {
                    ticketLibTypes[index] = "FREE";
                } else {
                    // Check if user has VIP ticket
                    if (
                        tickets.hasVIPTicket &&
                        tickets.vipTicketNFT != address(0)
                    ) {
                        try
                            ITicket_NFT(tickets.vipTicketNFT).balanceOf(
                                msg.sender
                            )
                        returns (uint256 balance) {
                            if (balance > 0) {
                                ticketLibTypes[index] = "VIP";
                                index++;
                                continue;
                            }
                        } catch {}
                    }

                    // Check if user has REGULAR ticket
                    if (
                        tickets.hasRegularTicket &&
                        tickets.regularTicketNFT != address(0)
                    ) {
                        try
                            ITicket_NFT(tickets.regularTicketNFT).balanceOf(
                                msg.sender
                            )
                        returns (uint256 balance) {
                            if (balance > 0) {
                                ticketLibTypes[index] = "REGULAR";
                                index++;
                                continue;
                            }
                        } catch {}
                    }

                    // If we couldn't determine the exact type but user is registered
                    ticketLibTypes[index] = "UNKNOWN";
                }

                index++;
            }
        }

        return (eventIds, ticketLibTypes, verified);
    }

    /**
     * @dev Calculate required stake based on organizer reputation and event details
     * @param _organiser The address of the event organizer
     * @param _expectedAttendees Expected number of attendees
     * @param _ticketType Type of event (FREE or PAID)
     * @param _estimatedTicketFee Estimated ticket fee (0 for FREE events)
     * @return Required stake amount
     */
    function calculateRequiredStake(
        address _organiser,
        uint256 _expectedAttendees,
        LibTypes.TicketType _ticketType,
        uint256 _estimatedTicketFee
    ) public view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        // Free events have no stake requirement
        if (_ticketType == LibTypes.TicketType.FREE) {
            return 0;
        }

        // For paid events, calculate stake based on expected revenue
        uint256 expectedRevenue = _expectedAttendees * _estimatedTicketFee;
        uint256 baseStakePercentage = LibConstants.STAKE_PERCENTAGE;

        // Apply penalties for new organizers or those with scam history
        if (s.organizerSuccessfulEvents[_organiser] == 0) {
            baseStakePercentage += LibConstants.NEW_ORGANIZER_PENALTY;
        }

        // Apply discounts for organizers with good reputation
        uint256 successEvents = s.organizerSuccessfulEvents[_organiser];
        uint256 reputationDiscount = 0;

        if (successEvents > 0) {
            reputationDiscount =
                successEvents *
                LibConstants.REPUTATION_DISCOUNT_FACTOR;
            if (reputationDiscount > LibConstants.MAX_REPUTATION_DISCOUNT) {
                reputationDiscount = LibConstants.MAX_REPUTATION_DISCOUNT;
            }
        }

        // Calculate final stake percentage (ensure it doesn't go below minimum)
        uint256 finalStakePercentage = 0;
        if (baseStakePercentage > reputationDiscount) {
            finalStakePercentage = baseStakePercentage - reputationDiscount;
        } else {
            finalStakePercentage = 5; // Minimum 5% stake even for best organizers
        }

        return (expectedRevenue * finalStakePercentage) / 100;
    }

  
}
