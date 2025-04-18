# Ticket City Platform Documentation

## Overview

Ticket City is a decentralized ticketing platform built on blockchain technology that addresses common problems in the event ticketing industry such as fraud, scalping, and lack of transparency. The platform leverages smart contracts to create a trustless environment where event organizers and attendees can interact with confidence.

The platform utilizes two key blockchain technologies to enhance security and usability:

1. **Soulbound NFT Tickets**: Each ticket is represented as a non-transferable (soulbound) NFT, preventing unauthorized reselling and ensuring tickets remain with their original purchasers.

2. **Stablecoin Payments**: The platform exclusively uses ERC20 stablecoins for all transactions, providing price stability for both organizers and attendees while maintaining the benefits of blockchain-based payments.

The platform has been implemented using the Diamond Proxy pattern for enhanced modularity, upgradeability, and gas efficiency.

## Core Features

### Event Management

- **Event Creation**: Organizers can create events with details including title, description, image, location, start/end dates, and expected attendance.
- **Ticket Types**: Support for different ticket categories (FREE, REGULAR, VIP) with varying price points.
- **Stablecoin Support**: Multiple ERC20 stablecoins can be supported for payments.
- **Revenue Management**: Automated release of revenue to organizers after successful events.
- **ERC20Permit Support**: Enhanced UX with gasless approvals using permit signatures.
- **Optimized Data Structures**: Event parameters are now grouped into structured types to enhance gas efficiency and code readability.

### Trust & Security Mechanisms

- **Staking System**: Event organizers provide an initial stake when creating paid events, with additional stake required when creating tickets. The stake amount is calculated based on ticket price and expected attendance, with 20% of expected revenue required as stake.
- **Self-Verification**: Attendees verify their attendance by providing a signed message with a verification code displayed at the event.
- **Flagging System**: Ticket holders can flag events as fraudulent after they end, providing reasons for the flag. There is a 4-day flagging period after event conclusion.
- **Dispute Resolution**: Organizers can request manual review with explanations if their event is heavily flagged. The platform owner can manually confirm events as scams after investigation.
- **Reputation Tracking**: The system tracks both successful events and scam events per organizer, which affects future staking requirements.
- **Organizer Blacklisting**: The platform maintains a blacklist of fraudulent organizers who are prevented from creating new events.
- **Enhanced Data Validation**: Improved input validation with detailed error messages for event details and ticket parameters.

### Advanced Anti-Fraud Measures

- **Soulbound NFT Tickets**: Non-transferable tickets prevent unauthorized reselling and secondary markets.
- **Stablecoin-Based Payments**: Using stablecoins provides price stability and auditability for all transactions.
- **Simple Flagging Mechanism**: Any ticket holder can flag an event with a reason if they believe it was fraudulent.
- **Time-Limited Flagging**: Flags must be submitted within 4 days of the event ending.
- **Attendance Verification**: Self-verification system with cryptographic signatures ensures only legitimate attendees are counted.

## Architecture Overview

The project implements the Diamond Proxy pattern, which provides several advantages:

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

1. **EventManagementFacet**: Handles event creation and management
2. **TicketManagementFacet**: Manages ticket creation, types, and purchasing
3. **TokenManagementFacet**: Manages supported ERC20 stablecoins for payments
4. **RevenueManagementFacet**: Handles revenue release, refunds, and scam event processing
5. **FlaggingFacet**: Implements the event flagging system
6. **OwnershipFacet**: Implements the IERC173 interface for ownership management

## Key Components In Detail

### Event System

Events in Ticket City are created by organizers who define parameters such as:

- Event title, description, and image URI
- Physical location
- Start and end dates
- Expected number of attendees
- Ticket type (FREE or PAID)
- Payment stablecoin (for PAID events)

For PAID events, organizers must provide an initial minimal stake of 10 USDC (10e6 in smallest units), with additional stake required when creating tickets. This stake amount varies based on the organizer's reputation score and past performance.

The platform has improved its event creation function by using structured parameters to reduce stack variables and enhance readability:

