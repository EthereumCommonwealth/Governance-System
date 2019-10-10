pragma solidity ^0.4.24;

library SafeMath {
  function mul(uint a, uint b) internal pure returns (uint) {
    if (a == 0) {
      return 0;
    }
    uint c = a * b;
    require(c / a == b);
    return c;
  }

  function div(uint a, uint b) internal pure returns (uint) {
    uint c = a / b;
    return c;
  }

  function sub(uint a, uint b) internal pure returns (uint) {
    require(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    require(c >= a);
    return c;
  }
}

interface TreasuryVoting{
    function update_voter(address _who, uint _new_weight) external;
    
    function is_voter(address _who) public constant returns (bool);
}


contract ColdStaking 
{
    using SafeMath for uint;
    event Staking(address addr, uint value, uint amount, uint time);
    event WithdrawStake(address staker, uint amount);
    event Claim(address staker, uint reward);
    event DonationDeposited(address _address, uint value);
    event VoterWithrawlDeadlineUpdate(address _voter,uint _time);
    event InactiveStaker(address _addr,uint value);

    struct Staker {
        uint stake;
        uint reward;        
        uint lastClaim;
        uint lastWeightedBlockReward;
        uint voteWithdrawalDeadline;
    }
    
    mapping(address => Staker) public staker;
    
    
    uint public staked_amount;
    uint public rewardToRedistribute;
    uint public weightedBlockReward;
    uint public totalClaimedReward;
    uint public lastTotalReward;
    uint public lastBlockNumber;
    uint public total_donations;
 
    /*
    uint public claim_delay = 27 days;
    uint public max_delay = 365 * 2 days; // 2 years.
    */
    
    /* TESTING VALUES */
    
    uint public claim_delay = 5 minutes;
    uint public max_delay = 3 days; // 2 years.
    
    /* END TEST VALUES*/
    
    address public governance_contract = 0x0; // address to be added either by setter or hardcoded
    
    constructor() public {
        lastBlockNumber = block.number;
    }
    
    modifier only_staker {
        require(staker[msg.sender].stake > 0);
        _;
    }
    
    modifier onlyGovernanceContract {
        require(msg.sender == governance_contract);
        _;
    }
    
    modifier only_rewarded {
        require(staker[msg.sender].stake > 0 || staker[msg.sender].reward > 0);
        _;
    }

    function() public payable {
        start_staking();
    }
    
    // the proposal allow the staker to stake more clo, at any given time without changing the basic description of the formula however he will have to wait another 27 days to claim.
    function start_staking() public payable {
        require(msg.value > 0);
        require(!deposits_disabled);
        
        staking_update(msg.value,true);
        staker_reward_update(); 
        
        staker[msg.sender].stake = staker[msg.sender].stake.add(msg.value); 
        staker[msg.sender].lastClaim = block.timestamp;
        
        // update TreasuryVoting contract
        // EDIT: not every Staker is Voter
        if( TreasuryVoting(governance_contract).is_voter(msg.sender) )
        {
            TreasuryVoting(governance_contract).update_voter(msg.sender,staker[msg.sender].stake);
        }
        
        emit Staking(msg.sender,msg.value,staker[msg.sender].stake,block.timestamp);
    }
    
    

    function staking_update(uint _value, bool _sign) internal {
    
        // Computing the total block reward (20% of the mining reward) that have been sent
        // to the contract since the last call of staking_update.
        // the smart contract now is independent from any change of the monetary policy.
        
        uint _total_sub_ = staked_amount.add(msg.value).add(total_donations);
        uint _total_add_ = totalClaimedReward;
        
        uint newTotalReward = address(this).balance.add(_total_add_).sub(_total_sub_);
        uint intervalReward = newTotalReward - lastTotalReward;
        
        lastTotalReward = lastTotalReward + intervalReward + total_donations;
        total_donations = 0;
        
        if (staked_amount!=0) {
            weightedBlockReward = weightedBlockReward.add(intervalReward.add(redistributed_reward()).mul(1 ether).div(staked_amount));
        } else {
            rewardToRedistribute = rewardToRedistribute.add(intervalReward).add(redistributed_reward());
        }
        if(_sign ) staked_amount = staked_amount.add(_value);
        else staked_amount = staked_amount.sub(_value);
    }
    
    
    // calculate the redistributed reward ( the unlcaimed stakers reward that were reported + the donation ), only partialy vested 100 CLO for every block.
    function redistributed_reward() internal returns(uint) {
        // the redistributed reward per block is set to 100 but can be changed.
        uint _amount = (block.number -lastBlockNumber) * 100 ether;
        if (_amount > rewardToRedistribute) {
            _amount =  rewardToRedistribute;
            rewardToRedistribute = 0;
        } else {
            rewardToRedistribute = rewardToRedistribute.sub(_amount); 
        }
        lastBlockNumber = block.number;
        return _amount;
    }
    
    
    // update the reward for the msg.sender
    function staker_reward_update() internal {
        uint stakerIntervalWeightedBlockReward = weightedBlockReward.sub(staker[msg.sender].lastWeightedBlockReward);
        uint _reward = staker[msg.sender].stake.mul(stakerIntervalWeightedBlockReward).div(1 ether);
        
        staker[msg.sender].reward = staker[msg.sender].reward.add(_reward);
        staker[msg.sender].lastWeightedBlockReward = weightedBlockReward;
    }

    // withdraw stake and claim the reward
    function withdraw_stake() public only_staker 
    {
        require(!withdrawals_disabled);
        require(staker[msg.sender].lastClaim + claim_delay < block.timestamp && staker[msg.sender].voteWithdrawalDeadline < block.timestamp );
            
        staking_update(staker[msg.sender].stake,false);
        staker_reward_update();
        
        uint _stake = staker[msg.sender].stake;
        staker[msg.sender].stake = 0;
        
        uint _reward = staker[msg.sender].reward;
        staker[msg.sender].reward = 0;
        
        totalClaimedReward = totalClaimedReward.add(_reward); 
        
        staker[msg.sender].lastClaim = block.timestamp;
        msg.sender.transfer(_stake.add(_reward));
        
        // update TreasuryVoting contract
        // EDIT: not every Staker is Voter
        if( TreasuryVoting(governance_contract).is_voter(msg.sender) )
        {
             TreasuryVoting(governance_contract).update_voter(msg.sender,staker[msg.sender].stake);
        }
        
        emit WithdrawStake(msg.sender,_stake);
    }

    // reward claim
    function claim() public only_rewarded {
        if(staker[msg.sender].lastClaim + claim_delay <= block.timestamp) {
            
            staking_update(0,true);
            staker_reward_update();
        
            staker[msg.sender].lastClaim = block.timestamp;
            uint _reward = staker[msg.sender].reward;
            staker[msg.sender].reward = 0;
            totalClaimedReward = totalClaimedReward.add(_reward);
            msg.sender.transfer(_reward);
        
            emit Claim(msg.sender, _reward);
        }
    }
    
    
    function redistributed_reward_info() internal returns(uint) {
        // the redistributed reward per block is set to 100 but can be changed.
        uint _amount = (block.number -lastBlockNumber) * 100 ether;
        if (_amount > rewardToRedistribute) {
            _amount =  rewardToRedistribute;

        }
        return _amount;
    }
    
    // ---------------------------------------------- Estimation Functions ----------------------------------- //
    // The following function can be called to give the exact esstimation of the user reward at the moment of the call
    // please note that the raward is completely independent from the users interactions.
    
    function staker_info() public view returns(uint256 weight, uint256 init, uint256 actual_block,uint256 _reward)
    {
        
        uint _total_sub_ = staked_amount.add(msg.value).add(total_donations);
        uint _total_add_ = totalClaimedReward;
        
        uint newTotalReward = address(this).balance.add(_total_add_).sub(_total_sub_);
        uint intervalReward = newTotalReward - lastTotalReward;
        
        if (staked_amount!=0) {
            uint _weightedBlockReward = weightedBlockReward.add(intervalReward.add(redistributed_reward_info()).mul(1 ether).div(staked_amount));
            uint _stakerIntervalWeightedBlockReward = _weightedBlockReward.sub(staker[msg.sender].lastWeightedBlockReward);
            _reward = staker[msg.sender].stake.mul(_stakerIntervalWeightedBlockReward).div(1 ether);

        } 
        
        return (
        staker[msg.sender].stake,
        staker[msg.sender].lastClaim,
        block.number,
        _reward = staker[msg.sender].reward + _reward
        );
    }
    
    function report_abuse(address _addr) public only_staker
    {
        require(staker[_addr].stake > 0);
        require(staker[_addr].lastClaim.add(max_delay) < block.timestamp);
        
        staking_update(staker[_addr].stake,false);
        staker_reward_update();
        
        rewardToRedistribute = rewardToRedistribute.add(staker[_addr].reward);
        staker[_addr].reward = 0;
        
        uint _stake = staker[_addr].stake; 
        staker[_addr].stake = 0;
        _addr.transfer(_stake);
      
        // update TreasuryVoting contract
        // EDIT: not every Staker is Voter
        if( TreasuryVoting(governance_contract).is_voter(_addr) )
        {
             TreasuryVoting(governance_contract).update_voter(_addr,staker[_addr].stake);
        }
        
        emit InactiveStaker(_addr,_stake);
    }
    
    function vote_casted(address voter, uint _voteWithdrawalDeadline) external onlyGovernanceContract
    {
        // voteWithdrawalDeadline is the deadline of the proposal from which the voter can withdraw his stake once the deadline reached.
        if(_voteWithdrawalDeadline >  staker[voter].voteWithdrawalDeadline)
        {
            staker[voter].voteWithdrawalDeadline = _voteWithdrawalDeadline;
            emit VoterWithrawlDeadlineUpdate(voter,_voteWithdrawalDeadline);
        }
    }
    
    function DEBUG_donation() public payable 
    {
        emit DonationDeposited(msg.sender, msg.value);
        rewardToRedistribute = rewardToRedistribute.add(msg.value);
        total_donations = total_donations.add(msg.value);
    }
    
    
    // DEBUGGING FUNCTIONS
    /*-------------------------------------------------------*/
    
    address public treasurer;
    
    modifier only_treasurer
    {
        require(msg.sender == treasurer);
        _;
    }
    
    bool public deposits_disabled = false;
    bool public withdrawals_disabled = false;
    
    function set_governance_contract(address _new_governance_contract) only_treasurer
    {
        governance_contract = _new_governance_contract;
    }
    
    function restrict_deposits(bool _status) only_treasurer
    {
        deposits_disabled = _status;
    }
    
    function restrict_withdrawals(bool _status) only_treasurer
    {
        withdrawals_disabled = _status;
    }
    
    function balanceContract() public view returns(uint256)
    {
        return this.balance;
    }
    
    /*-------------------------------------------------------*/
    // END DEBUGGING FUNCTIONS
    
    // -------------------------------------------------------------------------------------------- //
    // --------------------------- test function used to deposit the 20% block reward ------------- //
    // --------------------------- to be delete for mainnet --------------------------------------- //
    function deposit_block_reward() public payable 
    {
        
    }
}
