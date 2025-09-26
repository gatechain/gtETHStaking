// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IWithdrawalQueueERC721} from "./interfaces/IWithdrawalQueueERC721.sol";
import {Error} from "./lib/Error.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract WithdrawalQueueERC721 is ERC721EnumerableUpgradeable, AccessControlUpgradeable, IWithdrawalQueueERC721, IERC4906, UUPSUpgradeable {
    
    // ================ constants ================
    bytes32 public constant WITHDRAWAL_REQUEST_ROLE = keccak256("WITHDRAWAL_REQUEST_ROLE");
    bytes32 public constant WITHDRAWAL_FINALIZE_ROLE = keccak256("WITHDRAWAL_FINALIZE_ROLE");
    bytes32 public constant WITHDRAWAL_CLAIM_ROLE = keccak256("WITHDRAWAL_CLAIM_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // ================ state variables ================
    uint256 public currentRequestId;
    uint256 public lastFinalizeId;
    string public metadataURI;
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    function initialize(string memory _name, string memory _symbol, address _initialOwner) public initializer {
        __ERC721_init(_name, _symbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // grant roles to the initial owner
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        _grantRole(WITHDRAWAL_REQUEST_ROLE, _initialOwner);
        _grantRole(WITHDRAWAL_FINALIZE_ROLE, _initialOwner);
        _grantRole(WITHDRAWAL_CLAIM_ROLE, _initialOwner);
        _grantRole(UPGRADER_ROLE, _initialOwner);
    }

    // ================ view functions ================
    function getWithdrawalRequest(uint256 _requestId) external view returns (WithdrawalRequest memory) {
        return withdrawalRequests[_requestId];
    }

    function getWithdrawalRequestStatus(uint256 _requestId) external view returns (WithdrawalRequestStatus memory) {
        WithdrawalRequest memory request = withdrawalRequests[_requestId];
        uint256 previousRequestId = _requestId - 1;
        WithdrawalRequest memory previousRequest = withdrawalRequests[previousRequestId];
        return WithdrawalRequestStatus({
            gtETHAmount: request.cumulativeGTETHAmount - previousRequest.cumulativeGTETHAmount,
            ethAmount: request.cumulativeETHAmount - previousRequest.cumulativeETHAmount,
            creator: request.creator,
            createdAt: request.createdAt,
            recipient: request.recipient,
            claimedAt: request.claimedAt,
            isClaimed: request.isClaimed,
            isFinalized: _requestId <= lastFinalizeId
        });
    }

    function tokenURI(uint256 /*_tokenId*/) public view virtual override returns (string memory) {
        return metadataURI;
    }

    function calcFinalize(uint256 _finalizeId) external view returns (uint256 etherToLockOnWithdrawalQueue, uint256 sharesToBurnFromWithdrawalQueue) {
        WithdrawalRequest memory lastFinalizedRequest = withdrawalRequests[lastFinalizeId];
        WithdrawalRequest memory requestToFinalize = withdrawalRequests[_finalizeId];
        etherToLockOnWithdrawalQueue = requestToFinalize.cumulativeETHAmount - lastFinalizedRequest.cumulativeETHAmount;
        sharesToBurnFromWithdrawalQueue = requestToFinalize.cumulativeGTETHAmount - lastFinalizedRequest.cumulativeGTETHAmount;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721EnumerableUpgradeable, AccessControlUpgradeable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Check if a withdrawal request can be claimed
     * @param _requestId ID of the withdrawal request
     * @return canClaim Whether the request can be claimed
     */
    function canClaim(uint256 _requestId) external view returns (bool) {
        try this.ownerOf(_requestId) {
            // Token exists
        } catch {
            return false;
        }
        WithdrawalRequest memory request = withdrawalRequests[_requestId];
        return _requestId <= lastFinalizeId && !request.isClaimed;
    }


    // ================ external functions ================

    /**
     * @notice Request withdrawal of GTETH for ETH
     * @param _gtETHAmount Amount of GTETH to withdraw
     * @param _ethAmount Expected ETH amount to receive
     * @param _creator The creator of the withdrawal request
     * @return requestId The ID of the withdrawal request
     */
    function requestWithdrawal(uint256 _gtETHAmount, uint256 _ethAmount, address _creator) external onlyRole(WITHDRAWAL_REQUEST_ROLE) returns (uint256 requestId) {
        currentRequestId = currentRequestId + 1;
        requestId = currentRequestId;
        _safeMint(_creator, requestId);
        uint256 previousRequestId = requestId - 1;
        WithdrawalRequest memory previousRequest = withdrawalRequests[previousRequestId];
        withdrawalRequests[requestId] = WithdrawalRequest({
            cumulativeGTETHAmount: previousRequest.cumulativeGTETHAmount + _gtETHAmount,
            cumulativeETHAmount: previousRequest.cumulativeETHAmount + _ethAmount,
            creator: _creator,
            createdAt: block.timestamp,
            recipient: address(0),
            claimedAt: 0,
            isClaimed: false
        });
        
        emit WithdrawalRequested(_creator, requestId, _gtETHAmount, _ethAmount);
    }

    /// @notice Finalize requests from last finalized one up to `_lastRequestIdToBeFinalized`
    function finalize(uint256 _lastRequestIdToBeFinalized) external payable onlyRole(WITHDRAWAL_FINALIZE_ROLE) {
        uint256 firstFinalizedRequestId = lastFinalizeId + 1;
        _finalize(_lastRequestIdToBeFinalized, msg.value);
        emit BatchMetadataUpdate(firstFinalizedRequestId, _lastRequestIdToBeFinalized);
    }

    /**
     * @notice Claim ETH for a finalized withdrawal request
     * @param _requestId ID of the withdrawal request to claim
     * @param _recipient The recipient of the withdrawal
     */
    function claimWithdrawal(uint256 _requestId, address _recipient) external onlyRole(WITHDRAWAL_CLAIM_ROLE) {
        // check if the request is finalized
        if (_requestId > lastFinalizeId) {
            revert Error.RequestNotFinalized();
        }
        // check owner of the request
        if (ownerOf(_requestId) != _recipient) {
            revert Error.NotTheOwnerOfTheRequest();
        }

        WithdrawalRequest storage request = withdrawalRequests[_requestId];
        // check if the request is claimed
        if (request.isClaimed) {
            revert Error.RequestAlreadyClaimed();
        }
        uint256 previousRequestId = _requestId - 1;
        WithdrawalRequest memory previousRequest = withdrawalRequests[previousRequestId];
        uint256 ethAmount = request.cumulativeETHAmount - previousRequest.cumulativeETHAmount;
        
        if (ethAmount > 0) {
            // Transfer ETH to the user if the amount is greater than 0
            // avoid transfer zero amount
            (bool success, ) = _recipient.call{value: ethAmount}("");
            if (!success) {
                revert Error.TransferFailed();
            }
        }
        
        request.isClaimed = true;
        request.recipient = _recipient;
        request.claimedAt = block.timestamp;
        emit WithdrawalClaimed(_recipient, _requestId, ethAmount);
    }
    
    // ================ internal functions ================
    
    /// @dev Finalize requests in the queue
    ///  Emits WithdrawalsFinalized event.
    function _finalize(uint256 _lastRequestIdToBeFinalized, uint256 _amountOfETH) internal {
        if (_lastRequestIdToBeFinalized > currentRequestId) revert Error.InvalidRequestId(_lastRequestIdToBeFinalized);
        uint256 lastFinalizedRequestId = lastFinalizeId;
        if (_lastRequestIdToBeFinalized <= lastFinalizedRequestId) revert Error.InvalidRequestId(_lastRequestIdToBeFinalized);

        WithdrawalRequest memory lastFinalizedRequest = withdrawalRequests[lastFinalizedRequestId];
        WithdrawalRequest memory requestToFinalize = withdrawalRequests[_lastRequestIdToBeFinalized];

        uint256 gtETHToFinalize = requestToFinalize.cumulativeGTETHAmount - lastFinalizedRequest.cumulativeGTETHAmount;
        uint256 ethToFinalize = requestToFinalize.cumulativeETHAmount - lastFinalizedRequest.cumulativeETHAmount;
        if (_amountOfETH > ethToFinalize) revert Error.TooMuchEtherToFinalize(_amountOfETH, gtETHToFinalize);

        uint256 firstRequestIdToFinalize = lastFinalizedRequestId + 1;
        lastFinalizeId = _lastRequestIdToBeFinalized;

        emit WithdrawalsFinalized(
            firstRequestIdToFinalize,
            _lastRequestIdToBeFinalized,
            _amountOfETH,
            gtETHToFinalize,
            block.timestamp
        ); 
    }
    
    // ================ governance functions ================
    function setMetadataURI(string memory _metadataURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        metadataURI = _metadataURI;
    }

    /**
     * @dev Authorize upgrade for UUPS proxy
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        // Can add additional upgrade validation logic here
    }
}
