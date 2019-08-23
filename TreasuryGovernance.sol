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
    
    function vote_casted(address _addr, uint _proposal_deadline) public { }
    
    uint public a;
    
}

contract TreasuryGovernance {
    
    // TODO: Update calculations with SafeMath functions.

    using SafeMath for uint;
    
    event VoterUpdated(address indexed voter, uint weight);
    event ProposalSubmitted(bytes32 indexed hash, address indexed owner, uint total_payment);
    event ProposalEvaluated(bytes32 indexed hash, uint status);
    event ProposalReevaluation(bytes32 indexed hash, uint status);
    event VoteRecorded(address indexed voter, bytes32 indexed proposal, uint indexed code, uint weight);
    
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
        uint    payment_amount; // Amount of payment per epoch.
        // NOTE: If a proposal is intended to be paid in multiple epochs then
        //       it will reveive (`payment_amount` * epochs count) funds.
        uint    last_funded_epoch; // Number of the epoch in which the proposal was last funded.
        
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
        uint    vote_code; // 0 - for, 1 - against, 2 - abstain
        uint    weight;
    }
    
    ColdStaking public cold_staking_contract = ColdStaking(0xd813419749b3c2cdc94a2f9cfcf154113264a9d6); // Staking contract address and ABI.
    
    uint public proposals_count;
    
    uint public epoch_length        = 27 days; // Voting epoch length.
    uint public start_timestamp     = now;
    
    uint public total_voting_weight = 0; // This variable preserves the total amount of staked funds which participate in voting.
    uint public proposal_threshold  = 500 ether; // The amount of funds that will be held by voting contract during the proposal consideration/voting.
    uint public voting_threshold    = 50; // Percentage of votes which is required to consider that there are enough votes for the proposal. 
                                          // If a proposal was not voted enough then it will be rejected automatically.
    
    mapping(address => uint)     public voting_weight; // Each voters weight. Calculated and updated on each Cold Staked deposit change.
    mapping(bytes32 => Proposal) public proposals; // Use `bytes32` sha3 hash of proposal name to identify a proposal entity.
    mapping(bytes32 => mapping(address => Vote))     public votes;


    // Cold Staker can become a voter by executing this funcion.
    // Voting contract must read the weight of the staker
    // and update the total voting weight.
    function become_voter() public
    {
        require(voting_weight[msg.sender] == 0);
        
        uint _amount;
        uint _time;
        (_amount, _time) = cold_staking_contract.staker(msg.sender);
        voting_weight[msg.sender] = _amount;
        total_voting_weight += _amount;
        
        emit VoterUpdated(msg.sender, voting_weight[msg.sender]);
    }
    
    // Voter can resign from his voting rights.
    // In this case, his voting weight will be subtracted from total voting weight.
    // This person can become voter again by calling the `become_voter` function.
    function resign_voter() public
    {
        require(voting_weight[msg.sender] != 0);
        
        total_voting_weight -= voting_weight[msg.sender];
        voting_weight[msg.sender] = 0;
        
        emit VoterUpdated(msg.sender, voting_weight[msg.sender]);
    }
    
    
    // Staking Contract MUST call this function on each staking deposit update (on withdrawals and deposits).
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
        
        emit VoterUpdated(msg.sender, voting_weight[msg.sender]);
    }
    
    // Returns the id of current Treasury Epoch.
    function get_current_epoch() public constant returns (uint)
    {
        return ((block.timestamp - start_timestamp) / epoch_length);
    }
    
    function submit_proposal(string _name, string _url, bytes32 _hash, uint _start, uint _end, address _destination, uint _funding) public payable
    {
        require(_destination != address(0x0)); // Address of a newly submitted proposal must not be 0x0.
        require(proposals[sha3(_name)].payment_address == address(0x0)); // Check whether a proposal exists (assuming that a proposal with address 0x0 does not exist).
        require(msg.value > proposal_threshold);
        require(get_current_epoch() < _start);
        require(_end > _start);
        
        proposals[sha3(_name)].name            = _name;
        proposals[sha3(_name)].URL             = _url;
        proposals[sha3(_name)].hash            = _hash;
        proposals[sha3(_name)].start_epoch     = _start;
        proposals[sha3(_name)].end_epoch       = _end;
        proposals[sha3(_name)].payment_address = _destination;
        proposals[sha3(_name)].payment_amount  = _funding;
        
        proposals[sha3(_name)].status          = 0;
        
        emit ProposalSubmitted(_hash, _destination, _funding * (_end - _start));
    }
    
    function is_votable_proposal(string _name) constant returns (bool)
    {
        return (proposals[sha3(_name)].start_epoch == get_current_epoch() && proposals[sha3(_name)].status == 0);
    }
    
    
    
    function cast_vote(string _proposal_name, uint _vote_code) only_voter
    {
        
        // Vote encodings:
        // 0 - for
        // 1 - against
        // 2 - abstain
        
        
        // Check whether proposal is submitted for first voting
        // OR a multiepoch proposal is undergoing a re-evaluation.
        require(proposals[sha3(_proposal_name)].start_epoch == get_current_epoch() ||
        (proposals[sha3(_proposal_name)].start_epoch < get_current_epoch() && proposals[sha3(_proposal_name)].status == 0) );
        
        // Check whether msg.sender has already voted on this proposal
        // clear his vote first if so.
        if(votes[sha3(_proposal_name)][msg.sender].weight != 0)
        {
            clear_vote(_proposal_name, msg.sender);
        }
        
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
        
        // Record voter, code and weight to prevent multiple votings from single address.
        votes[sha3(_proposal_name)][msg.sender].weight    = voting_weight[msg.sender];
        votes[sha3(_proposal_name)][msg.sender].vote_code = _vote_code;
        
        if(!stakecast_disabled)
        {
            cold_staking_contract.vote_casted( msg.sender, (start_timestamp + epoch_length * get_current_epoch()) );
        }
        
        emit VoteRecorded(msg.sender, proposals[sha3(_proposal_name)].hash, _vote_code, voting_weight[msg.sender]);
    }
    
    function evaluate_proposal(string _name)
    {
        require(proposals[sha3(_name)].start_epoch < get_current_epoch());
        require(proposals[sha3(_name)].end_epoch >= get_current_epoch());
        require(proposals[sha3(_name)].status == 0);
        
        uint _total_votes = proposals[sha3(_name)].votes_abstain + proposals[sha3(_name)].votes_against + proposals[sha3(_name)].votes_for;
        if ( _total_votes < ((total_voting_weight * voting_threshold)/100) )
        {
            // Proposal was not voted enough.
            proposals[sha3(_name)].status = 3;
            return;
        }
        
        if (proposals[sha3(_name)].votes_for > proposals[sha3(_name)].votes_against)
        {
            // Proposal is accepted if "FOR" votes weight > "AGAINST"
            proposals[sha3(_name)].status = 1;
            
            // If the proposal is accepted then send the first payment immediately.
            fund_proposal(_name);
        }
        else
        { 
            // Assign `rejected` status.
            proposals[sha3(_name)].status = 2;
        }
        
        emit ProposalEvaluated(proposals[sha3(_name)].hash, proposals[sha3(_name)].status);
    }
    
    
   function fund_proposal(string _name) internal
   {
       // Checking conditions first.
       // Proposal must be `accepted` and it must not be expired.
       assert(proposals[sha3(_name)].status == 1);
       assert(proposals[sha3(_name)].end_epoch <= get_current_epoch());
       assert(proposals[sha3(_name)].last_funded_epoch < get_current_epoch());
       
       uint epoch_delta = get_current_epoch() - proposals[sha3(_name)].last_funded_epoch;
       
       proposals[sha3(_name)].payment_address.transfer( (proposals[sha3(_name)].payment_amount * epoch_delta) ); // Send payment * unpaid epochs count.
       proposals[sha3(_name)].last_funded_epoch = get_current_epoch(); // Modify the last payment epoch.
   }
   
   function clear_vote(string _proposal_name, address _voter) internal
   {
       // IMPORTANT: Voters weight could change since the moment of proposal voting.
       // `votes[sha3(_proposal_name)][_voter].weight` is not necessarily equal to `voting_weight[_voter]`
       
       // Check if _voter has a record of _proposal voting.
       assert(votes[sha3(_proposal_name)][_voter].weight != 0);
       
       if(votes[sha3(_proposal_name)][_voter].vote_code == 0)
       {
           // If _voter casted a vote FOR then reduce the weight of FOR votes.
           proposals[sha3(_proposal_name)].votes_for -= votes[sha3(_proposal_name)][_voter].weight;
       }
       else if(votes[sha3(_proposal_name)][_voter].vote_code == 1)
       {
           // If _voter casted a vote AGAINST then reduce the weight of AGAINST votes.
           proposals[sha3(_proposal_name)].votes_against -= votes[sha3(_proposal_name)][_voter].weight;
       }
       else
       {
           // Assume that _voter casted ABSTAIN vote.
           proposals[sha3(_proposal_name)].votes_abstain -= votes[sha3(_proposal_name)][_voter].weight;
       }
       
       // Zero out _voter's weight and voting record entry.
       votes[sha3(_proposal_name)][_voter].weight    = 0;
       votes[sha3(_proposal_name)][_voter].vote_code = 0;
        
        emit VoteRecorded(_voter, proposals[sha3(_proposal_name)].hash, 0, 0);
   }
   
   // Anyone can request a funding for accepted proposal.
   function request_funding(string _proposal_name)
   {
       if (proposals[sha3(_proposal_name)].status == 0)
       {
           // If proposal has `votable` status then it must be re-evaluated. This may happen in case of multiepoch proposal.
           evaluate_proposal(_proposal_name); // Automatically funding proposal at the end of evaluation if proposal is `accepted`.
       }
       else
       {
           fund_proposal(_proposal_name); // Pay proposal if it does not require re-evaluation.
       }
   }
   
   function reevaluate_multiepoch_proposal(string _proposal_name) only_voter
   {
       // Each voter can request a re-evaluation of already-accepted proposal if the proposal was already paid at current epoch.
       // Allows to re-evaluate each voting record manually.
       
       if (proposals[sha3(_proposal_name)].last_funded_epoch == get_current_epoch())
       {
           proposals[sha3(_proposal_name)].status = 0; // Assign `votable` status. Preserves voting records from the previous voting session.
           
           emit ProposalReevaluation(proposals[sha3(_proposal_name)].hash, proposals[sha3(_proposal_name)].status);
       }
       
   }
    
    // Manually re-evaluates specified voting record.
    // This may be necessary to re-evaluate cold staker's weight
    // if it changes after the last vote record of the cold staker.
    function reevaluate_vote_record(string _proposal_name, address _voter) only_voter
    {
        /*uint _delta;
        if(votes[sha3(_proposal_name)][_voter].weight > voting_weight[_voter])
        {
            // Decrease the corresponding amount of vote records of the proposal if voter's weight decreases.
            _delta = votes[sha3(_proposal_name)][_voter].weight - voting_weight[_voter];
            
            if(votes[sha3(_proposal_name)][_voter].vote_code == 0)
            {
                proposals[sha3(_proposal_name)].votes_for 
            }
        }*/
        
        require(proposals[sha3(_proposal_name)].status == 0); // Allow re-evaluation of `votable` proposals only.
        uint _vote_code = votes[sha3(_proposal_name)][_voter].vote_code; // Preserve the decision from the previous voting session.
        
        clear_vote(_proposal_name, _voter); // Clear the previous vote.
        
        // Cas a vote on _voter's behalf depending on previous voting session decision (FOR, AGAINST, ABSTAIN).
        if(_vote_code == 0)
        {
            proposals[sha3(_proposal_name)].votes_for += voting_weight[_voter];
        }
        else if (_vote_code == 1)
        {
            proposals[sha3(_proposal_name)].votes_against += voting_weight[_voter];
        }
        else if (_vote_code == 2)
        {
            proposals[sha3(_proposal_name)].votes_abstain += voting_weight[_voter];
        }
        
        votes[sha3(_proposal_name)][_voter].weight    = voting_weight[_voter];
        votes[sha3(_proposal_name)][_voter].vote_code = _vote_code;
        
        emit VoteRecorded(_voter, proposals[sha3(_proposal_name)].hash, _vote_code, voting_weight[_voter]);
    }
    
    function withdraw_proposal(string _name)
    {
        require(proposals[sha3(_name)].payment_address == msg.sender);
        
        proposals[sha3(_name)].status = 3;
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
    
    
    /* Commented out getter functions - prone to compiler mistakes
    
    
    // Getter functions:
    // NOTE: Solidity 0.4.25 compiler does not support enough stack depth
    // Thats why getter functions were separated into _meta_info and _votes_info getters
    // to avoid compiler stack-depth-related errors.
    
    function get_proposal_meta_info(string _name) public view returns(
                string  URL,
                bytes32 hash,
                uint    start_epoch,
                uint    end_epoch,
                address payment_address,
                uint    payment_amount,
                uint    last_funded_epoch
                )
    {
        return(
            proposals[sha3(_name)].URL,
            proposals[sha3(_name)].hash,
            proposals[sha3(_name)].start_epoch,
            proposals[sha3(_name)].end_epoch,
            proposals[sha3(_name)].payment_address,
            proposals[sha3(_name)].payment_amount,
            proposals[sha3(_name)].last_funded_epoch
            );
    }
    
    function get_proposal_votes_info(string _name) public view returns(
                uint votes_for,
                uint votes_against,
                uint votes_abstain,
                uint status
                )
    {
        return(
            proposals[sha3(_name)].votes_for,
            proposals[sha3(_name)].votes_against,
            proposals[sha3(_name)].votes_abstain,
            proposals[sha3(_name)].status
            );
    }
    
    end of commenting getter functions */
    
    // DEBUGGING FUNCTIONS
    /*-------------------------------------------------------*/
    
    address public treasurer = msg.sender;
    
    modifier only_treasurer
    {
        require(msg.sender == treasurer);
        _;
    }
    bool public stakecast_disabled = false;
    
    function restrict_stakecast(bool _status) only_treasurer
    {
        stakecast_disabled = _status;
    }
    
    function set_staking_contract(address _new_staking_contract) only_treasurer
    {
        cold_staking_contract = ColdStaking(_new_staking_contract);
    }
    
    function set_start(uint _time) only_treasurer
    {
        start_timestamp = _time;
    }
    
    // Epoch length is set in seconds.
    function set_epoch_length(uint _epoch_length) only_treasurer
    {
        epoch_length = _epoch_length;
    }
    
    function set_proposal_threshold(uint _threshold) only_treasurer
    {
        proposal_threshold = _threshold;
    }
    
    // Voting threshold is set in percents.
    function set_voting_threshold(uint _threshold) only_treasurer
    {
        voting_threshold = _threshold;
    }
    
    /*-------------------------------------------------------*/
    // END DEBUGGING FUNCTIONS
}
