// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {TicketCityDiamond} from "../src/TicketCityDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {EventManagementFacet} from "../src/facets/EventManagementFacet.sol";
import {FlaggingFacet} from "../src/facets/FlaggingFacet.sol";
import {RevenueManagementFacet} from "../src/facets/RevenueManagementFacet.sol";
import {TicketManagementFacet} from "../src/facets/TicketManagementFacet.sol";
import {TokenManagementFacet} from "../src/facets/TokenManagementFacet.sol";

contract DeployTicketCity is Script {
    function run() external {
        // Get deployer address
        vm.startBroadcast();

        address deployerAddress = msg.sender;
        console.log("Deployer address:", deployerAddress);

        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        // Deploy facets
        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        EventManagementFacet eventManagementFacet = new EventManagementFacet();
        FlaggingFacet flaggingFacet = new FlaggingFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        RevenueManagementFacet revenueManagementFacet = new RevenueManagementFacet();
        TicketManagementFacet ticketManagementFacet = new TicketManagementFacet();
        TokenManagementFacet tokenManagementFacet = new TokenManagementFacet();

        console.log("DiamondCutFacet deployed at:", address(diamondCutFacet));
        console.log(
            "DiamondLoupeFacet deployed at:",
            address(diamondLoupeFacet)
        );
        console.log(
            "EventManagementFacet deployed at:",
            address(eventManagementFacet)
        );
        console.log("FlaggingFacet deployed at:", address(flaggingFacet));
        console.log("OwnershipFacet deployed at:", address(ownershipFacet));
        console.log(
            "RevenueManagementFacet deployed at:",
            address(revenueManagementFacet)
        );
        console.log(
            "TicketManagementFacet deployed at:",
            address(ticketManagementFacet)
        );
        console.log(
            "TokenManagementFacet deployed at:",
            address(tokenManagementFacet)
        );

        // Constructor expects: (address _contractOwner, address _diamondCutFacet)
        TicketCityDiamond diamond = new TicketCityDiamond(
            deployerAddress,
            address(diamondCutFacet)
        );
        console.log("Diamond contract deployed at:", address(diamond));

        // Create facet cut structs for remaining facets
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](7);

        // Add DiamondLoupeFacet
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectorsForLoupeFacet()
        });

        // Add OwnershipFacet
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectorsForOwnershipFacet()
        });

        // Add EventManagementFacet
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(eventManagementFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectorsForEventManagementFacet()
        });

        // Add FlaggingFacet
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(flaggingFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectorsForFlaggingFacet()
        });

        // Add RevenueManagementFacet
        cuts[4] = IDiamondCut.FacetCut({
            facetAddress: address(revenueManagementFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectorsForRevenueManagementFacet()
        });

        // Add TicketManagementFacet
        cuts[5] = IDiamondCut.FacetCut({
            facetAddress: address(ticketManagementFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectorsForTicketManagementFacet()
        });

        // Add TokenManagementFacet
        cuts[6] = IDiamondCut.FacetCut({
            facetAddress: address(tokenManagementFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectorsForTokenManagementFacet()
        });

        // Add remaining facets via diamondCut
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        console.log("Added remaining facets via diamondCut");

        vm.stopBroadcast();
    }

    // Selector helper functions
    function getFunctionSelectorsForLoupeFacet()
        internal
        pure
        returns (bytes4[] memory)
    {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = DiamondLoupeFacet.facets.selector;
        selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        selectors[3] = DiamondLoupeFacet.facetAddress.selector;
        selectors[4] = DiamondLoupeFacet.supportsInterface.selector;
        return selectors;
    }

    function getFunctionSelectorsForOwnershipFacet()
        internal
        pure
        returns (bytes4[] memory)
    {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = OwnershipFacet.transferOwnership.selector;
        selectors[1] = OwnershipFacet.owner.selector;
        return selectors;
    }

    function getFunctionSelectorsForEventManagementFacet()
        internal
        pure
        returns (bytes4[] memory)
    {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = EventManagementFacet.createEventWithPermit.selector;
        selectors[1] = EventManagementFacet.getEvent.selector;
        selectors[2] = EventManagementFacet
            .getEventsWithoutTicketsByUser
            .selector;
        selectors[3] = EventManagementFacet.getEventsWithTicketByUser.selector;
        return selectors;
    }

    function getFunctionSelectorsForFlaggingFacet()
        internal
        pure
        returns (bytes4[] memory)
    {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = FlaggingFacet.flagEvent.selector;
        selectors[1] = FlaggingFacet.getFlagThresholdInfo.selector;
        selectors[2] = FlaggingFacet.requestManualReview.selector;
        return selectors;
    }

    function getFunctionSelectorsForRevenueManagementFacet()
        internal
        pure
        returns (bytes4[] memory)
    {
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = RevenueManagementFacet.releaseRevenue.selector;
        selectors[1] = RevenueManagementFacet.claimScamEventRefund.selector;
        selectors[2] = RevenueManagementFacet.withdrawPlatformRevenue.selector;
        selectors[3] = RevenueManagementFacet.checkReleaseStatus.selector;
        selectors[4] = RevenueManagementFacet.canReleaseRevenue.selector;
        selectors[5] = RevenueManagementFacet
            .getEventsRequiringManualReview
            .selector;
        return selectors;
    }

    function getFunctionSelectorsForTicketManagementFacet()
        internal
        pure
        returns (bytes4[] memory)
    {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = TicketManagementFacet.createTicketWithPermit.selector;
        selectors[1] = TicketManagementFacet.purchaseTicketWithPermit.selector;
        selectors[2] = TicketManagementFacet.verifyAttendance.selector;
        selectors[3] = TicketManagementFacet.isAddressVerified.selector;
        selectors[4] = TicketManagementFacet
            .allEventsRegisteredForByAUser
            .selector;
        selectors[5] = TicketManagementFacet.getUserTicketType.selector;
        selectors[6] = TicketManagementFacet.getMyTickets.selector;
        return selectors;
    }

    function getFunctionSelectorsForTokenManagementFacet()
        internal
        pure
        returns (bytes4[] memory)
    {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TokenManagementFacet.addSupportedToken.selector;
        selectors[1] = TokenManagementFacet.removeSupportedToken.selector;
        selectors[2] = TokenManagementFacet.isTokenSupported.selector;
        selectors[3] = TokenManagementFacet.getSupportedTokens.selector;
        return selectors;
    }
}