```solidity
function createEventWithPermit(
    EventCreateParams calldata _params,
    SignatureParams calldata _sig
) external nonReentrant returns (uint256)
```

Where `EventCreateParams` and `SignatureParams` are structured types that group related parameters:

```solidity
struct EventCreateParams {
    string title;
    string desc;
    string imageUri;
    string location;
    uint256 startDate;
    uint256 endDate;
    uint256 expectedAttendees;
    LibTypes.TicketType ticketType;
    IERC20Permit paymentToken;
}

struct SignatureParams {
    uint8 v;
    bytes32 r;
    bytes32 s;
}
```

The platform also provides several methods to fetch events:

- `getEventsWithoutTicketsByUser`: Enhanced to accurately filter events without tickets, considering both FREE and PAID event types and their different ticket configurations.
- `getEventsWithTicketByUser`: Optimized to return only events with properly configured tickets.
- `getAllValidEvents`: Identifies valid events with available tickets that haven't ended.

### Ticketing System

Once an event is created, organizers can define different ticket types:

- **FREE tickets**: No cost to attendees
- **REGULAR tickets**: Standard paid admission
- **VIP tickets**: Premium paid admission at a higher price point

Each ticket is represented as a soulbound (non-transferable) NFT, providing verifiable ownership while preventing ticket scalping and unauthorized transfers. The `TicketNFT` contract enforces this non-transferability by overriding the `_update` function to revert when attempted transfers occur between non-zero addresses.

The ticket creation function has been improved to use structured parameters:

```solidity
function createTicketWithPermit(
    TicketCreateParams calldata _params,
    SignatureParams calldata _sig
) external nonReentrant returns (bool success_)
```

Where `TicketCreateParams` is a structured type for ticket parameters:

```solidity
struct TicketCreateParams {
    uint256 eventId;
    LibTypes.PaidTicketCategory category;
    uint256 ticketFee;
    string ticketUri;
    bytes32 verificationCode;
}
```

Similarly, ticket purchasing has been improved with structured parameters:

```solidity
function purchaseTicketWithPermit(
    TicketPurchaseParams calldata _params,
    SignatureParams calldata _sig
) external nonReentrant
```

Where `TicketPurchaseParams` is:

```solidity
struct TicketPurchaseParams {
    uint256 eventId;
    LibTypes.PaidTicketCategory category;
}
```

This approach offers:
- Reduced stack usage for better gas efficiency
- Improved readability and maintainability
- Better grouping of related parameters
- Enhanced error handling with specific revert messages

The platform stores ticket information in dedicated structures and provides optimized methods to track the ticket types owned by users:

- `getUserTicketType`: Determines the specific ticket type a user has for an event
- `hasVIPTicket`: Quickly checks if a user has a VIP ticket
- `getMyTickets`: Returns comprehensive information about all tickets a user has purchased

### Stablecoin Management System

The platform supports multiple ERC20 stablecoins for payments, with the following functionality:

- Adding supported tokens (admin only)
- Removing supported tokens (admin only)
- Checking if a token is supported
- Getting the list of all supported tokens

```solidity
function addSupportedToken(address _tokenAddress) external returns (bool success)
function removeSupportedToken(address _tokenAddress) external returns (bool success)
function isTokenSupported(address _tokenAddress) external view returns (bool isSupported)
function getSupportedTokens() external view returns (address[] memory tokens)
```

This allows for flexibility in payment options while maintaining control over which stablecoins are accepted.

### Staking & Attendance Verification System

The platform's staking mechanism includes a reputation system:

- New organizers provide a fixed initial stake (10e6 units of the stablecoin) when creating a paid event
- Additional stake is calculated when creating the first ticket, requiring 20% of expected revenue, with adjustments based on reputation
- New organizers face a 10% penalty, increasing their required stake
- Successful events earn organizers a 5% discount on future stakes, up to a maximum of 15%
- The stake serves as economic collateral for potential refunds if an event is determined to be fraudulent

