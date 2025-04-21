// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {TokenManagementFacet} from "../src/facets/TokenManagementFacet.sol";

contract UpgradeTokenManagementFacet is Script {
    address constant DIAMOND_ADDRESS =
        0x81e629e4411F9f15b4971a2739D2A816fDa94d14;

    function run() external {
        vm.startBroadcast();

        // Deploying the new version of the TokenManagementFacet
        TokenManagementFacet newTokenManagementFacet = new TokenManagementFacet();
        console.log(
            "New TokenManagementFacet deployed at:",
            address(newTokenManagementFacet)
        );

        // Creating facet cut for replacing all functions in the TokenManagementFacet
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);

        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(newTokenManagementFacet),
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: getTokenManagementFacetSelectors()
        });

        // Execute diamond cut
        IDiamondCut(DIAMOND_ADDRESS).diamondCut(cuts, address(0), "");
        console.log("TokenManagementFacet successfully replaced");

        vm.stopBroadcast();
    }

    // Function selectors for the TokenManagementFacet
    function getTokenManagementFacetSelectors()
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
