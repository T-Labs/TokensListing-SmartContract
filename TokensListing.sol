pragma solidity ^0.5.2;

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
    require(b > 0);
    uint c = a / b;
    return c;
  }

  function sub(uint a, uint b) internal pure returns (uint) {
  require(b <= a);
    uint c = a - b;
    return c;
  }

  function add(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    require(c >= a);
    return c;
  }
}

contract Token {
  /// @return total amount of tokens
  function totalSupply() public returns (uint supply) {}

  /// @param _owner The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _owner) public returns (uint balance) {}

  /// @notice send `_value` token to `_to` from `msg.sender`
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transfer(address _to, uint _value) public returns (bool success) {}

  /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
  /// @param _from The address of the sender
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transferFrom(address _from, address _to, uint _value) public  returns (bool success) {}

  /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @param _value The amount of wei to be approved for transfer
  /// @return Whether the approval was successful or not
  function approve(address _spender, uint _value) public returns (bool success) {}

  /// @param _owner The address of the account owning tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @return Amount of remaining tokens allowed to spent
  function allowance(address _owner, address _spender) public returns (uint remaining) {}

  event Transfer(address indexed _from, address indexed _to, uint _value);
  event Approval(address indexed _owner, address indexed _spender, uint _value);

  uint public decimals;
  string public name;
  string public symbol;
}

contract TokensListing {
  using SafeMath for uint;

  mapping (address => mapping (address => uint)) public tokens; //mapping of token addresses to mapping of account balances (token=0 means Ether)
  mapping (address => mapping (bytes32 => bool)) public orders; //mapping of user accounts to mapping of order hashes to booleans (true = submitted by user, equivalent to offchain signature)
  mapping (address => mapping (bytes32 => uint)) public orderFills; //mapping of user accounts to mapping of order hashes to uints (amount of order that has been filled)

  event Order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user);
  event Cancel(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s);
  event Trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, address get, address give);
  event Deposit(address token, address user, uint amount, uint balance);
  event Withdraw(address token, address user, uint amount, uint balance);

  function deposit() public payable {
    tokens[address(0)][msg.sender] = tokens[address(0)][msg.sender];
    emit Deposit(address(0), msg.sender, msg.value, tokens[address(0)][msg.sender]);
  }

  function withdraw(uint amount) public {
    require(tokens[address(0)][msg.sender] >= amount);
    // TODO
    tokens[address(0)][msg.sender] = tokens[address(0)][msg.sender].sub(amount);
    msg.sender.transfer(amount);
    emit Withdraw(address(0), msg.sender, amount, tokens[address(0)][msg.sender]);
  }

  function depositToken(address token, uint amount) public {
    //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
    require(token!=address(0));
    require(Token(token).transferFrom(msg.sender, address(this), amount));
    tokens[token][msg.sender] = tokens[token][msg.sender].add(amount);
    emit Deposit(token, msg.sender, amount, tokens[token][msg.sender]);
  }

  function withdrawToken(address token, uint amount) public {
    require(token!=address(0));
    require(tokens[token][msg.sender] >= amount);
    // TODO
    tokens[token][msg.sender] = tokens[token][msg.sender].sub(amount);
    require(Token(token).transfer(msg.sender, amount));
    emit Withdraw(token, msg.sender, amount, tokens[token][msg.sender]);
  }

  function balanceOf(address token, address user) view public returns (uint) {
    return tokens[token][user];
  }

  function order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce) public {
    bytes32 hash = sha256(abi.encodePacked(address(this), tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    orders[msg.sender][hash] = true;
    emit Order(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, msg.sender);
  }

  function trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount) public {
    //amount is in amountGet terms
    bytes32 hash = sha256(abi.encodePacked(address(this), tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    require((
      (orders[user][hash] || ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)),v,r,s) == user) &&
      block.number <= expires &&
      orderFills[user][hash].add(amount) <= amountGet
    ));
    
    uint amountBackward = amountGive.mul(amount).div(amountGet);
    tradeBalances(tokenGet, tokenGive, amountBackward, user, amount);
    orderFills[user][hash] = orderFills[user][hash].add(amount);
    emit Trade(tokenGet, amount, tokenGive, amountBackward, user, msg.sender);
  }

  function tradeBalances(address tokenGet, address tokenGive, uint amountBackward, address user, uint amount) private {
    tokens[tokenGet][msg.sender] = tokens[tokenGet][msg.sender].sub(amount);
    tokens[tokenGet][user] = tokens[tokenGet][user].add(amount);
    tokens[tokenGive][user] = tokens[tokenGive][user].sub(amountBackward);
    tokens[tokenGive][msg.sender] = tokens[tokenGive][msg.sender].add(amountBackward);
  }

  function testTrade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount, address sender) view public returns(bool) {
    if (!(
      tokens[tokenGet][sender] >= amount &&
      availableVolume(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, user, v, r, s) >= amount
    )) return false;
    return true;
  }

  function availableVolume(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s) view public returns(uint) {
    bytes32 hash = sha256(abi.encodePacked(address(this), tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    if (!(
      (orders[user][hash] || ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)),v,r,s) == user) &&
      block.number <= expires
    )) return 0;
    uint available1 = available1(user, amountGet, hash);
    uint available2 = available2(user, tokenGive, amountGet, amountGive);
    if (available1<available2) return available1;
    return available2;
  }

  function available1(address user, uint amountGet, bytes32 hash) view public returns(uint) {
    return  amountGet.sub(orderFills[user][hash]);
  }

  function available2(address user, address tokenGive, uint amountGet, uint amountGive) view public returns(uint) {
    return tokens[tokenGive][user].mul(amountGet).div(amountGive);
  }


  function amountFilled(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user) view public returns(uint) {
    bytes32 hash = sha256(abi.encodePacked(address(this), tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    return orderFills[user][hash];
  }

  function cancelOrder(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, uint8 v, bytes32 r, bytes32 s) public {
    bytes32 hash = sha256(abi.encodePacked(address(this), tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    require (orders[msg.sender][hash] || ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)),v,r,s) == msg.sender);
    orderFills[msg.sender][hash] = amountGet;
    emit Cancel(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, msg.sender, v, r, s);
  }
}