Attendance verification has been enhanced with a more secure implementation using cryptographic signatures:

1. Organizers set a verification code for attendees using `setEventVerificationCode()`
2. Attendees verify their attendance by signing a message containing the verification code using `verifyAttendance()`
3. The platform can check if an address is verified using `isAddressVerified()`

```solidity
function verifyAttendance(uint256 _eventId, bytes32 _verificationCode, bytes calldata _signature) external
function isAddressVerified(uint256 _eventId, address _address) external view returns (bool)
```

The verification system now uses ECDSA signature recovery to validate that the attendee personally signed the verification message, enhancing security and preventing unauthorized verifications.

### Flagging & Dispute Resolution

The platform implements a straightforward system to handle disputes:

#### Flagging System

Attendees can flag events as fraudulent after they end, with these key characteristics:

- Flags must be raised within a defined period after the event (4 days as defined in LibConstants.FLAGGING_PERIOD)
- Each flag requires a reason explaining why the event is considered fraudulent
- Only users who purchased a ticket can flag an event
- Currently, all flags have equal weight (1)

```solidity
function flagEvent(uint256 _eventId, string calldata _reason) external
```

#### Dispute Resolution

The dispute resolution process includes:

1. **Attendance-based checks**: Events with attendance rate below 60% require waiting through the flagging period
2. **Flag percentage threshold**: If the flagged percentage exceeds 70% of users who did not verify attendance, revenue cannot be automatically released
3. **Manual review request**: Organizers can request manual review and provide evidence to contest flags
4. **Admin decision**: The platform owner can confirm events as scams after investigation, with a 30-day window for confirmation

```solidity
function requestManualReview(uint256 _eventId, string calldata _explanation) external
function confirmEventAsScam(uint256 _eventId, string calldata _details) external
```

## Revenue Management

Revenue from ticket sales is held in escrow until the event concludes successfully. The current release logic includes:

- Event must have ended
- If attendance rate is below minimum threshold (60% as defined in LibConstants.MINIMUM_ATTENDANCE_RATE), there's a waiting period (flagging period)
- Flagging threshold must not be exceeded
- Revenue must not have been already released
- Event must not be confirmed as a scam

Service fees are applied as follows:

- For paid events: 5% of total revenue
- For free events with attendance above threshold: Base fee with multiplier based on attendance

The system provides several revenue-related functions:

```solidity
function releaseRevenue(uint256 _eventId) external nonReentrant
function checkReleaseStatus(uint256 _eventId) external view returns (bool canRelease, uint8 reason)
function canReleaseRevenue(uint256 _eventId) external view returns (bool canRelease, uint256 attendanceRate, uint256 revenue)
```

For events confirmed as scams, a refund mechanism exists:

```solidity
function claimScamEventRefund(uint256 _eventId) external nonReentrant
function checkRefundEligibility(uint256 _eventId, address _user) external view returns (bool canClaim, uint256 refundAmount, bool alreadyClaimed)
```

When an event is confirmed as a scam:

1. The platform takes 10% of the staked amount as a platform fee
2. The remaining 90% is divided among ticket holders
3. Ticket holders can also get refunds of their ticket purchase amounts

## Platform Constants

The platform behavior is governed by several constants defined in LibConstants:

- `MINIMUM_ATTENDANCE_RATE`: 60% of registered attendees must verify their attendance for automatic revenue release
- `FLAGGING_THRESHOLD`: 70% of the remaining percentage of people who did not verify attendance (specialized calculation)
- `FLAGGING_PERIOD`: Period after event when flags can be submitted (4 days)
- `SCAM_CONFIRM_PERIOD`: Period during which an event can be confirmed as a scam (30 days)
- `FREE_TICKET_PRICE`: Fixed at 0
- `PAID_EVENT_SERVICE_FEE_PERCENT`: 5% of total event revenue
- `FREE_EVENT_SERVICE_FEE_BASE`: Base fee for free events (2.5 USD equivalent)
- `FREE_EVENT_ATTENDEE_THRESHOLD`: Threshold for free event attendance (50 attendees)
- `STAKE_PERCENTAGE`: 20% of expected revenue must be staked
- `PLATFORM_FEE_PERCENTAGE`: 10% of stake is taken by platform for scam events

