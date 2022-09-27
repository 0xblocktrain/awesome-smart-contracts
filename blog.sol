contract Medium is ERC721, ERC721URIStorage, Ownable {

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    uint256 public fees;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 fees_
    ) ERC721(name_, symbol_){
        fees = fees_;
    }

    function safeMint(address to, string memory uri) public payable {

        require(msg.value >= fees, "Not enough MATIC");
        payable(owner()).transfer(fees);

        //Mint NFT

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        // Return oversupplied fees

        uint256 contractBalance = address(this).balance;

        if (contractBalance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }
}