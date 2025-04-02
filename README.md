# Ticket City Platform Documentation

## Overview

Ticket City is a decentralized ticketing platform built on blockchain technology that aims to solve common problems in the event ticketing industry such as fraud, scalping, and lack of transparency. The platform leverages smart contracts to create a trustless environment where event organizers and attendees can interact with confidence.

The platform has been implemented using the Diamond Proxy pattern for enhanced modularity, upgradeability, and gas efficiency.

## Core Features

### Event Management

- **Event Creation**: Organizers can create events with details including title, description, image, location, start/end dates, and expected attendance.
- **Ticket Types**: Support for different ticket categories (FREE, REGULAR, VIP) with varying price points.
- **Revenue Management**: Automated release of revenue to organizers after successful events.

### Trust & Security Mechanisms

- **Staking System**: Event organizers stake a percentage of expected revenue as collateral, with the amount varying based on organizer reputation.
- **Attendance Verification**: Attendees verify their attendance using cryptographic proofs, ensuring event quality metrics.
- **Flagging System**: Weighted mechanism for attendees to flag fraudulent events with evidence.
- **Dispute Resolution**: Multi-tiered dispute resolution process with algorithmic first-pass and jury system for complex cases.
- **Reputation System**: Dynamic reputation scores for both organizers and attendees based on their behavior.

### Advanced Anti-Fraud Measures

- **Organizer Blacklisting**: Automatic blacklisting of organizers who exceed the maximum allowed scam events.
- **Weighted Flagging**: Higher weight given to VIP ticket holders and users with good reputation when flagging.
- **Evidence-Based Disputes**: Organizers can provide evidence to contest flags against their events.
- **Time-Dependent Thresholds**: Flagging thresholds adjust over time after an event ends.

## Architecture Overview

The project has been converted to use the Diamond Proxy pattern, which provides several advantages:

- **Modularity**: Functionality is separated into logical facets
- **Upgradeability**: Individual facets can be upgraded without affecting the entire system
- **Gas Efficiency**: Only deployed facets contribute to contract size
- **Storage Management**: Shared storage layout across all facets

### Diamond Pattern Implementation

The Ticket City platform uses the Diamond Standard (EIP-2535) with the following components:

1. **Diamond Proxy**: The main entry point that delegates calls to the appropriate facets
2. **Facets**: Specialized modules that implement specific functionalities
3. **Diamond Storage**: Shared storage pattern across all facets
4. **Diamond Loupe**: Functionality to introspect the diamond

### Core Facets

The platform's functionality is distributed across several facets:

1. **EventFacet**: Handles event creation and management
2. **TicketFacet**: Manages ticket creation, types, and purchasing
3. **AttendanceFacet**: Controls attendance verification
4. **RevenueFacet**: Manages revenue release rules and processes
5. **FlaggingFacet**: Implements the event flagging system
6. **DisputeFacet**: Handles the dispute resolution process
7. **ReputationFacet**: Manages user reputation scores
8. **AdminFacet**: Admin-only functions for platform management

## Key Components In Detail

### Event System

Events in Ticket City are created by organizers who define parameters such as:

- Event title, description, and image URI
- Physical location
- Start and end dates
- Expected number of attendees
- Ticket type (FREE or PAID)

For PAID events, organizers must stake a percentage of expected revenue as collateral. This stake amount varies based on the organizer's reputation score and past performance.

```solidity
function createEvent(
    string memory _title,
    string memory _desc,
    string memory _imageUri,
    string memory _location,
    uint256 _startDate,
    uint256 _endDate,
    uint256 _expectedAttendees,
    Types.TicketType _ticketType
) external payable returns (uint256)
```

### Ticketing System

Once an event is created, organizers can define different ticket types:

- **FREE tickets**: No cost to attendees
- **REGULAR tickets**: Standard paid admission
- **VIP tickets**: Premium paid admission at a higher price point

Each ticket is represented as an NFT, providing verifiable ownership and preventing duplication.

```solidity
function createTicket(
    uint256 _eventId,
    Types.PaidTicketCategory _category,
    uint256 _ticketFee,
    string memory _ticketUri
) external payable
```

### Staking & Reputation System

The platform implements a dynamic staking requirement based on organizer reputation:

- New organizers are required to stake a higher percentage of expected revenue
- Successful events reduce future staking requirements
- Failed or fraudulent events increase staking requirements
- Reputation scores range from -100 to 100