### Reputation System Constants

- `NEW_ORGANIZER_PENALTY`: Additional 10% stake requirement for new organizers
- `REPUTATION_DISCOUNT_FACTOR`: 5% stake discount per successful event
- `MAX_REPUTATION_DISCOUNT`: Maximum stake discount capped at 15%

## Ticket City Process Flow

```mermaid
graph TD
   subgraph "Event Creation Flow"
   A[Organizer] -->|Creates Event with<br>Structured Parameters & Permit| B[Ticket_City Contract]
   B -->|Collects Initial Stake| C[Stake Management]
   B -->|Creates Event Record| D[Event Storage]
   A -->|Creates Tickets with<br>Structured Parameters & Permit| B
   B -->|Deploys| E[Soulbound NFT Contract]
   B -->|Sets| F[Ticket Types]
   F -->|FREE| G[Single Ticket Type]
   F -->|PAID| H[Regular/VIP Options]
   B -->|Collects Additional Stake<br>Based on Reputation| C
end
```

## Ticket Purchase Flow

```mermaid
graph TD
    A[Attendee] -->|Uses Structured Parameters<br>& Permit for Approval| B[Ticket_City Contract]
    B -->|Validates Signature| C[Signature Validation]
    C -->|Success| D[Mint Soulbound NFT Ticket]
    D -->|Updates| E[Event Records]
    D -->|Adds to| F[Revenue Escrow]
```

## Attendance Verification Flow

```mermaid
graph TD
    A[Organizer] -->|Sets Verification Code| B[Ticket_City Contract]
    C[Attendee] -->|Signs Message with Code| B
    B -->|Verifies ECDSA Signature| D[Validation Logic]
    D -->|Valid| E[Mark Attendance Verified]
    D -->|Invalid| F[Reject Verification]
    E -->|Updates| G[Attendance Metrics]
```

## Revenue Release Flow

```mermaid
    graph TD
    A[Event Ends] -->|Starts| B[Waiting Period]
    B -->|Check| C{Attendance Rate ≥ 60%?}
    C -->|Yes| D{Flagging Threshold Met?}
    C -->|No| E{Flagging Period Ended?}
    E -->|Yes| D
    E -->|No| F[Cannot Release Yet]
    D -->|No| G[Release Revenue to Organizer]
    D -->|Yes| H[Revenue Locked for Review]
    H -->|Owner Reviews| I{Confirm as Scam?}
    I -->|Yes| J[Enable Refunds]
    I -->|No| G
```

## Flagging and Dispute Flow

```mermaid
graph TD
    A[Attendee] -->|Flags Event| B[Ticket_City Contract]
    B -->|Stores Flag| C[Flag Storage]
    D[Organizer] -->|Requests Review| E[Manual Review Process]
    E -->|Platform Owner Reviews| F{Decision}
    F -->|Legitimate Event| G[Manual Revenue Release]
    F -->|Scam Confirmed| H[Enable Refunds]
    H -->|Attendees Claim| I[Refund Distribution]
```

## Reputation System Flow

```mermaid
graph TD
    A[New Organizer] -->|Creates First Event| B[+10% Stake Penalty]
    C[Successful Event] -->|Improves Reputation| D[Earn 5% Discount]
    D -->|Up to Maximum| E[15% Maximum Discount]
    F[Scam Event] -->|Damages Reputation| G[Blacklisted]
```

## ERC20 Permit Integration

The platform integrates ERC20 Permit functionality for enhanced user experience:

- **Gasless Approvals**: Users can sign approval messages off-chain instead of submitting separate approval transactions
- **Reduced Transaction Steps**: Creating events, tickets, and purchasing tickets now require only one transaction
- **Streamlined Experience**: Provides a more seamless user experience, especially for new blockchain users

