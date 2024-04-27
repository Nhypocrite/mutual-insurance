// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract UnemploymentInsurance is Ownable {
    struct Employee {
        bytes32 nameHash;
        string emailAddress;
        string nric;
        uint256 monthlySalary;
        uint contributionAmount;
        uint[] paymentTimestamps;
        uint monthsPaid;
        uint8 status; // 0 - Registered but not confirmed, 1 - Confirmed but not enough payments, 2 - Eligible for claim, 3 - Claim submitted, 4 - Claimed or exited
        uint verifiedTimestamp;
    }

    struct Company {
        address hrWallet;
        bytes32 companyNameHash;
        string companyName;
        address[] employeeAddresses;
    }

    mapping(bytes32 => Company) public companiesByHash;
    mapping(address => Employee) public employees;

    event CompanyRegistered(bytes32 companyNameHash, string companyName);
    event EmployeeRegistered(address indexed employeeAddress, string companyName);
    event EmployeeStatusChanged(address indexed employeeAddress, uint8 status);
    event PremiumPaid(address indexed employeeAddress, uint amount, uint timestamp);
    event ClaimSubmitted(address indexed employeeAddress);
    event ClaimConfirmed(address indexed employeeAddress, uint payout);
    event EmployeeExited(address indexed employeeAddress);



    constructor() Ownable(msg.sender) { }


    // Function to register a company
    function registerCompany(string memory companyName, address hrWallet) public onlyOwner {
        bytes32 companyNameHash = generateNameHash(companyName);
        require(companiesByHash[companyNameHash].hrWallet == address(0), "Company already registered");
        require(bytes(companyName).length > 0, "Company name cannot be empty");
        require(hrWallet != address(0), "HR wallet address cannot be zero");
        companiesByHash[companyNameHash] = Company(hrWallet, companyNameHash, companyName, new address[](0));
        emit CompanyRegistered(companyNameHash, companyName);
    }

    // Function to register an employee
    function registerEmployee(string memory companyName, uint salary, bytes32 employeeNameHash, string memory emailAddress, string memory nric) public {
        require(bytes(companyName).length > 0, "Company name cannot be empty");
        require(salary > 0, "Salary must be greater than zero");
        bytes32 companyNameHash = generateNameHash(companyName);
        Company storage company = companiesByHash[companyNameHash];
        company.employeeAddresses.push(msg.sender);
        employees[msg.sender] = Employee(employeeNameHash, emailAddress, nric, salary, determineContribution(salary), new uint[](0), 0, 0, 0);
        emit EmployeeRegistered(msg.sender, companyName);
    }

    // Function to confirm employment status by HR
    function confirmEmploymentStatus(string memory companyName, address employeeAddress) public {
        bytes32 companyNameHash = generateNameHash(companyName);
        require(msg.sender == companiesByHash[companyNameHash].hrWallet, "Only HR can confirm employment status.");
        Employee storage employee = employees[employeeAddress];
        employee.status = 1;    // Set status to Confirmed but not enough payments
        employee.verifiedTimestamp = block.timestamp;
        emit EmployeeStatusChanged(employeeAddress, 1);
    }

    // Function to pay premium
    function payPremium(uint months) public payable {
        checkAndUpdateStatus(msg.sender);
        Employee storage employee = employees[msg.sender];
        require(employee.status != 4, "Already claimed or exited!");
        require(employee.status != 0, "Registration not confirmed yet!");
        require(employee.status != 3, "Claim request already made, pending approval!");
        require(employee.status == 1 || employee.status == 2, "Not in a valid state to pay premiums.");
        require(msg.value == employee.contributionAmount * months, "Incorrect premium amount.");
        for (uint i = 0; i < months; i++) {
            employee.paymentTimestamps.push(block.timestamp);
        }
        employee.monthsPaid += months;
        if (employee.monthsPaid >= 3){
            employee.status = 2;
            emit EmployeeStatusChanged(msg.sender, employee.status);
        }
        emit PremiumPaid(msg.sender, msg.value, block.timestamp);
    }

    // Function to submit a claim
    function submitClaim() public {
        checkAndUpdateStatus(msg.sender);
        Employee storage employee = employees[msg.sender];
        require(employee.status != 4, "Already claimed or exited!");
        require(employee.status != 0, "Registration not confirmed yet!");
        require(employee.status != 1, "Not enough monthly payments made!");
        require(employee.status != 3, "Claim request already made, pending approval!");
        require(employee.status == 2, "Not eligible to claim yet!");
        employee.status = 3;    // Set status to Claim submitted
        emit EmployeeStatusChanged(msg.sender, employee.status);
        emit ClaimSubmitted(msg.sender);
    }

    // Function to confirm claim
    function confirmClaim(string memory companyName, address employeeAddress) public {
        bytes32 companyNameHash = generateNameHash(companyName);
        require(msg.sender == companiesByHash[companyNameHash].hrWallet, "Only HR can confirm the claim.");
        Employee storage employee = employees[employeeAddress];
        require(employee.status != 4, "Already claimed or exited!");
        require(employee.status == 3, "No submitted claim!");
        uint payout = calculatePayout(employee.monthlySalary);
        require(address(this).balance >= payout, "Insufficient funds.");
        payable(employeeAddress).transfer(payout);
        employee.status = 4;    // Set status to Claimed or exited
        emit EmployeeStatusChanged(employeeAddress, employee.status);
        emit ClaimConfirmed(employeeAddress, payout);
    }

    // Function to exit the insurance system
    function exit(address employeeAddress) public {
        Employee storage employee = employees[employeeAddress];
        employee.status = 4;    // Set status to Claimed or exited
        emit EmployeeStatusChanged(employeeAddress, employee.status);
        emit EmployeeExited(employeeAddress);
    }


// >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> View functions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // View function to get employee information
    function getEmployeeInfo(address employeeAddress) public view returns (Employee memory) {
        return employees[employeeAddress];
    }

    // View function to get company information
    function getCompanyInfo(string memory companyName) public view returns (Company memory) {
        bytes32 companyNameHash = generateNameHash(companyName);
        return companiesByHash[companyNameHash];
    }

    // View function to get the addresses of employees of a certain compony
    function getAddressByCompanyName(string memory companyName) public view returns (address[] memory) {
        bytes32 companyNameHash = generateNameHash(companyName);
        return companiesByHash[companyNameHash].employeeAddresses;
    }


// >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Helper functions <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Helper function to check if the employ has exceeded the 3 month limit after last payment before each action
    function checkAndUpdateStatus(address employeeAddress) public {
        Employee storage employee = employees[employeeAddress];
        if (block.timestamp > employee.verifiedTimestamp + employee.monthsPaid * 30 days + 3 *30 days) {
            employee.status = 4;    // Set status to claimed or exited due to non-payment
            emit EmployeeStatusChanged(employeeAddress, employee.status);
        }
    }

    // Helper function to generate hash of company name
    function generateNameHash(string memory name) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    // Helper function to determine contribution based on salary
    function determineContribution(uint salary) private pure returns (uint) {
        if (salary <= 2000) {
            return 20 ether;
        } else if (salary <= 5000) {
            return 40 ether;
        } else if (salary <= 10000) {
            return 60 ether;
        } else {
            return 80 ether;
        }
    }

    // Helper function to calculate payout
    function calculatePayout(uint salary) public pure returns (uint) {
        if (salary <= 2000) {
            return salary * 50 / 100;
        } else if (salary <= 5000) {
            return salary * 40 / 100;
        } else if (salary <= 10000) {
            return salary * 30 / 100;
        } else {
            return salary * 20 / 100;
        }
    }

}