The staking system serves as economic collateral that can be used for refunds if an event is determined to be fraudulent.

### Flagging & Dispute Resolution

The platform implements a sophisticated system to handle disputes:

#### Flagging System

Attendees can flag events as fraudulent after they end, with several mechanisms to ensure fairness:

- Flags are weighted based on ticket type (VIP > REGULAR > FREE)
- User reputation impacts flag weight
- Flagging requires a minimum stake
- Evidence must be provided when flagging

```solidity
function flagEventWithEvidence(
    uint256 _eventId,
    uint8 _reason,
    string calldata _evidence
) external payable nonReentrant
```

#### Dispute Resolution

A two-tiered dispute resolution process:

1. **Algorithm-based resolution**: Uses data points like attendance rate and flag percentage to automatically resolve simple cases
2. **Jury system**: For complex cases, a jury of reputable users votes on the outcome

```solidity
function _resolveDisputeTier1(uint256 _eventId) internal
function _finalizeJuryVoting(uint256 _eventId) internal
```

### Revenue Management

Revenue from ticket sales is held in escrow until the event concludes successfully. Release criteria include:

- Event has ended
- Minimum attendance rate has been met (60% by default)
- Flagging threshold has not been met
- Waiting period has passed (if attendance was below threshold)

```solidity
function releaseRevenue(uint256 _eventId) external nonReentrant
```

### Attendance Verification

Attendees must verify their attendance with cryptographic proof:

```solidity
function verifyAttendanceWithProof(
    uint256 _eventId,
    bytes memory _proof
) external
```

The attendance rate is critical for:
- Determining event success
- Affecting organizer reputation
- Factoring into dispute resolution

## Platform Constants

The platform behavior is governed by several constants that can be adjusted by governance:

- `MINIMUM_ATTENDANCE_RATE`: 60% default
- `FLAGGING_THRESHOLD`: 80% default
- `WAITING_PERIOD`: 7 days after event ends
- `STAKE_PERCENTAGE`: 30% of expected revenue
- `MAX_ALLOWED_SCAM_EVENTS`: 1 event before blacklisting
- `MINIMUM_FLAG_STAKE`: 0.01 ETH
- `DISPUTE_PERIOD`: 3 days
- `JURY_SIZE`: 5 members
- `DISPUTE_RESOLUTION_THRESHOLD`: 60% majority
- `CLAIM_PERIOD`: 30 days
- Various reputation modifiers for different actions

## User Interaction Flow

### For Event Organizers

1. **Create an event** by providing details and paying an initial stake
2. **Create ticket types** for the event (FREE, REGULAR, VIP)
3. **Monitor attendance** as the event progresses
4. **Verify attendees** at the venue
5. **Release revenue** after the event concludes successfully or dispute flags if necessary

### For Attendees

1. **Purchase tickets** for desired events
2. **Attend the event** and get verified
3. **Flag events** if they were fraudulent or didn't deliver as promised
4. **Participate in disputes** either as a flagger or jury member
5. **Claim refunds or compensation** if eligible

## Upgrade Considerations

Since the system has been converted to the Diamond Proxy pattern, the following upgrade considerations apply:

1. New facets can be added to extend functionality
2. Existing facets can be upgraded to fix bugs or enhance features
3. Storage layout must be preserved across upgrades
4. Access control should be carefully managed, with only authorized addresses allowed to perform upgrades

## Security Measures

The platform implements several security measures:

- `ReentrancyGuard` to prevent reentrancy attacks
- Validation checks for all inputs
- Economic incentives aligned with honest behavior
- Timelocks and waiting periods before sensitive actions
- Error handling with custom error types
- Separate dispute resolution tiers with different mechanisms

## Future Extensions

The system is designed to be extensible with potential future features including:

- Integration with external identity verification systems
- Enhanced analytics and reporting features
- Support for recurring events and subscription models
- Secondary market functionality with controlled resale parameters
- Integration with external oracles for dispute resolution
- Multi-chain deployment support

## Conclusion

Ticket City leverages blockchain technology and the Diamond Proxy pattern to create a robust, upgradeable platform for ticketing that addresses the common issues of fraud, scalping, and lack of transparency in the traditional ticketing industry. Through its staking, flagging, and dispute resolution mechanisms, it aligns incentives to encourage honest behavior from all participants.