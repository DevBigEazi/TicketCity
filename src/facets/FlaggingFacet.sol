// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibConstants.sol";
import "../libraries/LibEvents.sol";
import "../libraries/Types.sol";
import "../libraries/Errors.sol";
import "../interfaces/ITicket_NFT.sol";
import "../libraries/LibDiamond.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FlaggingFacet
 * @dev Handles event flagging, dispute resolution, and reputation management
 */
contract FlaggingFacet is ReentrancyGuard {
    using LibAppStorage for LibAppStorage.AppStorage;
    using Types for *;
    using Errors for *;

    /**
     * @dev Calculate reputation factor for flag weighting
     * @param _user The address of the user
     * @return A factor between 1 and 5 based on reputation
     */
    function _calculateReputationFactor(
        address _user
    ) internal view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        int256 reputation = s.userReputationScores[_user];

        // Scale reputation from -100..100 to 1..5
        if (reputation <= -80) return 1;
        if (reputation <= -40) return 2;
        if (reputation <= 40) return 3;
        if (reputation <= 80) return 4;
        return 5;
    }

    /**
     * @dev Get total flag weight for an event (accounting for ticket type and reputation)
     * @param _eventId The ID of the event
     * @return totalWeight The total weighted flags for the event
     * @return maximumWeight The maximum possible weight if all users flagged
     */
    function getTotalFlagWeight(
        uint256 _eventId
    ) public view returns (uint256 totalWeight, uint256 maximumWeight) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        address[] memory allAttendees = _getEventAttendees(_eventId);

        totalWeight = 0;
        maximumWeight = 0;

        for (uint256 i = 0; i < allAttendees.length; i++) {
            address attendee = allAttendees[i];

            // Calculate maximum possible weight for this attendee
            uint256 maxWeightForUser = _getUserFlagWeight(attendee, _eventId);
            maximumWeight += maxWeightForUser;

            // Add actual weight if user flagged
            if (s.hasFlaggerdEvent[attendee][_eventId]) {
                totalWeight += maxWeightForUser;
            }
        }

        return (totalWeight, maximumWeight);
    }

    /**
     * @dev Helper to get all attendees for an event
     * @param _eventId The ID of the event
     * @return Array of attendee addresses
     */
    function _getEventAttendees(
        uint256 _eventId
    ) internal view returns (address[] memory) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];
        uint256 count = eventDetails.userRegCount;

        // This is a simplified implementation - in production, you'd need
        // to track attendees in a more efficient way
        address[] memory attendees = new address[](count);

        // Placeholder logic - actual implementation would need a more efficient storage method
        // This is conceptual and would be replaced with proper tracking
        for (uint256 i = 0; i < s.allEvents.length; i++) {
            // In a real implementation, we'd have a mapping from eventId to attendee addresses
            // This is just a demonstration of the concept
        }

        return attendees;
    }

    /**
     * @dev Calculate flag weight for a specific user on a specific event
     * @param _user The address of the user
     * @param _eventId The ID of the event
     * @return Weight based on ticket type and reputation
     */
    function _getUserFlagWeight(
        address _user,
        uint256 _eventId
    ) internal view returns (uint256) {
        string memory ticketType = getUserTicketType(_user, _eventId);
        uint256 baseWeight = 1;

        // Adjust weight based on ticket type
        if (
            keccak256(abi.encodePacked(ticketType)) ==
            keccak256(abi.encodePacked("VIP"))
        ) {
            baseWeight = 3;
        } else if (
            keccak256(abi.encodePacked(ticketType)) ==
            keccak256(abi.encodePacked("REGULAR"))
        ) {
            baseWeight = 2;
        }

        // Multiply by reputation factor (normalized to range 1-5)
        uint256 reputationFactor = _calculateReputationFactor(_user);
        return baseWeight * reputationFactor;
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

        Types.EventDetails storage eventDetails = s.events[_eventId];
        Types.TicketTypes storage tickets = s.eventTickets[_eventId];

        if (eventDetails.ticketType == Types.TicketType.FREE) {
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
     * @dev Flag an event with detailed reason and evidence, requires stake
     * @param _eventId The ID of the event to flag
     * @param _reason The reason code for flagging
     * @param _evidence String with evidence or explanation
     */
    function flagEventWithEvidence(
        uint256 _eventId,
        uint8 _reason,
        string calldata _evidence
    ) external payable nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Basic validation
        require(
            _eventId > 0 && _eventId <= s.totalEventOrganised,
            "Event does not exist"
        );
        require(
            block.timestamp > eventDetails.endDate,
            "Event has not ended yet"
        );
        require(
            block.timestamp <=
                eventDetails.endDate + LibConstants.WAITING_PERIOD,
            "Flagging period has ended"
        );
        require(
            s.hasRegistered[msg.sender][_eventId],
            "Not a ticket buyer for this event"
        );
        require(
            !s.hasFlaggerdEvent[msg.sender][_eventId],
            "Already flagged this event"
        );

        // Require stake and attendance verification
        require(
            msg.value >= LibConstants.MINIMUM_FLAG_STAKE,
            "Insufficient stake to flag event"
        );
        require(
            s.isVerified[msg.sender][_eventId],
            "Only verified attendees can flag"
        );

        // Validate reason code
        require(
            _reason <= uint8(Types.FlagReason.Other),
            "Invalid reason code"
        );

        // Store flag data
        Types.FlagData storage newFlag = s.flagData[msg.sender][_eventId];
        newFlag.reason = Types.FlagReason(_reason);
        newFlag.evidence = _evidence;
        newFlag.timestamp = block.timestamp;
        newFlag.stake = msg.value;

        // Store stake amount
        s.flaggingStakes[msg.sender][_eventId] = msg.value;

        // Add to event flaggers list
        s.eventFlaggers[_eventId].push(msg.sender);

        // Mark as flagged
        s.hasFlaggerdEvent[msg.sender][_eventId] = true;

        // Calculate and add weighted flag
        uint256 weight = _getUserFlagWeight(msg.sender, _eventId);
        s.flaggingWeight[msg.sender][_eventId] = weight;
        s.totalFlagsCount[_eventId] += weight;

        // Add stake to compensation pool
        s.compensationPool[_eventId] += msg.value;

        emit LibEvents.DetailedEventFlagged(
            _eventId,
            msg.sender,
            _reason,
            _evidence,
            msg.value
        );
        emit LibEvents.EventFlagged(
            _eventId,
            msg.sender,
            block.timestamp,
            weight
        );
    }

    /**
     * @dev Allows a user to flag an event as invalid or scam with weighted flagging
     * @param _eventId The ID of the event to flag
     */
    function flagEvent(uint256 _eventId) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Check if event exists and has ended
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();
        if (block.timestamp <= eventDetails.endDate)
            revert("Event has not ended yet");

        // Check if flagging period has ended
        if (
            block.timestamp > eventDetails.endDate + LibConstants.WAITING_PERIOD
        ) revert("Flagging period has ended");

        // Check if user is a ticket buyer
        if (!s.hasRegistered[msg.sender][_eventId])
            revert("Not a ticket buyer for this event");

        // Check if user has already flagged
        if (s.hasFlaggerdEvent[msg.sender][_eventId])
            revert("Already flagged this event");

        // Determine flag weight based on ticket type
        uint256 weight = 1; // Default weight

        string memory ticketType = getUserTicketType(msg.sender, _eventId);

        if (
            keccak256(abi.encodePacked(ticketType)) ==
            keccak256(abi.encodePacked("VIP"))
        ) {
            weight = 3; // VIP tickets have 3x weight
        } else if (
            keccak256(abi.encodePacked(ticketType)) ==
            keccak256(abi.encodePacked("REGULAR"))
        ) {
            weight = 1; // Regular tickets have standard weight
        } else if (
            keccak256(abi.encodePacked(ticketType)) ==
            keccak256(abi.encodePacked("FREE"))
        ) {
            weight = 1; // Free tickets have standard weight
        }

        // Mark as flagged and increment count with weight
        s.hasFlaggerdEvent[msg.sender][_eventId] = true;
        s.flaggingWeight[msg.sender][_eventId] = weight;
        s.totalFlagsCount[_eventId] += weight;

        emit LibEvents.EventFlagged(
            _eventId,
            msg.sender,
            block.timestamp,
            weight
        );
    }

    /**
     * @dev Initiate dispute resolution process
     * @param _eventId The ID of the event
     * @param _evidence Evidence provided by organizer
     */
    function initiateDispute(
        uint256 _eventId,
        string calldata _evidence
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Validation
        require(
            msg.sender == eventDetails.organiser,
            "Only event organizer can dispute"
        );
        require(s.totalFlagsCount[_eventId] > 0, "No flags to dispute");
        require(!s.eventDisputed[_eventId], "Already disputed");
        require(
            block.timestamp <=
                eventDetails.endDate +
                    LibConstants.WAITING_PERIOD +
                    LibConstants.DISPUTE_PERIOD,
            "Dispute period has ended"
        );

        // Mark as disputed
        s.eventDisputed[_eventId] = true;
        s.disputeEvidence[_eventId] = _evidence;

        // Initialize dispute resolution
        Types.DisputeResolution storage resolution = s.disputeResolutions[
            _eventId
        ];
        resolution.inProgress = true;
        resolution.resolved = false;
        resolution.currentTier = 1; // Start with algorithm-based resolution
        resolution.organizerEvidence = _evidence;

        emit LibEvents.EventDisputed(_eventId, msg.sender, _evidence);
        emit LibEvents.DisputeInitiated(_eventId, msg.sender, 1);

        // Immediately process first tier resolution
        _resolveDisputeTier1(_eventId);
    }

    /**
     * @dev Algorithm-based first tier dispute resolution
     * @param _eventId The ID of the event
     */
    function _resolveDisputeTier1(uint256 _eventId) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];
        Types.DisputeResolution storage resolution = s.disputeResolutions[
            _eventId
        ];

        // Get flag weight data
        (uint256 totalWeight, uint256 maximumWeight) = getTotalFlagWeight(
            _eventId
        );

        // Calculate percentage of weighted flags
        uint256 flagPercentage = (totalWeight * 100) / maximumWeight;

        // Check attendance rate
        uint256 attendanceRate = 0;
        if (eventDetails.userRegCount > 0) {
            attendanceRate =
                (eventDetails.verifiedAttendeesCount * 100) /
                eventDetails.userRegCount;
        }

        // Automatic resolution based on algorithms:
        // 1. If very high attendance rate and moderate flags, favor organizer
        // 2. If very low attendance rate and high flags, favor flaggers
        // 3. Otherwise, escalate to tier 2

        if (attendanceRate >= 85 && flagPercentage < 70) {
            // Strong evidence event was legitimate
            _resolveInFavorOfOrganizer(_eventId);
            resolution.currentTier = 1;
            resolution.resolved = true;
            emit LibEvents.DisputeResolved(_eventId, true, 1);
        } else if (attendanceRate < 30 && flagPercentage >= 75) {
            // Strong evidence event was fraudulent
            _resolveInFavorOfFlaggers(_eventId);
            resolution.currentTier = 1;
            resolution.resolved = true;
            emit LibEvents.DisputeResolved(_eventId, false, 1);
        } else {
            // Escalate to tier 2
            resolution.currentTier = 2;
            _selectJury(_eventId);
        }
    }

    /**
     * @dev Select jury members for tier 2 dispute resolution
     * @param _eventId The ID of the event
     */
    function _selectJury(uint256 _eventId) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.DisputeResolution storage resolution = s.disputeResolutions[
            _eventId
        ];

        // Initialize jury array
        address[] memory jury = new address[](LibConstants.JURY_SIZE);

        // In a real implementation, this would select from a pool of eligible jurors
        // For this demonstration, we're using a simplified approach

        // Selecting jury members would ideally use a more sophisticated method
        // such as random selection from verified attendees of other events
        // who have good reputation scores

        // This is a placeholder for jury selection logic
        uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    _eventId,
                    LibConstants.JURY_SELECTION_SEED
                )
            )
        );

        // Store jury members
        resolution.juryMembers = jury;

        emit LibEvents.JurySelected(_eventId, jury);
    }

    /**
     * @dev Submit jury vote for dispute resolution
     * @param _eventId The ID of the event
     * @param _supportOrganizer Whether the juror supports the organizer
     */
    function submitJuryVote(uint256 _eventId, bool _supportOrganizer) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.DisputeResolution storage resolution = s.disputeResolutions[
            _eventId
        ];

        // Validate juror
        bool isJuror = false;
        for (uint256 i = 0; i < resolution.juryMembers.length; i++) {
            if (resolution.juryMembers[i] == msg.sender) {
                isJuror = true;
                break;
            }
        }
        require(isJuror, "Not a selected juror for this dispute");

        // Check if already voted
        require(!resolution.juryVotes[msg.sender], "Juror already voted");

        // Record vote
        resolution.juryVotes[msg.sender] = true;

        if (_supportOrganizer) {
            resolution.positiveVotes++;
        } else {
            resolution.negativeVotes++;
        }

        emit LibEvents.JuryVoteSubmitted(
            _eventId,
            msg.sender,
            _supportOrganizer
        );

        // Check if voting is complete
        uint256 totalVotes = resolution.positiveVotes +
            resolution.negativeVotes;
        if (totalVotes == LibConstants.JURY_SIZE) {
            _finalizeJuryVoting(_eventId);
        }
    }

    /**
     * @dev Finalize jury voting and determine outcome
     * @param _eventId The ID of the event
     */
    function _finalizeJuryVoting(uint256 _eventId) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.DisputeResolution storage resolution = s.disputeResolutions[
            _eventId
        ];

        // Calculate percentage of positive votes (in favor of organizer)
        uint256 positivePercentage = (resolution.positiveVotes * 100) /
            LibConstants.JURY_SIZE;

        if (positivePercentage >= LibConstants.DISPUTE_RESOLUTION_THRESHOLD) {
            // Majority supports organizer
            _resolveInFavorOfOrganizer(_eventId);
            resolution.resolved = true;
            emit LibEvents.DisputeResolved(_eventId, true, 2);
        } else {
            // Majority supports flaggers
            _resolveInFavorOfFlaggers(_eventId);
            resolution.resolved = true;
            emit LibEvents.DisputeResolved(_eventId, false, 2);
        }

        resolution.resolutionTimestamp = block.timestamp;
    }

    /**
     * @dev Resolve dispute in favor of organizer
     * @param _eventId The ID of the event
     */
    function _resolveInFavorOfOrganizer(uint256 _eventId) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Return stakes to event organizer
        uint256 totalCompensation = s.compensationPool[_eventId];
        s.compensationPool[_eventId] = 0;

        if (totalCompensation > 0) {
            (bool success, ) = eventDetails.organiser.call{
                value: totalCompensation
            }("");
            require(success, "Failed to return compensation to organizer");
        }

        // Penalize false flaggers and adjust reputation
        address[] memory flaggers = s.eventFlaggers[_eventId];
        for (uint256 i = 0; i < flaggers.length; i++) {
            address flagger = flaggers[i];

            // Reduce reputation score for false flagging
            _adjustReputation(
                flagger,
                int256(LibConstants.REPUTATION_CHANGE_BASE * 2)
            );

            emit LibEvents.FalseFlaggerPenalized(
                _eventId,
                flagger,
                s.flaggingStakes[flagger][_eventId]
            );
        }

        // Increase organizer reputation
        _adjustReputation(
            eventDetails.organiser,
            int256(LibConstants.REPUTATION_CHANGE_BASE * 3)
        );

        // Make revenue available for release
        // (we don't call releaseRevenue directly to avoid reentrancy concerns)
    }

    /**
     * @dev Resolve dispute in favor of flaggers
     * @param _eventId The ID of the event
     */
    function _resolveInFavorOfFlaggers(uint256 _eventId) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Return stakes to flaggers and increase their reputation
        address[] memory flaggers = s.eventFlaggers[_eventId];
        for (uint256 i = 0; i < flaggers.length; i++) {
            address flagger = flaggers[i];
            uint256 stake = s.flaggingStakes[flagger][_eventId];

            // Return stake and add bonus from organizer stake
            uint256 totalCompensation = stake;

            // Return stake to flagger
            if (totalCompensation > 0) {
                (bool success, ) = flagger.call{value: totalCompensation}("");
                if (success) {
                    // Successfully returned stake
                    s.hasClaimed[flagger][_eventId] = true;
                }
            }

            // Increase reputation for valid flagging
            _adjustReputation(
                flagger,
                int256(LibConstants.REPUTATION_CHANGE_BASE)
            );
        }

        // Add this to organizer's scam event count
        s.organizerScammedEvents[eventDetails.organiser]++;

        // Decrease organizer reputation significantly
        _adjustReputation(
            eventDetails.organiser,
            -int256(LibConstants.REPUTATION_CHANGE_BASE * 5)
        );

        // Check if organizer should be blacklisted
        if (
            s.organizerScammedEvents[eventDetails.organiser] >
            LibConstants.MAX_ALLOWED_SCAM_EVENTS
        ) {
            s.blacklistedOrganizers[eventDetails.organiser] = true;
            emit LibEvents.OrganizerBlacklisted(
                eventDetails.organiser,
                block.timestamp
            );
        }

        // Process refunds to attendees
        // This would typically call a helper function to process refunds
    }

    /**
     * @dev Adjust user reputation score within bounds
     * @param _user The address of the user
     * @param _change The change to apply (positive or negative)
     */
    function _adjustReputation(address _user, int256 _change) internal {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        int256 currentScore = s.userReputationScores[_user];
        int256 newScore = currentScore + _change;

        // Ensure score stays within bounds
        if (newScore < LibConstants.MIN_REPUTATION_SCORE) {
            newScore = LibConstants.MIN_REPUTATION_SCORE;
        } else if (newScore > LibConstants.MAX_REPUTATION_SCORE) {
            newScore = LibConstants.MAX_REPUTATION_SCORE;
        }

        s.userReputationScores[_user] = newScore;

        emit LibEvents.ReputationChanged(_user, newScore, _change);
    }

    /**
     * @dev Allow user to claim compensation or refund after dispute resolution
     * @param _eventId The ID of the event
     */
    function claimCompensation(uint256 _eventId) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        require(
            !s.hasClaimed[msg.sender][_eventId],
            "Already claimed compensation"
        );

        Types.DisputeResolution storage resolution = s.disputeResolutions[
            _eventId
        ];
        require(resolution.resolved, "Dispute not resolved yet");
        require(
            block.timestamp <=
                resolution.resolutionTimestamp + LibConstants.CLAIM_PERIOD,
            "Claim period has ended"
        );

        // Different logic based on whether user is a flagger or regular attendee
        if (s.hasFlaggerdEvent[msg.sender][_eventId]) {
            // Check if resolution was in favor of flaggers
            if (resolution.positiveVotes < resolution.negativeVotes) {
                // Calculate compensation (original stake + share of organizer's stake)
                uint256 stake = s.flaggingStakes[msg.sender][_eventId];
                uint256 organizerStake = s.stakedAmounts[_eventId];
                uint256 flaggersCount = s.eventFlaggers[_eventId].length;

                uint256 bonusShare = 0;
                if (flaggersCount > 0) {
                    bonusShare = organizerStake / flaggersCount;
                }

                uint256 totalCompensation = stake + bonusShare;

                // Process payment
                if (totalCompensation > 0) {
                    (bool success, ) = msg.sender.call{
                        value: totalCompensation
                    }("");
                    require(success, "Failed to send compensation");

                    emit LibEvents.CompensationClaimed(
                        _eventId,
                        msg.sender,
                        totalCompensation
                    );
                    s.hasClaimed[msg.sender][_eventId] = true;
                }
            }
        } else if (s.hasRegistered[msg.sender][_eventId]) {
            // Regular attendee claiming refund
            // Check if resolution was in favor of flaggers
            if (resolution.positiveVotes < resolution.negativeVotes) {
                // Calculate refund based on ticket type
                uint256 refundAmount = 0;

                string memory ticketType = getUserTicketType(
                    msg.sender,
                    _eventId
                );
                Types.TicketTypes storage tickets = s.eventTickets[_eventId];

                if (
                    keccak256(abi.encodePacked(ticketType)) ==
                    keccak256(abi.encodePacked("VIP"))
                ) {
                    refundAmount = tickets.vipTicketFee;
                } else if (
                    keccak256(abi.encodePacked(ticketType)) ==
                    keccak256(abi.encodePacked("REGULAR"))
                ) {
                    refundAmount = tickets.regularTicketFee;
                }

                // Process refund
                if (refundAmount > 0) {
                    (bool success, ) = msg.sender.call{value: refundAmount}("");
                    if (success) {
                        emit LibEvents.RefundProcessed(
                            _eventId,
                            msg.sender,
                            refundAmount
                        );
                        s.hasClaimed[msg.sender][_eventId] = true;
                    }
                }
            }
        }
    }

    /**
     * @dev Check if an event has been successfully flagged as fraudulent
     * @param _eventId The ID of the event
     * @return isFraudulent Whether the event is considered fraudulent
     */
    function isEventFraudulent(
        uint256 _eventId
    ) public view returns (bool isFraudulent) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.DisputeResolution storage resolution = s.disputeResolutions[
            _eventId
        ];

        // If dispute is resolved, check the outcome
        if (resolution.resolved) {
            // More negative votes means fraudulent
            return resolution.negativeVotes > resolution.positiveVotes;
        }

        // If dispute period has ended without resolution, check flag weight
        if (
            block.timestamp >
            s.events[_eventId].endDate +
                LibConstants.WAITING_PERIOD +
                LibConstants.DISPUTE_PERIOD
        ) {
            (uint256 totalWeight, uint256 maximumWeight) = getTotalFlagWeight(
                _eventId
            );

            // If flagging threshold was met and no dispute was filed, consider it fraudulent
            if (maximumWeight > 0) {
                uint256 flagPercentage = (totalWeight * 100) / maximumWeight;
                return flagPercentage >= LibConstants.FLAGGING_THRESHOLD;
            }
        }

        return false;
    }

    /**
     * @dev Return the current flagging threshold based on time elapsed since event end
     * @param _eventId The ID of the event
     * @return Current threshold percentage required for flagging
     */
    function getFlaggingThreshold(
        uint256 _eventId
    ) public view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Time since event ended
        uint256 timeElapsed = block.timestamp - eventDetails.endDate;

        // Require more flags as time passes (harder to scam flag)
        if (timeElapsed < 1 days) {
            return 70; // 70% threshold in first day
        } else if (timeElapsed < 3 days) {
            return 75; // 75% threshold between 1-3 days
        } else {
            return LibConstants.FLAGGING_THRESHOLD; // Default 80% after 3 days
        }
    }

    /**
     * @dev Allows organizers to dispute flagging with evidence
     * @param _eventId The ID of the event
     * @param _evidence String containing dispute evidence/explanation
     */
    function disputeFlags(
        uint256 _eventId,
        string calldata _evidence
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();

        require(
            msg.sender == s.events[_eventId].organiser,
            "Not event organizer"
        );
        require(s.totalFlagsCount[_eventId] > 0, "No flags to dispute");
        require(!s.eventDisputed[_eventId], "Already disputed");

        s.eventDisputed[_eventId] = true;
        s.disputeEvidence[_eventId] = _evidence;

        emit LibEvents.EventDisputed(_eventId, msg.sender, _evidence);
    }

    /**
     * @dev Process refunds for a flagged event
     * @param _eventId The ID of the event to process refunds for
     * @param _buyers Array of buyer addresses to refund
     */
    function processRefunds(
        uint256 _eventId,
        address[] calldata _buyers
    ) external nonReentrant {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Verify event and flagging status
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();

        // Get current flagging threshold based on time elapsed
        uint256 currentThreshold = getFlaggingThreshold(_eventId);

        // Check if flagging threshold is met
        uint256 flagPercentage = (s.totalFlagsCount[_eventId] * 100) /
            eventDetails.userRegCount;
        require(
            flagPercentage >= currentThreshold,
            "Flagging threshold not met"
        );

        // Only contract owner or event organizer can process refunds
        require(
            msg.sender == s.owner || msg.sender == eventDetails.organiser,
            "Only owner or organizer can process refunds"
        );

        // Check if revenue was already released
        require(!s.revenueReleased[_eventId], "Revenue already released");

        // Process refunds for each buyer
        for (uint256 i = 0; i < _buyers.length; i++) {
            address buyer = _buyers[i];

            // Verify buyer status
            if (!s.hasRegistered[buyer][_eventId]) continue;

            // Determine refund amount based on ticket type
            uint256 refundAmount = 0;
            Types.TicketTypes storage tickets = s.eventTickets[_eventId];

            if (eventDetails.ticketType == Types.TicketType.PAID) {
                // Check for VIP ticket
                if (hasVIPTicket(buyer, _eventId)) {
                    refundAmount = tickets.vipTicketFee;
                } else {
                    // Check for Regular ticket
                    try
                        ITicket_NFT(tickets.regularTicketNFT).balanceOf(buyer)
                    returns (uint256 balance) {
                        if (balance > 0) {
                            refundAmount = tickets.regularTicketFee;
                        }
                    } catch {}
                }
            }

            // Skip if no refund to process
            if (refundAmount == 0) continue;

            // Process refund from revenue or staked amount
            uint256 revenueBalance = s.organiserRevBal[eventDetails.organiser][
                _eventId
            ];

            if (refundAmount <= revenueBalance) {
                // Refund from revenue
                s.organiserRevBal[eventDetails.organiser][
                    _eventId
                ] -= refundAmount;
            } else {
                // If revenue isn't enough, use staked amount (for paid events)
                uint256 availableStake = s.stakedAmounts[_eventId];
                if (availableStake >= refundAmount) {
                    s.stakedAmounts[_eventId] -= refundAmount;
                } else {
                    // Not enough funds to refund fully
                    refundAmount = availableStake;
                    s.stakedAmounts[_eventId] = 0;
                }
            }

            // Send refund to buyer
            if (refundAmount > 0) {
                (bool success, ) = buyer.call{value: refundAmount}("");
                if (success) {
                    emit LibEvents.RefundProcessed(
                        _eventId,
                        buyer,
                        refundAmount
                    );
                }
            }
        }

        // Penalize organizer by incrementing scam count
        s.organizerScammedEvents[eventDetails.organiser]++;
        emit LibEvents.ReputationChanged(
            eventDetails.organiser,
            int256(s.organizerSuccessfulEvents[eventDetails.organiser]),
            int256(s.organizerScammedEvents[eventDetails.organiser])
        );
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
        Types.TicketTypes storage tickets = s.eventTickets[_eventId];

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
     * @dev Enhanced attendance verification with proof
     * @param _eventId The ID of the event
     * @param _proof Cryptographic proof of attendance (can be expanded based on needs)
     */
    function verifyAttendanceWithProof(
        uint256 _eventId,
        bytes memory _proof
    ) external {
        LibAppStorage.AppStorage storage s = LibDiamond.appStorage();
        Types.EventDetails storage eventDetails = s.events[_eventId];

        // Validate if event exist or has started
        if (_eventId == 0 || _eventId > s.totalEventOrganised)
            revert Errors.EventDoesNotExist();
        if (block.timestamp < eventDetails.startDate)
            revert Errors.EventNotStarted();

        // Check if attendee is registered
        if (!s.hasRegistered[msg.sender][_eventId])
            revert Errors.NotRegisteredForEvent();

        // Check if already verified
        if (s.isVerified[msg.sender][_eventId]) revert Errors.AlreadyVerified();

        // Validate proof
        require(_proof.length > 0, "Empty proof provided");

        // Store proof for future reference
        s.attendanceProofs[msg.sender][_eventId] = _proof;

        // Mark attendee as verified
        s.isVerified[msg.sender][_eventId] = true;
        eventDetails.verifiedAttendeesCount += 1;

        // Record verification time
        s.verificationTimes[_eventId] = block.timestamp;

        emit LibEvents.AttendeeVerified(_eventId, msg.sender, block.timestamp);
    }
}