This integration affects multiple facets with parameter structuring:

```solidity
// EventManagementFacet
function createEventWithPermit(EventCreateParams calldata _params, SignatureParams calldata _sig)

// TicketManagementFacet
function createTicketWithPermit(TicketCreateParams calldata _params, SignatureParams calldata _sig)
function purchaseTicketWithPermit(TicketPurchaseParams calldata _params, SignatureParams calldata _sig)
```

## User Guides

### For Event Organizers

1. **Create an event** by providing structured parameters and signing a permit for the initial stake
2. **Create ticket types** for the event (FREE, REGULAR, VIP) with verification code
3. **Set the verification code** for attendance verification
4. **Monitor attendance** as the event progresses
5. **Release revenue** after the event concludes successfully or **dispute flags** if necessary

### For Attendees

1. **Purchase tickets** for desired events by signing a permit message
2. **Attend the event** and verify attendance with the verification code and cryptographic signature
3. **Flag events** if they were fraudulent or didn't deliver as promised
4. **Claim refunds** if the event is confirmed as a scam

### For Platform Owner

1. **Manage supported stablecoins** by adding or removing ERC20 tokens
2. **Review flagged events** requiring manual validation
3. **Confirm or reject** events as scams based on evidence
4. **Withdraw platform revenue** when needed
5. **Transfer ownership** of the platform if needed

## Security Measures

The platform implements several security measures:

- `ReentrancyGuard` to prevent reentrancy attacks
- Validation checks for all inputs with enhanced error handling
- Economic incentives aligned with honest behavior
- Timelocks and waiting periods before sensitive actions
- Error handling with custom error types
- Enhanced cryptographic signatures for secure attendance verification using ECDSA
- Structured parameter handling to prevent stack too deep errors
- SafeERC20 for secure token transfers
- Permit signatures with deadlines to prevent replay attacks

## Code Improvements

The latest update includes several code improvements:

1. **Structured Parameter Types**: Functions now use structured types to group related parameters, reducing stack variables and improving code readability.

2. **Enhanced Query Functions**: Event and ticket query functions have been optimized to provide more accurate filtering for user experiences.

3. **Improved Security**: Attendance verification now uses ECDSA signature recovery for enhanced security.

4. **Better Error Handling**: Specific error messages for each validation check using custom error types.

5. **Gas Optimization**: Code restructuring to optimize gas usage in core functions.

## Future Extensions

The system is designed to be extensible with potential future features including:

- Enhanced reputation system with more granular rewards and penalties
- Integration with external identity verification systems
- Enhanced analytics and reporting features
- Support for recurring events and subscription models
- Secondary market functionality with controlled resale parameters
- Cross-chain deployment support

## Conclusion

Ticket City leverages blockchain technology and the Diamond Proxy pattern to create a robust, upgradeable platform for ticketing that addresses the common issues of fraud, scalping, and lack of transparency in the traditional ticketing industry.

The platform's implementation of soulbound NFT tickets forms a critical anti-scalping measure, as these non-transferable tokens ensure that tickets cannot be resold on secondary markets, maintaining fair access and pricing for all attendees. This represents a significant improvement over both traditional ticketing systems and earlier blockchain ticketing platforms that used transferable tokens.

With the addition of ERC20 Permit functionality, a simplified verification system, and structured parameter handling, Ticket City now provides an even more user-friendly and gas-efficient experience while maintaining strong security guarantees. The permit-based approach reduces transaction steps and gas costs, making the platform more accessible to mainstream users.

The reputation system enhances trust by incentivizing organizers to build a positive track record through successful events, with tangible benefits in reduced stake requirements. New organizers face higher stake requirements until they prove their reliability, creating a balanced ecosystem that protects attendees while allowing legitimate organizers to flourish.

Through its combination of soulbound NFTs, stablecoin payments, and mechanisms like staking, flagging, and dispute resolution, Ticket City aligns incentives to encourage honest behavior from all participants while providing the security and transparency benefits of blockchain technology.