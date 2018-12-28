pragma solidity ^0.4.25;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
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
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
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

contract ColdStaking {
    
    struct Staker
    {
        uint amount;
        uint time;
    }
    
    mapping(address => Staker) public staker;
    
    uint public a;
    
}

contract TreasuryVoting {
    
    // TODO: Update calculations with SafeMath functions.

    using SafeMath for uint;
    
    struct Proposal
    {
        // Based on IOHK Treasury proposal system.
        string  name;
        string  URL;
        bytes32 hash;
        uint    start_block;
        uint    end_block;
        address payment_address;
        uint    payment_amount;
        
        // Collateral tx id is not necessary.
        // Proposal sublission tx requires `proposal_threshold` to be paid.
    }
    
    ColdStaking public cold_staking_contract = ColdStaking(0xd813419749b3c2cdc94a2f9cfcf154113264a9d6); // Staking contract address and ABI.
    
    uint public epoch_length = 27 days; // Voting epoch length.
    uint public start_timestamp = now;
    
    uint public total_voting_weight = 0; // This variable preserves the total amount of staked funds which participate in voting.
    uint public proposal_threshold = 500 ether; // The amount of funds that will be held by voting contract during the proposal consideration/voting.
    
    mapping(address => uint) public voting_weight; // Each voters weight. Calculated and updated on each Cold Staked deposit change.


    // Cold Staker can become a voter by executing this funcion.
    // Voting contract must read the weight of the staker
    // and update the total voting weight.
    function become_voter() public
    {
        uint _amount;
        uint _time;
        (_amount, _time) = cold_staking_contract.staker(msg.sender);
        voting_weight[msg.sender] = _amount;
        total_voting_weight += _amount;
    }
    
    
    // Staking Contract MUST call this function on each staking deposit update.
    function update_voter(address _who, uint _new_weight) public only_staking_contract()
    {
        // If the voting weight of a given address decreases
        // subtract the delta from `total_voting_weight`.
        if(voting_weight[_who] > _new_weight)
        {
            total_voting_weight -= (voting_weight[_who] - _new_weight);
        }
        
        // Otherwise the weight did not change or increases
        // we need to increase the total_voting_weight by delta.
        else
        {
            total_voting_weight += (_new_weight - voting_weight[_who]);
        }
        voting_weight[_who] = _new_weight;
    }
    
    // Returns the id of current Treasury Epoch.
    function get_epoch() public constant returns (uint)
    {
        return ((block.timestamp - start_timestamp) / epoch_length);
    }
    
    function submit_proposal() public payable
    {
        require(msg.value > proposal_threshold);
        
    }
    
    function is_voter(address _who) public constant returns (bool)
    {
        return voting_weight[_who] > 0;
    } 
    
    modifier only_staking_contract()
    {
        require(msg.sender == address(cold_staking_contract));
        _;
    }
}
