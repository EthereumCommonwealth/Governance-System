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
    
    function vote_casted(address _addr) public { }
    
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
        uint    start_epoch; // Number of the epoch when proposal voting begins.
        uint    end_epoch;   // Number of the epoch when proposal funding ends.
        // NOTE: If a proposal is intended to be a one-time payment then 
        //       it must have `start_epoch` = `i` and `end_epoch` = `i + 1` because
        //       the proposal will be paid in the next epoch after the voting epoch ends.
        
        address payment_address;
        uint    payment_amount;
        
        uint votes_for;
        uint votes_against;
        uint votes_abstain;
        
        uint status;
        
        // STATUS:
        // 0 - voting
        // 1 - accepted/ awaiting payment
        // 2 - declined
        // 3 - withdrawn
        
        // Collateral tx id is not necessary.
        // Proposal sublission tx requires `proposal_threshold` to be paid.
    }
    
    struct Vote
    {
        address voter;
        uint    vote_code; // 0 - for, 1 - against, 2 - abstain
        uint    weight;
    }
    
    ColdStaking public cold_staking_contract = ColdStaking(0xd813419749b3c2cdc94a2f9cfcf154113264a9d6); // Staking contract address and ABI.
    
    uint public epoch_length        = 27 days; // Voting epoch length.
    uint public start_timestamp     = now;
    
    uint public total_voting_weight = 0; // This variable preserves the total amount of staked funds which participate in voting.
    uint public proposal_threshold  = 500 ether; // The amount of funds that will be held by voting contract during the proposal consideration/voting.
    
    mapping(address => uint) public     voting_weight; // Each voters weight. Calculated and updated on each Cold Staked deposit change.
    mapping(bytes32 => Proposal) public proposals; // Use `bytes32` sha3 hash of proposal name to identify a proposal entity.
    mapping(bytes32 => Vote) public     votes;


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
    function get_current_epoch() public constant returns (uint)
    {
        return ((block.timestamp - start_timestamp) / epoch_length);
    }
    
    function submit_proposal(string _name, string _url, bytes32 _hash, uint _start, uint _end, address _destination, uint _funding) public payable
    {
        require(msg.value > proposal_threshold);
        require(get_current_epoch() < _start);
        require(_end > _start);
        require(_destination != address(0x0)); // Address of a newly submitted proposal must not be 0x0.
        require(proposals[sha3(_name)].payment_address == address(0x0)); // Check whether a proposal exists (assuming that a proposal with address 0x0 does not exist).
        
        proposals[sha3(_name)].name            = _name;
        proposals[sha3(_name)].URL             = _url;
        proposals[sha3(_name)].hash            = _hash;
        proposals[sha3(_name)].start_epoch     = _start;
        proposals[sha3(_name)].end_epoch       = _end;
        proposals[sha3(_name)].payment_address = _destination;
        proposals[sha3(_name)].payment_amount  = _funding;
        
        proposals[sha3(_name)].status          = 0;
    }
    
    function is_votable_proposal(string _name) constant returns (bool)
    {
        return (proposals[sha3(_name)].start_epoch == get_current_epoch());
    }
    
    
    
    function cast_vote(string _proposal_name, uint _vote_code) only_voter
    {
        
        // Vote encodings:
        // 0 - for
        // 1 - against
        // 2 - abstain
        
        require(proposals[sha3(_proposal_name)].start_epoch == get_current_epoch());
        
        if(_vote_code == 0)
        {
            proposals[sha3(_proposal_name)].votes_for += voting_weight[msg.sender];
        }
        else if (_vote_code == 1)
        {
            proposals[sha3(_proposal_name)].votes_against += voting_weight[msg.sender];
        }
        else if (_vote_code == 2)
        {
            proposals[sha3(_proposal_name)].votes_abstain += voting_weight[msg.sender];
        }
        else
        {
            revert();
        }
        
        cold_staking_contract.vote_casted(msg.sender);
    }
    
    function evaluate_proposal(string _name)
    {
        require(proposals[sha3(_name)].start_epoch < get_current_epoch());
        require(proposals[sha3(_name)].end_epoch >= get_current_epoch());
        
        uint _total_votes = proposals[sha3(_name)].votes_abstain + proposals[sha3(_name)].votes_against + proposals[sha3(_name)].votes_for;
        if (_total_votes * 4 < total_voting_weight)
        {
            // Proposal was not voted enough.
            proposals[sha3(_name)].status = 3;
            return;
        }
        
        // TODO
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
    
    modifier only_voter
    {
        require(is_voter(msg.sender));
        _;
    }
}
