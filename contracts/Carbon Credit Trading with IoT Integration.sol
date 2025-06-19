// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title Carbon Credit Trading with IoT Integration
 * @dev Smart contract for automated carbon credit generation, trading, and verification using IoT sensor data
 */
contract Project is ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    // Carbon Credit Token (CCT) - represents 1 ton of CO2 equivalent
    struct CarbonProject {
        address owner;
        string projectName;
        string location;
        uint256 totalCreditsGenerated;
        uint256 availableCredits;
        uint256 pricePerCredit;
        bool isActive;
        bool isVerified;
        uint256 creationTime;
    }

    struct IoTSensor {
        address sensorAddress;
        uint256 projectId;
        string sensorType; // "air_quality", "forest_density", "soil_carbon", etc.
        bool isActive;
        bool isVerified;
        uint256 lastReading;
        uint256 lastUpdateTime;
    }

    struct CarbonOffset {
        address buyer;
        uint256 projectId;
        uint256 credits;
        uint256 totalCost;
        uint256 timestamp;
        string offsetReason;
    }

    // State variables
    mapping(uint256 => CarbonProject) public carbonProjects;
    mapping(address => IoTSensor) public iotSensors;
    mapping(uint256 => CarbonOffset[]) public projectOffsets;
    mapping(address => uint256[]) public userProjects;
    mapping(address => uint256) public userCarbonFootprint;

    uint256 public nextProjectId = 1;
    uint256 public totalCarbonCredits = 0;
    uint256 public totalOffsetsGenerated = 0;
    uint256 public minimumCreditPrice = 10 * 10**18; // 10 tokens minimum
    uint256 public platformFeePercentage = 300; // 3%
    
    // IoT Integration parameters
    uint256 public constant CARBON_CREDIT_THRESHOLD = 1000; // Minimum sensor reading for credit generation
    uint256 public constant CREDIT_GENERATION_RATE = 1; // Credits per 1000 units of positive environmental impact

    // Events
    event ProjectRegistered(uint256 indexed projectId, address indexed owner, string projectName, string location);
    event IoTSensorRegistered(address indexed sensorAddress, uint256 indexed projectId, string sensorType);
    event SensorDataUpdated(address indexed sensorAddress, uint256 reading, uint256 timestamp);
    event CarbonCreditsGenerated(uint256 indexed projectId, uint256 credits, uint256 timestamp);
    event CarbonCreditsTraded(uint256 indexed projectId, address indexed buyer, uint256 credits, uint256 totalCost);
    event CarbonFootprintUpdated(address indexed user, uint256 newFootprint);

    constructor() ERC20("Carbon Credit Token", "CCT") Ownable(msg.sender) {
        // Mint initial supply for platform operations
        _mint(msg.sender, 1000000 * 10**decimals());
    }

    /**
     * @dev Core Function 1: Register carbon project and IoT sensors for automated credit generation
     * @param _projectName Name of the carbon offset project
     * @param _location Geographic location of the project
     * @param _pricePerCredit Price per carbon credit in wei
     * @param _sensorAddresses Array of IoT sensor addresses
     * @param _sensorTypes Array of sensor types corresponding to addresses
     */
    function registerCarbonProject(
        string memory _projectName,
        string memory _location,
        uint256 _pricePerCredit,
        address[] memory _sensorAddresses,
        string[] memory _sensorTypes
    ) external nonReentrant {
        require(bytes(_projectName).length > 0, "Project name cannot be empty");
        require(bytes(_location).length > 0, "Location cannot be empty");
        require(_pricePerCredit >= minimumCreditPrice, "Price below minimum threshold");
        require(_sensorAddresses.length == _sensorTypes.length, "Sensor arrays length mismatch");
        require(_sensorAddresses.length > 0, "At least one sensor required");

        // Create carbon project
        carbonProjects[nextProjectId] = CarbonProject({
            owner: msg.sender,
            projectName: _projectName,
            location: _location,
            totalCreditsGenerated: 0,
            availableCredits: 0,
            pricePerCredit: _pricePerCredit,
            isActive: true,
            isVerified: false, // Requires manual verification initially
            creationTime: block.timestamp
        });

        // Register IoT sensors for the project
        for (uint256 i = 0; i < _sensorAddresses.length; i++) {
            require(_sensorAddresses[i] != address(0), "Invalid sensor address");
            
            iotSensors[_sensorAddresses[i]] = IoTSensor({
                sensorAddress: _sensorAddresses[i],
                projectId: nextProjectId,
                sensorType: _sensorTypes[i],
                isActive: true,
                isVerified: false, // Requires verification
                lastReading: 0,
                lastUpdateTime: block.timestamp
            });

            emit IoTSensorRegistered(_sensorAddresses[i], nextProjectId, _sensorTypes[i]);
        }

        userProjects[msg.sender].push(nextProjectId);
        
        emit ProjectRegistered(nextProjectId, msg.sender, _projectName, _location);
        nextProjectId++;
    }

    /**
     * @dev Core Function 2: Update IoT sensor data and automatically generate carbon credits
     * @param _sensorAddress Address of the IoT sensor
     * @param _reading Environmental reading from the sensor
     * @param _timestamp Timestamp of the reading
     */
    function updateSensorDataAndGenerateCredits(
        address _sensorAddress,
        uint256 _reading,
        uint256 _timestamp
    ) external nonReentrant {
        IoTSensor storage sensor = iotSensors[_sensorAddress];
        require(sensor.isActive, "Sensor is not active");
        require(sensor.isVerified, "Sensor is not verified");
        require(_timestamp > sensor.lastUpdateTime, "Timestamp must be newer than last update");
        
        // Only authorized sensor operators or project owners can update
        CarbonProject storage project = carbonProjects[sensor.projectId];
        require(
            msg.sender == _sensorAddress || 
            msg.sender == project.owner || 
            msg.sender == owner(),
            "Unauthorized sensor update"
        );

        // Update sensor data
        sensor.lastReading = _reading;
        sensor.lastUpdateTime = _timestamp;

        emit SensorDataUpdated(_sensorAddress, _reading, _timestamp);

        // Automatic carbon credit generation based on sensor reading
        if (_reading >= CARBON_CREDIT_THRESHOLD && project.isActive && project.isVerified) {
            uint256 creditsToGenerate = _reading.div(CARBON_CREDIT_THRESHOLD).mul(CREDIT_GENERATION_RATE);
            
            if (creditsToGenerate > 0) {
                // Mint carbon credit tokens to the project owner
                _mint(project.owner, creditsToGenerate * 10**decimals());
                
                // Update project statistics
                project.totalCreditsGenerated = project.totalCreditsGenerated.add(creditsToGenerate);
                project.availableCredits = project.availableCredits.add(creditsToGenerate);
                totalCarbonCredits = totalCarbonCredits.add(creditsToGenerate);

                emit CarbonCreditsGenerated(sensor.projectId, creditsToGenerate, _timestamp);
            }
        }
    }

    /**
     * @dev Core Function 3: Purchase carbon credits for offset and track carbon footprint
     * @param _projectId ID of the carbon project
     * @param _credits Number of credits to purchase
     * @param _offsetReason Reason for carbon offset (optional)
     */
    function purchaseCarbonCredits(
        uint256 _projectId,
        uint256 _credits,
        string memory _offsetReason
    ) external payable nonReentrant {
        CarbonProject storage project = carbonProjects[_projectId];
        
        require(project.isActive, "Project is not active");
        require(project.isVerified, "Project is not verified");
        require(_credits > 0, "Credits must be greater than 0");
        require(project.availableCredits >= _credits, "Insufficient available credits");
        
        uint256 totalCost = _credits.mul(project.pricePerCredit);
        require(msg.value >= totalCost, "Insufficient payment");

        // Calculate platform fee
        uint256 platformFee = totalCost.mul(platformFeePercentage).div(10000);
        uint256 projectOwnerPayment = totalCost.sub(platformFee);

        // Transfer payment to project owner
        payable(project.owner).transfer(projectOwnerPayment);

        // Update project available credits
        project.availableCredits = project.availableCredits.sub(_credits);

        // Transfer carbon credit tokens to buyer
        _transfer(project.owner, msg.sender, _credits * 10**decimals());

        // Record the carbon offset
        projectOffsets[_projectId].push(CarbonOffset({
            buyer: msg.sender,
            projectId: _projectId,
            credits: _credits,
            totalCost: totalCost,
            timestamp: block.timestamp,
            offsetReason: _offsetReason
        }));

        // Update user's carbon footprint (reduce by offset amount)
        if (userCarbonFootprint[msg.sender] >= _credits) {
            userCarbonFootprint[msg.sender] = userCarbonFootprint[msg.sender].sub(_credits);
        } else {
            userCarbonFootprint[msg.sender] = 0;
        }

        totalOffsetsGenerated = totalOffsetsGenerated.add(_credits);

        emit CarbonCreditsTraded(_projectId, msg.sender, _credits, totalCost);
        emit CarbonFootprintUpdated(msg.sender, userCarbonFootprint[msg.sender]);

        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value.sub(totalCost));
        }
    }

    // Additional utility functions

    /**
     * @dev Verify carbon project (only owner)
     * @param _projectId ID of the project to verify
     */
    function verifyProject(uint256 _projectId) external onlyOwner {
        require(carbonProjects[_projectId].owner != address(0), "Project does not exist");
        carbonProjects[_projectId].isVerified = true;
    }

    /**
     * @dev Verify IoT sensor (only owner)
     * @param _sensorAddress Address of the sensor to verify
     */
    function verifySensor(address _sensorAddress) external onlyOwner {
        require(iotSensors[_sensorAddress].sensorAddress != address(0), "Sensor does not exist");
        iotSensors[_sensorAddress].isVerified = true;
    }

    /**
     * @dev Update user's carbon footprint (can be called by verified environmental tracking systems)
     * @param _user Address of the user
     * @param _footprint New carbon footprint value
     */
    function updateCarbonFootprint(address _user, uint256 _footprint) external onlyOwner {
        userCarbonFootprint[_user] = _footprint;
        emit CarbonFootprintUpdated(_user, _footprint);
    }

    /**
     * @dev Get project details
     * @param _projectId ID of the project
     */
    function getProjectDetails(uint256 _projectId) external view returns (CarbonProject memory) {
        return carbonProjects[_projectId];
    }

    /**
     * @dev Get sensor details
     * @param _sensorAddress Address of the sensor
     */
    function getSensorDetails(address _sensorAddress) external view returns (IoTSensor memory) {
        return iotSensors[_sensorAddress];
    }

    /**
     * @dev Get user's projects
     * @param _user Address of the user
     */
    function getUserProjects(address _user) external view returns (uint256[] memory) {
        return userProjects[_user];
    }

    /**
     * @dev Get project offsets
     * @param _projectId ID of the project
     */
    function getProjectOffsets(uint256 _projectId) external view returns (CarbonOffset[] memory) {
        return projectOffsets[_projectId];
    }

    /**
     * @dev Get platform statistics
     */
    function getPlatformStats() external view returns (
        uint256 totalProjects,
        uint256 totalCredits,
        uint256 totalOffsets,
        uint256 activeProjects
    ) {
        totalProjects = nextProjectId - 1;
        totalCredits = totalCarbonCredits;
        totalOffsets = totalOffsetsGenerated;
        
        // Count active projects
        uint256 active = 0;
        for (uint256 i = 1; i < nextProjectId; i++) {
            if (carbonProjects[i].isActive) {
                active++;
            }
        }
        activeProjects = active;
    }

    /**
     * @dev Update project status (only project owner)
     * @param _projectId ID of the project
     * @param _isActive New active status
     */
    function updateProjectStatus(uint256 _projectId, bool _isActive) external {
        require(carbonProjects[_projectId].owner == msg.sender, "Only project owner can update status");
        carbonProjects[_projectId].isActive = _isActive;
    }

    /**
     * @dev Update credit price (only project owner)
     * @param _projectId ID of the project
     * @param _newPrice New price per credit
     */
    function updateCreditPrice(uint256 _projectId, uint256 _newPrice) external {
        require(carbonProjects[_projectId].owner == msg.sender, "Only project owner can update price");
        require(_newPrice >= minimumCreditPrice, "Price below minimum threshold");
        carbonProjects[_projectId].pricePerCredit = _newPrice;
    }

    /**
     * @dev Withdraw platform fees (only owner)
     */
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner()).transfer(balance);
    }

    /**
     * @dev Update platform fee percentage (only owner)
     * @param _newFeePercentage New fee percentage in basis points
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 1000, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }

    /**
     * @dev Emergency pause/unpause project (only owner)
     * @param _projectId ID of the project
     * @param _isPaused Pause status
     */
    function emergencyPauseProject(uint256 _projectId, bool _isPaused) external onlyOwner {
        carbonProjects[_projectId].isActive = !_isPaused;
    }
}
